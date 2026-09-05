import crypto from "node:crypto";

import { RegentError } from "../errors.js";
import { loadKeychain } from "./keychain.js";

const DEK_BYTES = 32;

/** Environment variable that supplies the data-encryption key for headless agents. */
export const DEK_ENV_VAR = "REGENTS_WALLET_KEY";
/** OS keychain service the DEK is stored under. */
export const KEYCHAIN_SERVICE = "sh.regents.cli";
/** OS keychain account (entry name) the DEK is stored under. */
export const KEYCHAIN_ACCOUNT = "wallet-dek";

/** How the active DEK was resolved, for status reporting (never the key itself). */
export type DekSource = "env" | "keychain";

const decodeDek = (encoded: string, source: DekSource): Buffer => {
  let decoded: Buffer;
  try {
    decoded = Buffer.from(encoded, "base64");
  } catch {
    throw new RegentError(
      "wallet_dek_invalid",
      `The wallet encryption key from ${source} is not valid base64.`,
    );
  }

  if (decoded.length !== DEK_BYTES) {
    throw new RegentError(
      "wallet_dek_invalid",
      `The wallet encryption key from ${source} must decode to ${DEK_BYTES} bytes.`,
    );
  }

  return decoded;
};

const UNAVAILABLE_MESSAGE =
  `No wallet encryption key is available. Set ${DEK_ENV_VAR} to a base64 32-byte key for headless agents, ` +
  "or run on a machine with an OS keychain. Regent will not read or write an unencrypted key.";

/**
 * Resolve the 32-byte data-encryption key by precedence:
 *   1. env `REGENTS_WALLET_KEY` (base64 32 bytes) — headless agents;
 *   2. OS keychain (service `sh.regents.cli`, account `wallet-dek`);
 *   3. FAIL CLOSED — throw `wallet_key_unavailable`.
 *
 * It never falls back to a plaintext key, never writes the DEK to disk, and
 * never returns without a valid key.
 */
export const resolveDek = async (): Promise<{ dek: Buffer; source: DekSource }> => {
  const fromEnv = process.env[DEK_ENV_VAR];
  if (fromEnv) {
    return { dek: decodeDek(fromEnv, "env"), source: "env" };
  }

  const keychain = await loadKeychain();
  if (keychain) {
    const stored = keychain.get(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT);
    if (stored) {
      return { dek: decodeDek(stored, "keychain"), source: "keychain" };
    }
  }

  throw new RegentError("wallet_key_unavailable", UNAVAILABLE_MESSAGE);
};

/**
 * Get the DEK for a write (import), creating and persisting a fresh one when
 * none exists:
 *   - env `REGENTS_WALLET_KEY` present → use it (do not touch the keychain);
 *   - else OS keychain available → reuse the stored DEK, or generate one and
 *     store it in the keychain;
 *   - else FAIL CLOSED — never write the DEK to disk.
 */
export const resolveOrCreateDek = async (): Promise<{ dek: Buffer; source: DekSource }> => {
  const fromEnv = process.env[DEK_ENV_VAR];
  if (fromEnv) {
    return { dek: decodeDek(fromEnv, "env"), source: "env" };
  }

  const keychain = await loadKeychain();
  if (keychain) {
    const stored = keychain.get(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT);
    if (stored) {
      return { dek: decodeDek(stored, "keychain"), source: "keychain" };
    }

    const generated = crypto.randomBytes(DEK_BYTES);
    keychain.set(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, generated.toString("base64"));
    return { dek: generated, source: "keychain" };
  }

  throw new RegentError("wallet_key_unavailable", UNAVAILABLE_MESSAGE);
};
