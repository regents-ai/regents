import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { writeIdentityReceipt } from "../../src/internal-runtime/identity/cache.js";
import { StateStore } from "../../src/internal-runtime/store/state-store.js";
import { writeFileAtomicSync, writeJsonFileAtomicSync } from "../../src/internal-runtime/paths.js";

const mode = (filePath: string): number => fs.statSync(filePath).mode & 0o777;

describe("secure local writes", () => {
  const tempDirs: string[] = [];

  afterEach(() => {
    vi.restoreAllMocks();
    for (const tempDir of tempDirs.splice(0)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  const tempHome = (prefix: string): string => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
    tempDirs.push(tempDir);
    return tempDir;
  };

  it("writes config, state, receipt, and secret files with private permissions", () => {
    const homeDir = tempHome("regent-secure-writes-");
    vi.spyOn(os, "homedir").mockReturnValue(homeDir);

    const configPath = path.join(homeDir, ".regent", "config.json");
    const statePath = path.join(homeDir, ".regent", "state", "runtime-state.json");
    const secretPath = path.join(homeDir, ".regent", "keys", "agent-wallet.json");
    const genericPath = path.join(homeDir, ".regent", "plans", "plan.json");

    writeInitialConfig(configPath);
    new StateStore(statePath).write({ lastUsedNodeIdempotencyKey: "node-key" });
    writeIdentityReceipt({
      version: 1,
      regent_base_url: "http://127.0.0.1:4000",
      network: "base-sepolia",
      provider: "coinbase-cdp",
      address: "0x1111111111111111111111111111111111111111",
      agent_id: "eip155:84532:0x2222222222222222222222222222222222222222:1",
      token_id: "1",
      agent_registry: "0x2222222222222222222222222222222222222222",
      signer_type: "evm_personal_sign",
      verified: "onchain",
      receipt: "receipt",
      receipt_issued_at: "2026-04-01T00:00:00.000Z",
      receipt_expires_at: "2999-01-01T00:00:00.000Z",
      cached_at: "2026-04-01T00:00:00.000Z",
    });
    writeFileAtomicSync(secretPath, "{\"privateKey\":\"secret\"}\n");
    writeJsonFileAtomicSync(genericPath, { plan_id: "plan_1" });

    const receiptPath = path.join(homeDir, ".regent", "identity", "receipt-v1.json");
    for (const filePath of [configPath, statePath, receiptPath, secretPath, genericPath]) {
      expect(mode(filePath)).toBe(0o600);
      expect(mode(path.dirname(filePath))).toBe(0o700);
    }
  });
});
