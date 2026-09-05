import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { privateKeyToAccount } from "viem/accounts";

import {
  decryptPrivateKey,
  encryptPrivateKey,
  type WalletKeyEnvelope,
} from "../../src/internal-runtime/agent/wallet-crypto.js";
import {
  resolveDek,
  resolveOrCreateDek,
  DEK_ENV_VAR,
  KEYCHAIN_SERVICE,
  KEYCHAIN_ACCOUNT,
} from "../../src/internal-runtime/agent/wallet-dek.js";
import {
  readEncryptedKeystore,
  writeEncryptedKeystore,
} from "../../src/internal-runtime/agent/wallet-keystore.js";
import { LocalKeySignerBackend } from "../../src/internal-runtime/agent/local-signer-backend.js";
import {
  setKeychainForTesting,
  resetKeychainForTesting,
  type KeychainApi,
} from "../../src/internal-runtime/agent/keychain.js";

// A test private key (well-known Hardhat account #0). Never a real key.
const TEST_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;
const TEST_DEK = crypto.randomBytes(32);

// In-memory fake keychain injected through the shim seam; never touches the OS.
const makeFakeKeychain = (): KeychainApi & { store: Map<string, string> } => {
  const store = new Map<string, string>();
  const key = (service: string, account: string) => `${service}::${account}`;
  return {
    store,
    get: (service, account) => store.get(key(service, account)) ?? null,
    set: (service, account, secret) => {
      store.set(key(service, account), secret);
    },
    delete: (service, account) => store.delete(key(service, account)),
  };
};

let tempDir = "";
const savedEnv = { dek: process.env[DEK_ENV_VAR] };

beforeEach(() => {
  tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-signer-core-"));
  delete process.env[DEK_ENV_VAR];
});

afterEach(() => {
  resetKeychainForTesting();
  if (savedEnv.dek === undefined) {
    delete process.env[DEK_ENV_VAR];
  } else {
    process.env[DEK_ENV_VAR] = savedEnv.dek;
  }
  fs.rmSync(tempDir, { recursive: true, force: true });
});

describe("wallet-crypto AES-256-GCM envelope", () => {
  it("round-trips: decrypt(encrypt(key)) === key", () => {
    const envelope = encryptPrivateKey(TEST_KEY, TEST_DEK);
    expect(decryptPrivateKey(envelope, TEST_DEK)).toBe(TEST_KEY);
  });

  it("produces a RegentWalletKeyV1 envelope shape", () => {
    const envelope = encryptPrivateKey(TEST_KEY, TEST_DEK);
    expect(envelope.version).toBe("RegentWalletKeyV1");
    expect(envelope.cipher).toBe("aes-256-gcm");
    expect(typeof envelope.nonce).toBe("string");
    expect(typeof envelope.ciphertext).toBe("string");
    expect(typeof envelope.tag).toBe("string");
    expect(typeof envelope.created_at).toBe("string");
  });

  it("throws on a tampered ciphertext (GCM tag mismatch)", () => {
    const envelope = encryptPrivateKey(TEST_KEY, TEST_DEK);
    const flippedCipher = Buffer.from(envelope.ciphertext, "base64");
    flippedCipher[0] ^= 0xff;
    const tampered: WalletKeyEnvelope = { ...envelope, ciphertext: flippedCipher.toString("base64") };
    expect(() => decryptPrivateKey(tampered, TEST_DEK)).toThrowError(/tamper|decrypt/i);
  });

  it("throws with the wrong DEK", () => {
    const envelope = encryptPrivateKey(TEST_KEY, TEST_DEK);
    expect(() => decryptPrivateKey(envelope, crypto.randomBytes(32))).toThrow();
  });
});

describe("DEK resolution precedence and fail-closed", () => {
  it("uses env REGENTS_WALLET_KEY and does NOT consult the keychain", async () => {
    const fake = makeFakeKeychain();
    setKeychainForTesting(fake);
    const dek = crypto.randomBytes(32);
    process.env[DEK_ENV_VAR] = dek.toString("base64");

    const resolved = await resolveDek();
    expect(resolved.source).toBe("env");
    expect(resolved.dek.equals(dek)).toBe(true);
    expect(fake.store.size).toBe(0); // keychain never touched
  });

  it("uses the OS keychain when env is unset", async () => {
    const fake = makeFakeKeychain();
    const dek = crypto.randomBytes(32);
    fake.set(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, dek.toString("base64"));
    setKeychainForTesting(fake);

    const resolved = await resolveDek();
    expect(resolved.source).toBe("keychain");
    expect(resolved.dek.equals(dek)).toBe(true);
  });

  it("FAILS CLOSED when neither env nor keychain has a key", async () => {
    setKeychainForTesting(null); // no keychain available
    await expect(resolveDek()).rejects.toMatchObject({ code: "wallet_key_unavailable" });
  });

  it("resolveOrCreateDek generates and stores a DEK in the keychain when none exists", async () => {
    const fake = makeFakeKeychain();
    setKeychainForTesting(fake);

    const created = await resolveOrCreateDek();
    expect(created.source).toBe("keychain");
    expect(created.dek.length).toBe(32);
    // Persisted for next time.
    expect(fake.get(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)).toBe(created.dek.toString("base64"));

    const again = await resolveOrCreateDek();
    expect(again.dek.equals(created.dek)).toBe(true);
  });

  it("resolveOrCreateDek FAILS CLOSED (no keychain, no env) — never writes a DEK to disk", async () => {
    setKeychainForTesting(null);
    await expect(resolveOrCreateDek()).rejects.toMatchObject({ code: "wallet_key_unavailable" });
  });
});

