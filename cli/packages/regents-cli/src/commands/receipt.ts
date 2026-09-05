import {
  createReceipt,
  findReceipt,
  readReceiptFile,
  receiptShareDraft,
} from "../internal-runtime/receipt-store.js";
import { loadConfig } from "../internal-runtime/config.js";
import { getBooleanFlag, getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson, printText, renderKeyValuePanel } from "../printer.js";

const printReceipt = (
  args: ParsedCliArgs,
  payload: { ok: true; receipt: { receipt_id: string; kind: string }; next_steps?: string[] },
): void => {
  if (getBooleanFlag(args, "json")) {
    printJson(payload);
    return;
  }

  printText(
    renderKeyValuePanel("◆ REGENT RECEIPT", [
      { label: "receipt", value: payload.receipt.receipt_id },
      { label: "kind", value: payload.receipt.kind },
      { label: "share", value: `regents receipt share-draft --receipt ${payload.receipt.receipt_id}` },
      { label: "next", value: `regents receipt share-draft --receipt ${payload.receipt.receipt_id}` },
    ]),
  );
};

export async function runReceiptCreate(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const receipt = createReceipt(config, {
    x402_payment_id: getFlag(args, "from-x402-payment"),
    budget_entry: getFlag(args, "from-budget-entry"),
  });
  printReceipt(args, {
    ok: true,
    receipt,
    next_steps: [`regents receipt share-draft --receipt ${receipt.receipt_id}`],
  });
  return 0;
}

export async function runReceiptGet(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const receipt = findReceipt(config, requireArg(getFlag(args, "receipt"), "--receipt"));
  printJson({
    ok: true,
    receipt,
    next_steps: [`regents receipt share-draft --receipt ${receipt.receipt_id}`],
  });
  return 0;
}

export async function runReceiptList(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const receipts = readReceiptFile(config).receipts;
  if (getBooleanFlag(args, "json")) {
    printJson({ ok: true, receipts });
    return 0;
  }

  printText(receipts.length === 0
    ? "No Regent receipts yet.\nnext: regents receipt create --from-x402-payment <payment-id> --json"
    : `${receipts.map((entry) => entry.receipt_id).join("\n")}\nnext: regents receipt get --receipt ${receipts[0]?.receipt_id}`);
  return 0;
}

export async function runReceiptShareDraft(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const receipt = findReceipt(config, requireArg(getFlag(args, "receipt"), "--receipt"));
  const draft = receiptShareDraft(receipt);
  if (getBooleanFlag(args, "json")) {
    printJson({ ok: true, draft, next_steps: [] });
    return 0;
  }

  printText(draft.copy);
  return 0;
}
