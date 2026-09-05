import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { IdentityServiceClient } from "../../src/internal-runtime/identity/service.js";
import type { RegentIdentityReceipt } from "../../src/internal-types/index.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { captureOutput } from "../../../../test-support/test-helpers.js";

const TEST_WALLET = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8" as const;

const writeReceipt = (homeDir: string, receipt: RegentIdentityReceipt): void => {
  const receiptPath = path.join(homeDir, ".regent", "identity", "receipt-v1.json");
  fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, "utf8");
};

describe("identity status command", () => {
  let tempDir = "";
  let configPath = "";
  let originalHome: string | undefined;
  let originalPath: string | undefined;
  let originalKeyId: string | undefined;
  let originalKeySecret: string | undefined;
  let originalWalletSecret: string | undefined;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-identity-status-"));
    configPath = path.join(tempDir, "regent.config.json");
    originalHome = process.env.HOME;
    originalPath = process.env.PATH;
    originalKeyId = process.env.CDP_KEY_ID;
    originalKeySecret = process.env.CDP_KEY_SECRET;
    originalWalletSecret = process.env.CDP_WALLET_SECRET;

    process.env.HOME = tempDir;
    process.env.PATH = `${writeFakeCdp(tempDir)}:${originalPath ?? ""}`;
    process.env.CDP_KEY_ID = "test-key";
    process.env.CDP_KEY_SECRET = "test-secret";
    process.env.CDP_WALLET_SECRET = "test-wallet-secret";

    writeInitialConfig(configPath, {
      runtime: {
        socketPath: path.join(tempDir, "runtime", "regent.sock"),
        stateDir: path.join(tempDir, "state"),
        logLevel: "debug",
      },
      auth: {
        audience: "techtree",
        defaultChainId: 8453,
      },
      services: {
        siwa: {
          baseUrl: "https://regent.example",
          requestTimeoutMs: 1_000,
        },
        platform: {
          baseUrl: "https://regent.example",
          requestTimeoutMs: 1_000,
        },
        autolaunch: {
          baseUrl: "http://127.0.0.1:4010",
          requestTimeoutMs: 1_000,
        },
      },
      wallet: {
        privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
        keystorePath: path.join(tempDir, "keys", "agent-wallet.json"),
      },
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    process.env.HOME = originalHome;
    process.env.PATH = originalPath;
    process.env.CDP_KEY_ID = originalKeyId;
    process.env.CDP_KEY_SECRET = originalKeySecret;
    process.env.CDP_WALLET_SECRET = originalWalletSecret;
  });

  it("does not report ready when the cached receipt belongs to a different network", async () => {
    writeReceipt(tempDir, {
      version: 1,
      regent_base_url: "https://regent.example",
      network: "base",
      provider: "coinbase-cdp",
      address: TEST_WALLET,
      agent_id: "eip155:8453:0x2222222222222222222222222222222222222222:99",
      token_id: "99",
      agent_registry: "0x2222222222222222222222222222222222222222",
      signer_type: "evm_personal_sign",
      verified: "onchain",
      receipt: "receipt-valid",
      receipt_issued_at: "2026-04-17T00:00:00.000Z",
      receipt_expires_at: "2999-01-01T00:00:00.000Z",
      cached_at: "2026-04-17T00:00:00.000Z",
      wallet_hint: "main",
    });

    vi.spyOn(IdentityServiceClient.prototype, "status").mockResolvedValue({
      ok: true,
      code: "identity_status_resolved",
      data: {
        network: "base-sepolia",
        address: TEST_WALLET,
        provider: "coinbase-cdp",
        registered: false,
        verified: "unregistered",
      },
    });

    const output = await captureOutput(async () =>
      runCliEntrypoint(["identity", "status", "--json", "--network", "base-sepolia", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(JSON.parse(output.stdout)).toEqual(
      expect.objectContaining({
        ok: false,
        provider: "coinbase-cdp",
        network: "base-sepolia",
        wallet_ready: true,
        identity_ready: false,
        address: TEST_WALLET,
        next_action: expect.objectContaining({
          command: "regents identity ensure",
        }),
      }),
    );
  });

});
