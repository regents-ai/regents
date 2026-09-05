import { putOptionalStringFlag } from "../../command-input.js";
import {
  getBooleanFlag,
  getFlag,
  requireArg,
  requirePositional,
  type ParsedCliArgs,
} from "../../parse.js";
import { printJson } from "../../printer.js";
import {
  preparedWalletActionFromEnvelope,
  printWalletActionEnvelope,
} from "../../terminal/wallet-action.js";
import {
  type JsonObject,
  requestJson,
  submitPreparedTxRequest,
  txRequestFromWalletAction,
} from "./shared.js";

const autolaunchPreparedAction = (envelope: JsonObject): JsonObject =>
  preparedWalletActionFromEnvelope(
    envelope,
    "This Autolaunch action did not include a transaction to submit.",
  ) as JsonObject;

const prepareOrSubmitWalletAction = async (
  preparePath: string,
  body: Record<string, unknown>,
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> => {
  const prepared = await requestJson("POST", preparePath, {
    body,
    requireAgentAuth: true,
    configPath,
  });

  if (!getBooleanFlag(args, "submit")) {
    printWalletActionEnvelope(args, prepared, {
      title: "AUTOLAUNCH WALLET ACTION",
      submitHint: "Run the same command with --submit when ready.",
      missingMessage: "This Autolaunch action did not include a transaction to submit.",
    });
    return;
  }

  const preparedAction = autolaunchPreparedAction(prepared);
  const txRequest = txRequestFromWalletAction(preparedAction.wallet_action);

  if (!txRequest) {
    throw new Error("This Autolaunch action did not include a transaction to submit.");
  }

  const txHash = await submitPreparedTxRequest(txRequest, configPath);

  printJson({ ok: true, tx_hash: txHash, prepared: preparedAction });
};

export async function runAutolaunchSubjectByToken(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const token = requireArg(getFlag(args, "token"), "token");
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/subjects/by-token/${encodeURIComponent(token)}`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchSubjectGet(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requirePositional(args, 3, "subject-id");
  printJson(
    await requestJson("GET", `/api/autolaunch/v1/agent/subjects/${encodeURIComponent(subjectId)}`, {
      requireAgentAuth: true,
      configPath,
    }),
  );
}

export async function runAutolaunchSubjectIngress(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requirePositional(args, 3, "subject-id");
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/subjects/${encodeURIComponent(subjectId)}/ingress`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchSubjectStaking(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requirePositional(args, 3, "subject-id");
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/subjects/${encodeURIComponent(subjectId)}/staking`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchSubjectBuybacks(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requirePositional(args, 3, "subject-id");
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/subjects/${encodeURIComponent(subjectId)}/buybacks`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchSubjectPaymentLinks(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requirePositional(args, 3, "subject-id");
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/subjects/${encodeURIComponent(subjectId)}/payment-links`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchPaymentLinkCreate(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requireArg(getFlag(args, "subject"), "subject");
  const body: Record<string, unknown> = {
    label: requireArg(getFlag(args, "label"), "label"),
    canonical: getBooleanFlag(args, "canonical"),
    salt: requireArg(getFlag(args, "salt"), "salt"),
  };

  await prepareOrSubmitWalletAction(
    `/api/autolaunch/v1/agent/contracts/subjects/${encodeURIComponent(subjectId)}/payment_link_factory/create/prepare`,
    body,
    args,
    configPath,
  );
}

export async function runAutolaunchPaymentLinkSetCanonical(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requireArg(getFlag(args, "subject"), "subject");
  const address = requireArg(getFlag(args, "address"), "address");

  await prepareOrSubmitWalletAction(
    `/api/autolaunch/v1/agent/contracts/subjects/${encodeURIComponent(subjectId)}/payment_link_factory/set_canonical/prepare`,
    {
      canonical: requireArg(getFlag(args, "canonical"), "canonical"),
      payment_link: address,
    },
    args,
    configPath,
  );
}

export async function runAutolaunchPaymentLinkSetState(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requireArg(getFlag(args, "subject"), "subject");
  const address = requireArg(getFlag(args, "address"), "address");
  const body: Record<string, unknown> = {
    active: requireArg(getFlag(args, "active"), "active"),
    payment_link: address,
  };
  putOptionalStringFlag(body, "replacement", args, "replacement");

  await prepareOrSubmitWalletAction(
    `/api/autolaunch/v1/agent/contracts/subjects/${encodeURIComponent(subjectId)}/payment_link_factory/set_state/prepare`,
    body,
    args,
    configPath,
  );
}

export async function runAutolaunchSubjectSweepIngress(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requirePositional(args, 3, "subject-id");
  const address = requireArg(getFlag(args, "address"), "address");

  await prepareOrSubmitWalletAction(
    `/api/autolaunch/v1/agent/contracts/subjects/${encodeURIComponent(subjectId)}/ingress_account/sweep/prepare`,
    { ingress_address: address },
    args,
    configPath,
  );
}
