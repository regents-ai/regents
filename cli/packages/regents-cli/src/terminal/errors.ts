import { CliUsageError } from "../cli-usage-error.js";
import { codeForError } from "../exit-codes.js";
import { JsonRpcError, RegentError } from "../internal-runtime/index.js";

import { renderPanel } from "./panel.js";
import { CLI_PALETTE, escapeTerminalText, isHumanTerminal, tone } from "./palette.js";

const renderNextLines = (nextSteps: readonly string[] | undefined): string[] => {
  const steps = nextSteps && nextSteps.length > 0 ? nextSteps : ["regents --help"];
  return steps.map((step) => `${tone("Next:", CLI_PALETTE.secondary)} ${tone(escapeTerminalText(step), CLI_PALETTE.emphasis, true)}`);
};

const renderErrorPanel = (
  message: string,
  code?: string,
  details: readonly string[] = [],
  nextSteps?: readonly string[],
): string =>
  renderPanel(
    "◆ REGENT ERROR",
    [
      ...(code
        ? [`${tone("code", CLI_PALETTE.secondary)} ${tone(escapeTerminalText(code), CLI_PALETTE.error, true)}`]
        : []),
      `${tone("message", CLI_PALETTE.secondary)} ${tone(escapeTerminalText(message), CLI_PALETTE.primary, true)}`,
      ...details,
      ...renderNextLines(nextSteps),
    ],
    { borderColor: CLI_PALETTE.error, titleColor: CLI_PALETTE.title },
  );

const errorPayload = (
  message: string,
  code: string,
  details?: Record<string, unknown>,
): Record<string, Record<string, unknown>> => ({
  error: {
    code,
    message,
    ...(details ?? {}),
  },
});

const jsonRpcDetails = (error: JsonRpcError): string[] => {
  const socketPath = error.details?.socket_path;
  return typeof socketPath === "string"
    ? [`${tone("runtime", CLI_PALETTE.secondary)} ${tone(escapeTerminalText(socketPath), CLI_PALETTE.primary, true)}`]
    : [];
};

export function printError(error: unknown, options?: { readonly nextStep?: string }): void {
  const fallbackNextSteps = options?.nextStep ? [options.nextStep] : undefined;

  if (error instanceof CliUsageError) {
    const details = [
      error.command ? `${tone("command", CLI_PALETTE.secondary)} ${tone(error.command, CLI_PALETTE.primary, true)}` : undefined,
      error.usage ? `${tone("usage", CLI_PALETTE.secondary)} ${tone(error.usage, CLI_PALETTE.primary, true)}` : undefined,
      error.missing.length > 0 ? `${tone("missing", CLI_PALETTE.secondary)} ${tone(error.missing.join(", "), CLI_PALETTE.primary, true)}` : undefined,
      error.validValues.length > 0
        ? `${tone("valid", CLI_PALETTE.secondary)} ${tone(error.validValues.join(", "), CLI_PALETTE.primary, true)}`
        : undefined,
      error.example ? `${tone("example", CLI_PALETTE.secondary)} ${tone(error.example, CLI_PALETTE.primary, true)}` : undefined,
    ].filter((line): line is string => Boolean(line));
    const payloadDetails = {
      ...(error.command ? { command: error.command } : {}),
      ...(error.usage ? { usage: error.usage } : {}),
      ...(error.missing.length > 0 ? { missing: error.missing } : {}),
      ...(error.validValues.length > 0 ? { valid_values: error.validValues } : {}),
      ...(error.example ? { example: error.example } : {}),
    };

    if (isHumanTerminal()) {
      const nextSteps = error.command ? [`${error.command} --help`] : fallbackNextSteps;
      process.stderr.write(`${renderErrorPanel(error.message, error.code, details, nextSteps)}\n`);
      return;
    }

    process.stderr.write(`${JSON.stringify(errorPayload(error.message, error.code, payloadDetails), null, 2)}\n`);
    return;
  }

  if (error instanceof JsonRpcError) {
    const nextSteps = error.nextSteps && error.nextSteps.length > 0 ? error.nextSteps : fallbackNextSteps;
    const payloadDetails = {
      ...(error.details ?? {}),
      ...(nextSteps && nextSteps.length > 0 ? { next_steps: nextSteps } : {}),
    };

    if (isHumanTerminal()) {
      process.stderr.write(`${renderErrorPanel(error.message, error.code, jsonRpcDetails(error), nextSteps)}\n`);
      return;
    }

    process.stderr.write(`${JSON.stringify(errorPayload(error.message, error.code, payloadDetails), null, 2)}\n`);
    return;
  }

  const fallbackDetails = fallbackNextSteps ? { next_steps: fallbackNextSteps } : undefined;

  if (error instanceof RegentError) {
    if (isHumanTerminal()) {
      process.stderr.write(`${renderErrorPanel(error.message, error.code, [], fallbackNextSteps)}\n`);
      return;
    }

    process.stderr.write(`${JSON.stringify(errorPayload(error.message, error.code, fallbackDetails), null, 2)}\n`);
    return;
  }

  if (error instanceof Error) {
    if (isHumanTerminal()) {
      process.stderr.write(`${renderErrorPanel(error.message, codeForError(error), [], fallbackNextSteps)}\n`);
      return;
    }

    process.stderr.write(`${JSON.stringify(errorPayload(error.message, codeForError(error), fallbackDetails), null, 2)}\n`);
    return;
  }

  const fallbackMessage = String(error);
  if (isHumanTerminal()) {
    process.stderr.write(`${renderErrorPanel(fallbackMessage, codeForError(error), [], fallbackNextSteps)}\n`);
    return;
  }

  process.stderr.write(`${JSON.stringify(errorPayload(fallbackMessage, codeForError(error), fallbackDetails), null, 2)}\n`);
}
