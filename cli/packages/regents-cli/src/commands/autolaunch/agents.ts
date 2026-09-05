import type { paths as AutolaunchPaths } from "../../generated/autolaunch-openapi.js";
import type { ParsedCliArgs } from "../../parse.js";
import { getBooleanFlag } from "../../parse.js";
import { printJson } from "../../printer.js";
import type { JsonSuccessResponseFor } from "../../contracts/openapi-helpers.js";
import { appendQuery, requestTypedJson } from "./shared.js";

type AutolaunchAgentsListResponse = JsonSuccessResponseFor<
  AutolaunchPaths,
  "/api/autolaunch/v1/agent/agents",
  "get"
>;
type AutolaunchAgentResponse = JsonSuccessResponseFor<
  AutolaunchPaths,
  "/api/autolaunch/v1/agent/agents/{id}",
  "get"
>;
type AutolaunchAgentReadinessResponse = JsonSuccessResponseFor<
  AutolaunchPaths,
  "/api/autolaunch/v1/agent/agents/{id}/readiness",
  "get"
>;
export async function runAutolaunchAgentsList(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestTypedJson<AutolaunchAgentsListResponse>(
      "GET",
      appendQuery("/api/autolaunch/v1/agent/agents", {
        launchable: getBooleanFlag(args, "launchable"),
      }),
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchAgentShow(
  agentId: string,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestTypedJson<AutolaunchAgentResponse>(
      "GET",
      `/api/autolaunch/v1/agent/agents/${encodeURIComponent(agentId)}`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchAgentReadiness(
  agentId: string,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestTypedJson<AutolaunchAgentReadinessResponse>(
      "GET",
      `/api/autolaunch/v1/agent/agents/${encodeURIComponent(agentId)}/readiness`,
      { requireAgentAuth: true, configPath },
    ),
  );
}
