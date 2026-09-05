import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

import { runBudgetGrant } from "../../src/commands/budget.js";
import { runReceiptShareDraft } from "../../src/commands/receipt.js";
import { runX402Pay, runX402Refund } from "../../src/commands/x402.js";
import { readBudgetFile } from "../../src/internal-runtime/budget-store.js";
import { loadConfig } from "../../src/internal-runtime/config.js";
import { writeInitialConfig } from "../../src/internal-runtime/index.js";
import { parseCliArgs } from "../../src/parse.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { runAwalJsonMock, kernelCallMock, kernelStopMock } = vi.hoisted(() => ({
  runAwalJsonMock: vi.fn(),
  kernelCallMock: vi.fn(),
  kernelStopMock: vi.fn(),
}));

vi.mock("../../src/internal-runtime/agentic-wallet/awal.js", () => ({
  AWAL_VERSION: "2.10.0",
  runAwalJson: runAwalJsonMock,
}));

vi.mock("../../src/internal-runtime/runtime.js", () => ({
  RegentKernel: vi.fn().mockImplementation(() => ({
    call: kernelCallMock,
    stop: kernelStopMock,
  })),
}));

const makeConfigPath = (): string => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-budget-x402-"));
  const configPath = path.join(tempDir, "regent.config.json");
  writeInitialConfig(configPath);
  return configPath;
};

