import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { loadConfig, writeInitialConfig } from "../../src/internal-runtime/config.js";
import { readIdentityReceipt } from "../../src/internal-runtime/identity/cache.js";
import { ensureIdentity } from "../../src/internal-runtime/identity/ensure.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { TechtreeContractServer } from "../../../../test-support/techtree-contract-server.js";
import { describeNetwork } from "../../../../test-support/integration.js";

const FIRST_WALLET = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8";
const SECOND_WALLET = "0x1111111111111111111111111111111111111111";

describeNetwork("ensureIdentity", () => {
  let server: TechtreeContractServer;
  let tempDir = "";
  let configPath = "";
  let originalHome: string | undefined;
  let originalPath: string | undefined;
  let originalKeyId: string | undefined;
  let originalKeySecret: string | undefined;
  let originalWalletSecret: string | undefined;

  beforeEach(async () => {
    server = new TechtreeContractServer();
    await server.start();

    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-identity-ensure-"));
    configPath = path.join(tempDir, "regent.config.json");
    originalHome = process.env.HOME;
    originalPath = process.env.PATH;
    originalKeyId = process.env.CDP_KEY_ID;
    originalKeySecret = process.env.CDP_KEY_SECRET;
    originalWalletSecret = process.env.CDP_WALLET_SECRET;

    process.env.HOME = tempDir;
    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "main", address: FIRST_WALLET }],
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
      auth: {
        audience: "techtree",
        defaultChainId: 8453,
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
  });

  afterEach(async () => {
    await server.stop();
    process.env.HOME = originalHome;
    process.env.PATH = originalPath;
    process.env.CDP_KEY_ID = originalKeyId;
    process.env.CDP_KEY_SECRET = originalKeySecret;
    process.env.CDP_WALLET_SECRET = originalWalletSecret;
  });

  it("refreshes the cached identity when the active Coinbase wallet changes", async () => {
    const config = loadConfig(configPath);

    const first = await ensureIdentity({
      config,
      network: "base",
      forceRefresh: false,
      timeoutSeconds: 1,
    });

    expect(first.address).toBe(FIRST_WALLET);
    expect(readIdentityReceipt()?.address).toBe(FIRST_WALLET);

    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "main", address: SECOND_WALLET }],
    })}:${originalPath ?? ""}`;

    const second = await ensureIdentity({
      config,
      network: "base",
      forceRefresh: false,
      timeoutSeconds: 1,
    });

    expect(second.address).toBe(SECOND_WALLET);
    expect(readIdentityReceipt()?.address).toBe(SECOND_WALLET);
  });
});
