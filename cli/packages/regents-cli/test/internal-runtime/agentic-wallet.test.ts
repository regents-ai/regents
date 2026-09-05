import { describe, expect, it, vi } from "vitest";

import {
  awalCommand,
  awalPaymentOutcome,
  runAwalJson,
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

describe("provider result fidelity", () => {
  it("preserves product tokens and public payment references while removing credentials", () => {
    expect(redactAwalValue({payment_id: "payment_1", amountPaid: "100000", paymentMade: true,
      data: {token_address: "0xabc", tokens: ["USDC"], token_count: 2},
      access_token: "private", refreshToken: "private", id_token: "private", privateKey: "private",
      paymentHeader: "signed", signature: "signed", authorization: "private"})).toEqual({
      payment_id: "payment_1", amountPaid: "100000", paymentMade: true,
      data: {token_address: "0xabc", tokens: ["USDC"], token_count: 2},
      access_token: "[redacted]", refreshToken: "[redacted]", id_token: "[redacted]", privateKey: "[redacted]",
      paymentHeader: "[redacted]", signature: "[redacted]", authorization: "[redacted]",
    });
    const echo = redactAwalCommand(awalCommand(["x402", "pay", "https://example.test/paid?secret=value", "--data", '{"private":"body"}']));
    expect(echo.join(" ")).not.toContain("secret=value");
    expect(echo.join(" ")).not.toContain("private");
  });
});

vi.mock("node:child_process", () => ({execFile: vi.fn((_file, _args, _options, callback) => {
  callback(Object.assign(new Error("secret argv"), {stdout: "secret stdout", stderr: "secret stderr", cmd: "secret body"}));
})}));

it("does not expose raw subprocess failure details", async () => {
  const failure = await runAwalJson(["x402", "pay", "https://example.test/paid"]).catch(error => error);
  expect(failure.code).toBe("awal_command_failed");
  expect(failure.cause).toBeUndefined();
  expect(failure.message).not.toContain("secret");
});

it("requires exact provider spend evidence and separates it from HTTP success", () => {
  for (const amountPaid of [undefined, 1.2, -1, Number.MAX_SAFE_INTEGER + 1, "1.0", "-1"]) {
    expect(awalPaymentOutcome({status: 200, paymentMade: true, amountPaid}).payment_status).toBe("unknown");
  }
  expect(awalPaymentOutcome({status: 500, paymentMade: true, amountPaid: "9007199254740993"})).toMatchObject({
    payment_status: "settled", http_ok: false, amount_atomic: "9007199254740993",
  });
  expect(awalPaymentOutcome({status: 200, paymentMade: false, amountPaid: "1"}).payment_status).toBe("unknown");
});
