import crypto from "node:crypto";
import path from "node:path";

import { ExactEvmScheme, toClientEvmSigner, type ClientEvmSigner } from "@x402/evm";
import { BatchSettlementEvmScheme, FileClientChannelStorage } from "@x402/evm/batch-settlement/client";
import {
  decodePaymentResponseHeader,
  x402Client,
  x402HTTPClient,
  type PaymentRequired,
  type PaymentRequirements,
} from "@x402/fetch";
import { createPublicClient, http } from "viem";
import { base, baseSepolia } from "viem/chains";

import type {
  X402DetailsResponse,
  X402FetchParams,
  X402FetchResponse,
  X402HttpMethod,
  X402IntentRecord,
  PaymentBindingV1,
  X402PrepareParams,
  X402PrepareResponse,
  X402QuoteParams,
  X402QuoteResponse,
  X402ReceiptGetResponse,
  X402ReceiptRecord,
  X402RefundParams,
  X402RefundResponse,
  X402RequestFingerprint,
  X402RequestInput,
  X402SelectedPaymentRequirement,
} from "../../internal-types/index.js";

import type { SignerBackend } from "../agent/signer-backend.js";
import { RegentError } from "../errors.js";
import { hashValue, sha256Hex } from "./hash.js";
import { X402LocalStore } from "./store.js";

type FetchLike = typeof globalThis.fetch;

interface X402WrapperOptions {
  stateDir: string;
  signer: SignerBackend;
  fetch?: FetchLike;
}

const PAYMENT_HEADER_NAMES = new Set([
  "payment-required",
  "payment-response",
  "payment-signature",
  "x-payment",
  "x-payment-response",
]);

const SUPPORTED_METHODS = new Set<X402HttpMethod>(["GET", "POST", "PUT", "PATCH", "DELETE"]);
const SUPPORTED_SCHEMES = new Set(["batch-settlement", "exact"]);
const SUPPORTED_BATCH_NETWORKS = new Set(["eip155:8453", "eip155:84532"]);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const nowIso = (): string => new Date().toISOString();

const normalizeUrl = (url: string): string => {
  try {
    return new URL(url).toString();
  } catch (error) {
    throw new RegentError("x402_invalid_url", "x402 resource URL is invalid.", error);
  }
};

const normalizeMethod = (method: X402HttpMethod | undefined): X402HttpMethod => {
  const normalized = (method ?? "GET").toUpperCase();
  if (!SUPPORTED_METHODS.has(normalized as X402HttpMethod)) {
    throw new RegentError("x402_invalid_method", `x402 method is not supported: ${normalized}`);
  }

  return normalized as X402HttpMethod;
};

const normalizeHeaders = (headers: Record<string, string> | undefined): Record<string, string> => {
  const normalized: Record<string, string> = {};

  for (const [name, value] of Object.entries(headers ?? {})) {
    const key = name.trim().toLowerCase();
    if (!key) {
      throw new RegentError("x402_invalid_header", "x402 request header name is empty.");
    }
    if (PAYMENT_HEADER_NAMES.has(key)) {
      throw new RegentError("x402_payment_header_forbidden", `x402 payment header is owned by Regent: ${name}`);
    }
    if (normalized[key] !== undefined) {
      throw new RegentError("x402_duplicate_header", `x402 request header is duplicated: ${name}`);
    }
    normalized[key] = value;
  }

  return Object.fromEntries(Object.entries(normalized).sort(([left], [right]) => left.localeCompare(right)));
};

const normalizeRequest = (input: X402RequestInput): Required<Pick<X402RequestInput, "url" | "method" | "headers">> & {
  body?: string;
} => {
  const method = normalizeMethod(input.method);
  const body = input.body;

  if ((method === "GET" || method === "DELETE") && body !== undefined) {
    throw new RegentError("x402_body_not_allowed", `${method} x402 requests cannot include a body.`);
  }

  return {
    url: normalizeUrl(input.url),
    method,
    headers: normalizeHeaders(input.headers),
    ...(body !== undefined ? { body } : {}),
  };
};

