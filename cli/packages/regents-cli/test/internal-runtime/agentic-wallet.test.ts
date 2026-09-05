import { describe, expect, it } from "vitest";

import {
  awalCommand,
  redactAwalCommand,
  redactAwalValue,
} from "../../src/internal-runtime/agentic-wallet/awal.js";

describe("Agentic Wallet command safety", () => {
  it("builds pinned argv for AWAL without shell strings", () => {
    expect(awalCommand(["status", "--json"])).toEqual([
      "npx",
      "-y",
      "awal@2.10.0",
      "status",
      "--json",
    ]);
  });

  it("redacts verification and payment-sensitive output", () => {
    expect(redactAwalCommand(awalCommand(["auth", "verify", "flow_123", "123456", "--json"]))).toEqual([
      "npx",
      "-y",
      "awal@2.10.0",
      "auth",
      "verify",
      "[redacted]",
      "[redacted]",
      "--json",
    ]);

    expect(redactAwalValue({
      ok: true,
      otp: "123456",
      nested: { paymentHeader: "secret-header", address: "0xabc" },
    })).toEqual({
      ok: true,
      otp: "[redacted]",
      nested: { paymentHeader: "[redacted]", address: "0xabc" },
    });
  });
});
