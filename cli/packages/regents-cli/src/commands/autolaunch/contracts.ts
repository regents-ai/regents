import { getFlag, requireArg, type ParsedCliArgs } from "../../parse.js";
import { printJson } from "../../printer.js";
import { loadResolvedPlatformSession, requestPlatformSessionJson } from "../platform.js";
import { requestJson } from "./shared.js";

const requireJobFlag = (args: ParsedCliArgs): string =>
  requireArg(getFlag(args, "job"), "job");
const requireSubjectFlag = (args: ParsedCliArgs): string =>
  requireArg(getFlag(args, "subject"), "subject");

const postPrepareJobAction = async (
  args: ParsedCliArgs,
  resource: string,
  action: string,
  body: Record<string, unknown> = {},
  configPath?: string,
): Promise<void> => {
  const jobId = requireJobFlag(args);

  printJson(
    await requestJson(
      "POST",
      `/api/autolaunch/v1/agent/contracts/jobs/${encodeURIComponent(jobId)}/${resource}/${action}/prepare`,
      { body, requireAgentAuth: true, configPath },
    ),
  );
};

const postPrepareSubjectAction = async (
  args: ParsedCliArgs,
  resource: string,
  action: string,
  body: Record<string, unknown> = {},
  configPath?: string,
): Promise<void> => {
  const subjectId = requireSubjectFlag(args);

  printJson(
    await requestJson(
      "POST",
      `/api/autolaunch/v1/agent/contracts/subjects/${encodeURIComponent(subjectId)}/${resource}/${action}/prepare`,
      { body, requireAgentAuth: true, configPath },
    ),
  );
};

const postPrepareAdminAction = async (
  resource: string,
  action: string,
  body: Record<string, unknown> = {},
  configPath?: string,
): Promise<void> => {
  printJson(
    await requestJson(
      "POST",
      `/api/autolaunch/v1/agent/contracts/admin/${resource}/${action}/prepare`,
      {
        body,
        requireAgentAuth: true,
        configPath,
      },
    ),
  );
};

export async function runAutolaunchContractsAdminShow(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const { origin, session } = await loadResolvedPlatformSession(args);
  const { data } = await requestPlatformSessionJson({
    origin,
    path: "/api/autolaunch/v1/app/contracts/admin",
    method: "GET",
    session,
    commandName: "regents autolaunch contracts admin",
    configPath,
  });

  printJson(data);
}

export async function runAutolaunchContractsJobShow(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const jobId = requireJobFlag(args);
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/contracts/jobs/${encodeURIComponent(jobId)}`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchContractsSubjectShow(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const subjectId = requireSubjectFlag(args);
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/contracts/subjects/${encodeURIComponent(subjectId)}`,
      { requireAgentAuth: true, configPath },
    ),
  );
}

export async function runAutolaunchStrategyMigrate(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "strategy", "migrate", {}, configPath);
}

export async function runAutolaunchAuctionClaimUnusedTokens(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "auction", "claim_unused_tokens", {}, configPath);
}

export async function runAutolaunchStrategySweepToken(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "strategy", "sweep_token", {}, configPath);
}

export async function runAutolaunchStrategySweepQuoteToken(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "strategy", "sweep_quote_token", {}, configPath);
}

export async function runAutolaunchVestingRelease(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "vesting", "release", {}, configPath);
}

export async function runAutolaunchVestingProposeBeneficiaryRotation(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "vesting", "propose_beneficiary_rotation", {
    beneficiary: requireArg(getFlag(args, "beneficiary"), "beneficiary"),
  }, configPath);
}

export async function runAutolaunchVestingCancelBeneficiaryRotation(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "vesting", "cancel_beneficiary_rotation", {}, configPath);
}

export async function runAutolaunchVestingExecuteBeneficiaryRotation(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "vesting", "execute_beneficiary_rotation", {}, configPath);
}

export async function runAutolaunchFeeRegistryGet(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await runAutolaunchContractsJobShow(args, configPath);
}

export async function runAutolaunchFeeVaultGet(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await runAutolaunchContractsJobShow(args, configPath);
}

export async function runAutolaunchFeeVaultWithdrawRegent(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareJobAction(args, "fee_vault", "withdraw_regent_share", {
    currency: requireArg(getFlag(args, "currency"), "currency"),
    amount: requireArg(getFlag(args, "amount"), "amount"),
    recipient: requireArg(getFlag(args, "recipient"), "recipient"),
  }, configPath);
}

export async function runAutolaunchSplitterGet(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await runAutolaunchContractsSubjectShow(args, configPath);
}

export async function runAutolaunchSplitterAcceptOwnership(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "revenue_splitter", "accept_ownership", {}, configPath);
}