const requestFingerprint = (input: X402RequestInput): X402RequestFingerprint => {
  const request = normalizeRequest(input);
  const bodySha256 = request.body === undefined ? null : sha256Hex(request.body);
  const headersSha256 = hashValue(request.headers);
  return {
    url: request.url,
    method: request.method,
    body_sha256: bodySha256,
    headers_sha256: headersSha256,
    request_hash: hashValue({
      url: request.url,
      method: request.method,
      body_sha256: bodySha256,
      headers: request.headers,
    }),
  };
};

const requestInit = (input: X402RequestInput, extraHeaders: Record<string, string> = {}): RequestInit => {
  const request = normalizeRequest(input);
  return {
    method: request.method,
    headers: {
      ...request.headers,
      ...extraHeaders,
    },
    ...(request.body !== undefined ? { body: request.body } : {}),
  };
};

const requirePaymentRequiredV2 = (paymentRequired: PaymentRequired): PaymentRequired => {
  if (paymentRequired.x402Version !== 2) {
    throw new RegentError("x402_unsupported_version", "Regent x402 currently supports x402 version 2.");
  }

  return paymentRequired;
};

const paymentRequirementHash = (requirement: PaymentRequirements): string => hashValue(requirement);

const paymentBindingHash = (binding: Omit<PaymentBindingV1, "binding_hash">): string => hashValue(binding);

const isPaymentBindingV1 = (value: unknown): value is PaymentBindingV1 => {
  if (!isRecord(value) || value.version !== "PaymentBindingV1") {
    return false;
  }

  return (
    typeof value.resource_id === "string" &&
    (typeof value.buyer_agent_id === "string" || value.buyer_agent_id === null) &&
    (typeof value.seller_agent_id === "string" || value.seller_agent_id === null) &&
    typeof value.network === "string" &&
    typeof value.asset === "string" &&
    typeof value.amount_atomic === "string" &&
    typeof value.pay_to === "string" &&
    (typeof value.expires_at === "string" || value.expires_at === null) &&
    typeof value.nonce === "string" &&
    typeof value.binding_hash === "string"
  );
};

const validatePaymentBindingHash = (binding: PaymentBindingV1): void => {
  const { binding_hash: bindingHash, ...withoutHash } = binding;
  if (paymentBindingHash(withoutHash) !== bindingHash) {
    throw new RegentError("x402_payment_binding_changed", "The x402 payment binding hash does not match its fields.");
  }
};

const serverPaymentBinding = (
  resource: Record<string, unknown>,
  selected: X402SelectedPaymentRequirement,
): PaymentBindingV1 | null => {
  const candidate = selected.extra.regentPaymentBindingV1;

  if (candidate === undefined || candidate === null) {
    if (resource.serviceName === "techtree" || typeof resource.bindingHash === "string") {
      throw new RegentError("x402_payment_binding_required", "This Regent x402 resource did not include a payment binding.");
    }

    return null;
  }

  if (!isPaymentBindingV1(candidate)) {
    throw new RegentError("x402_payment_binding_invalid", "The Regent x402 payment binding is invalid.");
  }

  validatePaymentBindingHash(candidate);

  if (typeof resource.bindingHash === "string" && resource.bindingHash !== candidate.binding_hash) {
    throw new RegentError("x402_payment_binding_changed", "The x402 resource binding does not match the payment terms.");
  }

  const expected: Array<[keyof PaymentBindingV1, string | null]> = [
    ["network", selected.network],
    ["asset", selected.asset],
    ["amount_atomic", selected.amount],
    ["pay_to", selected.pay_to],
  ];

  for (const [field, value] of expected) {
    if (candidate[field] !== value) {
      throw new RegentError("x402_payment_binding_changed", "The x402 payment binding does not match the payment terms.");
    }
  }

  return candidate;
};

