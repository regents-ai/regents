import { withNextSteps } from "../command-payload.js";
import type { ParsedCliArgs } from "../parse.js";

import type {
  X402FetchParams,
  X402PrepareParams,
  X402QuoteParams,
  X402ReceiptGetParams,
  X402RefundParams,
  X402RequestInput,
  X402PaymentStatus,
  X402SelectedPaymentRequirement,
} from "../internal-types/index.js";
import { RegentKernel } from "../internal-runtime/runtime.js";
import { runAwalJson, awalPayArgs, awalPaymentOutcome } from "../internal-runtime/agentic-wallet/awal.js";
import {
  atomicStringToUsdc,
  findBudget,
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

const paymentReferenceKeys = new Set(["payment_id", "paymentId", "receipt_id", "receiptId", "tx_hash", "transaction_hash", "transactionHash", "transaction"]);

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
    ? ["Use payment_required_response with your external x402 client and original request, or regents x402 quote --url <original-url> [original method, headers and body] --json"]
    : [result.ok ? "No payment is required for this resource." : "The HTTP operation failed without a valid payment challenge; inspect its status."];
  if (getBooleanFlag(args, "json")) {
    printJson(withNextSteps(result, nextSteps));
    return result.ok ? 0 : 1;
  }

  printText(
    renderKeyValuePanel("◆ X402 DETAILS", [
      { label: "payment", value: result.payment_required ? "required" : "not required" },
      { label: "status", value: String(result.status) },
      { label: "request", value: result.request.request_hash },
      { label: "next", value: nextSteps[0] ?? "" },
    ]),
  );
  return result.ok ? 0 : 1;
}

export async function runX402Search(args: ParsedCliArgs): Promise<number> {
  const result = await runAwalJson(["x402", "bazaar", "search", x402Query(args), "--json"]);
  printJson(withNextSteps(result, ["regents x402 details --url <paid-url> --json"]));
  return 0;
}

