import path from "node:path";

import type {
  LocalAgentIdentity,
  RegentConfig,
  SiwaAudience,
  SiwaSession,
} from "../internal-types/index.js";

import { loadConfig, StateStore } from "../internal-runtime/index.js";
import { readIdentityReceipt } from "../internal-runtime/identity/cache.js";
import { receiptToIdentity } from "../internal-runtime/identity/shared.js";
import { resolveAuthenticatedAgentSigningContext } from "../internal-runtime/techtree/auth.js";
import { buildSignerBackedAgentHeaders } from "../internal-runtime/siwa/signing.js";
import { SessionStore } from "../internal-runtime/store/session-store.js";

export const loadAgentAuthState = (
  configPath?: string,
): {
  config: RegentConfig;
  stateStore: StateStore;
  sessionStore: SessionStore;
  session: SiwaSession | null;
  identity: LocalAgentIdentity | null;
} => {
  const config = loadConfig(configPath);
  const stateFilePath = path.join(config.runtime.stateDir, "runtime-state.json");
  const stateStore = new StateStore(stateFilePath);
  const sessionStore = new SessionStore(stateStore);
  const receipt = readIdentityReceipt();
  const session = sessionStore.getSiwaSession();
  const storedIdentity = stateStore.read().agent;
  const identity =
    receipt
      ? receiptToIdentity(receipt)
      : storedIdentity ??
        (session
          ? {
              walletAddress: session.walletAddress,
              chainId: session.chainId,
              ...(session.registryAddress ? { registryAddress: session.registryAddress } : {}),
              ...(session.tokenId ? { tokenId: session.tokenId } : {}),
            }
          : null);

  return {
    config,
    stateStore,
    sessionStore,
    session,
    identity,
  };
};

interface AgentAuthStateOptions {
  readonly audience?: SiwaAudience;
}

const authLoginCommand = (audience?: SiwaAudience): string =>
  audience ? `regents auth login --audience ${audience}` : "regents auth login";

const authProductName = (audience?: SiwaAudience): string =>
  audience === "autolaunch" ? "Autolaunch" : "Regent";

const requireSessionAudience = (
  session: SiwaSession,
  audience?: SiwaAudience,
): void => {
  if (!audience || session.audience === audience) {
    return;
  }

  throw new Error(
    `This command needs a ${authProductName(audience)} sign-in. Run \`${authLoginCommand(audience)}\` first.`,
  );
};

export const requireAgentAuthState = (
  configPath?: string,
  options?: AgentAuthStateOptions,
): {
  config: RegentConfig;
  session: SiwaSession;
  identity: LocalAgentIdentity;
} => {
  const { config, sessionStore, session, identity } = loadAgentAuthState(configPath);

  if (!session) {
    throw new Error(`Run \`${authLoginCommand(options?.audience)}\` before using this command.`);
  }

  if (sessionStore.isReceiptExpired()) {
    throw new Error(
      `Your saved ${authProductName(options?.audience)} sign-in expired. Run \`${authLoginCommand(options?.audience)}\` again.`,
    );
  }

  requireSessionAudience(session, options?.audience);

  if (!identity?.walletAddress || typeof identity.chainId !== "number") {
    throw new Error("This machine does not have a saved Regent identity yet. Run `regents identity ensure` first.");
  }

  if (!identity.registryAddress || !identity.tokenId) {
    throw new Error("This command needs a saved Agent account. Run `regents identity ensure` first.");
  }

  return {
    config,
    session,
    identity,
  };
};

export const buildAgentAuthHeaders = async (
  input: {
    method: string;
    path: string;
    body?: string;
    configPath?: string;
    audience: SiwaAudience;
  },
): Promise<Record<string, string>> => {
  requireAgentAuthState(input.configPath, {
    audience: input.audience,
  });
  const { config, stateStore, sessionStore } = loadAgentAuthState(input.configPath);
  const { session, identity, signer } = await resolveAuthenticatedAgentSigningContext(
    config,
    sessionStore,
    stateStore,
    config.services.siwa.requestTimeoutMs,
  );
  requireSessionAudience(session, input.audience);
  if (!identity.registryAddress || !identity.tokenId) {
    throw new Error("This command needs a saved Agent account. Run `regents identity ensure` first.");
  }

  return buildSignerBackedAgentHeaders({
    method: input.method,
    path: input.path,
    ...(input.body === undefined ? {} : { body: input.body }),
    walletAddress: identity.walletAddress,
    chainId: identity.chainId,
    registryAddress: identity.registryAddress,
    tokenId: identity.tokenId,
    receipt: session.receipt,
    signMessage: signer.signMessage,
  });
};