describe("budget, guarded x402, and local receipts", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    kernelStopMock.mockResolvedValue(undefined);
    runAwalJsonMock.mockResolvedValue({
      ok: true,
      command: ["npx", "-y", "awal@2.10.0", "x402", "pay"],
      data: { ok: true, payment_id: "awal_payment_1" },
    });
  });

  it("converts max USDC exactly and decrements budget only after payment succeeds", async () => {
    const configPath = makeConfigPath();
    const grantOutput = await captureOutput(() =>
      runBudgetGrant(
        parseCliArgs([
          "budget",
          "grant",
          "--agent",
          "agent_123",
          "--amount-usdc",
          "10",
          "--max-payment-usdc",
          "0.25",
          "--mode",
          "techtree_research",
          "--rail",
          "agentic-wallet",
          "--expires",
          "7d",
          "--json",
        ]),
        configPath,
      ),
    );
    const grant = parsePrintedJson<{ budget: { budget_id: string } }>(grantOutput.stdout);

    const payOutput = await captureOutput(() =>
      runX402Pay(
        parseCliArgs([
          "x402",
          "pay",
          "https://api.example.com/paid",
          "--budget",
          grant.budget.budget_id,
          "--max-usdc",
          "0.25",
          "--rail",
          "agentic-wallet",
          "--receipt",
          "--json",
        ]),
        configPath,
      ),
    );

    expect(runAwalJsonMock).toHaveBeenCalledWith([
      "x402",
      "pay",
      "https://api.example.com/paid",
      "--max-amount",
      "250000",
      "--json",
    ]);
    const paid = parsePrintedJson<{
      budget: { remaining_usdc: string; ledger: Array<{ entry_id: string; type: string; rail?: string; reference?: string; reservation_id?: string }> };
      receipt: { receipt_id: string; recognized_revenue: boolean; x402: { payments: string[] } };
    }>(payOutput.stdout);
    expect(paid.budget.remaining_usdc).toBe("9.75");
    expect(paid.budget.ledger.at(-2)).toEqual(expect.objectContaining({
      type: "reserve",
      rail: "agentic-wallet",
      reference: "https://api.example.com/paid",
    }));
    expect(paid.budget.ledger.at(-1)).toEqual(expect.objectContaining({
      type: "settle",
      rail: "agentic-wallet",
      reference: "awal_payment_1",
      reservation_id: paid.budget.ledger.at(-2)!.entry_id,
    }));
    expect(paid.receipt.recognized_revenue).toBe(false);
    expect(paid.receipt.x402.payments).toEqual(["awal_payment_1"]);

    const shareOutput = await captureOutput(() =>
      runReceiptShareDraft(parseCliArgs(["receipt", "share-draft", "--receipt", paid.receipt.receipt_id]), configPath),
    );
    expect(shareOutput.stdout).toContain("not a revenue claim");
  });

  it("uses the local budget ledger as the receipt source when Agentic Wallet does not return a payment id", async () => {
    runAwalJsonMock.mockResolvedValueOnce({
      ok: true,
      command: ["npx", "-y", "awal@2.10.0", "x402", "pay"],
      data: { ok: true },
    });

    const configPath = makeConfigPath();
    const grantOutput = await captureOutput(() =>
      runBudgetGrant(
        parseCliArgs([
          "budget",
          "grant",
          "--agent",
          "agent_123",
          "--amount-usdc",
          "1",
          "--max-payment-usdc",
          "0.10",
          "--mode",
          "techtree_research",
          "--rail",
          "agentic-wallet",
          "--expires",
          "7d",
          "--json",
        ]),
        configPath,
      ),
    );
    const grant = parsePrintedJson<{ budget: { budget_id: string } }>(grantOutput.stdout);

    const payOutput = await captureOutput(() =>
      runX402Pay(
        parseCliArgs([
          "x402",
          "pay",
          "https://api.example.com/paid",
          "--budget",
          grant.budget.budget_id,
          "--max-usdc",
          "0.10",
          "--rail",
          "agentic-wallet",
          "--receipt",
          "--json",
        ]),
        configPath,
      ),
    );

    const paid = parsePrintedJson<{
      budget: { ledger: Array<{ entry_id: string; type: string; rail?: string; reference?: string }> };
      receipt: { kind: string; budget: { ledger_entry: string } };
    }>(payOutput.stdout);
    const spendEntry = paid.budget.ledger.at(-1)!;
    expect(spendEntry.type).toBe("settle");
    expect(spendEntry.rail).toBe("agentic-wallet");
    expect(spendEntry.reference).toBeUndefined();
    expect(paid.receipt.kind).toBe("budget_entry");
    expect(paid.receipt.budget.ledger_entry).toBe(spendEntry.entry_id);
  });

  it("rejects over-budget x402 pay before calling Agentic Wallet", async () => {
    const configPath = makeConfigPath();
    const grantOutput = await captureOutput(() =>
      runBudgetGrant(
        parseCliArgs([
          "budget",
          "grant",
          "--agent",
          "agent_123",
          "--amount-usdc",
          "1",
          "--max-payment-usdc",
          "0.10",
          "--mode",
          "techtree_research",
          "--rail",
          "agentic-wallet",
          "--expires",
          "7d",
          "--json",
        ]),
        configPath,
      ),
    );
    const grant = parsePrintedJson<{ budget: { budget_id: string } }>(grantOutput.stdout);

    await expect(
      runX402Pay(
        parseCliArgs([
          "x402",
          "pay",
          "https://api.example.com/paid",
          "--budget",
          grant.budget.budget_id,
          "--max-usdc",
          "0.25",
          "--rail",
          "agentic-wallet",
          "--json",
        ]),
        configPath,
      ),
    ).rejects.toThrow("--max-usdc is larger than this budget allows.");
    expect(runAwalJsonMock).not.toHaveBeenCalled();
  });

  it("releases a reserved budget when payment fails before completion", async () => {
    runAwalJsonMock.mockRejectedValueOnce(new Error("wallet denied"));

    const configPath = makeConfigPath();
    const grantOutput = await captureOutput(() =>
      runBudgetGrant(
        parseCliArgs([
          "budget",
          "grant",
          "--agent",
          "agent_123",
          "--amount-usdc",
          "1",
          "--max-payment-usdc",
          "0.10",
          "--mode",
          "techtree_research",
          "--rail",
          "agentic-wallet",
          "--expires",
          "7d",
          "--json",
        ]),
        configPath,
      ),
    );
    const grant = parsePrintedJson<{ budget: { budget_id: string } }>(grantOutput.stdout);

    await expect(
      runX402Pay(
        parseCliArgs([
          "x402",
          "pay",
          "https://api.example.com/paid",
          "--budget",
          grant.budget.budget_id,
          "--max-usdc",
          "0.10",
          "--rail",
          "agentic-wallet",
          "--json",
        ]),
        configPath,
      ),
    ).rejects.toThrow("wallet denied");

    const budget = readBudgetFile(loadConfig(configPath)).budgets[0]!;
    expect(budget.remaining_usdc).toBe("1");
    expect(budget.ledger.at(-2)).toEqual(expect.objectContaining({
      type: "reserve",
      amount_usdc: "0.1",
    }));
    expect(budget.ledger.at(-1)).toEqual(expect.objectContaining({
      type: "release",
      amount_usdc: "0.1",
      reservation_id: budget.ledger.at(-2)!.entry_id,
    }));
  });

  it("uses the Regent wallet rail and records the actual x402 receipt amount", async () => {
    kernelCallMock
      .mockResolvedValueOnce({
        ok: true,
        intent: {
          intent_id: "x402_intent_1",
          selected: { amount: "100000" },
        },
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        content_type: "application/json",
        body_text: "{\"ok\":true}",
        receipt: {
          receipt_id: "x402_receipt_1",
          intent_id: "x402_intent_1",
          status: 200,
          ok: true,
        },
      });

    const configPath = makeConfigPath();
    const grantOutput = await captureOutput(() =>
      runBudgetGrant(
        parseCliArgs([
          "budget",
          "grant",
          "--agent",
          "agent_123",
          "--amount-usdc",
          "10",
          "--max-payment-usdc",
          "0.25",
          "--mode",
          "techtree_research",
          "--rail",
          "regent-wallet",
          "--expires",
          "7d",
          "--json",
        ]),
        configPath,
      ),
    );
    const grant = parsePrintedJson<{ budget: { budget_id: string } }>(grantOutput.stdout);

    const payOutput = await captureOutput(() =>
      runX402Pay(
        parseCliArgs([
          "x402",
          "pay",
          "https://api.example.com/paid",
          "--budget",
          grant.budget.budget_id,
          "--max-usdc",
          "0.25",
          "--rail",
          "regent-wallet",
          "--receipt",
          "--json",
        ]),
        configPath,
      ),
    );

    expect(kernelCallMock).toHaveBeenNthCalledWith(1, "x402.prepare", expect.objectContaining({
      approve: true,
      max_amount: "250000",
      url: "https://api.example.com/paid",
    }));
    expect(kernelCallMock).toHaveBeenNthCalledWith(2, "x402.fetch", expect.objectContaining({
      intent_id: "x402_intent_1",
      url: "https://api.example.com/paid",
    }));
    expect(runAwalJsonMock).not.toHaveBeenCalled();

    const paid = parsePrintedJson<{
      budget: { remaining_usdc: string; ledger: Array<{ entry_id?: string; type: string; rail?: string; reference?: string; reservation_id?: string }> };
      receipt: { receipt_id: string };
    }>(payOutput.stdout);
    expect(paid.budget.remaining_usdc).toBe("9.9");
    expect(paid.budget.ledger.at(-2)).toEqual(expect.objectContaining({
      type: "reserve",
      rail: "regent-wallet",
      reference: "https://api.example.com/paid",
    }));
    expect(paid.budget.ledger.at(-1)).toEqual(expect.objectContaining({
      type: "settle",
      rail: "regent-wallet",
      reference: "x402_receipt_1",
      reservation_id: paid.budget.ledger.at(-2)!.entry_id,
    }));
    expect(paid.receipt.receipt_id).toMatch(/^rcpt_/u);
  });

  it("requires explicit approval for paid service budgets", async () => {
    const configPath = makeConfigPath();
    const grantOutput = await captureOutput(() =>
      runBudgetGrant(
        parseCliArgs([
          "budget",
          "grant",
          "--agent",
          "agent_123",
          "--amount-usdc",
          "1",
          "--max-payment-usdc",
          "0.10",
          "--mode",
          "paid_service",
          "--rail",
          "agentic-wallet",
          "--expires",
          "7d",
          "--json",
        ]),
        configPath,
      ),
    );
    const grant = parsePrintedJson<{ budget: { budget_id: string } }>(grantOutput.stdout);

    await expect(
      runX402Pay(
        parseCliArgs([
          "x402",
          "pay",
          "https://api.example.com/paid",
          "--budget",
          grant.budget.budget_id,
          "--max-usdc",
          "0.10",
          "--rail",
          "agentic-wallet",
          "--json",
        ]),
        configPath,
      ),
    ).rejects.toThrow("Paid service budgets require --approve before payment.");
    expect(runAwalJsonMock).not.toHaveBeenCalled();
  });

  it("runs x402 refund through the local runtime", async () => {
    kernelCallMock.mockResolvedValueOnce({
      ok: true,
      url: "https://api.example.com/paid",
      amount: "1000",
      settlement: { success: true },
    });

    const configPath = makeConfigPath();
    const refundOutput = await captureOutput(() =>
      runX402Refund(
        parseCliArgs([
          "x402",
          "refund",
          "--url",
          "https://api.example.com/paid",
          "--amount",
          "1000",
          "--json",
        ]),
        configPath,
      ),
    );

    expect(kernelCallMock).toHaveBeenCalledWith("x402.refund", {
      url: "https://api.example.com/paid",
      amount: "1000",
    });
    expect(parsePrintedJson<{ ok: boolean }>(refundOutput.stdout).ok).toBe(true);
  });
});