const paymentBindingForIntent = (input: {
  intentId: string;
  request: X402RequestFingerprint;
  resource: Record<string, unknown>;
  selected: X402SelectedPaymentRequirement;
  expiresAt: string;
}): PaymentBindingV1 => {
  const serverBinding = serverPaymentBinding(input.resource, input.selected);
  if (serverBinding) {
    return serverBinding;
  }

  const withoutHash = {
    version: "PaymentBindingV1" as const,
    resource_id: hashValue({
      request_hash: input.request.request_hash,
      resource: input.resource,
    }),
    buyer_agent_id: null,
    seller_agent_id: null,
    network: input.selected.network,
    asset: input.selected.asset,
    amount_atomic: input.selected.amount,
    pay_to: input.selected.pay_to,
    expires_at: input.expiresAt,
    nonce: input.intentId,
  };

  return {
    ...withoutHash,
    binding_hash: paymentBindingHash(withoutHash),
  };
};

const compareApprovedBinding = (intent: X402IntentRecord): void => {
  const expected = paymentBindingForIntent({
    intentId: intent.intent_id,
    request: intent.request,
    resource: intent.resource,
    selected: intent.selected,
    expiresAt: intent.expires_at,
  });

  if (hashValue(intent.payment_binding) !== hashValue(expected)) {
    throw new RegentError("x402_payment_binding_changed", "The approved x402 payment binding no longer matches this intent.");
  }
};

const requireAtomicAmount = (value: string, errorCode: string, message: string): void => {
  if (!/^\d+$/.test(value)) {
    throw new RegentError(errorCode, message);
  }
};

const isSupportedRequirement = (requirement: PaymentRequirements): boolean =>
  SUPPORTED_SCHEMES.has(requirement.scheme) &&
  requirement.network.startsWith("eip155:") &&
  (requirement.scheme !== "batch-settlement" || SUPPORTED_BATCH_NETWORKS.has(requirement.network));

const selectedRequirement = (requirement: PaymentRequirements): X402SelectedPaymentRequirement => {
  if (!SUPPORTED_SCHEMES.has(requirement.scheme)) {
    throw new RegentError("x402_unsupported_scheme", `Regent x402 does not support scheme ${requirement.scheme}.`);
  }
  if (!requirement.network.startsWith("eip155:")) {
    throw new RegentError("x402_unsupported_network", `Regent x402 does not support network ${requirement.network}.`);
  }
  if (requirement.scheme === "batch-settlement" && !SUPPORTED_BATCH_NETWORKS.has(requirement.network)) {
    throw new RegentError("x402_unsupported_network", `Regent x402 does not support network ${requirement.network}.`);
  }
  requireAtomicAmount(requirement.amount, "x402_invalid_amount", "x402 amount must be an atomic token integer.");
  if (typeof requirement.maxTimeoutSeconds !== "number" || requirement.maxTimeoutSeconds <= 0) {
    throw new RegentError("x402_invalid_timeout", "x402 payment requirement timeout is invalid.");
  }

  return {
    scheme: requirement.scheme,
    network: requirement.network,
    asset: requirement.asset,
    amount: requirement.amount,
    pay_to: requirement.payTo,
    max_timeout_seconds: requirement.maxTimeoutSeconds,
    extra: isRecord(requirement.extra) ? requirement.extra : {},
    requirement_hash: paymentRequirementHash(requirement),
  };
};

const selectRequirement = (
  accepts: readonly PaymentRequirements[],
  maxAmount?: string,
): X402SelectedPaymentRequirement => {
  const supported = accepts
    .filter(isSupportedRequirement)
    .sort((left, right) => {
      if (left.scheme === right.scheme) {
        return 0;
      }
      return left.scheme === "batch-settlement" ? -1 : 1;
    })
    .map(selectedRequirement);

  if (supported.length === 0) {
    throw new RegentError("x402_no_supported_requirement", "No Regent-supported x402 payment requirement was offered.");
  }

  const selected = supported[0];

  if (maxAmount !== undefined) {
    requireAtomicAmount(maxAmount, "x402_invalid_max_amount", "x402 max amount must be an atomic token integer.");
    if (BigInt(selected.amount) > BigInt(maxAmount)) {
      throw new RegentError("x402_amount_above_limit", "x402 quote is above the approved maximum amount.");
    }
  }

  return selected;
};

