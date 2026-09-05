import fs from "node:fs";
import path from "node:path";

import type { RegentConfig } from "../internal-types/index.js";

import { ensureParentDir, SECURE_FILE_MODE } from "./paths.js";

export interface RegentStructuredLogEntry {
  readonly timestamp: string;
  readonly level: "info" | "warn" | "error";
  readonly event: string;
  readonly command?: string;
  readonly service?: string;
  readonly method?: string;
  readonly path?: string;
  readonly status?: number;
  readonly ok?: boolean;
  readonly requestId?: string;
  readonly durationMs?: number;
  readonly chainId?: number;
  readonly error?: string;
  readonly redacted: true;
}

export const structuredLogPath = (config: RegentConfig): string =>
  path.join(path.dirname(config.runtime.stateDir), "logs", "regents.jsonl");

const SENSITIVE_QUERY_KEYS = new Set([
  "access_token",
  "authorization",
  "cookie",
  "csrf",
  "csrf_token",
  "identity_token",
  "key",
  "nonce",
  "private_key",
  "receipt",
  "secret",
  "signature",
  "token",
]);

const redactedValue = "[redacted]";

export const redactStructuredLogPath = (rawPath: string | undefined): string | undefined => {
  if (!rawPath) {
    return rawPath;
  }

  const [pathname, query] = rawPath.split("?", 2);
  if (!query) {
    return pathname;
  }

  const params = new URLSearchParams(query);
  for (const key of [...params.keys()]) {
    if (SENSITIVE_QUERY_KEYS.has(key.toLowerCase())) {
      params.set(key, redactedValue);
    }
  }

  const redactedQuery = params.toString();
  return redactedQuery ? `${pathname}?${redactedQuery}` : pathname;
};

export const appendStructuredLog = (config: RegentConfig, entry: RegentStructuredLogEntry): void => {
  const filePath = structuredLogPath(config);
  ensureParentDir(filePath);
  fs.appendFileSync(
    filePath,
    `${JSON.stringify({ ...entry, path: redactStructuredLogPath(entry.path), redacted: true })}\n`,
    { encoding: "utf8", mode: SECURE_FILE_MODE },
  );
  fs.chmodSync(filePath, SECURE_FILE_MODE);
};
