import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  EXPECTED_PLATFORM_CONTRACT_DIGEST,
  SUPPORTED_PLATFORM_CONTRACT_MAJOR,
} from "../../../src/generated/platform-contract-digest.js";
import { runScopedDoctor, writeInitialConfig } from "../../../src/internal-runtime/index.js";

const savedWalletKeyEnv = process.env.REGENT_WALLET_PRIVATE_KEY;

afterEach(() => {
  vi.unstubAllGlobals();
  if (savedWalletKeyEnv === undefined) {
    delete process.env.REGENT_WALLET_PRIVATE_KEY;
  } else {
    process.env.REGENT_WALLET_PRIVATE_KEY = savedWalletKeyEnv;
  }
});

describe("runtime-scoped doctor", () => {
  it("applies safe local fixes for missing runtime dirs and stale socket files", async () => {
    // Keep the platform contract check off the network.
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response("openapi: 3.0.3\n", {
          status: 200,
          headers: {
            "x-regents-contract-major": SUPPORTED_PLATFORM_CONTRACT_MAJOR,
            "x-regents-contract-digest": EXPECTED_PLATFORM_CONTRACT_DIGEST,
          },
        }),
      ),
    );

    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-doctor-runtime-"));
    const configPath = path.join(tempDir, "regent.config.json");
    const socketPath = path.join(tempDir, "runtime", "regent.sock");
    const stateDir = path.join(tempDir, "state");
    const keystorePath = path.join(tempDir, "keys", "agent-wallet.json");
    const gossipsubDir = path.join(tempDir, "p2p");

    writeInitialConfig(configPath, {
      runtime: {
        socketPath,
        stateDir,
        logLevel: "info",
      },
      wallet: {
        privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
        keystorePath,
      },
    });

    fs.mkdirSync(path.dirname(socketPath), { recursive: true });
    fs.writeFileSync(socketPath, "stale socket", "utf8");
    // Provide the wallet key via the env source (the headless path); the signer
    // resolves it without any key on disk.
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

    const report = await runScopedDoctor(
      {
        scope: "runtime",
        fix: true,
      },
      {
        configPath,
      },
    );

    expect(report.mode).toBe("scoped");
    expect(report.scope).toBe("runtime");
    expect(report.summary.fail).toBe(0);
    expect(fs.existsSync(stateDir)).toBe(true);
    expect(fs.existsSync(socketPath)).toBe(false);
    expect(fs.existsSync(gossipsubDir)).toBe(true);

    expect(report.checks).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: "runtime.paths.ensure",
          status: "ok",
        }),
        expect.objectContaining({
          id: "runtime.socket.reachable",
          status: "warn",
          fixApplied: true,
        }),
      ]),
    );
  });
});
