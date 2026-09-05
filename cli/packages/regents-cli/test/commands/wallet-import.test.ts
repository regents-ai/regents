import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { privateKeyToAccount } from "viem/accounts";

import { runWalletImport } from "../../src/commands/wallet.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import {
  setKeychainForTesting,
  resetKeychainForTesting,
  type KeychainApi,
} from "../../src/internal-runtime/agent/keychain.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

// Hardhat account #1 — the key the user intends to import via stdin.
const STDIN_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const STDIN_ADDRESS = privateKeyToAccount(STDIN_KEY).address;
// Hardhat account #0 — a stale env key that must NOT be imported.
const ENV_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;

const ENV_KEY_VAR = "REGENT_WALLET_PRIVATE_KEY";
const DEK_ENV_VAR = "REGENTS_WALLET_KEY";

const makeFakeKeychain = (): KeychainApi => {
  const store = new Map<string, string>();
  const key = (s: string, a: string) => `${s}::${a}`;
  return {
    get: (s, a) => store.get(key(s, a)) ?? null,
    set: (s, a, v) => {
      store.set(key(s, a), v);
    },
    delete: (s, a) => store.delete(key(s, a)),
  };
};

let tempDir = "";
let configPath = "";
const saved = { env: process.env[ENV_KEY_VAR], dek: process.env[DEK_ENV_VAR] };
let originalStdin: PropertyDescriptor | undefined;

const stubStdin = (input: string): void => {
  originalStdin = Object.getOwnPropertyDescriptor(process, "stdin");
  Object.defineProperty(process, "stdin", {
    value: Readable.from([Buffer.from(input, "utf8")]),
    configurable: true,
  });
};

beforeEach(() => {
  tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-wallet-import-"));
  configPath = path.join(tempDir, "regent.config.json");
  writeInitialConfig(configPath, {
    wallet: {
      privateKeyEnv: ENV_KEY_VAR,
      keystorePath: path.join(tempDir, "keys", "agent-wallet.json"),
    },
  });
  delete process.env[ENV_KEY_VAR];
  process.env[DEK_ENV_VAR] = Buffer.alloc(32, 7).toString("base64");
  setKeychainForTesting(makeFakeKeychain());
});

afterEach(() => {
  resetKeychainForTesting();
  if (originalStdin) {
    Object.defineProperty(process, "stdin", originalStdin);
    originalStdin = undefined;
  }
  for (const [k, v] of Object.entries(saved)) {
    const name = k === "env" ? ENV_KEY_VAR : DEK_ENV_VAR;
    if (v === undefined) {
      delete process.env[name];
    } else {
      process.env[name] = v;
    }
  }
  fs.rmSync(tempDir, { recursive: true, force: true });
});

describe("wallet import", () => {
  const keystorePath = () => path.join(tempDir, "keys", "agent-wallet.json");

  it("REFUSES when REGENT_WALLET_PRIVATE_KEY is set, and writes nothing (the wrong-wallet repro is blocked)", async () => {
    // Exact repro: a stale env key is set; the user pipes a different key.
    process.env[ENV_KEY_VAR] = ENV_KEY;
    stubStdin(`${STDIN_KEY}\n`);

    const output = await captureOutput(() => runWalletImport(["import", "--json"], configPath));

    expect(output.result).not.toBe(0);
    const payload = parsePrintedJson<{ ok: boolean; code: string }>(output.stdout);
    expect(payload.ok).toBe(false);
    expect(payload.code).toBe("wallet_import_env_conflict");
    // Nothing written.
    expect(fs.existsSync(keystorePath())).toBe(false);
  });

  it("with the env unset, imports the key piped on stdin (the correct wallet)", async () => {
    stubStdin(`${STDIN_KEY}\n`);

    const output = await captureOutput(() => runWalletImport(["import", "--json"], configPath));

    expect(output.result).toBe(0);
    const payload = parsePrintedJson<{ ok: boolean; address: string; encrypted: boolean }>(output.stdout);
    expect(payload.ok).toBe(true);
    // The imported wallet is the STDIN key, never the env key.
    expect(payload.address).toBe(STDIN_ADDRESS);
    expect(payload.encrypted).toBe(true);

    // The file on disk is an encrypted envelope, not the plaintext key.
    const raw = fs.readFileSync(keystorePath(), "utf8");
    expect(raw).not.toContain(STDIN_KEY);
    expect(raw).toContain("RegentWalletKeyV1");
  });

  it("rejects a malformed stdin key with wallet_private_key_invalid", async () => {
    stubStdin("not-a-key\n");

    const output = await captureOutput(() => runWalletImport(["import", "--json"], configPath));

    expect(output.result).not.toBe(0);
    expect(parsePrintedJson<{ code: string }>(output.stdout).code).toBe("wallet_private_key_invalid");
    expect(fs.existsSync(keystorePath())).toBe(false);
  });
});
