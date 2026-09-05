export type RegentIdentityProvider = "coinbase-cdp";
export type RegentResolvedIdentityProvider = RegentIdentityProvider;
export type RegentIdentityNetwork = "base" | "base-sepolia";

export interface IdentityStatusRequest {
  network: RegentIdentityNetwork;
  address: `0x${string}`;
  provider: RegentResolvedIdentityProvider;
  wallet_hint?: string;
}

export interface IdentityStatusResponse {
  ok: true;
  code: "identity_status_resolved";
  data: {
    network: RegentIdentityNetwork;
    address: `0x${string}`;
    provider: RegentResolvedIdentityProvider;
    registered: boolean;
    verified: "unregistered" | "onchain";
    agent_id?: string;
    token_id?: string;
    agent_registry?: string;
    receipt_expires_at?: string;
  };
  meta?: Record<string, unknown>;
}

export interface IdentityRegistrationIntentRequest {
  network: RegentIdentityNetwork;
  address: `0x${string}`;
  provider: RegentResolvedIdentityProvider;
  wallet_hint?: string;
}

export interface IdentityRegistrationIntentResponse {
  ok: true;
  code: "identity_registration_intent_created";
  data: {
    intent_id: string;
    intent_kind: string;
    signing_payload: {
      message: string;
      [key: string]: unknown;
    };
  };
  meta?: Record<string, unknown>;
}

export interface IdentityRegistrationCompletionRequest {
  intent_id: string;
  address: `0x${string}`;
  signature: `0x${string}`;
  message?: string;
}

export interface IdentityRegistrationCompletionResponse {
  ok: true;
  code: "identity_registration_completed";
  data: {
    registered: true;
    agent_id: string;
    token_id: string;
    agent_registry: string;
  };
  meta?: Record<string, unknown>;
}

export interface IdentitySiwaNonceRequest {
  network: RegentIdentityNetwork;
  address: `0x${string}`;
  token_id: string;
  agent_registry: string;
}

export interface IdentitySiwaNonceResponse {
  ok: true;
  code: "identity_siwa_nonce_issued";
  data: {
    nonce_token: string;
    message: string;
    address: `0x${string}`;
    agent_id: string;
    token_id: string;
    agent_registry: string;
    expires_at: string;
  };
  meta?: Record<string, unknown>;
}

export interface IdentitySiwaVerifyRequest {
  network: RegentIdentityNetwork;
  message: string;
  signature: `0x${string}`;
  nonce_token: string;
  address?: `0x${string}`;
  token_id?: string;
  agent_registry?: string;
}

export interface IdentitySiwaVerifyResponse {
  ok: true;
  code: "identity_siwa_verified";
  data: {
    verified: "onchain";
    network: RegentIdentityNetwork;
    address: `0x${string}`;
    agent_id: string;
    token_id: string;
    agent_registry: string;
    signer_type: string;
    receipt: string;
    receipt_issued_at: string;
    receipt_expires_at: string;
  };
  meta?: Record<string, unknown>;
}

export interface RegentIdentityReceipt {
  version: 1;
  regent_base_url: string;
  network: RegentIdentityNetwork;
  provider: RegentResolvedIdentityProvider;
  address: `0x${string}`;
  agent_id: string;
  token_id: string;
  agent_registry: string;
  signer_type: string;
  verified: "onchain";
  receipt: string;
  receipt_issued_at: string;
  receipt_expires_at: string;
  cached_at: string;
  wallet_hint?: string;
  world?: {
    human_id: string;
    connected_at: string;
    source: string;
    platform_session_id: string;
  };
}

export interface IdentityEnsureSuccess {
  status: "ok";
  provider: RegentResolvedIdentityProvider;
  network: RegentIdentityNetwork;
  address: `0x${string}`;
  agent_id: string;
  token_id: string;
  agent_registry: string;
  verified: "onchain";
  receipt_expires_at: string;
  cache_path: string;
}

export interface IdentityEnsureFailure {
  status: "error";
  code:
    | "COINBASE_CDP_MISSING"
    | "REGISTRATION_FAILED"
    | "SIWA_VERIFY_FAILED"
    | "CACHE_WRITE_FAILED"
    | "SERVICE_UNAVAILABLE"
    | "UNSUPPORTED_NETWORK";
  message: string;
  provider?: RegentResolvedIdentityProvider;
  details?: Record<string, unknown>;
}
