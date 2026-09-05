import type { ParsedCliArgs } from "../parse.js";
import { daemonCall } from "../daemon-client.js";
import { getFlag } from "../parse.js";
import { printJson } from "../printer.js";

const callAgent = async (
  method: Parameters<typeof daemonCall>[0],
  params?: Record<string, unknown>,
  configPath?: string,
): Promise<void> => {
  printJson(await daemonCall(method, params, configPath));
};

export async function runAgentInit(configPath?: string): Promise<void> {
  await callAgent("agent.init", undefined, configPath);
}

export async function runAgentStatus(configPath?: string): Promise<void> {
  await callAgent("agent.status", undefined, configPath);
}

export async function runAgentProfileList(configPath?: string): Promise<void> {
  await callAgent("agent.profile.list", undefined, configPath);
}

export async function runAgentProfileGet(args: readonly string[] | ParsedCliArgs, configPath?: string): Promise<void> {
  await callAgent(
    "agent.profile.show",
    {
      profile: getFlag(args, "profile"),
    },
    configPath,
  );
}

export async function runAgentHarnessList(configPath?: string): Promise<void> {
  await callAgent("agent.harness.list", undefined, configPath);
}
