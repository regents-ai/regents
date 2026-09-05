import fs from "node:fs";

import type {
  RegentIdentityNetwork,
  RegentIdentityReceipt,
} from "../../internal-types/index.js";

import { CommandExitError } from "../errors.js";
import { writeJsonFileAtomicSync } from "../paths.js";
import { identityCachePath, isReceiptExpired, normalizeRegentBaseUrl } from "./shared.js";

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isNetwork = (value: unknown): value is RegentIdentityNetwork =>
  value === "base" || value === "base-sepolia";

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/u;

const normalizeAddress = (value: string | undefined): `0x${string}` | null => {
  if (!value || !ADDRESS_REGEX.test(value)) {
    return null;
  }

  return value.toLowerCase() as `0x${string}`;
};

const isReceipt = (value: unknown): value is RegentIdentityReceipt => {
  if (!isObject(value)) {
    return false;
  }

  const world = value.world;
  const worldValid =
    world === undefined ||
    (isObject(world) &&
      typeof world.human_id === "string" &&
      typeof world.connected_at === "string" &&
      typeof world.source === "string" &&
      typeof world.platform_session_id === "string");

  return (
    value.version === 1 &&
    typeof value.regent_base_url === "string" &&
    isNetwork(value.network) &&
    value.provider === "coinbase-cdp" &&
    typeof value.address === "string" &&
    typeof value.agent_id === "string" &&
    typeof value.token_id === "string" &&
    typeof value.agent_registry === "string" &&
    typeof value.signer_type === "string" &&
    value.verified === "onchain" &&
    typeof value.receipt === "string" &&
    typeof value.receipt_issued_at === "string" &&
    typeof value.receipt_expires_at === "string" &&
    typeof value.cached_at === "string" &&
    (value.wallet_hint === undefined || typeof value.wallet_hint === "string") &&
    worldValid
  );
};

export const readIdentityReceipt = (): RegentIdentityReceipt | null => {
  const cachePath = identityCachePath();
  if (!fs.existsSync(cachePath)) {
    return null;
  }

  const raw = fs.readFileSync(cachePath, "utf8").trim();
  if (!raw) {
    return null;
  }

  const parsed: unknown = JSON.parse(raw);
  if (!isReceipt(parsed)) {
    return null;
  }

  return parsed;
};

export const receiptMatchesRequest = (input: {
  receipt: RegentIdentityReceipt;
  network: RegentIdentityNetwork;
  regentBaseUrl: string;
  walletHint?: string;
}): boolean => {
  const requestedAddress = normalizeAddress(input.walletHint);
  const cachedAddress = normalizeAddress(input.receipt.address);

  return (
    input.receipt.network === input.network &&
    normalizeRegentBaseUrl(input.receipt.regent_base_url) === normalizeRegentBaseUrl(input.regentBaseUrl) &&
    input.receipt.provider === "coinbase-cdp" &&
    (!input.walletHint ||
      input.receipt.wallet_hint === input.walletHint ||
      (requestedAddress !== null && cachedAddress === requestedAddress)) &&
    !isReceiptExpired(input.receipt)
  );
};

export const writeIdentityReceipt = (receipt: RegentIdentityReceipt): string => {
  const cachePath = identityCachePath();

  try {
    writeJsonFileAtomicSync(cachePath, receipt);
  } catch (error) {
    throw new CommandExitError("CACHE_WRITE_FAILED", "Could not save the Regent identity receipt.", {
      cause: error,
      details: { cachePath },
    });
  }

  return cachePath;
};

export const updateIdentityReceipt = (
  updater: (receipt: RegentIdentityReceipt) => RegentIdentityReceipt,
): RegentIdentityReceipt => {
  const receipt = readIdentityReceipt();

  if (!receipt) {
    throw new CommandExitError(
      "CACHE_WRITE_FAILED",
      "This machine does not have a saved Regent identity yet. Run `regents identity ensure` first.", { details: { cachePath: identityCachePath() } },
    );
  }

  const updated = updater(receipt);
  writeIdentityReceipt(updated);
  return updated;
};