const validateMaxDepositAmount = (scheme: string, maxDepositAmount?: string): string | undefined => {
  if (scheme !== "batch-settlement") {
    return undefined;
  }

  if (maxDepositAmount === undefined) {
    throw new RegentError(
      "x402_deposit_limit_required",
      "Batch-settlement x402 payments need --max-deposit-amount so Regent knows the largest escrow you approve.",
    );
  }

  requireAtomicAmount(
    maxDepositAmount,
    "x402_invalid_max_deposit_amount",
    "x402 max deposit amount must be an atomic token integer.",
  );

  if (BigInt(maxDepositAmount) <= 0n) {
    throw new RegentError("x402_invalid_max_deposit_amount", "x402 max deposit amount must be greater than zero.");
  }

  return maxDepositAmount;
};

const viemChainForNetwork = (network: string) => {
  switch (network) {
    case "eip155:8453":
      return base;
    case "eip155:84532":
      return baseSepolia;
    default:
      throw new RegentError("x402_unsupported_network", `Regent x402 does not support network ${network}.`);
  }
};

const rpcEnvForNetwork = (network: string): string => {
  switch (network) {
    case "eip155:8453":
      return "X402_BASE_MAINNET_RPC_URL or BASE_MAINNET_RPC_URL";
    case "eip155:84532":
      return "X402_BASE_SEPOLIA_RPC_URL or BASE_SEPOLIA_RPC_URL";
    default:
      return "a supported Base RPC URL";
  }
};

const rpcUrlForNetwork = (network: string): string | undefined => {
  switch (network) {
    case "eip155:8453":
      return process.env.X402_BASE_MAINNET_RPC_URL ?? process.env.BASE_MAINNET_RPC_URL ?? process.env.BASE_RPC_URL;
    case "eip155:84532":
      return process.env.X402_BASE_SEPOLIA_RPC_URL ?? process.env.BASE_SEPOLIA_RPC_URL ?? process.env.BASE_RPC_URL;
    default:
      return undefined;
  }
};

const requireRpcUrlForNetwork = (network: string): string => {
  const rpcUrl = rpcUrlForNetwork(network);
  if (rpcUrl && rpcUrl.trim()) {
    return rpcUrl;
  }

  throw new RegentError(
    "x402_rpc_url_required",
    `Batch-settlement x402 payments on ${network} need ${rpcEnvForNetwork(network)} before paying or refunding.`,
  );
};

const parseJsonBody = (bodyText: string): unknown | undefined => {
  if (bodyText.trim() === "") {
    return undefined;
  }

  try {
    return JSON.parse(bodyText);
  } catch {
    return undefined;
  }
};

const settlementFromHeaders = (headers: Headers): Record<string, unknown> | null => {
  const header = headers.get("payment-response") ?? headers.get("x-payment-response");
  if (!header) {
    return null;
  }

  try {
    return decodePaymentResponseHeader(header) as unknown as Record<string, unknown>;
  } catch {
    return null;
  }
};

const fetchWithInjectedHeaders = (fetchImpl: FetchLike, headers: Record<string, string>): FetchLike => {
  if (Object.keys(headers).length === 0) {
    return fetchImpl;
  }

  return (input, init) => {
    const merged = new Headers(headers);
    new Headers(init?.headers).forEach((value, key) => {
      merged.set(key, value);
    });

    return fetchImpl(input, {
      ...init,
      headers: merged,
    });
  };
};

const compareApprovedRequest = (intent: X402IntentRecord, current: X402RequestFingerprint): void => {
  if (intent.request.request_hash !== current.request_hash) {
    throw new RegentError("x402_request_changed", "The x402 request no longer matches the approved intent.");
  }
};

