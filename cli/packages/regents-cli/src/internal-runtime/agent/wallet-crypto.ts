import crypto from "node:crypto";

import { RegentError } from "../errors.js";

const ENVELOPE_VERSION = "RegentWalletKeyV1" as const;
const CIPHER = "aes-256-gcm" as const;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const DEK_BYTES = 32;

const PRIVATE_KEY_REGEX = /^0x[0-9a-fA-F]{64}$/;

/**
 * The at-rest envelope for an encrypted wallet private key. Only these fields
 * live on disk; the data-encryption key (DEK) never does.
 */
export interface WalletKeyEnvelope {
  readonly version: typeof ENVELOPE_VERSION;
  readonly cipher: typeof CIPHER;
  readonly nonce: string;
  readonly ciphertext: string;
  readonly tag: string;
  readonly created_at: string;
}

const requireDek = (dek: Buffer): void => {
  if (dek.length !== DEK_BYTES) {
    throw new RegentError(
      "wallet_dek_invalid",
      `Wallet encryption key must be ${DEK_BYTES} bytes, received ${dek.length}.`,
    );
  }
};

const requirePrivateKeyHex = (value: string): `0x${string}` => {
  if (!PRIVATE_KEY_REGEX.test(value)) {
    throw new RegentError(
      "wallet_private_key_invalid",
      "Decrypted wallet value is not a valid 32-byte hex private key.",
    );
  }

  return value as `0x${string}`;
};

/** Encrypt a private key hex string into an AES-256-GCM envelope. */
export const encryptPrivateKey = (privateKeyHex: string, dek: Buffer): WalletKeyEnvelope => {
  requireDek(dek);
  requirePrivateKeyHex(privateKeyHex);

  const nonce = crypto.randomBytes(NONCE_BYTES);
  const cipher = crypto.createCipheriv(CIPHER, dek, nonce);
  const ciphertext = Buffer.concat([cipher.update(privateKeyHex, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();

  return {
    version: ENVELOPE_VERSION,
    cipher: CIPHER,
    nonce: nonce.toString("base64"),
    ciphertext: ciphertext.toString("base64"),
    tag: tag.toString("base64"),
    created_at: new Date().toISOString(),
  };
};

const requireEnvelope = (value: unknown): WalletKeyEnvelope => {
  if (
    typeof value !== "object" ||
    value === null ||
    (value as WalletKeyEnvelope).version !== ENVELOPE_VERSION ||
    (value as WalletKeyEnvelope).cipher !== CIPHER ||
    typeof (value as WalletKeyEnvelope).nonce !== "string" ||
    typeof (value as WalletKeyEnvelope).ciphertext !== "string" ||
    typeof (value as WalletKeyEnvelope).tag !== "string"
  ) {
    throw new RegentError(
      "wallet_keystore_invalid",
      "The wallet keystore file is not a valid RegentWalletKeyV1 envelope.",
    );
  }

  return value as WalletKeyEnvelope;
};

/**
 * Decrypt an AES-256-GCM envelope back to the private key hex. The GCM auth tag
 * is verified, so any tampering (or a wrong DEK) throws rather than returning a
 * corrupted key.
 */
export const decryptPrivateKey = (envelope: unknown, dek: Buffer): `0x${string}` => {
  requireDek(dek);
  const parsed = requireEnvelope(envelope);

  const nonce = Buffer.from(parsed.nonce, "base64");
  const tag = Buffer.from(parsed.tag, "base64");
  if (nonce.length !== NONCE_BYTES || tag.length !== TAG_BYTES) {
    throw new RegentError(
      "wallet_keystore_invalid",
      "The wallet keystore file has an invalid nonce or authentication tag.",
    );
  }

  const decipher = crypto.createDecipheriv(CIPHER, dek, nonce);
  decipher.setAuthTag(tag);

  let plaintext: string;
  try {
    plaintext = Buffer.concat([
      decipher.update(Buffer.from(parsed.ciphertext, "base64")),
      decipher.final(),
    ]).toString("utf8");
  } catch (error) {
    throw new RegentError(
      "wallet_keystore_tampered",
      "The wallet keystore could not be decrypted; the file may be tampered or the encryption key is wrong.",
      error,
    );
  }

  return requirePrivateKeyHex(plaintext);
};
