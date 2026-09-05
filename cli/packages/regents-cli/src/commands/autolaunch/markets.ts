import type { paths as AutolaunchPaths } from "../../generated/autolaunch-openapi.js";
import {
  getBooleanFlag,
  getFlag,
  requireArg,
  type ParsedCliArgs,
} from "../../parse.js";
import { printJson } from "../../printer.js";
import type { JsonSuccessResponseFor } from "../../contracts/openapi-helpers.js";
import { appendQuery, requestJson, requestTypedJson } from "./shared.js";

type AutolaunchAuctionsListResponse = JsonSuccessResponseFor<
  AutolaunchPaths,
  "/api/autolaunch/v1/agent/auctions",
  "get"
>;
type AutolaunchAuctionResponse = JsonSuccessResponseFor<
  AutolaunchPaths,
  "/api/autolaunch/v1/agent/auctions/{id}",
  "get"
>;

export async function runAutolaunchAuctionsList(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestTypedJson<AutolaunchAuctionsListResponse>(
      "GET",
      appendQuery("/api/autolaunch/v1/agent/auctions", {
        sort: getFlag(args, "sort") ?? "hottest",
        status: getFlag(args, "status"),
        chain: getFlag(args, "chain"),
        mine_only: getBooleanFlag(args, "mine-only"),
      }),
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchAuctionShow(
  auctionId: string,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestTypedJson<AutolaunchAuctionResponse>(
      "GET",
      `/api/autolaunch/v1/agent/auctions/${encodeURIComponent(auctionId)}`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchBidsQuote(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const auctionId = requireArg(getFlag(args, "auction"), "auction");
  const body = {
    amount: requireArg(getFlag(args, "amount"), "amount"),
    max_price: requireArg(getFlag(args, "max-price"), "max-price"),
  };

  printJson(
    await requestJson(
      "POST",
      `/api/autolaunch/v1/agent/auctions/${encodeURIComponent(auctionId)}/bid_quote`,
      {
        body,
        requireAgentAuth: true,
        configPath,
      },
    ),
  );
}

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
