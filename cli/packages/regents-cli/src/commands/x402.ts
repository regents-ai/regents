import { withNextSteps } from "../command-payload.js";
import type { ParsedCliArgs } from "../parse.js";

import type {
  X402FetchParams,
  X402PrepareParams,
  X402QuoteParams,
  X402ReceiptGetParams,
  X402RefundParams,
  X402RequestInput,
} from "../internal-types/index.js";
import { RegentKernel } from "../internal-runtime/runtime.js";
import { runAwalJson } from "../internal-runtime/agentic-wallet/awal.js";
import {
  atomicStringToUsdc,
  releaseBudgetReservation,
  reserveBudgetPayment,
  settleBudgetReservation,
  usdcToAtomicString,
  type PaymentRail,
} from "../internal-runtime/budget-store.js";
import { createReceipt } from "../internal-runtime/receipt-store.js";
import { loadConfig } from "../internal-runtime/config.js";
import { getBooleanFlag, getFlag, getFlags, requireArg } from "../parse.js";
import { CLI_PALETTE, printJson, printText, renderKeyValuePanel } from "../printer.js";
import { CliUsageError } from "../cli-usage-error.js";

const parseHeaders = (args: ParsedCliArgs): Record<string, string> | undefined => {
  const headers = getFlags(args, "header");
  if (headers.length === 0) {
    return undefined;
  }

  return Object.fromEntries(
    headers.map((header) => {
      const separatorIndex = header.indexOf(":");
      if (separatorIndex <= 0) {
        throw new CliUsageError({
          code: "invalid_header",
          message: "--header must use Name: value form.",
          example: "regents x402 quote --url https://api.example.com/paid --header 'accept: application/json'",
        });
      }

      return [header.slice(0, separatorIndex).trim(), header.slice(separatorIndex + 1).trim()];
    }),
  );
};

const requestInput = (args: ParsedCliArgs): X402RequestInput => ({
  url: requireArg(getFlag(args, "url"), "--url"),
  method: getFlag(args, "method")?.toUpperCase() as X402RequestInput["method"],
  headers: parseHeaders(args),
  body: getFlag(args, "body"),
});

const quoteInput = (args: ParsedCliArgs): X402QuoteParams => ({
  ...requestInput(args),
  max_amount: getFlag(args, "max-amount"),
  max_deposit_amount: getFlag(args, "max-deposit-amount"),
});

const prepareInput = (args: ParsedCliArgs): X402PrepareParams => ({
  ...quoteInput(args),
  approve: getBooleanFlag(args, "approve"),
});

const fetchInput = (args: ParsedCliArgs): X402FetchParams => ({
  ...requestInput(args),
  intent_id: requireArg(getFlag(args, "intent-id"), "--intent-id"),
});

const receiptGetInput = (args: ParsedCliArgs): X402ReceiptGetParams => ({
  id: requireArg(getFlag(args, "id"), "--id"),
});

const refundInput = (args: ParsedCliArgs): X402RefundParams => {
  const headers = parseHeaders(args);
  const amount = getFlag(args, "amount");

  return {
    url: requireArg(getFlag(args, "url"), "--url"),
    ...(headers ? { headers } : {}),
    ...(amount ? { amount } : {}),
  };
};

const x402Query = (args: ParsedCliArgs): string => requireArg(args.positionals.slice(2).join(" "), "query");

const x402PayUrl = (args: ParsedCliArgs): string => requireArg(args.positionals[2], "url");

const parseRail = (value: string | undefined): PaymentRail => {
  if (value === "regent-wallet" || value === "agentic-wallet") {
    return value;
  }

  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--rail must be regent-wallet or agentic-wallet.",
    validValues: ["regent-wallet", "agentic-wallet"],
  });
};

const payRequestInput = (args: ParsedCliArgs): X402RequestInput => ({
  url: x402PayUrl(args),
  method: getFlag(args, "method")?.toUpperCase() as X402RequestInput["method"],
  headers: parseHeaders(args),
  body: getFlag(args, "body"),
});

const paymentReferenceKeys = new Set(["id", "payment_id", "paymentId", "receipt_id", "receiptId", "tx_hash", "transaction_hash"]);

