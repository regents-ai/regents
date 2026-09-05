import type { paths as AutolaunchPaths } from "../../generated/autolaunch-public-openapi.js";
import {
  getFlag,
  requireArg,
  type ParsedCliArgs,
} from "../../parse.js";
import { CliUsageError } from "../../cli-usage-error.js";
import { printJson } from "../../printer.js";
import type { JsonSuccessResponseFor } from "../../contracts/openapi-helpers.js";
import { appendQuery, requestJson, requestTypedJson } from "./shared.js";

type AutolaunchAuctionsListResponse = JsonSuccessResponseFor<
  AutolaunchPaths,
  "/api/v1/auctions",
  "get"
>;
type AutolaunchAuctionResponse = JsonSuccessResponseFor<
  AutolaunchPaths,
  "/api/v1/auctions/{id}",
  "get"
>;

export async function runAutolaunchAuctionsList(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  assertPublicFlags(args, ["mode", "sort", "limit"]);
  printJson(
    await requestTypedJson<AutolaunchAuctionsListResponse>(
      "GET",
      appendQuery("/api/v1/auctions", {
        mode: getFlag(args, "mode"),
        sort: getFlag(args, "sort"),
        limit: getFlag(args, "limit"),
      }),
      { publicRead: true, configPath },
    ),
  );
}

export async function runAutolaunchAuctionShow(
  auctionId: string,
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  assertPublicFlags(args, []);
  printJson(
    await requestTypedJson<AutolaunchAuctionResponse>(
      "GET",
      `/api/v1/auctions/${publicPathSegment(auctionId)}`,
      { publicRead: true, configPath },
    ),
  );
}

export async function runAutolaunchBidsQuote(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  assertPublicFlags(args, ["auction", "amount", "max-price"]);
  const auctionId = requireArg(getFlag(args, "auction"), "auction");
  const body = {
    amount: requireArg(getFlag(args, "amount"), "amount"),
    max_price: requireArg(getFlag(args, "max-price"), "max-price"),
  };

  printJson(
    await requestJson(
      "POST",
      `/api/v1/auctions/${publicPathSegment(auctionId)}/bid-quote`,
      {
        body,
        publicRead: true,
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

export async function runAutolaunchTokensList(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  assertPublicFlags(args, ["limit"]);
  printJson(await requestTypedJson<JsonSuccessResponseFor<AutolaunchPaths, "/api/v1/tokens", "get">>(
    "GET", appendQuery("/api/v1/tokens", { limit: getFlag(args, "limit") }),
    { publicRead: true, configPath },
  ));
}

export async function runAutolaunchTreasurySecurity(
  address: string,
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  assertPublicFlags(args, []);
  printJson(await requestTypedJson<JsonSuccessResponseFor<AutolaunchPaths, "/api/v1/treasury-security/{address}", "get">>(
    "GET", `/api/v1/treasury-security/${publicPathSegment(address)}`,
    { publicRead: true, configPath },
  ));
}

// URL parsers normalize dot-only segments even after encodeURIComponent.
const publicPathSegment = (value: string): string => {
  if (value === "." || value === "..") {
    throw new CliUsageError({ message: "A record identifier cannot be a dot-only path segment." });
  }
  return encodeURIComponent(value);
};

const assertPublicFlags = (args: ParsedCliArgs, allowed: readonly string[]): void => {
  for (const [flag, value] of args.flags) {
    if (flag === "json" || flag === "help" || flag === "config") continue;
    if (!allowed.includes(flag) || typeof value !== "string" || value === "") {
      throw new CliUsageError({
        code: "invalid_flag_value",
        message: `Unsupported or missing value for --${flag}.`,
      });
    }
  }
};
