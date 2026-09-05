import fs from "node:fs";

import { RegentError } from "../errors.js";
import { writeJsonFileAtomicSync } from "../paths.js";
import { decryptPrivateKey, encryptPrivateKey, type WalletKeyEnvelope } from "./wallet-crypto.js";
import { resolveDek, resolveOrCreateDek } from "./wallet-dek.js";

const PRIVATE_KEY_REGEX = /^0x[0-9a-fA-F]{64}$/;

/**
 * ESCAPE HATCH — resolve the raw private key for external SDKs that require key
 * material and cannot accept a viem account or `signMessage` callback (currently
 * only the Safe protocol-kit `SafeSdk.init({ signer })`). Everything else must
 * use the `SignerBackend` so the key never leaves the signer. Same source
 * precedence as `LocalKeySignerBackend`: env `REGENT_WALLET_PRIVATE_KEY` →
 * encrypted keystore (DEK-resolved) → fail closed.
 */
export const resolveRawPrivateKeyForExternalSdk = async (input: {
  privateKeyEnv: string;
  keystorePath: string;
}): Promise<`0x${string}`> => {
  const fromEnv = process.env[input.privateKeyEnv];
  if (fromEnv) {
    const trimmed = fromEnv.trim();
    if (!PRIVATE_KEY_REGEX.test(trimmed)) {
      throw new RegentError(
        "wallet_private_key_invalid",
        `environment variable ${input.privateKeyEnv} does not contain a valid 32-byte hex private key`,
      );
    }
    return trimmed as `0x${string}`;
  }

  return readEncryptedKeystore(input.keystorePath);
};

/** Read and decrypt the encrypted keystore file at `filePath`. */
export const readEncryptedKeystore = async (filePath: string): Promise<`0x${string}`> => {
  let raw: string;
  try {
    raw = fs.readFileSync(filePath, "utf8");
  } catch (error) {
    throw new RegentError(
      "wallet_keystore_missing",
      `Encrypted wallet keystore file not found at ${filePath}.`,
      error,
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new RegentError(
      "wallet_keystore_invalid",
      `Encrypted wallet keystore file at ${filePath} is not valid JSON.`,
      error,
    );
  }

  const { dek } = await resolveDek();
  return decryptPrivateKey(parsed, dek);
};

/**
 * Encrypt `privateKeyHex` and write the envelope to `filePath` at mode 0600
 * (atomic). The DEK is resolved-or-created via keychain/env; nothing is written
 * unencrypted, and the DEK never lands on disk.
 */
export const writeEncryptedKeystore = async (
  filePath: string,
  privateKeyHex: string,
): Promise<{ envelope: WalletKeyEnvelope; dekSource: "env" | "keychain" }> => {
  const { dek, source } = await resolveOrCreateDek();
  const envelope = encryptPrivateKey(privateKeyHex, dek);
  writeJsonFileAtomicSync(filePath, envelope);
  return { envelope, dekSource: source };
};
