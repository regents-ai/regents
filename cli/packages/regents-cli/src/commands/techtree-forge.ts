import { CliUsageError } from "../cli-usage-error.js";
import {
  handleTechtreeForgeFamilyShow,
  handleTechtreeForgeFamilyValidate,
} from "../internal-runtime/handlers/techtree/forge.js";
import type { TechtreeForgeFamilyValidationInput } from "../internal-types/index.js";
import { getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

export async function runTechtreeForgeFamilyShow(): Promise<void> {
  printJson(await handleTechtreeForgeFamilyShow());
}

export async function runTechtreeForgeFamilyValidate(args: ParsedCliArgs): Promise<void> {
  const rawInput = requireArg(getFlag(args, "input-json"), "--input-json");
  let input: unknown;
  try {
    input = JSON.parse(rawInput);
  } catch {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: "--input-json must be valid JSON.",
    });
  }

  printJson(
    await handleTechtreeForgeFamilyValidate({
      input: input as TechtreeForgeFamilyValidationInput,
    }),
  );
}
