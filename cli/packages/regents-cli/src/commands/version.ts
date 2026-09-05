import type { ParsedCliArgs } from "../parse.js";

import { getBooleanFlag } from "../parse.js";
import { cliVersion, printJson, printText } from "../printer.js";

export async function runVersion(args: ParsedCliArgs): Promise<number> {
  const version = cliVersion() || "unknown";

  if (getBooleanFlag(args, "json")) {
    printJson({ ok: true, name: "@regentslabs/cli", version });
    return 0;
  }

  printText(version);
  return 0;
}
