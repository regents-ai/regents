import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { CliUsageError } from "../cli-usage-error.js";
import type { RegentConfig } from "../internal-types/index.js";

import { writeJsonFileAtomicSync } from "./paths.js";

export interface RegentReceipt {
  readonly schema: "regents.receipt.v1";
  readonly receipt_id: string;
  readonly created_at: string;
  readonly kind: "x402_payment" | "budget_entry";
  readonly x402?: {
    readonly payments: readonly string[];
    readonly earnings: readonly string[];
  };
  readonly budget?: {
    readonly ledger_entry: string;
  };
  readonly recognized_revenue: boolean;
  readonly share_copy: string;
}

interface ReceiptFile {
  readonly schema: "regents.receipts.v1";
  readonly receipts: readonly RegentReceipt[];
}

const receiptFilePath = (config: RegentConfig): string => path.join(config.runtime.stateDir, "receipts.json");

const emptyReceiptFile = (): ReceiptFile => ({ schema: "regents.receipts.v1", receipts: [] });

export const readReceiptFile = (config: RegentConfig): ReceiptFile => {
  const filePath = receiptFilePath(config);
  if (!fs.existsSync(filePath)) {
    return emptyReceiptFile();
  }

  const raw = fs.readFileSync(filePath, "utf8");
  if (raw.trim() === "") {
    return emptyReceiptFile();
  }

  const parsed = JSON.parse(raw) as ReceiptFile;
  return parsed && parsed.schema === "regents.receipts.v1" && Array.isArray(parsed.receipts)
    ? parsed
    : emptyReceiptFile();
};

const writeReceiptFile = (config: RegentConfig, file: ReceiptFile): void => {
  writeJsonFileAtomicSync(receiptFilePath(config), file);
};

const buildShareCopy = (input: {
  readonly x402_payment_id?: string;
  readonly budget_entry?: string;
}): string => {
  if (input.budget_entry) {
    return `My agent recorded budget activity with reference ${input.budget_entry}.`;
  }
  return `My agent completed an x402 payment with reference ${input.x402_payment_id}.`;
};

export const createReceipt = (
  config: RegentConfig,
  input: {
    readonly x402_payment_id?: string;
    readonly budget_entry?: string;
  },
): RegentReceipt => {
  const selected = [input.x402_payment_id, input.budget_entry].filter(Boolean);
  if (selected.length !== 1) {
    throw new CliUsageError({
      code: "invalid_receipt_source",
      message: "Choose exactly one receipt source.",
      validValues: ["--from-x402-payment", "--from-budget-entry"],
      example: "regents receipt create --from-x402-payment payment_123 --json",
    });
  }

  const receipt: RegentReceipt = {
    schema: "regents.receipt.v1",
    receipt_id: `rcpt_${crypto.randomBytes(12).toString("hex")}`,
    created_at: new Date().toISOString(),
    kind: input.x402_payment_id ? "x402_payment" : "budget_entry",
    ...(input.x402_payment_id
      ? { x402: { payments: [input.x402_payment_id], earnings: [] } }
      : { budget: { ledger_entry: input.budget_entry as string } }),
    recognized_revenue: false,
    share_copy: buildShareCopy(input),
  };

  const current = readReceiptFile(config);
  writeReceiptFile(config, { schema: "regents.receipts.v1", receipts: [...current.receipts, receipt] });
  return receipt;
};

export const findReceipt = (config: RegentConfig, receiptId: string): RegentReceipt => {
  const receipt = readReceiptFile(config).receipts.find((entry) => entry.receipt_id === receiptId);
  if (!receipt) {
    throw new CliUsageError({ code: "receipt_not_found", message: `Receipt not found: ${receiptId}.` });
  }
  return receipt;
};

export const receiptShareDraft = (receipt: RegentReceipt): { receipt_id: string; draft_only: true; copy: string } => ({
  receipt_id: receipt.receipt_id,
  draft_only: true,
  copy: receipt.recognized_revenue
    ? receipt.share_copy
    : `${receipt.share_copy} This is a work receipt, not a revenue claim.`,
});