const extractPaymentReference = (value: unknown): string | undefined => {
  if (!value || typeof value !== "object") {
    return undefined;
  }

  for (const [key, entry] of Object.entries(value)) {
    if (paymentReferenceKeys.has(key) && typeof entry === "string" && entry.trim()) {
      return entry;
    }
    if (entry && typeof entry === "object") {
      const nested = extractPaymentReference(entry);
      if (nested) {
        return nested;
      }
    }
  }

  return undefined;
};

const withKernel = async <T>(
  configPath: string | undefined,
  run: (kernel: RegentKernel) => Promise<T>,
): Promise<T> => {
  const kernel = new RegentKernel(configPath);
  try {
    return await run(kernel);
  } finally {
    await kernel.stop();
  }
};

export async function runX402Details(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const result = await withKernel(configPath, (kernel) => kernel.call("x402.details", requestInput(args)));
  const nextSteps = result.payment_required
    ? [`regents x402 quote --url ${result.request.url} --json`]
    : ["No payment is required for this resource."];
  if (getBooleanFlag(args, "json")) {
    printJson(withNextSteps(result, nextSteps));
    return 0;
  }

  printText(
    renderKeyValuePanel("◆ X402 DETAILS", [
      { label: "payment", value: result.payment_required ? "required" : "not required" },
      { label: "status", value: String(result.status) },
      { label: "request", value: result.request.request_hash },
      { label: "next", value: nextSteps[0] ?? "" },
    ]),
  );
  return 0;
}

export async function runX402Search(args: ParsedCliArgs): Promise<number> {
  const result = await runAwalJson(["x402", "bazaar", "search", x402Query(args), "--json"]);
  printJson(withNextSteps(result, ["regents x402 details --url <paid-url> --json"]));
  return 0;
}

export async function runX402Quote(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const result = await withKernel(configPath, (kernel) => kernel.call("x402.quote", quoteInput(args)));
  const nextSteps = [`regents x402 prepare --url ${result.request.url} --max-amount ${result.selected.amount} --approve --json`];
  if (getBooleanFlag(args, "json")) {
    printJson(withNextSteps(result, nextSteps));
    return 0;
  }

  printText(
    renderKeyValuePanel("◆ X402 QUOTE", [
      { label: "amount", value: result.selected.amount, valueColor: CLI_PALETTE.emphasis },
      { label: "network", value: result.selected.network },
      { label: "asset", value: result.selected.asset },
      { label: "pay to", value: result.selected.pay_to },
      { label: "next", value: nextSteps[0] ?? "" },
    ]),
  );
  return 0;
}

export async function runX402Prepare(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const result = await withKernel(configPath, (kernel) => kernel.call("x402.prepare", prepareInput(args)));
  if (getBooleanFlag(args, "json")) {
    printJson(result);
    return 0;
  }

  printText(
    renderKeyValuePanel("◆ X402 PREPARED", [
      { label: "intent", value: result.intent.intent_id, valueColor: CLI_PALETTE.emphasis },
      { label: "approval", value: result.intent.approval_status },
      { label: "amount", value: result.intent.selected.amount },
      { label: "next", value: result.next_action.command },
    ]),
  );
  return 0;
}

export async function runX402Fetch(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const result = await withKernel(configPath, (kernel) => kernel.call("x402.fetch", fetchInput(args)));
  if (getBooleanFlag(args, "json")) {
    printJson(withNextSteps(
      result,
      result.receipt ? [`regents x402 receipts get --id ${result.receipt.receipt_id} --json`] : [],
    ));
    return result.ok ? 0 : 1;
  }

  printText(result.body_text);
  return result.ok ? 0 : 1;
}

export async function runX402Refund(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const result = await withKernel(configPath, (kernel) => kernel.call("x402.refund", refundInput(args)));
  if (getBooleanFlag(args, "json")) {
    printJson(withNextSteps(result, ["regents x402 receipts get --id <receipt-id> --json"]));
    return 0;
  }

  printText(
    renderKeyValuePanel("◆ X402 REFUND", [
      { label: "url", value: result.url },
      { label: "amount", value: result.amount ?? "full unused balance", valueColor: CLI_PALETTE.emphasis },
      { label: "next", value: "regents x402 receipts get --id <receipt-id> --json" },
    ]),
  );
  return 0;
}