export async function runAutolaunchSplitterSetPaused(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "set_paused", {
    paused: requireArg(getFlag(args, "paused"), "paused"),
  }, configPath);
}

export async function runAutolaunchSplitterSetLabel(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "set_label", {
    label: requireArg(getFlag(args, "label"), "label"),
  }, configPath);
}

export async function runAutolaunchSplitterProposeEligibleRevenueShare(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "propose_eligible_revenue_share", {
    share_bps: requireArg(getFlag(args, "share-bps"), "share-bps"),
  }, configPath);
}

export async function runAutolaunchSplitterCancelEligibleRevenueShare(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "cancel_eligible_revenue_share", {}, configPath);
}

export async function runAutolaunchSplitterActivateEligibleRevenueShare(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "activate_eligible_revenue_share", {}, configPath);
}

export async function runAutolaunchSplitterProposeTreasuryRecipientRotation(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(
    args,
    "splitter",
    "propose_treasury_recipient_rotation",
    {
      recipient: requireArg(getFlag(args, "recipient"), "recipient"),
    },
    configPath,
  );
}

export async function runAutolaunchSplitterCancelTreasuryRecipientRotation(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(
    args,
    "splitter",
    "cancel_treasury_recipient_rotation",
    {},
    configPath,
  );
}

export async function runAutolaunchSplitterExecuteTreasuryRecipientRotation(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(
    args,
    "splitter",
    "execute_treasury_recipient_rotation",
    {},
    configPath,
  );
}

export async function runAutolaunchSplitterSweepTreasuryResidual(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "sweep_treasury_residual", {
    amount: requireArg(getFlag(args, "amount"), "amount"),
  }, configPath);
}

export async function runAutolaunchSplitterSweepTreasuryReserved(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "sweep_treasury_reserved", {
    amount: requireArg(getFlag(args, "amount"), "amount"),
  }, configPath);
}

export async function runAutolaunchSplitterReassignDust(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "splitter", "reassign_dust", {
    amount: requireArg(getFlag(args, "amount"), "amount"),
  }, configPath);
}

export async function runAutolaunchIngressCreate(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "ingress_factory", "create", {
    label: requireArg(getFlag(args, "label"), "label"),
    make_default: getFlag(args, "make-default") ?? "false",
  }, configPath);
}

export async function runAutolaunchIngressSetDefault(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "ingress_factory", "set_default", {
    ingress_address: requireArg(getFlag(args, "address"), "address"),
  }, configPath);
}

export async function runAutolaunchIngressSetLabel(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "ingress_account", "set_label", {
    ingress_address: requireArg(getFlag(args, "address"), "address"),
    label: requireArg(getFlag(args, "label"), "label"),
  }, configPath);
}

export async function runAutolaunchIngressRescue(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "ingress_account", "rescue", {
    ingress_address: requireArg(getFlag(args, "address"), "address"),
    token: requireArg(getFlag(args, "token"), "token"),
    amount: requireArg(getFlag(args, "amount"), "amount"),
    recipient: requireArg(getFlag(args, "recipient"), "recipient"),
  }, configPath);
}

export async function runAutolaunchRegistryGet(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await runAutolaunchContractsSubjectShow(args, configPath);
}

export async function runAutolaunchRegistrySetSubjectManager(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "registry", "set_subject_manager", {
    account: requireArg(getFlag(args, "account"), "account"),
    enabled: requireArg(getFlag(args, "enabled"), "enabled"),
  }, configPath);
}

export async function runAutolaunchRegistryLinkIdentity(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "registry", "link_identity", {
    identity_chain_id: requireArg(
      getFlag(args, "identity-chain-id"),
      "identity-chain-id",
    ),
    identity_registry: requireArg(
      getFlag(args, "identity-registry"),
      "identity-registry",
    ),
    identity_agent_id: requireArg(
      getFlag(args, "identity-agent-id"),
      "identity-agent-id",
    ),
  }, configPath);
}

export async function runAutolaunchRegistryRotateSafe(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareSubjectAction(args, "registry", "rotate_safe", {
    new_safe: requireArg(getFlag(args, "new-safe"), "new-safe"),
  }, configPath);
}

export async function runAutolaunchRevenueShareFactorySetAuthorizedCreator(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareAdminAction(
    "revenue_share_factory",
    "set_authorized_creator",
    {
      account: requireArg(getFlag(args, "account"), "account"),
      enabled: requireArg(getFlag(args, "enabled"), "enabled"),
    },
    configPath,
  );
}

export async function runAutolaunchRevenueIngressFactorySetAuthorizedCreator(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await postPrepareAdminAction(
    "revenue_ingress_factory",
    "set_authorized_creator",
    {
      account: requireArg(getFlag(args, "account"), "account"),
      enabled: requireArg(getFlag(args, "enabled"), "enabled"),
    },
    configPath,
  );
}