describe("encrypted keystore file at rest", () => {
  const keystorePath = () => path.join(tempDir, "keys", "agent-wallet.json");

  it("writes an envelope that does NOT contain the plaintext key, at mode 0600", async () => {
    process.env[DEK_ENV_VAR] = TEST_DEK.toString("base64");
    await writeEncryptedKeystore(keystorePath(), TEST_KEY);

    const raw = fs.readFileSync(keystorePath(), "utf8");
    expect(raw).not.toContain(TEST_KEY);
    expect(raw).not.toContain(TEST_KEY.slice(2)); // not even without 0x
    const parsed = JSON.parse(raw) as WalletKeyEnvelope;
    expect(parsed.version).toBe("RegentWalletKeyV1");

    const mode = fs.statSync(keystorePath()).mode & 0o777;
    expect(mode).toBe(0o600);
  });

  it("round-trips through the keystore file (write then read)", async () => {
    process.env[DEK_ENV_VAR] = TEST_DEK.toString("base64");
    await writeEncryptedKeystore(keystorePath(), TEST_KEY);
    expect(await readEncryptedKeystore(keystorePath())).toBe(TEST_KEY);
  });

  it("reading FAILS CLOSED when the DEK is unavailable", async () => {
    process.env[DEK_ENV_VAR] = TEST_DEK.toString("base64");
    await writeEncryptedKeystore(keystorePath(), TEST_KEY);

    delete process.env[DEK_ENV_VAR];
    setKeychainForTesting(null);
    await expect(readEncryptedKeystore(keystorePath())).rejects.toMatchObject({
      code: "wallet_key_unavailable",
    });
  });
});

describe("LocalKeySignerBackend adapter correctness", () => {
  const keystorePath = () => path.join(tempDir, "keys", "agent-wallet.json");
  const ENV_KEY_VAR = "REGENT_WALLET_PRIVATE_KEY";

  afterEach(() => {
    delete process.env[ENV_KEY_VAR];
  });

  it("from an env raw key: address + signMessage match privateKeyToAccount", async () => {
    delete process.env[DEK_ENV_VAR];
    process.env[ENV_KEY_VAR] = TEST_KEY;
    const backend = new LocalKeySignerBackend({
      privateKeyEnv: ENV_KEY_VAR,
      keystorePath: keystorePath(),
    });

    const reference = privateKeyToAccount(TEST_KEY);
    expect(await backend.address()).toBe(reference.address);
    expect(backend.keySource).toBe("env");

    const message = "regent signer parity check";
    expect(await backend.signMessage(message)).toBe(await reference.signMessage({ message }));
  });

  it("from the encrypted keystore: resolves the key and signs identically", async () => {
    process.env[DEK_ENV_VAR] = TEST_DEK.toString("base64");
    await writeEncryptedKeystore(keystorePath(), TEST_KEY);
    delete process.env[ENV_KEY_VAR];

    const backend = new LocalKeySignerBackend({
      privateKeyEnv: ENV_KEY_VAR,
      keystorePath: keystorePath(),
    });

    const reference = privateKeyToAccount(TEST_KEY);
    expect(await backend.address()).toBe(reference.address);
    expect(backend.keySource).toBe("keystore");
    const message = "keystore parity";
    expect(await backend.signMessage(message)).toBe(await reference.signMessage({ message }));
  });

  it("toViemAccount returns a viem account with the matching address", async () => {
    process.env[ENV_KEY_VAR] = TEST_KEY;
    const backend = new LocalKeySignerBackend({
      privateKeyEnv: ENV_KEY_VAR,
      keystorePath: keystorePath(),
    });
    const account = await backend.toViemAccount();
    expect(account.address).toBe(privateKeyToAccount(TEST_KEY).address);
  });

  it("FAILS CLOSED when neither env key nor a keystore exists", async () => {
    delete process.env[ENV_KEY_VAR];
    setKeychainForTesting(null);
    const backend = new LocalKeySignerBackend({
      privateKeyEnv: ENV_KEY_VAR,
      keystorePath: keystorePath(),
    });
    await expect(backend.address()).rejects.toMatchObject({ code: "wallet_keystore_missing" });
  });

  it("rejects a malformed env key with wallet_private_key_invalid (not a raw viem error)", async () => {
    process.env[ENV_KEY_VAR] = "not-a-valid-key";
    const backend = new LocalKeySignerBackend({
      privateKeyEnv: ENV_KEY_VAR,
      keystorePath: keystorePath(),
    });
    await expect(backend.address()).rejects.toMatchObject({ code: "wallet_private_key_invalid" });
  });

  it("does not permanently cache a rejected resolution: a retry after the key appears succeeds", async () => {
    delete process.env[ENV_KEY_VAR];
    setKeychainForTesting(null);
    const backend = new LocalKeySignerBackend({
      privateKeyEnv: ENV_KEY_VAR,
      keystorePath: keystorePath(),
    });

    // First call fails (no key anywhere).
    await expect(backend.address()).rejects.toMatchObject({ code: "wallet_keystore_missing" });

    // Fix the condition, then retry the SAME backend instance.
    process.env[ENV_KEY_VAR] = TEST_KEY;
    expect(await backend.address()).toBe(privateKeyToAccount(TEST_KEY).address);
    expect(backend.keySource).toBe("env");
  });
});