const compareApprovedPayment = (intent: X402IntentRecord, paymentRequiredHash: string): void => {
  if (intent.payment_required_hash !== paymentRequiredHash) {
    throw new RegentError("x402_payment_requirements_changed", "The x402 payment terms changed after approval.");
  }
};

interface DiscoveredPayment {
  status: number;
  request: X402RequestFingerprint;
  response: Response;
  paymentRequired: PaymentRequired | null;
  paymentRequiredHash: string | null;
}

export class RegentX402Client {
  readonly store: X402LocalStore;
  private readonly signer: SignerBackend;
  private readonly fetch: FetchLike;

  constructor(options: X402WrapperOptions) {
    this.store = new X402LocalStore(options.stateDir);
    this.signer = options.signer;
    this.fetch = options.fetch ?? globalThis.fetch;
  }

  async details(input: X402RequestInput): Promise<X402DetailsResponse> {
    const discovered = await this.discover(input);

    if (!discovered.paymentRequired) {
      return {
        ok: true,
        payment_required: false,
        status: discovered.status,
        request: discovered.request,
      };
    }

    const paymentRequired = requirePaymentRequiredV2(discovered.paymentRequired);

    return {
      ok: true,
      payment_required: true,
      status: discovered.status,
      request: discovered.request,
      x402_version: paymentRequired.x402Version,
      resource: paymentRequired.resource as unknown as Record<string, unknown>,
      accepts: paymentRequired.accepts
        .filter(isSupportedRequirement)
        .map(selectedRequirement),
      payment_required_hash: discovered.paymentRequiredHash ?? hashValue(paymentRequired),
      ...(paymentRequired.error ? { error: paymentRequired.error } : {}),
    };
  }

  async quote(input: X402QuoteParams): Promise<X402QuoteResponse> {
    const discovered = await this.discover(input);
    if (!discovered.paymentRequired) {
      throw new RegentError("x402_payment_not_required", "The x402 resource did not request payment.");
    }

    const paymentRequired = requirePaymentRequiredV2(discovered.paymentRequired);
    const selected = selectRequirement(paymentRequired.accepts, input.max_amount);
    validateMaxDepositAmount(selected.scheme, input.max_deposit_amount);

    return {
      ok: true,
      payment_required: true,
      request: discovered.request,
      x402_version: paymentRequired.x402Version,
      resource: paymentRequired.resource as unknown as Record<string, unknown>,
      selected,
      payment_required_hash: discovered.paymentRequiredHash ?? hashValue(paymentRequired),
      quoted_at: nowIso(),
    };
  }

  async prepare(input: X402PrepareParams): Promise<X402PrepareResponse> {
    const quote = await this.quote(input);
    const createdAt = nowIso();
    const expiresAt = new Date(Date.now() + quote.selected.max_timeout_seconds * 1_000).toISOString();
    const maxDepositAmount = validateMaxDepositAmount(quote.selected.scheme, input.max_deposit_amount);
    const intentId = `x402_intent_${crypto.randomUUID()}`;
    const paymentBinding = paymentBindingForIntent({
      intentId,
      request: quote.request,
      resource: quote.resource,
      selected: quote.selected,
      expiresAt,
    });
    const intent: X402IntentRecord = this.store.saveIntent({
      intent_id: intentId,
      approval_status: input.approve ? "approved" : "pending",
      request: quote.request,
      x402_version: quote.x402_version,
      resource: quote.resource,
      selected: quote.selected,
      payment_binding: paymentBinding,
      payment_required_hash: quote.payment_required_hash,
      ...(input.max_amount ? { max_amount: input.max_amount } : {}),
      ...(maxDepositAmount ? { max_deposit_amount: maxDepositAmount } : {}),
      created_at: createdAt,
      expires_at: expiresAt,
      ...(input.approve ? { approved_at: createdAt } : {}),
    });

    return {
      ok: true,
      intent,
      next_action: input.approve
        ? {
            kind: "fetch",
            command: `regents x402 fetch --intent-id ${intent.intent_id} --url ${quote.request.url}`,
          }
        : {
            kind: "approve_locally",
            command: `regents x402 prepare --url ${quote.request.url} --approve`,
          },
    };
  }

