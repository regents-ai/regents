import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { loadConfig, writeInitialConfig } from "../../src/internal-runtime/config.js";
import { writeIdentityReceipt } from "../../src/internal-runtime/identity/cache.js";
import { handleAuthSiwaStatus } from "../../src/internal-runtime/handlers/auth.js";
import { SessionStore } from "../../src/internal-runtime/store/session-store.js";
import { StateStore } from "../../src/internal-runtime/store/state-store.js";

const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";
const TEST_AGENT_ID = `eip155:8453:${TEST_REGISTRY}:99`;
const TEST_WALLET = "0x1111111111111111111111111111111111111111";
const OTHER_WALLET = "0x3333333333333333333333333333333333333333";

describe("handleAuthSiwaStatus", () => {
  it("does not report protected routes ready when the cached identity no longer matches the active session", async () => {
    const tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "regent-auth-status-"));
    const originalHome = process.env.HOME;
    process.env.HOME = tempHome;

    try {
      const configPath = path.join(tempHome, "regent.config.json");
      writeInitialConfig(configPath, {
        runtime: {
          socketPath: path.join(tempHome, "runtime", "regent.sock"),
          stateDir: path.join(tempHome, "state"),
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
          keystorePath: path.join(tempHome, "keys", "agent-wallet.json"),
        },
      });
      const config = loadConfig(configPath);
      const stateStore = new StateStore(path.join(tempHome, "state", "runtime-state.json"));
      const sessionStore = new SessionStore(stateStore);

      sessionStore.setSiwaSession({
        walletAddress: TEST_WALLET,
        chainId: 8453,
        nonce: "nonce",
        keyId: TEST_WALLET,
        receipt: "receipt",
        receiptIssuedAt: "2026-04-01T00:00:00.000Z",
        receiptExpiresAt: "2999-01-01T00:00:00.000Z",
        audience: "techtree",
        registryAddress: TEST_REGISTRY,
        tokenId: "99",
      });
      stateStore.patch({
        agent: {
          walletAddress: TEST_WALLET,
          chainId: 8453,
          registryAddress: TEST_REGISTRY,
          tokenId: "99",
          label: "Coinbase wallet",
        },
      });

      writeIdentityReceipt({
        version: 1,
        regent_base_url: "https://regent.example",
        network: "base",
        provider: "coinbase-cdp",
        address: OTHER_WALLET,
        agent_id: TEST_AGENT_ID,
        token_id: "99",
        agent_registry: TEST_REGISTRY,
        signer_type: "evm_personal_sign",
        verified: "onchain",
        receipt: "identity-receipt",
        receipt_issued_at: "2026-04-01T00:00:00.000Z",
        receipt_expires_at: "2999-01-01T00:00:00.000Z",
        cached_at: "2026-04-01T00:00:00.000Z",
        wallet_hint: "main",
      });

      const status = await handleAuthSiwaStatus({
        config,
        stateStore,
        sessionStore,
      } as never);

      expect(status.authenticated).toBe(true);
      expect(status.missingIdentityFields).toEqual([]);
      expect(status.protectedRoutesReady).toBe(false);
    } finally {
      process.env.HOME = originalHome;
      fs.rmSync(tempHome, { recursive: true, force: true });
    }
  });
});
