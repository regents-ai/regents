import os from "node:os";
import path from "node:path";

import type {
  LocalAgentIdentity,
  RegentIdentityNetwork,
  RegentIdentityReceipt,
  RegentResolvedIdentityProvider,
  SiwaSession,
} from "../../internal-types/index.js";

export const IDENTITY_CACHE_FILENAME = "receipt-v1.json";

export const identityCachePath = (): string =>
  path.join(os.homedir(), ".regent", "identity", IDENTITY_CACHE_FILENAME);

export const identityNetworkChainId = (network: RegentIdentityNetwork): number => {
  switch (network) {
    case "base":
      return 8453;
    case "base-sepolia":
      return 84532;
  }
};

export const identityNetworkForChainId = (chainId: number): RegentIdentityNetwork => {
  switch (chainId) {
    case 8453:
      return "base";
    case 84532:
      return "base-sepolia";
    default:
      throw new Error(`unsupported chain id: ${chainId}`);
  }
};

export const normalizeRegentBaseUrl = (input: string): string => input.replace(/\/+$/u, "");

export const isReceiptExpired = (
  receipt: Pick<RegentIdentityReceipt, "receipt_expires_at">,
  nowUnixSeconds = Math.floor(Date.now() / 1000),
): boolean => {
  const expiresAtUnixSeconds = Math.floor(Date.parse(receipt.receipt_expires_at) / 1000);
  return !Number.isFinite(expiresAtUnixSeconds) || expiresAtUnixSeconds <= nowUnixSeconds;
};

export const parseAgentRegistryAddress = (agentRegistry: string): `0x${string}` => {
  const match = agentRegistry.match(/0x[a-fA-F0-9]{40}$/u);
  if (!match) {
    throw new Error(`invalid agent registry: ${agentRegistry}`);
  }

  return match[0].toLowerCase() as `0x${string}`;
};

export const receiptAgentTokenId = (receipt: Pick<RegentIdentityReceipt, "token_id">): string =>
  receipt.token_id;

export const receiptAgentKey = (
  receipt: Pick<RegentIdentityReceipt, "agent_id">,
): string =>
  receipt.agent_id;

export const receiptToSession = (receipt: RegentIdentityReceipt): SiwaSession => ({
  walletAddress: receipt.address,
  chainId: identityNetworkChainId(receipt.network),
  registryAddress: parseAgentRegistryAddress(receipt.agent_registry),
  tokenId: receiptAgentTokenId(receipt),
  audience: "regent-services",
  nonce: receiptAgentTokenId(receipt),
  keyId: receipt.address.toLowerCase(),
  receipt: receipt.receipt,
  receiptIssuedAt: receipt.receipt_issued_at,
  receiptExpiresAt: receipt.receipt_expires_at,
});

export const receiptToIdentity = (receipt: RegentIdentityReceipt): LocalAgentIdentity => ({
  walletAddress: receipt.address,
  chainId: identityNetworkChainId(receipt.network),
  registryAddress: parseAgentRegistryAddress(receipt.agent_registry),
  tokenId: receiptAgentTokenId(receipt),
  label: providerLabel(receipt.provider),
});

export const providerLabel = (provider: RegentResolvedIdentityProvider): string => {
  switch (provider) {
    case "coinbase-cdp":
      return "Coinbase wallet";
  }
};
