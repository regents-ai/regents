import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { runCliEntrypoint } from "../../src/index.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { TechtreeContractServer } from "../../../../test-support/techtree-contract-server.js";
import { captureOutput } from "../../../../test-support/test-helpers.js";

const TEST_WALLET = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8";
const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";
const TEST_AGENT_REGISTRY = `eip155:8453:${TEST_REGISTRY}`;
const TEST_AGENT_ID = `${TEST_AGENT_REGISTRY}:99`;

describe.sequential("wallet and identity functional flows", () => {
  let configPath = "";
  let originalHome: string | undefined;
  let originalKeyId: string | undefined;
  let originalKeySecret: string | undefined;
  let originalPath: string | undefined;
  let originalWalletSecret: string | undefined;
  let server: TechtreeContractServer;
  let tempDir = "";

  const receiptPath = (): string =>
    path.join(tempDir, ".regent", "identity", "receipt-v1.json");
  const walletStatePath = (): string =>
    path.join(tempDir, "state", "coinbase-wallet.json");
  const identityRequestCount = (): number =>
    server.requests.filter((request) =>
      request.pathname.startsWith("/api/shared/identity/"),
    ).length;

  beforeEach(async () => {
    server = new TechtreeContractServer();
    await server.start();

    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-wallet-identity-"));
    configPath = path.join(tempDir, "regent.config.json");
    originalHome = process.env.HOME;
    originalPath = process.env.PATH;
    originalKeyId = process.env.CDP_KEY_ID;
    originalKeySecret = process.env.CDP_KEY_SECRET;
    originalWalletSecret = process.env.CDP_WALLET_SECRET;

    process.env.HOME = tempDir;
    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "main", address: TEST_WALLET }],
    })}:${originalPath ?? ""}`;
    process.env.CDP_KEY_ID = "test-key";
    process.env.CDP_KEY_SECRET = "test-secret";
    process.env.CDP_WALLET_SECRET = "test-wallet-secret";

    writeInitialConfig(configPath, {
      runtime: {
        socketPath: path.join(tempDir, "runtime", "regent.sock"),
        stateDir: path.join(tempDir, "state"),
        logLevel: "debug",
      },
      services: {
        siwa: {
          baseUrl: server.baseUrl,
          requestTimeoutMs: 1_000,
        },
        platform: {
          baseUrl: server.baseUrl,
          requestTimeoutMs: 1_000,
        },
        autolaunch: {
          baseUrl: "http://127.0.0.1:4010",
          requestTimeoutMs: 1_000,
        },
      },
    });
  });

  afterEach(async () => {
    await server.stop();
    process.env.HOME = originalHome;
    process.env.PATH = originalPath;
    process.env.CDP_KEY_ID = originalKeyId;
    process.env.CDP_KEY_SECRET = originalKeySecret;
    process.env.CDP_WALLET_SECRET = originalWalletSecret;
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("creates the configured Coinbase wallet and persists its local state", async () => {
    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "secondary", address: TEST_WALLET }],
    })}:${originalPath ?? ""}`;

    const output = await captureOutput(async () =>
      runCliEntrypoint(["wallet", "setup", "--json", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(JSON.parse(output.stdout)).toEqual({
      ok: true,
      provider: "coinbase-cdp",
      wallet: {
        name: "main",
        address: TEST_WALLET,
      },
      created: true,
      state_path: walletStatePath(),
      next_steps: [
        "regents identity ensure",
      ],
    });
    expect(fs.existsSync(walletStatePath())).toBe(true);
  });

  it("creates an identity receipt, reuses its cache, and refreshes on request", async () => {
    await captureOutput(async () =>
      runCliEntrypoint(["wallet", "setup", "--json", "--config", configPath]),
    );

    const first = await captureOutput(async () =>
      runCliEntrypoint([
        "identity",
        "ensure",
        "--json",
        "--network",
        "base",
        "--config",
        configPath,
      ]),
    );

    expect(first.result).toBe(0);
    expect(JSON.parse(first.stdout)).toEqual({
      status: "ok",
      provider: "coinbase-cdp",
      network: "base",
      address: TEST_WALLET,
      agent_id: TEST_AGENT_ID,
      token_id: "99",
      agent_registry: TEST_AGENT_REGISTRY,
      verified: "onchain",
      receipt_expires_at: "2999-01-01T00:00:00.000Z",
      cache_path: receiptPath(),
      next_steps: [
        "regents auth login --audience platform",
        "regents run",
      ],
    });
    expect(JSON.parse(fs.readFileSync(receiptPath(), "utf8"))).toEqual({
      version: 1,
      regent_base_url: server.baseUrl,
      network: "base",
      provider: "coinbase-cdp",
      address: TEST_WALLET,
      agent_id: TEST_AGENT_ID,
      token_id: "99",
      agent_registry: TEST_AGENT_REGISTRY,
      signer_type: "evm_personal_sign",
      verified: "onchain",
      receipt: expect.stringContaining("receipt-valid."),
      receipt_issued_at: "2026-03-10T00:00:00.000Z",
      receipt_expires_at: "2999-01-01T00:00:00.000Z",
      cached_at: expect.any(String),
      wallet_hint: "main",
    });

    const requestsAfterFirstEnsure = identityRequestCount();
    const cached = await captureOutput(async () =>
      runCliEntrypoint([
        "identity",
        "ensure",
        "--json",
        "--network",
        "base",
        "--config",
        configPath,
      ]),
    );
    expect(cached.result).toBe(0);
    expect(identityRequestCount()).toBe(requestsAfterFirstEnsure);

    const refreshed = await captureOutput(async () =>
      runCliEntrypoint([
        "identity",
        "ensure",
        "--json",
        "--network",
        "base",
        "--force-refresh",
        "--config",
        configPath,
      ]),
    );
    expect(refreshed.result).toBe(0);
    expect(identityRequestCount()).toBeGreaterThan(requestsAfterFirstEnsure);
  }, 15_000);

  it("reports the Coinbase wallet and identity status", async () => {
    await captureOutput(async () =>
      runCliEntrypoint(["wallet", "setup", "--json", "--config", configPath]),
    );
    await captureOutput(async () =>
      runCliEntrypoint([
        "identity",
        "ensure",
        "--json",
        "--network",
        "base",
        "--config",
        configPath,
      ]),
    );

    const status = await captureOutput(async () =>
      runCliEntrypoint([
        "identity",
        "status",
        "--json",
        "--network",
        "base",
        "--config",
        configPath,
      ]),
    );

    expect(status.result).toBe(0);
    expect(JSON.parse(status.stdout)).toEqual(
      expect.objectContaining({
        ok: true,
        provider: "coinbase-cdp",
        network: "base",
        wallet_ready: true,
        identity_ready: true,
        address: TEST_WALLET,
        identity: expect.objectContaining({
          provider: "coinbase-cdp",
          registered: true,
          verified: "onchain",
        }),
      }),
    );
  }, 15_000);

  it("fails cleanly when the Coinbase CLI is unavailable", async () => {
    process.env.PATH = path.join(tempDir, "empty-bin");
    fs.mkdirSync(process.env.PATH, { recursive: true });

    const output = await captureOutput(async () =>
      runCliEntrypoint(["wallet", "status", "--json", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(JSON.parse(output.stdout)).toMatchObject({
      ok: false,
      provider: "coinbase-cdp",
      next_action: {
        command: expect.stringContaining("regents wallet setup"),
      },
    });
  });
});
