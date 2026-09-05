import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  callJsonRpc,
  RegentRuntime,
  writeInitialConfig,
} from "../src/internal-runtime/index.js";
import { runCliEntrypoint } from "../src/index.js";
import { writeFakeCdp } from "./support/fake-cdp.js";
import { TechtreeContractServer } from "../../../test-support/techtree-contract-server.js";
import { captureOutput } from "../../../test-support/test-helpers.js";

const TEST_PRIVATE_KEY =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

describe.sequential("CLI doctor command", () => {
  let configPath = "";
  let originalHome: string | undefined;
  let originalKeyId: string | undefined;
  let originalKeySecret: string | undefined;
  let originalPath: string | undefined;
  let originalPrivateKey: string | undefined;
  let originalWalletSecret: string | undefined;
  let runtime: RegentRuntime | null = null;
  let server: TechtreeContractServer;
  let socketPath = "";
  let tempDir = "";

  beforeEach(async () => {
    server = new TechtreeContractServer();
    await server.start();

    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-cli-doctor-"));
    configPath = path.join(tempDir, "regent.config.json");
    socketPath = path.join(tempDir, "runtime", "regent.sock");
    originalHome = process.env.HOME;
    originalPath = process.env.PATH;
    originalKeyId = process.env.CDP_KEY_ID;
    originalKeySecret = process.env.CDP_KEY_SECRET;
    originalWalletSecret = process.env.CDP_WALLET_SECRET;
    originalPrivateKey = process.env.REGENT_WALLET_PRIVATE_KEY;

    process.env.HOME = tempDir;
    process.env.PATH = `${writeFakeCdp(tempDir)}:${originalPath ?? ""}`;
    process.env.CDP_KEY_ID = "test-key";
    process.env.CDP_KEY_SECRET = "test-secret";
    process.env.CDP_WALLET_SECRET = "test-wallet-secret";
    process.env.REGENT_WALLET_PRIVATE_KEY = TEST_PRIVATE_KEY;

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
        privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
        keystorePath: path.join(tempDir, "keys", "agent-wallet.json"),
      },
    });

    runtime = new RegentRuntime(configPath);
    await runtime.start();
  });

  afterEach(async () => {
    await runtime?.stop();
    await server.stop();
    process.env.HOME = originalHome;
    process.env.PATH = originalPath;
    process.env.CDP_KEY_ID = originalKeyId;
    process.env.CDP_KEY_SECRET = originalKeySecret;
    process.env.CDP_WALLET_SECRET = originalWalletSecret;
    process.env.REGENT_WALLET_PRIVATE_KEY = originalPrivateKey;
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("renders human guidance when authentication is not established", async () => {
    const output = await captureOutput(async () =>
      runCliEntrypoint(["doctor", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(output.stdout).toContain("R E G E N T   D O C T O R");
    expect(output.stdout).toContain("SIWA session");
    expect(output.stdout).toContain("NEXT MOVES");
    expect(output.stdout).toContain("Run `regents identity ensure`");
  });

  it("renders authenticated doctor results as JSON", async () => {
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
    await expect(
      callJsonRpc(socketPath, "auth.siwa.login", {
        chainId: 8453,
        audience: "techtree",
      }),
    ).resolves.toMatchObject({ code: "siwa_verified" });

    const output = await captureOutput(async () =>
      runCliEntrypoint(["doctor", "--json", "--config", configPath]),
    );
    const report = JSON.parse(output.stdout);

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(report).toEqual(
      expect.objectContaining({
        mode: "default",
        checks: expect.arrayContaining([
          expect.objectContaining({
            id: "auth.siwa.nonce.endpoint",
            status: "ok",
          }),
          expect.objectContaining({
            id: "auth.siwa.verify.endpoint",
            status: "ok",
          }),
          expect.objectContaining({
            id: "auth.session.present",
            status: "ok",
          }),
          expect.objectContaining({
            id: "auth.http-envelope.build",
            status: "ok",
          }),
        ]),
      }),
    );
  }, 15_000);
});
