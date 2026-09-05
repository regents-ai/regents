import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { writeIdentityReceipt } from "../../src/internal-runtime/identity/cache.js";
import { callJsonRpc } from "../../src/internal-runtime/jsonrpc/client.js";
import { RegentRuntime } from "../../src/internal-runtime/runtime.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import {
  TechtreeContractServer,
  type TechtreeContractServerOptions,
} from "../../../../test-support/techtree-contract-server.js";

const TEST_PRIVATE_KEY =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
const TEST_WALLET = "0x1111111111111111111111111111111111111111";
const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";

describe.sequential("RegentRuntime local daemon", () => {
  let configPath = "";
  let originalHome: string | undefined;
  let originalPath: string | undefined;
  let originalPrivateKey: string | undefined;
  let originalKeyId: string | undefined;
  let originalKeySecret: string | undefined;
  let originalWalletSecret: string | undefined;
  let runtime: RegentRuntime | null = null;
  let server: TechtreeContractServer;
  let serverOptions: TechtreeContractServerOptions;
  let socketPath = "";
  let tempDir = "";

  beforeEach(async () => {
    serverOptions = {};
    server = new TechtreeContractServer(serverOptions);
    await server.start();

    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-daemon-"));
    configPath = path.join(tempDir, "regent.config.json");
    socketPath = path.join(tempDir, "runtime", "regent.sock");
    originalHome = process.env.HOME;
    originalPath = process.env.PATH;
    originalPrivateKey = process.env.REGENT_TEST_PRIVATE_KEY;
    originalKeyId = process.env.CDP_KEY_ID;
    originalKeySecret = process.env.CDP_KEY_SECRET;
    originalWalletSecret = process.env.CDP_WALLET_SECRET;

    process.env.HOME = tempDir;
    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "main", address: TEST_WALLET }],
    })}:${originalPath ?? ""}`;
    process.env.REGENT_TEST_PRIVATE_KEY = TEST_PRIVATE_KEY;
    process.env.CDP_KEY_ID = "test-key";
    process.env.CDP_KEY_SECRET = "test-secret";
    process.env.CDP_WALLET_SECRET = "test-wallet-secret";

    writeInitialConfig(configPath, {
      runtime: {
        socketPath,
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
      wallet: {
        privateKeyEnv: "REGENT_TEST_PRIVATE_KEY",
        keystorePath: path.join(tempDir, "keys", "agent-wallet.json"),
      },
    });

    writeIdentityReceipt({
      version: 1,
      regent_base_url: server.baseUrl,
      network: "base",
      provider: "coinbase-cdp",
      address: TEST_WALLET,
      agent_id: `eip155:8453:${TEST_REGISTRY}:99`,
      token_id: "99",
      agent_registry: TEST_REGISTRY,
      signer_type: "evm_personal_sign",
      verified: "onchain",
      receipt: "identity-receipt",
      receipt_issued_at: "2026-03-10T00:00:00.000Z",
      receipt_expires_at: "2999-01-01T00:00:00.000Z",
      cached_at: "2026-03-10T00:00:00.000Z",
      wallet_hint: "main",
    });
  });

  afterEach(async () => {
    await runtime?.stop();
    await server.stop();
    process.env.HOME = originalHome;
    process.env.PATH = originalPath;
    process.env.REGENT_TEST_PRIVATE_KEY = originalPrivateKey;
    process.env.CDP_KEY_ID = originalKeyId;
    process.env.CDP_KEY_SECRET = originalKeySecret;
    process.env.CDP_WALLET_SECRET = originalWalletSecret;
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  const startRuntime = async (): Promise<void> => {
    runtime = new RegentRuntime(configPath);
    await runtime.start();
  };

  it("serves local agent, notebook, doctor, status, and shutdown methods", async () => {
    await startRuntime();
    expect(await callJsonRpc(socketPath, "runtime.ping")).toEqual({ ok: true });
    await expect(callJsonRpc(socketPath, "agent.init")).resolves.toMatchObject({
      initialized: true,
      currentProfile: { name: "owner" },
    });

    const workspacePath = path.join(tempDir, "notebook");
    await expect(
      callJsonRpc(socketPath, "techtree.notebooks.init", {
        workspace_path: workspacePath,
        kind: "freeform",
        title: "Local notebook",
      }),
    ).resolves.toMatchObject({
      ok: true,
      workspace_path: workspacePath,
    });
    await expect(
      callJsonRpc(socketPath, "techtree.notebooks.pair", {
        workspace_path: workspacePath,
      }),
    ).resolves.toMatchObject({
      ok: true,
      notebook_path: path.join(workspacePath, "analysis.py"),
    });
    await expect(
      callJsonRpc(socketPath, "doctor.runScoped", { scope: "runtime" }),
    ).resolves.toMatchObject({ mode: "scoped", scope: "runtime" });
    await expect(callJsonRpc(socketPath, "runtime.status")).resolves.toMatchObject({
      running: true,
      gossipsub: { status: "disabled" },
    });
  });

  it("persists an authenticated SIWA session across daemon restart", async () => {
    await startRuntime();
    await expect(
      callJsonRpc(socketPath, "auth.siwa.login", {
        chainId: 8453,
        audience: "techtree",
      }),
    ).resolves.toMatchObject({ code: "siwa_verified" });

    await runtime!.stop();
    runtime = null;
    await startRuntime();

    await expect(callJsonRpc(socketPath, "auth.siwa.status")).resolves.toEqual({
      authenticated: true,
      session: expect.objectContaining({
        walletAddress: TEST_WALLET,
        registryAddress: TEST_REGISTRY,
        tokenId: "99",
        audience: "techtree",
      }),
      agentIdentity: {
        walletAddress: TEST_WALLET,
        chainId: 8453,
        registryAddress: TEST_REGISTRY,
        tokenId: "99",
        label: "Coinbase wallet",
      },
      protectedRoutesReady: true,
      missingIdentityFields: [],
      appSessions: [],
    });
    await expect(callJsonRpc(socketPath, "runtime.status")).resolves.toMatchObject({
      authenticated: true,
      session: { walletAddress: TEST_WALLET },
    });
  });

  it("rejects unsupported SIWA audiences through the daemon handler", async () => {
    await startRuntime();

    await expect(
      callJsonRpc(socketPath, "auth.siwa.login", {
        chainId: 8453,
        audience: "unknown-app",
      }),
    ).rejects.toMatchObject({ code: "invalid_audience" });
  });

  it("propagates authenticated SIWA verification failures over JSON-RPC", async () => {
    await startRuntime();
    await callJsonRpc(socketPath, "auth.siwa.login", {
      chainId: 8453,
      audience: "techtree",
    });

    serverOptions.verifyResponse = {
      statusCode: 401,
      payload: {
        error: {
          code: "siwa_verification_denied",
          message: "authenticated verification failed",
        },
      },
    };

    await expect(
      callJsonRpc(socketPath, "auth.siwa.login", {
        chainId: 8453,
        audience: "techtree",
      }),
    ).rejects.toMatchObject({
      code: "siwa_verification_denied",
      message: "authenticated verification failed",
    });
    await expect(callJsonRpc(socketPath, "auth.siwa.status")).resolves.toMatchObject({
      authenticated: true,
      session: { walletAddress: TEST_WALLET },
    });
  });
});
