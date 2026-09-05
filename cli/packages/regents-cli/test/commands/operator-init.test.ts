import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { operatorInitDeps, runOperatorInit, type OperatorInitDeps } from "../../src/commands/operator.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import type { RegentIdentityReceipt } from "../../src/internal-types/index.js";
import { parseCliArgs } from "../../src/parse.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { captureOutput } from "../../../../test-support/test-helpers.js";

const TEST_WALLET = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8" as const;
const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";
const TEST_AGENT_ID = `eip155:8453:${TEST_REGISTRY}:99`;

const readyDoctorReport = {
  ok: true,
  mode: "scoped" as const,
  scope: "runtime" as const,
  summary: { ok: 3, warn: 0, fail: 0, skip: 0 },
  checks: [],
  nextSteps: [],
  generatedAt: "2026-06-09T00:00:00.000Z",
};

const writeReceipt = (homeDir: string): void => {
  const receipt: RegentIdentityReceipt = {
    version: 1,
    regent_base_url: "https://regent.example",
    network: "base",
    provider: "coinbase-cdp",
    address: TEST_WALLET,
    agent_id: TEST_AGENT_ID,
    token_id: "99",
    agent_registry: TEST_REGISTRY,
    signer_type: "evm_personal_sign",
    verified: "onchain",
    receipt: "receipt-valid",
    receipt_issued_at: "2026-04-17T00:00:00.000Z",
    receipt_expires_at: "2999-01-01T00:00:00.000Z",
    cached_at: "2026-04-17T00:00:00.000Z",
    wallet_hint: "main",
  };
  const receiptPath = path.join(homeDir, ".regent", "identity", "receipt-v1.json");
  fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, "utf8");
};

describe("guided regents init", () => {
  let tempDir = "";
  let configPath = "";
  let originalHome: string | undefined;
  let originalPath: string | undefined;
  let originalKeyId: string | undefined;
  let originalKeySecret: string | undefined;
  let originalWalletSecret: string | undefined;
  const originalDeps: OperatorInitDeps = { ...operatorInitDeps };

  const installedRuntime = (runtime: "hermes" | "openclaw", installed: boolean) => ({
    runtime,
    installed,
    pluginPath: path.join(tempDir, `.${runtime}`),
    skillsPath: path.join(tempDir, `.${runtime}`, "skills"),
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-operator-init-"));
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

    operatorInitDeps.callJsonRpc = vi.fn().mockResolvedValue({ ok: true });
    operatorInitDeps.pluginStatus = vi.fn(() => ({
      ok: true,
      selectedRuntime: "auto",
      runtimes: [installedRuntime("hermes", true), installedRuntime("openclaw", true)],
    }));
    operatorInitDeps.runScopedDoctor = vi.fn().mockResolvedValue(readyDoctorReport);
  });

  afterEach(() => {
    Object.assign(operatorInitDeps, originalDeps);
    fs.rmSync(tempDir, { recursive: true, force: true });
    process.env.HOME = originalHome;
    process.env.PATH = originalPath;
    process.env.CDP_KEY_ID = originalKeyId;
    process.env.CDP_KEY_SECRET = originalKeySecret;
    process.env.CDP_WALLET_SECRET = originalWalletSecret;
  });

  it("reports ready without redoing work when everything is already set up", async () => {
    writeReceipt(tempDir);

    const output = await captureOutput(async () =>
      runOperatorInit(parseCliArgs(["--config", configPath]), configPath),
    );

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(JSON.parse(output.stdout)).toMatchObject({
      ok: true,
      command: "init",
      status: "ready",
      plugin: { installed_now: [] },
      daemon: { running: true, started_now: false },
      doctor: { ok: true, fail: 0 },
      wallet: { name: "main", address: TEST_WALLET },
      identity: { network: "base", agent_id: TEST_AGENT_ID },
      next_actions: ["regents status"],
    });
  });

  it("reports missing runtime tools and daemon work without performing it", async () => {
    operatorInitDeps.pluginStatus = vi.fn(() => ({
      ok: true,
      selectedRuntime: "auto",
      runtimes: [installedRuntime("hermes", true), installedRuntime("openclaw", false)],
    }));
    operatorInitDeps.callJsonRpc = vi.fn().mockRejectedValue(new Error("socket missing"));

    const output = await captureOutput(async () =>
      runOperatorInit(parseCliArgs(["--config", configPath]), configPath),
    );

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(JSON.parse(output.stdout)).toMatchObject({
      ok: true,
      command: "init",
      status: "waiting",
      plugin: { installed_now: [] },
      daemon: { running: false, started_now: false },
      next_actions: [
        "regents plugin install --runtime openclaw",
        "regents run",
        "regents identity ensure",
      ],
    });
  });
});
