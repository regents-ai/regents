import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { AuthError } from "../../src/internal-runtime/errors.js";
import { writeIdentityReceipt } from "../../src/internal-runtime/identity/cache.js";
import { SessionStore } from "../../src/internal-runtime/store/session-store.js";
import { StateStore } from "../../src/internal-runtime/store/state-store.js";
import { requireAuthenticatedAgentContext } from "../../src/internal-runtime/techtree/auth.js";

const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";
const TEST_AGENT_ID = `eip155:8453:${TEST_REGISTRY}:99`;
const TEST_WALLET = "0x1111111111111111111111111111111111111111";
const OTHER_WALLET = "0x3333333333333333333333333333333333333333";

describe("requireAuthenticatedAgentContext", () => {
  it("rejects a saved identity that does not match the active SIWA session", () => {
    const tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "regent-auth-context-"));
    const originalHome = process.env.HOME;
    process.env.HOME = tempHome;

    try {
      const stateStore = new StateStore(path.join(tempHome, "state", "runtime-state.json"));
      const sessionStore = new SessionStore(stateStore);
      sessionStore.setSiwaSession({
        walletAddress: TEST_WALLET,
        chainId: 8453,
        nonce: "nonce",
        keyId: TEST_WALLET,
        receipt: "receipt",
        receiptExpiresAt: "2999-01-01T00:00:00.000Z",
        audience: "techtree",
        registryAddress: TEST_REGISTRY,
        tokenId: "99",
      });

      writeIdentityReceipt({
        version: 1,
        regent_base_url: "http://127.0.0.1:4000",
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

      expect(() => requireAuthenticatedAgentContext(sessionStore, stateStore)).toThrowError(
        new AuthError(
          "agent_identity_mismatch",
          "stored Regent identity does not match the active SIWA session; run `regents identity ensure` again",
        ),
      );
    } finally {
      process.env.HOME = originalHome;
      fs.rmSync(tempHome, { recursive: true, force: true });
    }
  });
});
