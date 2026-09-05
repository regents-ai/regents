export interface CliUsageErrorDetails {
  readonly code?: string;
  readonly message: string;
  readonly command?: string;
  readonly usage?: string;
  readonly missing?: readonly string[];
  readonly validValues?: readonly string[];
  readonly example?: string;
}

export class CliUsageError extends Error {
  readonly code: string;
  readonly command?: string;
  readonly usage?: string;
  readonly missing: readonly string[];
  readonly validValues: readonly string[];
  readonly example?: string;

  constructor(details: CliUsageErrorDetails) {
    super(details.message);
    this.name = "CliUsageError";
    this.code = details.code ?? "usage_error";
    this.command = details.command;
    this.usage = details.usage;
    this.missing = details.missing ?? [];
    this.validValues = details.validValues ?? [];
    this.example = details.example;
  }
}

export const isCliUsageError = (error: unknown): error is CliUsageError =>
  error instanceof CliUsageError;

export const withCliUsageContext = (
  error: CliUsageError,
  context: {
    readonly command?: string;
    readonly usage?: string;
    readonly example?: string;
  },
): CliUsageError =>
  new CliUsageError({
    code: error.code,
    message: error.message,
    command: error.command ?? context.command,
    usage: error.usage ?? context.usage,
    missing: error.missing,
    validValues: error.validValues,
    example: error.example ?? context.example,
  });