  async fetchApproved(input: X402FetchParams): Promise<X402FetchResponse> {
    const intent = this.store.getIntent(input.intent_id);
    if (!intent) {
      throw new RegentError("x402_intent_not_found", "The x402 intent was not found.");
    }
    if (intent.approval_status !== "approved") {
      throw new RegentError("x402_intent_not_approved", "The x402 intent has not been approved.");
    }
    if (Date.parse(intent.expires_at) <= Date.now()) {
      throw new RegentError("x402_intent_expired", "The x402 intent has expired.");
    }

    const discovered = await this.discover(input);
    compareApprovedRequest(intent, discovered.request);
    compareApprovedBinding(intent);

    if (!discovered.paymentRequired) {
      const bodyText = await discovered.response.text();
      return {
        ok: discovered.response.ok,
        status: discovered.response.status,
        content_type: discovered.response.headers.get("content-type"),
        body_text: bodyText,
        receipt: null,
      };
    }

    compareApprovedPayment(intent, discovered.paymentRequiredHash ?? hashValue(discovered.paymentRequired));

    const httpClient = await this.createHttpClient(
      intent.selected.scheme,
      intent.selected.requirement_hash,
      intent.selected.network,
      intent.max_deposit_amount,
    );
    const paymentPayload = await httpClient.createPaymentPayload(discovered.paymentRequired);
    const paymentHeaders = httpClient.encodePaymentSignatureHeader(paymentPayload);
    const paidResponse = await this.fetch(input.url, requestInit(input, paymentHeaders));
    const bodyText = await paidResponse.text();
    const createdAt = nowIso();
    const receipt = this.store.saveReceipt({
      receipt_id: `x402_receipt_${crypto.randomUUID()}`,
      intent_id: intent.intent_id,
      url: intent.request.url,
      method: intent.request.method,
      status: paidResponse.status,
      ok: paidResponse.ok,
      payment_required_hash: intent.payment_required_hash,
      requirement_hash: intent.selected.requirement_hash,
      settlement: settlementFromHeaders(paidResponse.headers),
      created_at: createdAt,
    });

    this.store.saveIntent({
      ...intent,
      approval_status: "used",
      used_at: createdAt,
      receipt_id: receipt.receipt_id,
    });

    return {
      ok: paidResponse.ok,
      status: paidResponse.status,
      content_type: paidResponse.headers.get("content-type"),
      body_text: bodyText,
      receipt,
    };
  }

  receiptGet(input: { id: string }): X402ReceiptGetResponse {
    return {
      ok: true,
      receipt: this.store.getReceipt(input.id),
    };
  }

  async refund(input: X402RefundParams): Promise<X402RefundResponse> {
    const url = normalizeUrl(input.url);
    const headers = normalizeHeaders(input.headers);
    if (input.amount !== undefined) {
      requireAtomicAmount(input.amount, "x402_invalid_refund_amount", "x402 refund amount must be an atomic token integer.");
    }

    const discovered = await this.discover({ url, headers });
    if (!discovered.paymentRequired) {
      throw new RegentError("x402_payment_not_required", "This URL did not return x402 payment terms.");
    }

    const paymentRequired = requirePaymentRequiredV2(discovered.paymentRequired);
    const selected = paymentRequired.accepts
      .filter((requirement) => requirement.scheme === "batch-settlement" && SUPPORTED_BATCH_NETWORKS.has(requirement.network))
      .map(selectedRequirement)[0];
    if (!selected) {
      throw new RegentError("x402_refund_not_supported", "This URL does not offer batch-settlement refunds.");
    }

    const scheme = await this.createBatchSettlementScheme(selected.network);
    const settlement = await scheme.refund(url, {
      ...(input.amount !== undefined ? { amount: input.amount } : {}),
      fetch: fetchWithInjectedHeaders(this.fetch, headers),
    });

    return {
      ok: true,
      url,
      amount: input.amount ?? null,
      settlement: settlement as unknown as Record<string, unknown>,
    };
  }

