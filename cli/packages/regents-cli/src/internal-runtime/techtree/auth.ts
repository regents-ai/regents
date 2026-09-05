import type { LocalAgentIdentity, RegentConfig, SiwaSession } from "../../internal-types/index.js";

import { AuthError } from "../errors.js";
import { readIdentityReceipt } from "../identity/cache.js";
import { resolveIdentitySigner, resolveSignerFromReceipt, type IdentitySigner } from "../identity/providers.js";
import { identityNetworkForChainId } from "../identity/shared.js";
import { receiptToIdentity } from "../identity/shared.js";
import type { StateStore } from "../store/state-store.js";
import type { SessionStore } from "../store/session-store.js";

export interface AuthenticatedAgentContext {
  session: SiwaSession;
  identity: LocalAgentIdentity;
}

export interface AuthenticatedAgentSigningContext extends AuthenticatedAgentContext {
  signer: IdentitySigner;
}

export function requireAuthenticatedAgentContext(
  sessionStore: SessionStore,
  stateStore: StateStore,
): AuthenticatedAgentContext {
  const session = sessionStore.getSiwaSession();
  if (!session) {
    throw new AuthError("siwa_session_missing", "no Regent identity receipt found; run `regents identity ensure`");
  }

  if (sessionStore.isReceiptExpired()) {
    throw new AuthError("siwa_receipt_expired", "Regent identity receipt is expired; run `regents identity ensure` again");
  }

  const receipt = readIdentityReceipt();
  const identity = receipt ? receiptToIdentity(receipt) : stateStore.read().agent;
  if (!identity?.walletAddress || typeof identity.chainId !== "number") {
    throw new AuthError(
      "agent_identity_missing",
      "current agent identity is missing; run `regents identity ensure` first",
    );
  }

  if (!identity.registryAddress || !identity.tokenId) {
    throw new AuthError(
      "agent_identity_missing",
      "current Techtree identity is missing registry and token binding; run `regents identity ensure` again",
    );
  }

  if (!session.registryAddress || !session.tokenId) {
    throw new AuthError(
      "siwa_session_incomplete",
      "active SIWA session is missing Agent account details; run `regents auth login` again",
    );
  }

  const mismatches = [
    session.walletAddress.toLowerCase() !== identity.walletAddress.toLowerCase() ? "walletAddress" : null,
    session.chainId !== identity.chainId ? "chainId" : null,
    session.registryAddress.toLowerCase() !== identity.registryAddress.toLowerCase() ? "registryAddress" : null,
    session.tokenId !== identity.tokenId ? "tokenId" : null,
  ].filter((value): value is string => value !== null);

  if (mismatches.length > 0) {
    throw new AuthError(
      "agent_identity_mismatch",
      "stored Regent identity does not match the active SIWA session; run `regents identity ensure` again",
    );
  }

  return {
    session,
    identity,
  };
}

export async function resolveAuthenticatedAgentSigningContext(
  config: RegentConfig,
  sessionStore: SessionStore,
  stateStore: StateStore,
  timeoutMs = config.services.siwa.requestTimeoutMs,
): Promise<AuthenticatedAgentSigningContext> {
  const { session, identity } = requireAuthenticatedAgentContext(sessionStore, stateStore);
  const receipt = readIdentityReceipt();
  const signer = receipt
    ? await resolveSignerFromReceipt(receipt, { config, timeoutMs })
    : await resolveIdentitySigner({
        provider: "coinbase-cdp",
        network: identityNetworkForChainId(identity.chainId),
        walletHint: identity.walletAddress,
        config,
        timeoutMs,
        expectedAddress: identity.walletAddress,
      });

  return {
    session,
    identity,
    signer,
  };
}