export async function runX402Quote(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const result = await withKernel(configPath, (kernel) => kernel.call("x402.quote", quoteInput(args)));
  const nextSteps = [`regents x402 prepare --url <original-url> [original method, headers and body] --max-amount ${result.selected.amount} --approve --json`];
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

const requireUsdcBudgetRequirement = (selected: X402SelectedPaymentRequirement): void => {
  const assets: Record<string, string> = {
    "eip155:8453": "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
    "eip155:84532": "0x036cbd53842c5426634e7929541ec2318f3dcf7e",
  };
  if (selected.scheme !== "exact" || typeof selected.asset !== "string" ||
    assets[selected.network] !== selected.asset.toLowerCase()) {
    throw new CliUsageError({code: "x402_usdc_budget_unsupported",
      message: "USDC budgets support exact Base or Base Sepolia USDC only. Use the raw atomic quote/prepare/fetch flow for other assets or batch deposits."});
  }
};

export async function runX402Pay(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const booleans = new Set(["json", "approve", "receipt"]);
  const values = new Set(["config", "budget", "max-usdc", "rail", "max-deposit-amount", "method", "body", "header"]);
  if (args.positionals.length !== 3) {
    throw new CliUsageError({code: "invalid_argument", message: "x402 pay takes exactly one resource URL."});
  }
  for (const [flag, value] of args.flags) {
    const supplied = Array.isArray(value) ? value : [value];
    if ((!booleans.has(flag) && !values.has(flag)) ||
      (booleans.has(flag) && value !== true) ||
      (values.has(flag) && supplied.some(entry => typeof entry !== "string" || (flag !== "body" && !entry.trim()))) ||
      (Array.isArray(value) && flag !== "header")) {
      throw new CliUsageError({code: "invalid_flag_value", message: `Unsupported, repeated, or missing value for --${flag}.`});
    }
  }
  const config = loadConfig(configPath);
  const budgetId = requireArg(getFlag(args, "budget"), "--budget");
  const maxUsdc = requireArg(getFlag(args, "max-usdc"), "--max-usdc");
  const rail = parseRail(getFlag(args, "rail"));
  const request = payRequestInput(args);
  const maxAtomic = usdcToAtomicString(maxUsdc);
  // Validate the provider's byte/number limitations before any provider call.
  const providerArgs = rail === "agentic-wallet" ? awalPayArgs(request, maxAtomic) : undefined;
  const reservation = reserveBudgetPayment(config, {
    budget_id: budgetId, amount_usdc: maxUsdc, rail, url: request.url,
    approved: getBooleanFlag(args, "approve"),
  });
  const reservationId = reservation.ledger_entry.entry_id;
  let payment: unknown;
  let paymentReference: string | undefined;
  let intentId: string | undefined;
  let spentUsdc: string | undefined;
  let paymentStatus: X402PaymentStatus = "unknown";
  let httpOk = false;
  let httpStatus: number | null = null;
  let executionStarted = false;
  let problem: string | undefined;
  let budget = reservation.budget;
  let ledgerEntry = reservation.ledger_entry;

  try {
    if (rail === "agentic-wallet") {
      executionStarted = true;
      const result = await runAwalJson([...providerArgs!, "--correlation-id", reservationId]);
      payment = result;
      const outcome = awalPaymentOutcome(result.data);
      paymentStatus = outcome.payment_status;
      httpOk = outcome.http_ok;
      httpStatus = outcome.status;
      paymentReference = extractPaymentReference(result.data);
      if (outcome.amount_atomic !== undefined) spentUsdc = atomicStringToUsdc(outcome.amount_atomic);
    } else {
      await withKernel(configPath, async (kernel) => {
        const prepared = await kernel.call("x402.prepare", {
          ...request, max_amount: maxAtomic,
          max_deposit_amount: getFlag(args, "max-deposit-amount"), approve: true,
        });
        intentId = prepared.intent.intent_id;
        requireUsdcBudgetRequirement(prepared.intent.selected);
        executionStarted = true;
        const fetched = await kernel.call("x402.fetch", {...request, intent_id: intentId});
        payment = {prepared, fetched, receipt: fetched.receipt};
        paymentStatus = fetched.payment_status ?? "unknown";
        httpOk = fetched.ok;
        httpStatus = fetched.status;
        paymentReference = fetched.receipt?.receipt_id;
        if (paymentStatus === "settled") spentUsdc = atomicStringToUsdc(prepared.intent.selected.amount);
      });
    }

    if (paymentStatus === "settled" && spentUsdc !== undefined) {
      const spend = settleBudgetReservation(config, {
        budget_id: budgetId, reservation_id: reservationId, amount_usdc: spentUsdc,
        reference: paymentReference ?? reservationId, rail,
      });
      budget = spend.budget;
      ledgerEntry = spend.ledger_entry;
    } else if (paymentStatus === "not_paid" || paymentStatus === "not_required") {
      const released = releaseBudgetReservation(config, {
        budget_id: budgetId, reservation_id: reservationId, rail, note: "provider reported no payment",
      });
      budget = released.budget;
      ledgerEntry = released.ledger_entry;
    }
  } catch (error) {
    if (!executionStarted) {
      releaseBudgetReservation(config, {budget_id: budgetId, reservation_id: reservationId,
        rail, note: "refused before payment dispatch"});
      throw error;
    }
    // A subprocess/network error may arrive after settlement. Keep the reserve
    // and the stable recovery ID; never log raw subprocess argv or its output.
    budget = findBudget(config, budgetId);
    problem = "Payment execution or local accounting could not be confirmed. Check the recovery references before another payment.";
  }

  const receipt = getBooleanFlag(args, "receipt")
    ? createReceipt(config, paymentReference ? {x402_payment_id: paymentReference} : {budget_entry: ledgerEntry.entry_id})
    : undefined;
  const reserved = ledgerEntry.type === "reserve";
  const ok = httpOk && paymentStatus !== "unknown" && !problem;
  printJson({
    ok, rail, payment, payment_status: paymentStatus, http_status: httpStatus,
    ...(spentUsdc !== undefined ? {reported_spend_usdc: spentUsdc} : {}),
    accounting_status: reserved ? "reserved" : ledgerEntry.type,
    reservation_id: reservationId,
    ...(rail === "agentic-wallet" ? {provider_correlation_id: reservationId, settlement_evidence: "provider_reported"} : {}),
    ...(intentId ? {intent_id: intentId} : {}),
    ...(paymentReference ? {payment_reference: paymentReference} : {}),
    ...(problem ? {problem} : {}),
    budget, receipt,
    next_steps: reserved
      ? [`Inspect regents budget ledger --budget ${budgetId} and the provider correlation ID or local x402 receipt. Do not automatically pay again.`]
      : receipt ? [`regents receipt share-draft --receipt ${receipt.receipt_id}`]
        : [`regents budget ledger --budget ${budgetId}`],
  });
  return ok ? 0 : 1;
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
      { label: "payment", value: result.receipt.payment_status ?? "unknown" },
      { label: "next", value: `regents receipt create --from-x402-payment ${result.receipt.receipt_id} --json` },
    ]),
  );
  return result.receipt.ok ? 0 : 1;
}