export async function runX402Pay(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const budgetId = requireArg(getFlag(args, "budget"), "--budget");
  const maxUsdc = requireArg(getFlag(args, "max-usdc"), "--max-usdc");
  const rail = parseRail(getFlag(args, "rail"));
  const request = payRequestInput(args);
  const reservation = reserveBudgetPayment(config, {
    budget_id: budgetId,
    amount_usdc: maxUsdc,
    rail,
    url: request.url,
    approved: getBooleanFlag(args, "approve"),
  });

  const maxAtomic = usdcToAtomicString(maxUsdc);
  let payment: unknown;
  let paymentReference: string | undefined;
  let spentUsdc: string;
  let paymentCompleted = false;
  let spend:
    | ReturnType<typeof settleBudgetReservation>
    | undefined;

  try {
    if (rail === "agentic-wallet") {
      payment = await runAwalJson([
        "x402",
        "pay",
        request.url,
        "--max-amount",
        maxAtomic,
        "--json",
      ]);
      paymentReference = extractPaymentReference(payment);
      spentUsdc = maxUsdc;
      paymentCompleted = true;
    } else {
      const regentWalletPayment = await withKernel(configPath, async (kernel) => {
        const prepared = await kernel.call("x402.prepare", {
          ...request,
          max_amount: maxAtomic,
          max_deposit_amount: getFlag(args, "max-deposit-amount"),
          approve: true,
        });
        const fetched = await kernel.call("x402.fetch", {
          ...request,
          intent_id: prepared.intent.intent_id,
        });
        if (!fetched.ok || !fetched.receipt) {
          throw new CliUsageError({
            code: "x402_payment_failed",
            message: "The x402 payment did not complete.",
          });
        }
        return { prepared, fetched, receipt: fetched.receipt };
      });
      payment = regentWalletPayment;
      paymentReference = regentWalletPayment.receipt.receipt_id;
      spentUsdc = atomicStringToUsdc(regentWalletPayment.prepared.intent.selected.amount);
      paymentCompleted = true;
    }

    spend = settleBudgetReservation(config, {
      budget_id: budgetId,
      reservation_id: reservation.ledger_entry.entry_id,
      amount_usdc: spentUsdc,
      reference: paymentReference,
      rail,
    });
  } catch (error) {
    if (!paymentCompleted) {
      releaseBudgetReservation(config, {
        budget_id: budgetId,
        reservation_id: reservation.ledger_entry.entry_id,
        rail,
        note: "payment failed before completion",
      });
    }
    throw error;
  }

  if (!spend) {
    throw new CliUsageError({
      code: "budget_reservation_not_settled",
      message: "The budget reservation could not be settled.",
    });
  }

  const receipt = getBooleanFlag(args, "receipt")
    ? createReceipt(config, paymentReference ? { x402_payment_id: paymentReference } : { budget_entry: spend.ledger_entry.entry_id })
    : undefined;

  printJson({
    ok: true,
    rail,
    payment,
    budget: spend.budget,
    receipt,
    next_steps: receipt
      ? [`regents receipt share-draft --receipt ${receipt.receipt_id}`]
      : [`regents budget ledger --budget ${spend.budget.budget_id}`],
  });
  return 0;
}

export async function runX402ReceiptsGet(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const result = await withKernel(configPath, (kernel) => kernel.call("x402.receipts.get", receiptGetInput(args)));
  if (getBooleanFlag(args, "json")) {
    printJson(withNextSteps(
      result,
      result.receipt ? [`regents receipt create --from-x402-payment ${result.receipt.receipt_id} --json`] : [],
    ));
    return 0;
  }

  if (!result.receipt) {
    printText("No x402 receipt found.");
    return 1;
  }

  printText(
    renderKeyValuePanel("◆ X402 RECEIPT", [
      { label: "receipt", value: result.receipt.receipt_id, valueColor: CLI_PALETTE.emphasis },
      { label: "intent", value: result.receipt.intent_id },
      { label: "status", value: String(result.receipt.status) },
      { label: "paid", value: result.receipt.ok ? "yes" : "no" },
      { label: "next", value: `regents receipt create --from-x402-payment ${result.receipt.receipt_id} --json` },
    ]),
  );
  return result.receipt.ok ? 0 : 1;
}
