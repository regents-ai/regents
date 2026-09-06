import {CliUsageError} from "../cli-usage-error.js";
import {getFlag, type ParsedCliArgs} from "../parse.js";
import {printJson} from "../printer.js";
import {profileTarget, requestProfile, ProfileInputError} from "./profile-http.js";

export async function runProfile(operation: "get" | "sync" | "update", args: ParsedCliArgs): Promise<void> {
  const allowed = new Set(["json", "base-url", "timeout-ms", ...(operation === "update" ? ["display-name", "wallet-address", "clear-wallet"] : [])]);
  for (const [key, value] of args.flags) {
    if (!allowed.has(key) || Array.isArray(value) || (key !== "json" && typeof value !== "string")) throw new CliUsageError({message: "Unsupported or repeated profile option. Use profile --help."});
  }
  const timeout = Number(getFlag(args, "timeout-ms") ?? "30000");
  if (!Number.isSafeInteger(timeout) || timeout < 1 || timeout > 300000) throw new CliUsageError({message: "--timeout-ms must be an integer from 1 to 300000."});
  try {
    const target = profileTarget(operation, Object.fromEntries(args.flags));
    const result = await requestProfile(getFlag(args, "base-url") ?? "https://regents.sh", target, timeout);
    printJson(result);
    if (!result.ok) process.exitCode = result.error?.code === "aborted" ? 130 : 1;
  } catch (error) {
    if (error instanceof ProfileInputError) throw new CliUsageError({message: error.message});
    throw new Error("Profile could not be completed.");
  }
}
