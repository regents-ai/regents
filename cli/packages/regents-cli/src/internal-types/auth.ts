import type { LocalAgentIdentity } from "./runtime.js";

export type SiwaAudience = "platform" | "autolaunch" | "techtree" | "regent-services";

export interface SiwaNonceRequest {
  wallet_address: `0x${string}`;
  chain_id: number;
  registry_address: `0x${string}`;
  token_id: string;
  audience: SiwaAudience;
}

export interface SiwaNonceResponse {
  code: "nonce_issued";
  data: {
    nonce: string;
    walletAddress: `0x${string}`;
    chainId: number;
    registryAddress: `0x${string}`;
    tokenId: string;
    audience: SiwaAudience;
    expiresAt: string;
  };
  meta?: Record<string, unknown>;
}

export interface SiwaVerifyRequest {
  wallet_address: `0x${string}`;
  chain_id: number;
  registry_address: `0x${string}`;
  token_id: string;
  audience: SiwaAudience;
  nonce: string;
  message: string;
  signature: `0x${string}`;
}

export interface SiwaVerifyResponse {
  code: "siwa_verified";
  data: {
    verified: true;
    walletAddress: `0x${string}`;
    chainId: number;
    registryAddress: `0x${string}`;
    tokenId: string;
    audience: SiwaAudience;
    nonce: string;
    keyId: string;
    signatureScheme: "evm_personal_sign";
    receipt: string;
    receiptIssuedAt: string;
    receiptExpiresAt: string;
  };
  meta?: Record<string, unknown>;
}

export interface SiwaSession {
  walletAddress: `0x${string}`;
  chainId: number;
  registryAddress: `0x${string}`;
  tokenId: string;
  audience: SiwaAudience;
  nonce: string;
  keyId: string;
  receipt: string;
  receiptIssuedAt: string;
  receiptExpiresAt: string;
}

export interface AppSiwaSession {
  audience: Exclude<SiwaAudience, "regent-services">;
  walletAddress: `0x${string}`;
  chainId: number;
  registryAddress: `0x${string}`;
  tokenId: string;
  sessionId: string;
  issuedAt: string;
  expiresAt: string;
}

export type RequiredAgentIdentityField = "walletAddress" | "chainId" | "registryAddress" | "tokenId";

export interface AuthStatusResponse {
  authenticated: boolean;
  session: SiwaSession | null;
  agentIdentity: LocalAgentIdentity | null;
  protectedRoutesReady: boolean;
  missingIdentityFields: RequiredAgentIdentityField[];
  appSessions: AppSiwaSession[];
}

export interface SignedAgentRequestHeaders {
  "x-siwa-receipt": string;
  "x-key-id": string;
  "x-timestamp": string;
  "signature-input": string;
  signature: string;
  "x-agent-wallet-address": `0x${string}`;
  "x-agent-chain-id": string;
  "x-agent-registry-address": `0x${string}`;
  "x-agent-token-id": string;
}
