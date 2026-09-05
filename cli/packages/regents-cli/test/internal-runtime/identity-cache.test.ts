import { describe, expect, it } from "vitest";

import { receiptMatchesRequest } from "../../src/internal-runtime/identity/cache.js";
import type { RegentIdentityReceipt } from "../../src/internal-types/index.js";

const baseReceipt = (): RegentIdentityReceipt => ({
  version: 1,
  regent_base_url: "https://regent.example",
  network: "base",
  provider: "coinbase-cdp",
  address: "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
  agent_id: "eip155:8453:0x1111111111111111111111111111111111111111:99",
  token_id: "99",
  agent_registry: "0x1111111111111111111111111111111111111111",
  signer_type: "evm_personal_sign",
  verified: "onchain",
  receipt: "receipt-valid",
  receipt_issued_at: "2026-04-17T00:00:00.000Z",
  receipt_expires_at: "2999-01-01T00:00:00.000Z",
  cached_at: "2026-04-17T00:00:00.000Z",
});

describe("identity receipt cache matching", () => {
  it("accepts a cached receipt when the network and base URL match", () => {
    expect(
      receiptMatchesRequest({
        receipt: baseReceipt(),
        network: "base",
        regentBaseUrl: "https://regent.example",
      }),
    ).toBe(true);
  });

  it("rejects a cached receipt when the caller requests a different wallet hint", () => {
    expect(
      receiptMatchesRequest({
        receipt: { ...baseReceipt(), wallet_hint: "wallet_alpha" },
        network: "base",
        regentBaseUrl: "https://regent.example",
        walletHint: "wallet_beta",
      }),
    ).toBe(false);
  });

  it("accepts a cached receipt when the wallet hint points at the cached address", () => {
    expect(
      receiptMatchesRequest({
        receipt: { ...baseReceipt() },
        network: "base",
        regentBaseUrl: "https://regent.example",
        walletHint: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
      }),
    ).toBe(true);
  });
});
