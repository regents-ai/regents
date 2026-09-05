import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type { X402RequestInput, X402PaymentStatus } from "../../internal-types/x402.js";

import { RegentError } from "../errors.js";

const execFileAsync = promisify(execFile);

export const AWAL_VERSION = "2.10.0";

export interface AwalResult {
  readonly ok: true;
  readonly command: readonly string[];
  readonly data: unknown;
}

const credentialKeys = new Set([
  "secret", "secretkey", "privatekey", "token", "accesstoken", "refreshtoken", "idtoken", "authtoken", "sessiontoken",
  "otp", "password", "passphrase", "mnemonic", "seed", "seedphrase", "header", "headers",
  "paymentheader", "paymentheaders", "authorization", "proxyauthorization", "cookie", "setcookie",
  "signature", "paymentsignature", "xpayment", "signedtransaction", "rawtransaction", "apikey",
]);
const secretArgPreviousToken = new Set(["--otp", "-h", "--headers", "-d", "--data"]);

export const redactAwalValue = (value: unknown): unknown => {
  if (Array.isArray(value)) {
    return value.map(redactAwalValue);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        credentialKeys.has(key.replace(/[-_]/gu, "").toLowerCase()) ? "[redacted]" : redactAwalValue(entry),
      ]),
    );
  }

  return value;
};

export const awalCommand = (args: readonly string[]): readonly string[] => [
  "npx",
  "-y",
  `awal@${AWAL_VERSION}`,
  ...args,
];

export const redactAwalCommand = (command: readonly string[]): readonly string[] => {
  let redactNextCount = 0;
  return command.map((entry) => {
    if (redactNextCount > 0) {
      redactNextCount -= 1;
      return "[redacted]";
    }
    if (entry === "verify") {
      redactNextCount = 2;
    }
    if (secretArgPreviousToken.has(entry)) {
      redactNextCount = 1;
    }
    return /^https?:\/\//u.test(entry) ? "[resource-url]" : entry;
  });
};

export const runAwalJson = async (args: readonly string[]): Promise<AwalResult> => {
  const command = awalCommand(args);
  try {
    const { stdout } = await execFileAsync(command[0], command.slice(1), {
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024,
      shell: false,
    });
    const parsed = stdout.trim() ? JSON.parse(stdout) : {};
    return { ok: true, command: redactAwalCommand(command), data: redactAwalValue(parsed) };
  } catch {
    throw new RegentError(
      "awal_command_failed",
      "Agentic Wallet command failed. A payment may have completed; check its correlation ID before retrying.",
    );
  }
};

/** AWAL 2.10 reparses JSON bodies and cannot disable provider redirects. */
export const awalPayArgs = (request: X402RequestInput, maxAtomic: string): string[] => {
  const url = new URL(request.url);
  if (!["https:", "http:"].includes(url.protocol) || url.username || url.password) {
    throw new RegentError("awal_request_unsupported", "Use an HTTP URL without embedded credentials.");
  }
  const method = request.method ?? "GET";
  if (!["GET", "POST", "PUT", "PATCH", "DELETE"].includes(method)) {
    throw new RegentError("awal_request_unsupported", "This request method is not supported by Agentic Wallet.");
  }
  if (Object.keys(request.headers ?? {}).length) {
    throw new RegentError("awal_request_unsupported", "Agentic Wallet cannot safely preserve caller headers across provider redirects. Use the Regent rail or your own x402 client.");
  }
  if (!/^\d+$/.test(maxAtomic) || BigInt(maxAtomic) > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RegentError("awal_request_unsupported", "Agentic Wallet requires a maximum amount within JavaScript's safe integer range.");
  }
  if (request.body !== undefined) {
    let parsed: unknown;
    try { parsed = JSON.parse(request.body); } catch { /* rejected below */ }
    if (["GET", "DELETE"].includes(method) || !parsed || typeof parsed !== "object" || JSON.stringify(parsed) !== request.body) {
      throw new RegentError("awal_request_unsupported", "Agentic Wallet requires an exact canonical JSON object or array body. Use the Regent rail or an external client for other bodies.");
    }
  }
  return ["x402", "pay", request.url, "--method", method,
    ...(request.body !== undefined ? ["--data", request.body] : []), "--max-amount", maxAtomic, "--json"];
};

export const awalPaymentOutcome = (value: unknown): {
  payment_status: X402PaymentStatus; status: number | null; http_ok: boolean;
  amount_atomic?: string;
} => {
  const data = value && typeof value === "object" ? value as Record<string, unknown> : {};
  const status = typeof data.status === "number" && Number.isInteger(data.status) && data.status >= 100 && data.status <= 599 ? data.status : null;
  const rawAmount = data.amountPaid;
  const amount = typeof rawAmount === "string" && /^\d+$/.test(rawAmount) ? rawAmount
    : typeof rawAmount === "number" && Number.isSafeInteger(rawAmount) && rawAmount >= 0 ? String(rawAmount) : undefined;
  return {
    status, http_ok: status !== null && status >= 200 && status < 300,
    payment_status: data.paymentMade === true && amount !== undefined ? "settled"
      : data.paymentMade === false && (rawAmount === undefined || amount === "0") ? "not_paid" : "unknown",
    ...(data.paymentMade === true && amount !== undefined ? {amount_atomic: amount} : {}),
  };
};
