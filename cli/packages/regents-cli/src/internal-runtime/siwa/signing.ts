/**
 * Must remain compatible with the current SIWA request verification contract.
 * Do not change covered header names, casing assumptions, or canonical message
 * construction without updating the matching server-side verifier.
 */
import crypto from "node:crypto";

import { signPersonalMessage } from "../agent/wallet.js";

export const HTTP_SIGNATURE_BASE_COMPONENTS = [
  "@method",
  "@path",
  "x-siwa-receipt",
  "x-key-id",
  "x-timestamp",
  "x-agent-wallet-address",
  "x-agent-chain-id",
] as const;

export interface BuildSignedHeadersInput {
  method: string;
  path: string;
  body?: string;
  walletAddress: `0x${string}`;
  chainId: number;
  registryAddress: `0x${string}`;
  tokenId: string;
  receipt: string;
  privateKey: `0x${string}`;
  nowUnixSeconds?: number;
  expiresInSeconds?: number;
  nonce?: string;
}

export interface BuildSignerBackedHeadersInput
  extends Omit<BuildSignedHeadersInput, "privateKey"> {
  signMessage(message: string): Promise<`0x${string}`>;
}

export interface ParsedSignatureInputHeader {
  label: string;
  coveredComponents: string[];
  params: {
    created?: number;
    expires?: number;
    nonce?: string;
    keyid?: string;
  };
}

export function parseSignatureInputHeader(signatureInput: string): ParsedSignatureInputHeader | null {
  const trimmed = signatureInput.trim();
  const match = trimmed.match(/^([A-Za-z0-9_-]+)=(\(([^)]*)\))(?:;(.*))?$/);
  if (!match) {
    return null;
  }

  const [, label, , covered, paramsPart] = match;
  const coveredComponents = covered
    .split(" ")
    .map((component) => component.trim().replace(/^"|"$/g, ""))
    .filter(Boolean);

  const params: ParsedSignatureInputHeader["params"] = {};
  for (const chunk of (paramsPart ?? "").split(";")) {
    if (!chunk.trim()) {
      continue;
    }

    const [rawKey, ...rest] = chunk.split("=");
    const key = rawKey.trim();
    const rawValue = rest.join("=").trim().replace(/^"|"$/g, "");

    if (key === "created" || key === "expires") {
      const parsed = Number.parseInt(rawValue, 10);
      if (Number.isSafeInteger(parsed)) {
        params[key] = parsed;
      }
      continue;
    }

    if (key === "nonce" || key === "keyid") {
      params[key] = rawValue;
    }
  }

  return {
    label,
    coveredComponents,
    params,
  };
}

const signatureParamsFromHeader = (signatureInput: string): string => {
  return signatureInput.slice(5);
};

const toSig1SignatureHeader = (signatureHex: `0x${string}`): string => {
  const signatureBase64 = Buffer.from(signatureHex.slice(2), "hex").toString("base64");
  return `sig1=:${signatureBase64}:`;
};

export function contentDigestForBody(body: string): string {
  const digest = crypto.createHash("sha256").update(body).digest("base64");
  return `sha-256=:${digest}:`;
}

export function buildSignatureInputString(input: {
  coveredComponents: readonly string[];
  created: number;
  expires: number;
  nonce: string;
  keyId: string;
}): string {
  const signatureParams =
    `(${input.coveredComponents.map((component) => `"${component}"`).join(" ")})` +
    `;created=${input.created}` +
    `;expires=${input.expires}` +
    `;nonce="${input.nonce}"` +
    `;keyid="${input.keyId}"`;

  return `sig1=${signatureParams}`;
}

export function buildHttpSignatureSigningMessage(input: {
  method: string;
  path: string;
  headers: Record<string, string>;
}): string {
  const normalizedHeaders = Object.fromEntries(
    Object.entries(input.headers).map(([key, value]) => [key.toLowerCase(), value.trim()]),
  );
  const parsed = parseSignatureInputHeader(normalizedHeaders["signature-input"] ?? "");
  const signatureParams = signatureParamsFromHeader(normalizedHeaders["signature-input"] ?? "");
  const components = parsed?.coveredComponents ?? [];
  const lines = components.map((component) => {
    if (component === "@method") {
      return `"@method": ${input.method.toLowerCase()}`;
    }

    if (component === "@path") {
      return `"@path": ${input.path}`;
    }

    return `"${component}": ${normalizedHeaders[component] ?? ""}`;
  });

  lines.push(`"@signature-params": ${signatureParams}`);

  return lines.join("\n");
}

export function coveredComponentsForAgentHeaders(input: {
  includeContentDigest: boolean;
}): string[] {
  return [
    ...HTTP_SIGNATURE_BASE_COMPONENTS,
    ...(input.includeContentDigest ? ["content-digest"] : []),
    "x-agent-registry-address",
    "x-agent-token-id",
  ];
}

export async function buildSignedAgentHeaders(
  input: BuildSignedHeadersInput,
): Promise<Record<string, string>> {
  return buildSignerBackedAgentHeaders({
    ...input,
    signMessage: async (message) => signPersonalMessage(input.privateKey, message),
  });
}

export async function buildSignerBackedAgentHeaders(
  input: BuildSignerBackedHeadersInput,
): Promise<Record<string, string>> {
  const created = input.nowUnixSeconds ?? Math.floor(Date.now() / 1000);
  const expires = created + (input.expiresInSeconds ?? 120);
  const nonce = input.nonce ?? `sig-nonce-${crypto.randomUUID()}`;
  const keyId = input.walletAddress.toLowerCase();
  const contentDigest = typeof input.body === "string" ? contentDigestForBody(input.body) : undefined;

  const unsignedHeaders: Record<string, string> = {
    "x-siwa-receipt": input.receipt,
    "x-key-id": keyId,
    "x-timestamp": String(created),
    "x-agent-wallet-address": input.walletAddress,
    "x-agent-chain-id": String(input.chainId),
    "x-agent-registry-address": input.registryAddress,
    "x-agent-token-id": input.tokenId,
    ...(contentDigest ? { "content-digest": contentDigest } : {}),
  };
  const coveredComponents = coveredComponentsForAgentHeaders({
    includeContentDigest: typeof contentDigest === "string",
  });

  const signatureInput = buildSignatureInputString({
    coveredComponents,
    created,
    expires,
    nonce,
    keyId,
  });

  const signingMessage = buildHttpSignatureSigningMessage({
    method: input.method,
    path: input.path,
    headers: {
      ...unsignedHeaders,
      "signature-input": signatureInput,
    },
  });

  const signature = await input.signMessage(signingMessage);

  return {
    ...unsignedHeaders,
    "signature-input": signatureInput,
    signature: toSig1SignatureHeader(signature),
  };
}