  private async discover(input: X402RequestInput): Promise<DiscoveredPayment> {
    const request = requestFingerprint(input);
    const response = await this.fetch(input.url, requestInit(input));
    if (response.status !== 402) {
      return {
        status: response.status,
        request,
        response,
        paymentRequired: null,
        paymentRequiredHash: null,
      };
    }

    const bodyText = await response.clone().text();
    const body = parseJsonBody(bodyText);
    const parser = new x402HTTPClient(new x402Client());

    try {
      const paymentRequired = parser.getPaymentRequiredResponse((name) => response.headers.get(name), body);
      return {
        status: response.status,
        request,
        response,
        paymentRequired,
        paymentRequiredHash: hashValue(paymentRequired),
      };
    } catch (error) {
      throw new RegentError("x402_payment_required_invalid", "The x402 payment request could not be read.", error);
    }
  }

  private async createHttpClient(
    selectedScheme: string,
    selectedRequirementHash: string,
    selectedNetwork: string,
    maxDepositAmount?: string,
  ): Promise<x402HTTPClient> {
    const account = await this.signer.toViemAccount();
    const client = new x402Client((_version, requirements) => {
      const selected = requirements.find((requirement) => paymentRequirementHash(requirement) === selectedRequirementHash);
      if (!selected) {
        throw new Error("The approved x402 payment requirement was not offered.");
      }
      return selected;
    });
    const signer = account as unknown as ClientEvmSigner;
    client.register("eip155:*", new ExactEvmScheme(signer));
    if (selectedScheme === "batch-settlement") {
      client.register("eip155:*", await this.createBatchSettlementScheme(selectedNetwork, signer, maxDepositAmount));
    }
    return new x402HTTPClient(client);
  }

  private async createBatchSettlementScheme(
    selectedNetwork: string,
    signer?: ClientEvmSigner,
    maxDepositAmount?: string,
  ): Promise<BatchSettlementEvmScheme> {
    if (!SUPPORTED_BATCH_NETWORKS.has(selectedNetwork)) {
      throw new RegentError("x402_unsupported_network", `Regent x402 does not support network ${selectedNetwork}.`);
    }

    const evmSigner = signer ?? ((await this.signer.toViemAccount()) as unknown as ClientEvmSigner);
    return new BatchSettlementEvmScheme(
      toClientEvmSigner(
        evmSigner,
        createPublicClient({
          chain: viemChainForNetwork(selectedNetwork),
          transport: http(requireRpcUrlForNetwork(selectedNetwork)),
        }),
      ),
      {
        depositPolicy: { depositMultiplier: 5 },
        storage: new FileClientChannelStorage({ directory: path.join(this.store.rootDir, "channels") }),
        depositStrategy: ({ depositAmount, minimumDepositAmount }) => {
          if (maxDepositAmount === undefined) {
            throw new RegentError(
              "x402_deposit_limit_required",
              "Batch-settlement x402 payments need --max-deposit-amount so Regent knows the largest escrow you approve.",
            );
          }

          const cap = BigInt(maxDepositAmount);
          const minimum = BigInt(minimumDepositAmount);
          const proposed = BigInt(depositAmount);

          if (minimum > cap) {
            throw new RegentError(
              "x402_deposit_above_limit",
              `The required x402 deposit is ${minimum.toString()}, but --max-deposit-amount is ${cap.toString()}. Raise the limit or choose a lower-cost resource.`,
            );
          }

          return proposed > cap ? cap.toString() : undefined;
        },
      },
    );
  }
}
