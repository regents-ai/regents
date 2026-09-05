import fs from "node:fs";

import * as RegentRuntime from "../internal-runtime/index.js";

import { CliUsageError } from "../cli-usage-error.js";
import { getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

const resolveConfigPath = (args: ParsedCliArgs): string =>
  RegentRuntime.expandHome(getFlag(args, "config") ?? RegentRuntime.defaultConfigPath());

const readFileFlag = (value: string | undefined, name: string): string => {
  const fileFlag = requireArg(value, name);
  if (!fileFlag.startsWith("@")) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: `--${name} must use @/absolute/or/relative/path.json syntax`,
      example: `--${name} @./replacement.json`,
    });
  }

  return fs.readFileSync(fileFlag.slice(1), "utf8");
};

export async function runConfigGet(args: ParsedCliArgs): Promise<void> {
  printJson(RegentRuntime.loadConfig(resolveConfigPath(args)));
}

export async function runConfigWrite(args: ParsedCliArgs): Promise<void> {
  const configPath = resolveConfigPath(args);
  const rawInput = readFileFlag(getFlag(args, "input"), "input");
  const parsedInput = JSON.parse(rawInput) as unknown;
  const writtenConfig = RegentRuntime.writeConfigReplacement(configPath, parsedInput);

  printJson({
    ok: true,
    configPath,
    config: writtenConfig,
  });
}
