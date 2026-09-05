import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { coinbaseStatus, signMessageWithCoinbase } from "../../src/internal-runtime/coinbase.js";
import { loadConfig } from "../../src/internal-runtime/config.js";
import type { RegentIdentityReceipt } from "../../src/internal-types/index.js";
import { TEST_COINBASE_WALLET, writeFakeCdp } from "../support/fake-cdp.js";

const OTHER_WALLET = "0x1111111111111111111111111111111111111111" as const;
const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";
const TEST_AGENT_ID = `eip155:8453:${TEST_REGISTRY}:99`;

const writeReceipt = (homeDir: string, receipt: RegentIdentityReceipt): void => {
  const receiptPath = path.join(homeDir, ".regent", "identity", "receipt-v1.json");
  fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, "utf8");
};

const writeWalletState = (homeDir: string, wallet: { name: string; address: string }): void => {
  const walletStatePath = path.join(homeDir, "state", "coinbase-wallet.json");
  fs.mkdirSync(path.dirname(walletStatePath), { recursive: true });
  fs.writeFileSync(walletStatePath, `${JSON.stringify(wallet, null, 2)}\n`, "utf8");
};

describe("coinbaseStatus", () => {
  let tempDir = "";
  let originalHome: string | undefined;
  let originalPath: string | undefined;
  let originalKeyId: string | undefined;
  let originalKeySecret: string | undefined;
  let originalWalletSecret: string | undefined;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-coinbase-status-"));
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
  });

  afterEach(() => {
    process.env.HOME = originalHome;
    process.env.PATH = originalPath;
    process.env.CDP_KEY_ID = originalKeyId;
    process.env.CDP_KEY_SECRET = originalKeySecret;
    process.env.CDP_WALLET_SECRET = originalWalletSecret;
  });

  it("marks the identity ready when the cached receipt matches the active wallet and network", async () => {
    const config = loadConfig(path.join(tempDir, "regent.config.json"));
    writeReceipt(tempDir, {
      version: 1,
      regent_base_url: config.services.siwa.baseUrl,
      network: "base",
      provider: "coinbase-cdp",
      address: TEST_COINBASE_WALLET,
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
    });

    const status = await coinbaseStatus(config, { network: "base" });

    expect(status.ok).toBe(true);
    expect(status.identity_ready).toBe(true);
    expect(status.account).toEqual({
      name: "main",
      address: TEST_COINBASE_WALLET,
    });
  });

  it("does not trust a cached receipt from a different wallet", async () => {
    const config = loadConfig(path.join(tempDir, "regent.config.json"));
    writeReceipt(tempDir, {
      version: 1,
      regent_base_url: config.services.siwa.baseUrl,
      network: "base",
      provider: "coinbase-cdp",
      address: OTHER_WALLET,
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
    });

    const status = await coinbaseStatus(config, { network: "base" });

    expect(status.ok).toBe(false);
    expect(status.identity_ready).toBe(false);
    expect(status.next_action).toEqual({
      reason: "The wallet is ready, but the Regent identity receipt is missing or expired.",
      command: "regents identity ensure",
    });
  });

  it("does not trust a cached receipt from a different network", async () => {
    const config = loadConfig(path.join(tempDir, "regent.config.json"));
    writeReceipt(tempDir, {
      version: 1,
      regent_base_url: config.services.siwa.baseUrl,
      network: "base",
      provider: "coinbase-cdp",
      address: TEST_COINBASE_WALLET,
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
    });

    const status = await coinbaseStatus(config, { network: "base-sepolia" });

    expect(status.ok).toBe(false);
    expect(status.identity_ready).toBe(false);
    expect(status.next_action).toEqual({
      reason: "The wallet is ready, but the Regent identity receipt is missing or expired.",
      command: "regents identity ensure",
    });
  });

  it("does not silently switch to a different wallet when the saved Coinbase wallet is gone", async () => {
    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "secondary", address: OTHER_WALLET }],
    })}:${originalPath ?? ""}`;

    const config = loadConfig(path.join(tempDir, "regent.config.json"));
    writeWalletState(tempDir, {
      name: "missing-wallet",
      address: TEST_COINBASE_WALLET,
    });

    const status = await coinbaseStatus(config);

    expect(status.account).toBeNull();
    expect(status.ok).toBe(false);
    expect(status.next_action).toEqual({
      reason: "No Coinbase wallet account has been prepared for this machine.",
      command: "regents wallet setup",
    });
  });

  it("keeps using the saved wallet when the name changes but the address stays the same", async () => {
    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "renamed-wallet", address: TEST_COINBASE_WALLET }],
    })}:${originalPath ?? ""}`;

    const config = loadConfig(path.join(tempDir, "regent.config.json"));
    writeWalletState(tempDir, {
      name: "main",
      address: TEST_COINBASE_WALLET,
    });

    const status = await coinbaseStatus(config);

    expect(status.account).toEqual({
      name: "renamed-wallet",
      address: TEST_COINBASE_WALLET,
    });
  });

  it("signs with the saved wallet address when the cached wallet hint is stale", async () => {
    process.env.PATH = `${writeFakeCdp(tempDir, {
      accounts: [{ name: "renamed-wallet", address: TEST_COINBASE_WALLET }],
    })}:${originalPath ?? ""}`;

    const config = loadConfig(path.join(tempDir, "regent.config.json"));

    const signed = await signMessageWithCoinbase(config, {
      message: "hello",
      walletHint: "main",
      expectedAddress: TEST_COINBASE_WALLET,
    });

    expect(signed.address).toBe(TEST_COINBASE_WALLET);
    expect(signed.walletHint).toBe("renamed-wallet");
  });
});
