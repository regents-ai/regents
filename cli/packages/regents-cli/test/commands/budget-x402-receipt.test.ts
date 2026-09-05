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
  runAwalJsonMock: vi.fn(), kernelCallMock: vi.fn(), kernelStopMock: vi.fn(),
}));
vi.mock("../../src/internal-runtime/agentic-wallet/awal.js", async importOriginal => ({
  ...await importOriginal<typeof import("../../src/internal-runtime/agentic-wallet/awal.js")>(), runAwalJson: runAwalJsonMock,
}));
vi.mock("../../src/internal-runtime/runtime.js", () => ({
  RegentKernel: vi.fn().mockImplementation(() => ({call: kernelCallMock, stop: kernelStopMock})),
}));

const grant = async (rail = "agentic-wallet", mode = "techtree_research") => {
  const configPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "regents-budget-x402-")), "regent.config.json");
  writeInitialConfig(configPath);
  const output = await captureOutput(() => runBudgetGrant(parseCliArgs([
    "budget", "grant", "--agent", "agent_123", "--amount-usdc", "10", "--max-payment-usdc", "0.25",
    "--mode", mode, "--rail", rail, "--expires", "7d", "--json",
  ]), configPath));
  return {configPath, id: parsePrintedJson(output.stdout).budget.budget_id as string, rail};
};
const pay = (budget: Awaited<ReturnType<typeof grant>>, extra: string[] = []) => captureOutput(() => runX402Pay(parseCliArgs([
  "x402", "pay", "https://api.example.com/paid", "--budget", budget.id,
  "--max-usdc", "0.25", "--rail", budget.rail, "--receipt", "--json", ...extra,
]), budget.configPath));
const current = (budget: Awaited<ReturnType<typeof grant>>) => readBudgetFile(loadConfig(budget.configPath)).budgets[0]!;
const selected = {scheme: "exact", network: "eip155:8453", asset: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", amount: "100000"};

beforeEach(() => {
  vi.clearAllMocks();
  kernelStopMock.mockResolvedValue(undefined);
  runAwalJsonMock.mockResolvedValue({ok: true, command: [], data: {
    status: 200, paymentMade: true, amountPaid: "100000", payment_id: "awal_payment_1", data: {answer: "synthetic"},
  }});
});

describe("budget-backed x402 outcomes", () => {
  it("preserves the POST body and records reported spend rather than the maximum", async () => {
    const budget = await grant();
    const output = await pay(budget, ["--method", "POST", "--body", '{"note":"synthetic"}']);
    const result = parsePrintedJson(output.stdout);
    expect(runAwalJsonMock).toHaveBeenCalledWith([
      "x402", "pay", "https://api.example.com/paid", "--method", "POST", "--data", '{"note":"synthetic"}',
      "--max-amount", "250000", "--json", "--correlation-id", result.reservation_id,
    ]);
    expect(result.payment_status).toBe("settled");
    expect(result.settlement_evidence).toBe("provider_reported");
    expect(result.budget.remaining_usdc).toBe("9.9");
    expect(result.budget.ledger.at(-1)).toMatchObject({type: "settle", amount_usdc: "0.1", reference: "awal_payment_1"});
    const shared = await captureOutput(() => runReceiptShareDraft(parseCliArgs([
      "receipt", "share-draft", "--receipt", result.receipt.receipt_id,
    ]), budget.configPath));
    expect(shared.stdout).toContain("recorded an x402 payment reference");
    expect(shared.stdout).not.toContain("completed an x402 payment");
  });

  for (const response of [{ok: true}, {status: 200, payment_id: "not-proof"}, {status: 200, paymentMade: true}]) {
    it(`retains reservation without complete provider evidence ${JSON.stringify(response)}`, async () => {
      runAwalJsonMock.mockResolvedValueOnce({ok: true, data: response});
      const budget = await grant();
      const result = parsePrintedJson((await pay(budget)).stdout);
      expect(result.payment_status).toBe("unknown");
      expect(result.ok).toBe(false);
      expect(result.accounting_status).toBe("reserved");
      expect(result.budget.remaining_usdc).toBe("9.75");
      expect(result.provider_correlation_id).toBe(result.reservation_id);
      expect(result.reported_spend_usdc).toBeUndefined();
      expect(current(budget).ledger.at(-1)?.type).toBe("reserve");
    });
  }

  it("retains the reservation and correlation identity after a possibly submitted provider error", async () => {
    runAwalJsonMock.mockRejectedValueOnce(new Error("sensitive raw command/body must not appear"));
    const budget = await grant();
    const output = await pay(budget);
    const result = parsePrintedJson(output.stdout);
    expect(result.payment_status).toBe("unknown");
    expect(result.accounting_status).toBe("reserved");
    expect(result.provider_correlation_id).toBe(result.reservation_id);
    expect(output.stdout).not.toContain("sensitive raw command");
    expect(current(budget).remaining_usdc).toBe("9.75");
    expect(runAwalJsonMock).toHaveBeenCalledTimes(1);
  });

  it("records a settled payment even when the product HTTP operation failed", async () => {
    runAwalJsonMock.mockResolvedValueOnce({ok: true, data: {status: 500, paymentMade: true, amountPaid: 100000, paymentId: "paid_500"}});
    const result = parsePrintedJson((await pay(await grant())).stdout);
    expect(result.ok).toBe(false);
    expect(result.http_status).toBe(500);
    expect(result.payment_status).toBe("settled");
    expect(result.budget.remaining_usdc).toBe("9.9");
  });

  it("releases a reservation only for an explicit no-payment response", async () => {
    runAwalJsonMock.mockResolvedValueOnce({ok: true, data: {status: 402, paymentMade: false}});
    const result = parsePrintedJson((await pay(await grant())).stdout);
    expect(result.payment_status).toBe("not_paid");
    expect(result.budget.remaining_usdc).toBe("10");
    expect(result.budget.ledger.at(-1).type).toBe("release");
  });

  for (const extra of [["--header", "authorization: private"], ["--method", "POST", "--body", '{ "n":1 }'],
    ["--method", "POST", "--body", '{"n":9007199254740993}']]) {
    it(`rejects unsupported request form before provider dispatch: ${extra[0]}`, async () => {
      const budget = await grant();
      await expect(pay(budget, extra)).rejects.toThrow(/Agentic Wallet/);
      expect(runAwalJsonMock).not.toHaveBeenCalled();
      expect(current(budget).ledger.at(-1)?.type).toBe("grant");
    });
  }

  it("checks the local grant before calling the provider", async () => {
    const budget = await grant();
    await expect(captureOutput(() => runX402Pay(parseCliArgs(["x402", "pay", "https://api.example.com/paid", "--budget", budget.id, "--max-usdc", "0.5", "--rail", "agentic-wallet", "--json"]), budget.configPath))).rejects.toThrow(/larger than this budget/);
    expect(runAwalJsonMock).not.toHaveBeenCalled();
  });

  it("preserves explicit approval for paid-service budgets", async () => {
    await expect(pay(await grant("agentic-wallet", "paid_service"))).rejects.toThrow(/require --approve/);
    expect(runAwalJsonMock).not.toHaveBeenCalled();
  });

  for (const paymentStatus of ["settled", "unknown"]) {
    it(`keeps Regent settlement separate from a failed product result: ${paymentStatus}`, async () => {
      kernelCallMock.mockResolvedValueOnce({ok: true, intent: {intent_id: "intent_1", selected}})
        .mockResolvedValueOnce({ok: false, status: 500, payment_status: paymentStatus, receipt: {receipt_id: "receipt_1"}});
      const result = parsePrintedJson((await pay(await grant("regent-wallet"))).stdout);
      expect(result.ok).toBe(false);
      expect(result.payment_status).toBe(paymentStatus);
      expect(result.budget.remaining_usdc).toBe(paymentStatus === "settled" ? "9.9" : "9.75");
      expect(result.payment_reference).toBe("receipt_1");
      expect(result.intent_id).toBe("intent_1");
    });
  }

  for (const changed of [{asset: "0x0000000000000000000000000000000000000000"}, {network: "eip155:1"}, {scheme: "batch-settlement"}]) {
    it(`rejects an unsupported USDC-budget requirement before signing: ${JSON.stringify(changed)}`, async () => {
      kernelCallMock.mockResolvedValueOnce({ok: true, intent: {intent_id: "intent_1", selected: {...selected, ...changed}}});
      const budget = await grant("regent-wallet");
      await expect(pay(budget)).rejects.toThrow(/USDC budgets support exact/);
      expect(kernelCallMock).toHaveBeenCalledTimes(1);
      expect(current(budget).remaining_usdc).toBe("10");
      expect(current(budget).ledger.at(-1)?.type).toBe("release");
    });
  }

  it("runs raw atomic refunds through the existing local runtime", async () => {
    kernelCallMock.mockResolvedValueOnce({ok: true, settlement: {success: true}});
    const budget = await grant();
    await captureOutput(() => runX402Refund(parseCliArgs(["x402", "refund", "--url", "https://api.example.com/paid", "--amount", "1000", "--json"]), budget.configPath));
    expect(kernelCallMock).toHaveBeenCalledWith("x402.refund", {url: "https://api.example.com/paid", amount: "1000"});
  });
});

for (const extra of [["--headers", "authorization: private"], ["--metho", "POST"], ["--approve=false"], ["--receipt=true"], ["--json=false"], ["--method"], ["--", "extra-url"]]) {
  it(`rejects ambiguous paid CLI input before any dispatch or reservation: ${extra.join(" ")}`, async () => {
    const budget = await grant();
    await expect(pay(budget, extra)).rejects.toThrow();
    expect(runAwalJsonMock).not.toHaveBeenCalled();
    expect(kernelCallMock).not.toHaveBeenCalled();
    expect(current(budget).ledger.at(-1)?.type).toBe("grant");
  });
}
