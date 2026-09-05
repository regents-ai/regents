import path from "node:path";

import type { paths as PlatformPaths } from "../generated/platform-openapi.js";

import type {
  JsonRequestBodyFor,
  JsonSuccessResponseFor,
} from "../contracts/openapi-helpers.js";
import { loadConfig, StateStore } from "../internal-runtime/index.js";
import { getFlag, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";
import { requestProductJson } from "./product-http.js";

type BugReportRequest = JsonRequestBodyFor<
  PlatformPaths,
  "/api/platform/v1/agent/bug-report",
  "post"
>;
type BugReportResponse = JsonSuccessResponseFor<
  PlatformPaths,
  "/api/platform/v1/agent/bug-report",
  "post"
>;
type SecurityReportRequest = JsonRequestBodyFor<
  PlatformPaths,
  "/api/platform/v1/agent/security-report",
  "post"
>;
type SecurityReportResponse = JsonSuccessResponseFor<
  PlatformPaths,
  "/api/platform/v1/agent/security-report",
  "post"
>;

const readLocalAgentIdentity = (configPath?: string): NonNullable<BugReportRequest["reporting_agent"]> => {
  const config = loadConfig(configPath);
  const stateFilePath = path.join(config.runtime.stateDir, "runtime-state.json");
  const identity = new StateStore(stateFilePath).read().agent;

  if (
    !identity?.walletAddress ||
    typeof identity.chainId !== "number" ||
    !identity.registryAddress ||
    !identity.tokenId
  ) {
    throw new Error(
      "This machine does not have a saved Regent identity yet. Run `regents identity ensure` first.",
    );
  }

  if (identity.chainId !== 84532 && identity.chainId !== 8453) {
    throw new Error(
      "This machine does not have a Base Regent identity yet. Run `regents identity ensure` first.",
    );
  }

  return {
    wallet_address: identity.walletAddress,
    chain_id: identity.chainId as 84532 | 8453,
    registry_address: identity.registryAddress,
    token_id: identity.tokenId,
    ...(identity.label ? { label: identity.label } : {}),
  };
};

const requireTextFlag = (
  args: ParsedCliArgs,
  flag: string,
  errorMessage: string,
): string => {
  const value = getFlag(args, flag);
  if (value === undefined || value.trim() === "") {
    throw new Error(errorMessage);
  }

  return value;
};

export async function runBugReport(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const summary = requireTextFlag(
    args,
    "summary",
    'Bug reports need a non-empty --summary. Example: regents bug --summary "can\'t do xyz" --details "any more details here".',
  );
  const details = requireTextFlag(
    args,
    "details",
    'Bug reports need a non-empty --details. Example: regents bug --summary "can\'t do xyz" --details "any more details here".',
  );

  const payload: BugReportRequest = {
    summary,
    details,
    reporting_agent: readLocalAgentIdentity(configPath),
  };

  printJson(
    await requestProductJson<BugReportResponse>("POST", "/api/platform/v1/agent/bug-report", {
      body: payload,
      configPath,
      requireAgentAuth: true,
      authAudience: "regent-services",
      service: "platform",
      commandName: "regents bug",
    }),
  );
}

export async function runSecurityReport(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const summary = requireTextFlag(
    args,
    "summary",
    'Security reports need a non-empty --summary. Example: regents security-report --summary "private vuln" --details "steps and impact" --contact "@xyz on telegram".',
  );
  const details = requireTextFlag(
    args,
    "details",
    'Security reports need a non-empty --details. Example: regents security-report --summary "private vuln" --details "steps and impact" --contact "@xyz on telegram".',
  );
  const contact = requireTextFlag(
    args,
    "contact",
    'Security reports need a non-empty --contact. Example: regents security-report --summary "private vuln" --details "steps and impact" --contact "@xyz on telegram".',
  );

  const payload: SecurityReportRequest = {
    summary,
    details,
    contact,
    reporting_agent: readLocalAgentIdentity(configPath),
  };

  printJson(
    await requestProductJson<SecurityReportResponse>("POST", "/api/platform/v1/agent/security-report", {
      body: payload,
      configPath,
      requireAgentAuth: true,
      authAudience: "regent-services",
      service: "platform",
      commandName: "regents security-report",
    }),
  );
}
