import fs from "node:fs";
import path from "node:path";

import type { X402IntentRecord, X402ReceiptRecord } from "../../internal-types/index.js";

import { RegentError } from "../errors.js";
import { ensureSecureDir, writeJsonFileAtomicSync } from "../paths.js";

interface X402IntentStoreFile {
  version: 1;
  intents: X402IntentRecord[];
}

interface X402ReceiptStoreFile {
  version: 1;
  receipts: X402ReceiptRecord[];
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const readJsonFile = (filePath: string): unknown | null => {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new RegentError("x402_store_invalid", `Could not read local x402 state at ${filePath}.`, error);
  }
};

const readIntentStoreFile = (filePath: string): X402IntentStoreFile => {
  const parsed = readJsonFile(filePath);
  if (parsed === null) {
    return { version: 1, intents: [] };
  }

  if (!isRecord(parsed) || parsed.version !== 1 || !Array.isArray(parsed.intents)) {
    throw new RegentError("x402_store_invalid", `Local x402 intent state at ${filePath} is not valid.`);
  }

  return parsed as unknown as X402IntentStoreFile;
};

const readReceiptStoreFile = (filePath: string): X402ReceiptStoreFile => {
  const parsed = readJsonFile(filePath);
  if (parsed === null) {
    return { version: 1, receipts: [] };
  }

  if (!isRecord(parsed) || parsed.version !== 1 || !Array.isArray(parsed.receipts)) {
    throw new RegentError("x402_store_invalid", `Local x402 receipt state at ${filePath} is not valid.`);
  }

  return parsed as unknown as X402ReceiptStoreFile;
};

export class X402LocalStore {
  readonly rootDir: string;
  readonly intentsPath: string;
  readonly receiptsPath: string;

  constructor(stateDir: string) {
    this.rootDir = path.join(stateDir, "x402");
    this.intentsPath = path.join(this.rootDir, "intents.json");
    this.receiptsPath = path.join(this.rootDir, "receipts.json");
    ensureSecureDir(this.rootDir);
  }

  listIntents(): X402IntentRecord[] {
    return readIntentStoreFile(this.intentsPath).intents;
  }

  getIntent(intentId: string): X402IntentRecord | null {
    return this.listIntents().find((intent) => intent.intent_id === intentId) ?? null;
  }

  saveIntent(intent: X402IntentRecord): X402IntentRecord {
    const file = readIntentStoreFile(this.intentsPath);
    const withoutExisting = file.intents.filter((entry) => entry.intent_id !== intent.intent_id);
    const next = { version: 1 as const, intents: [...withoutExisting, intent] };
    writeJsonFileAtomicSync(this.intentsPath, next);
    return intent;
  }

  saveReceipt(receipt: X402ReceiptRecord): X402ReceiptRecord {
    const file = readReceiptStoreFile(this.receiptsPath);
    const withoutExisting = file.receipts.filter((entry) => entry.receipt_id !== receipt.receipt_id);
    const next = { version: 1 as const, receipts: [...withoutExisting, receipt] };
    writeJsonFileAtomicSync(this.receiptsPath, next);
    return receipt;
  }

  getReceipt(receiptId: string): X402ReceiptRecord | null {
    return readReceiptStoreFile(this.receiptsPath).receipts.find((receipt) => receipt.receipt_id === receiptId) ?? null;
  }
}
