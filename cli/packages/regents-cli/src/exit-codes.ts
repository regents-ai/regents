import { isCliUsageError } from "./cli-usage-error.js";
import { AuthError, RegentError } from "./internal-runtime/errors.js";
import { ProductHttpError } from "./internal-runtime/product-http-client.js";

/**
 * Canonical Regents CLI exit codes. Defined once here; documented in
 * docs/shared-cli-contract.yaml and the package README.
 */
export const EXIT_CODES = {
  success: 0,
  failure: 1,
  usage: 2,
  authMissing: 3,
  notFound: 4,
  backendUnreachable: 5,
} as const;

export type CliExitCode = (typeof EXIT_CODES)[keyof typeof EXIT_CODES];

const AUTH_ERROR_CODES = new Set([
  "unauthorized",
  "auth_error",
  "siwa_session_missing",
  "siwa_receipt_expired",
  "agent_identity_missing",
  "platform_session_missing",
  "SIWA_VERIFY_FAILED",
  "COINBASE_CDP_MISSING",
]);

const USAGE_ERROR_CODES = new Set([
  "usage_error",
  "missing_required_argument",
  "invalid_flag_value",
  "unknown_command",
  "command_not_available",
  "UNSUPPORTED_NETWORK",
]);

const BACKEND_UNREACHABLE_CODES = new Set([
  "runtime_unavailable",
  "backend_unreachable",
  "SERVICE_UNAVAILABLE",
]);

const isNotFoundCode = (code: string): boolean =>
  code === "not_found" || code.endsWith("_not_found") || code === "NOT_FOUND";

const exitCodeForKnownCode = (code: string): CliExitCode => {
  if (USAGE_ERROR_CODES.has(code)) {
    return EXIT_CODES.usage;
  }

  if (AUTH_ERROR_CODES.has(code)) {
    return EXIT_CODES.authMissing;
  }

  if (isNotFoundCode(code)) {
    return EXIT_CODES.notFound;
  }

  if (BACKEND_UNREACHABLE_CODES.has(code)) {
    return EXIT_CODES.backendUnreachable;
  }

  return EXIT_CODES.failure;
};

const productHttpErrorCode = (error: ProductHttpError): string => {
  if (error.status === 0) {
    return "backend_unreachable";
  }

  if (error.status === 401 || error.status === 403) {
    return "unauthorized";
  }

  if (error.status === 404) {
    return "not_found";
  }

  return `http_${error.status}`;
};

/**
 * Stable machine-readable code for any error the CLI can surface. Every JSON
 * error envelope printed by the CLI carries this code.
 */
export const codeForError = (error: unknown): string => {
  if (isCliUsageError(error)) {
    return error.code;
  }

  if (error instanceof RegentError) {
    return error.code;
  }

  if (error instanceof ProductHttpError) {
    return productHttpErrorCode(error);
  }

  return "command_failed";
};

/**
 * Map any error to the canonical exit code: 0 success, 1 failure,
 * 2 usage error, 3 sign-in or identity missing, 4 not found,
 * 5 backend unreachable.
 */
export const exitCodeForError = (error: unknown): CliExitCode => {
  if (isCliUsageError(error)) {
    return EXIT_CODES.usage;
  }

  if (error instanceof AuthError) {
    return EXIT_CODES.authMissing;
  }

  if (error instanceof ProductHttpError) {
    return exitCodeForKnownCode(productHttpErrorCode(error));
  }

  return exitCodeForKnownCode(codeForError(error));
};
