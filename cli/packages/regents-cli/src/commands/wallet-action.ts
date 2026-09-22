import {
  isAddress,
  isHex,
  type Address,
  type Hex,
} from "viem";

import {
  submitValidatedTransaction,
  type SupportedTransactionChainId,
  type TransactionRequest,
} from "../internal-runtime/base-contract-client.js";
import { getActiveSigner } from "../internal-runtime/agent/local-signer-backend.js";
import { loadConfig } from "../internal-runtime/config.js";

export interface JsonObject {
  readonly [key: string]: JsonValue;
}

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

export interface WalletAction {
  readonly action_id: string;
  readonly owner_product:
    | "platform"
    | "autolaunch"
    | "techtree"
    | "shared-services"
    | "ios"
    | "regents-cli";
  readonly resource: string;
  readonly resource_id: string;
  readonly action: string;
  readonly chain_id: SupportedTransactionChainId;
  readonly to: Address;
  readonly value: string;
  readonly data: Hex;
  readonly expected_signer: Address;
  readonly expires_at: string;
  readonly idempotency_key: string;
  readonly simulation: {
    readonly required: boolean;
    readonly status: "not_required" | "pending" | "passed" | "failed";
    readonly block_number?: number | null;
  };
  readonly risk_copy: string;
}

const requirePreparedTxChainId = (
  value: unknown,
): TransactionRequest["chain_id"] => {
  const chainId = Number(value);
  if (chainId === 1 || chainId === 8453 || chainId === 84532) {
    return chainId;
  }

  throw new Error(`unsupported chain for submit mode: ${String(value)}`);
};

const requireOwnerProduct = (value: unknown): WalletAction["owner_product"] => {
  const ownerProduct = requireStringField(value, "owner_product");
  if (
    ownerProduct === "platform" ||
    ownerProduct === "autolaunch" ||
    ownerProduct === "techtree" ||
    ownerProduct === "shared-services" ||
    ownerProduct === "ios" ||
    ownerProduct === "regents-cli"
  ) {
    return ownerProduct;
  }

  throw new Error("prepared wallet_action.owner_product is missing or invalid");
};

const requireStringField = (
  value: unknown,
  field: string,
): string => {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`prepared wallet_action.${field} is missing or invalid`);
  }

  return value;
};

const requireAddressField = (
  value: unknown,
  field: string,
): Address => {
  if (typeof value !== "string" || !isAddress(value)) {
    throw new Error(`prepared wallet_action.${field} is missing or invalid`);
  }

  return value;
};

const requireHexField = (
  value: unknown,
  field: string,
): Hex => {
  if (typeof value !== "string" || !isHex(value)) {
    throw new Error(`prepared wallet_action.${field} is missing or invalid`);
  }

  return value;
};

const requireSimulation = (value: unknown): WalletAction["simulation"] => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("prepared wallet_action.simulation is missing or invalid");
  }

  const simulation = value as Record<string, unknown>;
  if (typeof simulation.required !== "boolean") {
    throw new Error("prepared wallet_action.simulation.required is missing or invalid");
  }

  const status = simulation.status;
  if (
    status !== "not_required" &&
    status !== "pending" &&
    status !== "passed" &&
    status !== "failed"
  ) {
    throw new Error("prepared wallet_action.simulation.status is missing or invalid");
  }

  const blockNumber = simulation.block_number;
  if (
    blockNumber !== undefined &&
    blockNumber !== null &&
    (typeof blockNumber !== "number" ||
      !Number.isInteger(blockNumber) ||
      blockNumber < 0)
  ) {
    throw new Error("prepared wallet_action.simulation.block_number is missing or invalid");
  }

  return {
    required: simulation.required,
    status,
    ...(blockNumber === undefined ? {} : { block_number: blockNumber }),
  };
};

const extractWalletAction = (
  value: unknown,
): WalletAction | null => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const walletAction = value as Record<string, unknown>;

  return {
    action_id: requireStringField(walletAction.action_id, "action_id"),
    owner_product: requireOwnerProduct(walletAction.owner_product),
    resource: requireStringField(walletAction.resource, "resource"),
    resource_id: requireStringField(walletAction.resource_id, "resource_id"),
    action: requireStringField(walletAction.action, "action"),
    chain_id: requirePreparedTxChainId(walletAction.chain_id),
    to: requireAddressField(walletAction.to, "to"),
    value: requireHexField(walletAction.value, "value"),
    data: requireHexField(walletAction.data, "data"),
    expected_signer: requireAddressField(walletAction.expected_signer, "expected_signer"),
    expires_at: requireStringField(walletAction.expires_at, "expires_at"),
    idempotency_key: requireStringField(walletAction.idempotency_key, "idempotency_key"),
    simulation: requireSimulation(walletAction.simulation),
    risk_copy: requireStringField(walletAction.risk_copy, "risk_copy"),
  };
};

export const txRequestFromWalletAction = (
  value: unknown,
): TransactionRequest | null => {
  const walletAction = extractWalletAction(value);
  if (!walletAction) {
    return null;
  }

  return {
    chain_id: walletAction.chain_id,
    to: walletAction.to,
    value: walletAction.value,
    data: walletAction.data,
    expected_signer: walletAction.expected_signer,
    expires_at: walletAction.expires_at,
  };
};

export const submitPreparedTxRequest = async (
  txRequest: TransactionRequest,
  configPath?: string,
): Promise<`0x${string}`> => {
  const account = await (await getActiveSigner(loadConfig(configPath))).toViemAccount();
  return submitValidatedTransaction(account, txRequest);
};
