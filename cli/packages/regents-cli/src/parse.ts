import { CliUsageError } from "./cli-usage-error.js";

export interface ParsedCliArgs {
  raw: readonly string[];
  positionals: readonly string[];
  flags: ReadonlyMap<string, string | true | readonly (string | true)[]>;
}

const isFlagToken = (value: string): boolean => value.startsWith("--");

export function parseCliArgs(args: readonly string[]): ParsedCliArgs {
  const positionals: string[] = [];
  const flags = new Map<string, string | true | (string | true)[]>();
  const setFlag = (name: string, value: string | true): void => {
    const current = flags.get(name);
    if (current === undefined) {
      flags.set(name, value);
      return;
    }
    if (Array.isArray(current)) {
      current.push(value);
      return;
    }
    flags.set(name, [current, value]);
  };

  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (value === undefined) {
      continue;
    }

    if (value === "--") {
      positionals.push(...args.slice(index + 1));
      break;
    }

    if (isFlagToken(value)) {
      const equalsIndex = value.indexOf("=");
      if (equalsIndex > 0) {
        setFlag(value.slice(2, equalsIndex), value.slice(equalsIndex + 1));
        continue;
      }

      const next = args[index + 1];
      if (next === undefined || isFlagToken(next)) {
        setFlag(value.slice(2), true);
        continue;
      }

      setFlag(value.slice(2), next);
      index += 1;
      continue;
    }

    positionals.push(value);
  }

  return {
    raw: args,
    positionals,
    flags,
  };
}

const isParsedCliArgs = (args: readonly string[] | ParsedCliArgs): args is ParsedCliArgs =>
  !Array.isArray(args);

const ensureParsed = (args: readonly string[] | ParsedCliArgs): ParsedCliArgs =>
  isParsedCliArgs(args) ? args : parseCliArgs(args);

const isFlagValues = (value: unknown): value is readonly (string | true)[] => Array.isArray(value);

export function getFlag(args: readonly string[] | ParsedCliArgs, name: string): string | undefined {
  const parsed = ensureParsed(args);
  const value = parsed.flags.get(name);
  if (isFlagValues(value)) {
    const lastValue = value.at(-1);
    return lastValue === true ? undefined : lastValue;
  }
  return value === true ? undefined : value;
}

export function getBooleanFlag(args: readonly string[] | ParsedCliArgs, name: string): boolean {
  const parsed = ensureParsed(args);
  const value = parsed.flags.get(name);
  return isFlagValues(value) ? value.includes(true) : value === true;
}

export function getFlags(args: readonly string[] | ParsedCliArgs, name: string): readonly string[] {
  const parsed = ensureParsed(args);
  const value = parsed.flags.get(name);
  if (isFlagValues(value)) {
    return value.filter((entry): entry is string => entry !== true);
  }
  return typeof value === "string" ? [value] : [];
}

export function requireArg(value: string | undefined, name: string): string {
  if (!value) {
    const label = name.startsWith("--") ? name : `--${name}`;
    throw new CliUsageError({
      code: "missing_required_argument",
      message: `${label} is required.`,
      missing: [label],
    });
  }

  return value;
}

export function requirePositional(args: ParsedCliArgs, index: number, label: string): string {
  const value = args.positionals[index];
  if (!value) {
    throw new CliUsageError({
      code: "missing_required_argument",
      message: `${label} is required.`,
      missing: [label],
    });
  }

  return value;
}

export function parsePositiveInteger(value: string, errorMessage: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0 || String(parsed) !== value) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: errorMessage,
    });
  }

  return parsed;
}

export function parseIntegerFlag(args: readonly string[] | ParsedCliArgs, name: string): number | undefined {
  const value = getFlag(args, name);
  if (value === undefined) {
    return undefined;
  }

  return parsePositiveInteger(value, `invalid integer for --${name}`);
}
