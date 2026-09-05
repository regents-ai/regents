import fs from "node:fs";

import { CliUsageError } from "./cli-usage-error.js";
import {
  getFlag,
  getFlags,
  parseIntegerFlag,
  parsePositiveInteger,
  requireArg,
  type ParsedCliArgs,
} from "./parse.js";

export const readJsonObjectValue = (value: string, name: string): Record<string, unknown> => {
  const raw = value.startsWith("@") ? fs.readFileSync(value.slice(1), "utf8") : value;

  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error();
    }

    return parsed as Record<string, unknown>;
  } catch {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: `invalid ${name}`,
    });
  }
};

export const readOptionalJsonObjectFlag = (
  args: readonly string[] | ParsedCliArgs,
  flagName: string,
): Record<string, unknown> | undefined => {
  const value = getFlag(args, flagName);
  return value === undefined ? undefined : readJsonObjectValue(value, `--${flagName}`);
};

export const parseNonNegativeIntegerValue = (value: string, name: string): number => {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0 || String(parsed) !== value) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: `invalid integer for ${name}`,
    });
  }

  return parsed;
};

export const parseRequiredNonNegativeIntegerFlag = (
  args: readonly string[] | ParsedCliArgs,
  name: string,
): number => parseNonNegativeIntegerValue(requireArg(getFlag(args, name), name), `--${name}`);

export const parseOptionalNonNegativeIntegerFlag = (
  args: readonly string[] | ParsedCliArgs,
  name: string,
): number | undefined => {
  const value = getFlag(args, name);
  return value === undefined ? undefined : parseNonNegativeIntegerValue(value, `--${name}`);
};

export const parseOptionalPositiveIntegerFlag = (
  args: readonly string[] | ParsedCliArgs,
  name: string,
): number | undefined => {
  const value = getFlag(args, name);
  return value === undefined ? undefined : parsePositiveInteger(value, `invalid integer for --${name}`);
};

export const parseCsvFlag = (
  args: readonly string[] | ParsedCliArgs,
  name: string,
): string[] =>
  getFlags(args, name).flatMap((value) =>
    value.split(",").map((entry) => entry.trim()).filter(Boolean),
  );

export const optionalCsvFlag = (
  args: readonly string[] | ParsedCliArgs,
  name: string,
): string[] | undefined => {
  const values = parseCsvFlag(args, name);
  return values.length > 0 ? values : undefined;
};

export const putOptionalStringFlag = (
  body: Record<string, unknown>,
  key: string,
  args: readonly string[] | ParsedCliArgs,
  flagName: string,
): void => {
  const value = getFlag(args, flagName);
  if (value !== undefined) {
    body[key] = value;
  }
};

export const putOptionalIntegerFlag = (
  body: Record<string, unknown>,
  key: string,
  args: readonly string[] | ParsedCliArgs,
  flagName: string,
): void => {
  const value = parseIntegerFlag(args, flagName);
  if (value !== undefined) {
    body[key] = value;
  }
};
