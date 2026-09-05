import { getFlag, type ParsedCliArgs } from "../../parse.js";
import { printJson } from "../../printer.js";
import { appendQuery, requestJson } from "./shared.js";

export async function runAutolaunchAuctionReturnsList(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestJson(
      "GET",
      appendQuery("/api/autolaunch/v1/agent/auction-returns", {
        limit: getFlag(args, "limit"),
        offset: getFlag(args, "offset"),
      }),
      { requireAgentAuth: true, configPath },
    ),
  );
}
