const REDACTED = "[redacted]";

const SENSITIVE_KEY_PATTERNS = [
  /receipt/i,
  /signature/i,
  /authorization/i,
  /private[_-]?key/i,
  /mnemonic/i,
  /seed[_-]?phrase/i,
  /access[_-]?token/i,
  /refresh[_-]?token/i,
  /^token$/i,
  /api[_-]?key/i,
  /secret/i,
  /signed[_-]?tx/i,
  /raw[_-]?transaction/i,
  /^x-siwa-receipt$/i,
  /^x-key-id$/i,
  /^bearer[_-]?token$/i,
  /^auth[_-]?header$/i,
  /^sessionId$/i,
  /^payment-signature$/i,
  /^payment-response$/i,
  /^x-payment$/i,
  /^x-payment-response$/i,
];

// Value patterns scrub secrets that appear inside free-text strings regardless
// of the key they live under. These run on the error path, where an upstream
// error message can echo a private key, mnemonic, signed transaction, or bearer
// token with no sensitive key name to catch it. They are intentionally not run
// over success results, whose structured fields (tx hashes, calldata hashes)
// are 64-hex strings that must survive for the operator tool to be useful.
const SENSITIVE_VALUE_PATTERNS: readonly RegExp[] = [
  // Signed/raw transaction hex: long 0x-prefixed hex payloads.
  /\b0x[a-fA-F0-9]{100,}\b/g,
  // 32-byte private key (with or without 0x prefix).
  /\b(0x)?[a-fA-F0-9]{64}\b/g,
  // Bearer tokens embedded in text.
  /\bBearer\s+[A-Za-z0-9._~+/=-]{8,}/g,
  // JWT-shaped tokens (three base64url segments).
  /\beyJ[A-Za-z0-9._-]{10,}\b/g,
];

const isSensitiveKey = (key: string): boolean =>
  SENSITIVE_KEY_PATTERNS.some((pattern) => pattern.test(key));

/**
 * Redact secrets from a success-path tool result by sensitive key name. Applied
 * recursively over objects and arrays. String values are passed through so
 * legitimate structured output (tx hashes, calldata hashes, addresses) survives.
 */
export function redactRegentSecrets(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(redactRegentSecrets);
  }

  if (!value || typeof value !== "object") {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).map(([key, entry]) => [
      key,
      isSensitiveKey(key) ? REDACTED : redactRegentSecrets(entry),
    ]),
  );
}

/**
 * Scrub secret material from a free-text error message before it leaves the
 * process. The MCP SDK places a raw thrown error message into the tool result
 * without redaction, so the tool handler must run this on every error path.
 */
export function redactRegentErrorMessage(message: string): string {
  let scrubbed = message;
  for (const pattern of SENSITIVE_VALUE_PATTERNS) {
    pattern.lastIndex = 0;
    scrubbed = scrubbed.replace(pattern, REDACTED);
  }
  return scrubbed;
}
