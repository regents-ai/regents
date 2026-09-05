import {
  getBooleanFlag,
  getFlag,
  requireArg,
  type ParsedCliArgs,
} from "../../parse.js";
import { printJson } from "../../printer.js";
import { launchChainId, requestJson } from "./shared.js";

const buildEnsLinkBody = (args: ParsedCliArgs): Record<string, unknown> => {
  const body: Record<string, unknown> = {
    ens_name: requireArg(getFlag(args, "ens"), "ens"),
  };

  const identity = getFlag(args, "identity");
  if (identity) {
    body.identity_id = identity;
  }

  const chainId = getFlag(args, "chain-id") ?? launchChainId(args);
  if (chainId) {
    body.chain_id = chainId;
  }

  const agentId = getFlag(args, "agent-id");
  if (agentId) {
    body.agent_id = agentId;
  }

  const signerAddress = getFlag(args, "signer-address");
  if (signerAddress) {
    body.signer_address = signerAddress;
  }

  if (getBooleanFlag(args, "include-reverse")) {
    body.include_reverse = true;
  }

  return body;
};

export async function runAutolaunchEnsPlan(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestJson("POST", "/api/autolaunch/v1/agent/ens/link/plan", {
      body: buildEnsLinkBody(args),
      requireAgentAuth: true,
      configPath,
    }),
  );
}

export async function runAutolaunchEnsPrepareEnsip25(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestJson("POST", "/api/autolaunch/v1/agent/ens/link/prepare-ensip25", {
      body: buildEnsLinkBody(args),
      requireAgentAuth: true,
      configPath,
    }),
  );
}

export async function runAutolaunchEnsPrepareErc8004(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestJson("POST", "/api/autolaunch/v1/agent/ens/link/prepare-erc8004", {
      body: buildEnsLinkBody(args),
      requireAgentAuth: true,
      configPath,
    }),
  );
}

export async function runAutolaunchEnsPrepareBidirectional(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printJson(
    await requestJson("POST", "/api/autolaunch/v1/agent/ens/link/prepare-bidirectional", {
      body: buildEnsLinkBody(args),
      requireAgentAuth: true,
      configPath,
    }),
  );
}
