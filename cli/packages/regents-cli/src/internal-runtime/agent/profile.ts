import type { LocalAgentIdentity } from "../../internal-types/index.js";
import type { RequiredAgentIdentityField } from "../../internal-types/index.js";

import { AuthError } from "../errors.js";
import { readIdentityReceipt } from "../identity/cache.js";
import { receiptToIdentity } from "../identity/shared.js";
import type { StateStore } from "../store/state-store.js";

export type { LocalAgentIdentity } from "../../internal-types/index.js";

export function getCurrentAgentIdentity(stateStore: StateStore): LocalAgentIdentity | null {
  const receipt = readIdentityReceipt();
  if (receipt) {
    return receiptToIdentity(receipt);
  }

  const storedIdentity = stateStore.read().agent;
  if (storedIdentity) {
    return storedIdentity;
  }

  return null;
}

export function getMissingAgentIdentityFields(stateStore: StateStore): RequiredAgentIdentityField[] {
  const identity = getCurrentAgentIdentity(stateStore);

  return [
    identity?.walletAddress ? null : "walletAddress",
    typeof identity?.chainId === "number" ? null : "chainId",
    identity?.registryAddress ? null : "registryAddress",
    identity?.tokenId ? null : "tokenId",
  ].filter((field): field is RequiredAgentIdentityField => field !== null);
}

export function requireCurrentAgentIdentity(stateStore: StateStore): LocalAgentIdentity {
  const identity = getCurrentAgentIdentity(stateStore);
  if (!identity) {
    throw new AuthError(
      "agent_identity_missing",
      "current agent identity is missing; run `regents identity ensure` first",
    );
  }

  return identity;
}
