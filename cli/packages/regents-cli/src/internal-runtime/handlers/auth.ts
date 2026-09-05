import type {
  AuthStatusResponse,
  RequiredAgentIdentityField,
  SiwaAudience,
  SiwaVerifyResponse,
} from "../../internal-types/index.js";

import { getCurrentAgentIdentity } from "../agent/profile.js";
import { AuthError } from "../errors.js";
import { readIdentityReceipt } from "../identity/cache.js";
import { ensureIdentity } from "../identity/ensure.js";
import { resolveSignerFromReceipt } from "../identity/providers.js";
import { identityNetworkForChainId } from "../identity/shared.js";
import { receiptToIdentity } from "../identity/shared.js";
import type { RuntimeContext } from "../runtime.js";
import { requireAuthenticatedAgentContext } from "../techtree/auth.js";
import {
  buildSiwaMessage,
  siwaAudienceStatement,
  SiwaClient,
  siwaMessageLocation,
} from "../siwa/siwa.js";

const normalizeAudience = (value: string): SiwaAudience => {
  switch (value) {
    case "platform":
    case "autolaunch":
    case "techtree":
    case "regent-services":
      return value;
    default:
      throw new AuthError(
        "invalid_audience",
        "Shared Regent auth audience must be one of platform, autolaunch, techtree, or regent-services.",
      );
  }
};

export async function handleAuthSiwaLogin(
  ctx: RuntimeContext,
  params: {
    walletAddress?: `0x${string}`;
    chainId?: number;
    registryAddress?: never;
    tokenId?: never;
    audience?: string;
  },
): Promise<SiwaVerifyResponse> {
  const walletHint = params.walletAddress;
  const chainId = params.chainId ?? ctx.config.auth.defaultChainId;
  let network;
  try {
    network = identityNetworkForChainId(chainId);
  } catch {
    throw new AuthError(
      "unsupported_chain_id",
      "Shared Regent auth only supports Base and Base Sepolia for agent sign-in.",
    );
  }
  const audience = normalizeAudience(params.audience ?? ctx.config.auth.audience);
  const authClient = new SiwaClient(
    ctx.config.services.siwa.baseUrl,
    ctx.config.services.siwa.requestTimeoutMs,
    ctx.config,
  );

  await ensureIdentity({
    network,
    forceRefresh: false,
    walletHint,
    timeoutSeconds: Math.max(1, Math.ceil(ctx.config.services.siwa.requestTimeoutMs / 1000)),
    config: ctx.config,
  });

  const identityReceipt = readIdentityReceipt();
  if (!identityReceipt) {
    throw new AuthError(
      "agent_identity_missing",
      "Regent could not load the Base ERC-8004 identity needed for shared agent sign-in.",
    );
  }

  const signer = await resolveSignerFromReceipt(identityReceipt, {
    config: ctx.config,
    timeoutMs: ctx.config.services.siwa.requestTimeoutMs,
  });
  const identity = receiptToIdentity(identityReceipt);
  const walletAddress = signer.address;
  const registryAddress = identity.registryAddress;
  const tokenId = identity.tokenId;

  if (!registryAddress || !tokenId) {
    throw new AuthError(
      "agent_identity_missing",
      "Regent could not load the Base ERC-8004 identity needed for shared agent sign-in.",
    );
  }

  const nonceResponse = await authClient.requestNonce({
    wallet_address: walletAddress,
    chain_id: identity.chainId,
    registry_address: registryAddress,
    token_id: tokenId,
    audience,
  });

  const location = siwaMessageLocation(ctx.config.services.platform.baseUrl);
  const message = buildSiwaMessage({
    domain: location.domain,
    uri: location.uri,
    walletAddress,
    chainId: identity.chainId,
    registryAddress,
    tokenId,
    nonce: nonceResponse.data.nonce,
    statement: siwaAudienceStatement(audience),
  });

  const signature = await signer.signMessage(message);
  const verifyResponse = await authClient.verify({
    wallet_address: walletAddress,
    chain_id: identity.chainId,
    registry_address: registryAddress,
    token_id: tokenId,
    audience,
    nonce: nonceResponse.data.nonce,
    message,
    signature,
  });

  const session = {
    walletAddress: verifyResponse.data.walletAddress,
    chainId: verifyResponse.data.chainId,
    registryAddress: verifyResponse.data.registryAddress,
    tokenId: verifyResponse.data.tokenId,
    audience: verifyResponse.data.audience,
    nonce: verifyResponse.data.nonce,
    keyId: verifyResponse.data.keyId,
    receipt: verifyResponse.data.receipt,
    receiptIssuedAt: verifyResponse.data.receiptIssuedAt,
    receiptExpiresAt: verifyResponse.data.receiptExpiresAt,
  };

  ctx.sessionStore.setSiwaSession(session);
  ctx.stateStore.patch({ agent: identity });

  return verifyResponse;
}

export async function handleAuthSiwaStatus(ctx: RuntimeContext): Promise<AuthStatusResponse> {
  const session = ctx.sessionStore.getSiwaSession();
  const agentIdentity = getCurrentAgentIdentity(ctx.stateStore);
  const authenticated = !!session && !ctx.sessionStore.isReceiptExpired();
  const missingIdentityFields: RequiredAgentIdentityField[] = [
    agentIdentity?.walletAddress ? null : "walletAddress",
    typeof agentIdentity?.chainId === "number" ? null : "chainId",
    agentIdentity?.registryAddress ? null : "registryAddress",
    agentIdentity?.tokenId ? null : "tokenId",
  ].filter((field): field is RequiredAgentIdentityField => field !== null);
  let protectedRoutesReady = false;
  if (authenticated && missingIdentityFields.length === 0) {
    try {
      requireAuthenticatedAgentContext(ctx.sessionStore, ctx.stateStore);
      protectedRoutesReady = true;
    } catch {
      protectedRoutesReady = false;
    }
  }

  if (!authenticated) {
    return {
      authenticated: false,
      session,
      agentIdentity,
      protectedRoutesReady,
      missingIdentityFields,
      appSessions: ctx.sessionStore.getAppSiwaSessions(),
    };
  }

  return {
    authenticated: true,
    session,
    agentIdentity,
    protectedRoutesReady,
    missingIdentityFields,
    appSessions: ctx.sessionStore.getAppSiwaSessions(),
  };
}

export async function handleAuthSiwaLogout(ctx: RuntimeContext): Promise<{ ok: true }> {
  ctx.sessionStore.clearSiwaSession();
  return { ok: true };
}
