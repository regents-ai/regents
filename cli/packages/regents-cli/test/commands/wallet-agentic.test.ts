import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  runWalletAgenticFund,
  runWalletAgenticLogin,
  runWalletAgenticVerify,
} from "../../src/commands/wallet-agentic.js";
import { parseCliArgs } from "../../src/parse.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { runAwalJsonMock } = vi.hoisted(() => ({
  runAwalJsonMock: vi.fn(),
}));

vi.mock("../../src/internal-runtime/agentic-wallet/awal.js", () => ({
  AWAL_VERSION: "2.10.0",
  runAwalJson: runAwalJsonMock,
}));

describe("wallet agentic commands", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    runAwalJsonMock.mockResolvedValue({ ok: true, command: [], data: { ok: true } });
  });

  it("starts login with an email flag", async () => {
    await captureOutput(() =>
      runWalletAgenticLogin(parseCliArgs([
        "wallet",
        "agentic",
        "login",
        "--email",
        "user@example.com",
        "--json",
      ])),
    );

    expect(runAwalJsonMock).toHaveBeenCalledWith(["auth", "login", "user@example.com", "--json"]);
  });

  it("verifies with flow and OTP flags without printing raw positional secrets", async () => {
    runAwalJsonMock.mockResolvedValue({
      ok: true,
      command: ["npx", "-y", "awal@2.10.0", "auth", "verify", "[redacted]", "[redacted]", "--json"],
      data: { ok: true },
    });

    const output = await captureOutput(() =>
      runWalletAgenticVerify(parseCliArgs([
        "wallet",
        "agentic",
        "verify",
        "--flow-id",
        "flow_123",
        "--otp",
        "123456",
        "--json",
      ])),
    );

    expect(runAwalJsonMock).toHaveBeenCalledWith(["auth", "verify", "flow_123", "123456", "--json"]);
    expect(output.stdout).not.toContain("123456");
    expect(output.stdout).not.toContain("flow_123");
    expect(parsePrintedJson<{ command: string[] }>(output.stdout).command).toContain("[redacted]");
  });

  it("keeps funding guidance clear of internal runtime wording", async () => {
    const output = await captureOutput(() =>
      runWalletAgenticFund(parseCliArgs([
        "wallet",
        "agentic",
        "fund",
        "--amount-usdc",
        "10",
        "--chain",
        "base",
        "--json",
      ])),
    );

    const payload = parsePrintedJson<{ warning: string }>(output.stdout);
    expect(payload.warning).toContain("Safe treasury");
    expect(payload.warning).not.toContain("runtime");
  });
});
