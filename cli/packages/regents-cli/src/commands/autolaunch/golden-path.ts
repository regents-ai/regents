import fs from "node:fs";
import path from "node:path";

import { CliUsageError } from "../../cli-usage-error.js";
import { loadConfig } from "../../internal-runtime/config.js";
import { ensureSecureDir, writeJsonFileAtomicSync } from "../../internal-runtime/paths.js";
import { SiwaClient } from "../../internal-runtime/siwa/siwa.js";
import {
  getFlag,
  getBooleanFlag,
  requireArg,
  type ParsedCliArgs,
} from "../../parse.js";
import {
  CLI_PALETTE,
  isHumanTerminal,
  printJson,
  printText,
  renderPanel,
  tone,
} from "../../printer.js";
import { createPromptBoundary, type PromptBoundary } from "../../terminal/prompts.js";
import { requireAgentAuthState } from "../agent-auth.js";
import { printAlphaFundsWarning } from "./alpha-warning.js";
import {
  createAutolaunchAgentConnection,
  renderConnectionStartReceipt,
  type AgentConnectionSessionEnvelope,
} from "./pairing.js";
import { printAgentSafeExplainer } from "./safe-explainer.js";
import {
  configuredSigner,
  parsePollingIntervalSeconds,
  requestJson,
  submitPreparedTxRequest,
  txRequestFromWalletAction,
} from "./shared.js";

interface LocalPlanRecord {
  readonly plan_id: string;
  readonly saved_at: string;
  readonly remote_plan: Record<string, unknown>;
}

const PRELAUNCH_DIR = "autolaunch-plans";
const AUTOLAUNCH_CHAIN_ID = 8_453;
const REGENT_DECIMALS = 18;
const REGENT_SCALE = 10n ** BigInt(REGENT_DECIMALS);
const HIGH_MINIMUM_RAISE_QUOTE_WEI = 50_000n * REGENT_SCALE;
const PRELAUNCH_WIZARD_FLAGS = new Set([
  "agent",
  "agent-safe-address",
  "config",
  "connect-profile",
  "description",
  "fallback-operator-wallet",
  "image-url",
  "json",
  "launch-notes",
  "minimum-raise-quote",
  "name",
  "no-input",
  "plan",
  "subtitle",
  "symbol",
  "title",
  "website-url",
]);

const normalizeText = (value: string | undefined): string | undefined => {
  if (!value) {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
};

const validatedLengthText = (
  value: string,
  label: string,
  minLength: number,
  maxLength: number,
): string => {
  const trimmed = normalizeText(value);

  if (!trimmed) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: `${label} is required.`,
    });
  }

  const length = Array.from(trimmed).length;
  if (length < minLength || length > maxLength) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: `${label} must be ${minLength} to ${maxLength} characters.`,
    });
  }

  return trimmed;
};

const validatedMinimumRaiseQuote = (value: string): string => {
  const trimmed = normalizeText(value);

  if (!trimmed || !/^[0-9]+(?:\.[0-9]{1,18})?$/u.test(trimmed)) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: "Minimum $REGENT raise must be 0 or greater, with up to 18 decimals.",
    });
  }

  const [wholePart = "0", fractionalPart] = trimmed.split(".");
  const whole = wholePart.replace(/^0+(?=\d)/u, "");
  const fractional = fractionalPart?.replace(/0+$/u, "");

  return fractional ? `${whole}.${fractional}` : whole;
};

const quoteToWei = (value: string): bigint => {
  const [wholePart = "0", fractionalPart = ""] = value.split(".");
  const fractional = fractionalPart.padEnd(REGENT_DECIMALS, "0");

  return BigInt(wholePart) * REGENT_SCALE + BigInt(fractional);
};

const assertPrelaunchWizardFlags = (args: ParsedCliArgs): void => {
  const unsupported = Array.from(args.flags.keys())
    .filter((flag) => !PRELAUNCH_WIZARD_FLAGS.has(flag))
    .sort();

  if (unsupported.length > 0) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: `Unsupported flag for autolaunch prelaunch wizard: --${unsupported[0]}.`,
    });
  }
};

const confirmHighMinimumRaise = async (
  value: string,
  prompts: PromptBoundary,
): Promise<void> => {
  if (quoteToWei(value) <= HIGH_MINIMUM_RAISE_QUOTE_WEI) {
    return;
  }

  const confirmed = await prompts.confirm(
    `Minimum raise is ${value} $REGENT, which is above 50000. Continue?`,
    {
      unavailableMessage:
        "Minimum $REGENT raise above 50000 requires confirmation. Rerun in an interactive terminal.",
    },
  );

  if (!confirmed) {
    throw new CliUsageError({
      code: "high_minimum_raise_not_confirmed",
      message: "Minimum $REGENT raise was not confirmed.",
    });
  }
};

const stateDir = (configPath?: string): string =>
  loadConfig(configPath).runtime.stateDir;

const planDir = (configPath?: string): string => {
  const resolved = path.join(stateDir(configPath), PRELAUNCH_DIR);
  ensureSecureDir(resolved);
  return resolved;
};

const planPath = (planId: string, configPath?: string): string =>
  path.join(planDir(configPath), `${planId}.json`);

const saveLocalPlan = (
  plan: Record<string, unknown>,
  configPath?: string,
): LocalPlanRecord => {
  const planId = String(plan.plan_id ?? "");
  if (!planId) {
    throw new Error("remote plan payload is missing plan_id");
  }

  const record: LocalPlanRecord = {
    plan_id: planId,
    saved_at: new Date().toISOString(),
    remote_plan: plan,
  };

  writeJsonFileAtomicSync(planPath(planId, configPath), record);
  return record;
};

const loadLocalPlan = (
  planId: string,
  configPath?: string,
): LocalPlanRecord => {
  const raw = fs.readFileSync(planPath(planId, configPath), "utf8");
  return JSON.parse(raw) as LocalPlanRecord;
};

const latestLocalPlan = (configPath?: string): LocalPlanRecord | null => {
  const dir = planDir(configPath);
  const files = fs
    .readdirSync(dir)
    .filter((entry) => entry.endsWith(".json"))
    .map((entry) => path.join(dir, entry))
    .map((filePath) => ({ filePath, stat: fs.statSync(filePath) }))
    .sort((left, right) => right.stat.mtimeMs - left.stat.mtimeMs);

  if (files.length === 0) {
    return null;
  }

  return JSON.parse(
    fs.readFileSync(files[0]!.filePath, "utf8"),
  ) as LocalPlanRecord;
};

const resolvePlanId = (args: ParsedCliArgs, configPath?: string): string => {
  const explicit = getFlag(args, "plan");
  if (explicit) {
    return explicit;
  }

  const latest = latestLocalPlan(configPath);
  if (!latest) {
    throw new Error(
      "no local autolaunch plan found; run `regents autolaunch prelaunch wizard` first",
    );
  }

  return latest.plan_id;
};

const requiredFlagMessage = (label: string, flag: string, placeholder = "<value>"): string =>
  `${label} is required. Pass --${flag} ${placeholder}.`;

const promptedRequiredFlag = async (
  args: ParsedCliArgs,
  prompts: PromptBoundary,
  flag: string,
  label: string,
  promptLabel: string,
  placeholder = "<value>",
): Promise<string> =>
  normalizeText(getFlag(args, flag)) ??
  await prompts.text(promptLabel, {
    unavailableMessage: requiredFlagMessage(label, flag, placeholder),
  });

const promptedOptionalFlag = async (
  args: ParsedCliArgs,
  prompts: PromptBoundary,
  flag: string,
  promptLabel: string,
  fallback?: string,
): Promise<string | undefined> => {
  const explicit = normalizeText(getFlag(args, flag));
  if (explicit) {
    return explicit;
  }

  if (!prompts.inputAllowed) {
    return fallback;
  }

  return normalizeText(
    await prompts.text(promptLabel, {
      allowEmpty: true,
      fallback,
      unavailableMessage: `Pass --${flag} <value>.`,
    }),
  );
};

const resolveWalletAddress = async (
  args: ParsedCliArgs,
  plan: Record<string, unknown>,
  configPath?: string,
): Promise<`0x${string}`> => {
  const explicit = normalizeText(getFlag(args, "wallet-address"));
  if (explicit) {
    return explicit as `0x${string}`;
  }

  const fallbackWallet = normalizeText(
    plan.fallback_operator_wallet as string | undefined,
  );
  if (fallbackWallet) {
    return fallbackWallet as `0x${string}`;
  }

  return (await configuredSigner(configPath)).address();
};

const readImageInput = async (
  args: ParsedCliArgs,
): Promise<{
  image_url?: string;
}> => {
  const imageUrl = normalizeText(getFlag(args, "image-url"));
  if (imageUrl) {
    return { image_url: imageUrl };
  }

  return {};
};

const uploadImageIfNeeded = async (
  args: ParsedCliArgs,
  configPath?: string,
): Promise<{ image_url?: string; image_asset_id?: string }> => {
  const image = await readImageInput(args);
  if (image.image_url) {
    const payload = await requestJson("POST", "/api/autolaunch/v1/agent/prelaunch/assets", {
      body: { source_url: image.image_url },
      requireAgentAuth: true,
    });

    const asset = payload.asset as Record<string, unknown> | undefined;
    return {
      image_url: String(asset?.public_url ?? image.image_url),
      image_asset_id:
        typeof asset?.asset_id === "string" ? asset.asset_id : undefined,
    };
  }

  return {};
};

const createOrUpdateRemotePlan = async (
  args: ParsedCliArgs,
  configPath?: string,
): Promise<Record<string, unknown>> => {
  const prompts = createPromptBoundary(args);
  const agentId = await promptedRequiredFlag(args, prompts, "agent", "Agent id", "Agent id", "<agent>");
  const tokenName = validatedLengthText(
    await promptedRequiredFlag(args, prompts, "name", "Token name", "Token name", "<name>"),
    "Token name",
    3,
    15,
  );
  const tokenSymbol = validatedLengthText(
    await promptedRequiredFlag(args, prompts, "symbol", "Token symbol", "Token symbol", "<symbol>"),
    "Token symbol",
    2,
    10,
  );
  const minimumRaiseQuote = validatedMinimumRaiseQuote(
    normalizeText(getFlag(args, "minimum-raise-quote")) ??
      (prompts.inputAllowed
        ? await prompts.text("Minimum $REGENT raise", {
            fallback: "0",
            unavailableMessage: "Pass --minimum-raise-quote <amount>.",
          })
        : "0"),
  );
  await confirmHighMinimumRaise(minimumRaiseQuote, prompts);
  if (!normalizeText(getFlag(args, "agent-safe-address"))) {
    printAgentSafeExplainer();
  }
  const agentSafe =
    normalizeText(getFlag(args, "agent-safe-address")) ??
    (prompts.inputAllowed
      ? normalizeText(
          await prompts.text("Agent Safe (leave blank if you still need to create it)", {
            allowEmpty: true,
            unavailableMessage:
              "Agent Safe is required. Pass --agent-safe-address <safe>.",
          }),
        )
      : undefined);
  const fallbackWallet = await promptedOptionalFlag(
    args,
    prompts,
    "fallback-operator-wallet",
    "Fallback operator wallet (optional)",
  );
  const launchNotes = await promptedOptionalFlag(args, prompts, "launch-notes", "Launch notes (optional)");
  const title = await promptedOptionalFlag(args, prompts, "title", "Hosted page title", tokenName);
  const subtitle = await promptedOptionalFlag(args, prompts, "subtitle", "Hosted page subtitle", "CCA launch draft");
  const description = await promptedOptionalFlag(args, prompts, "description", "Hosted page description");
  const websiteUrl = await promptedOptionalFlag(args, prompts, "website-url", "Website URL (optional)");

  const payload = {
    agent_id: requireArg(agentId, "agent"),
    token_name: tokenName,
    token_symbol: tokenSymbol,
    minimum_raise_quote: minimumRaiseQuote,
    agent_safe_address:
      agentSafe ||
      (() => {
        throw new Error(
          "Agent Safe is required. Run `regents autolaunch safe wizard` first, then rerun with --agent-safe-address <safe>.",
        );
      })(),
    fallback_operator_wallet: fallbackWallet,
    launch_notes: launchNotes,
    metadata_draft: {
      title,
      subtitle,
      description,
      website_url: websiteUrl,
    },
  };

  const planId = normalizeText(getFlag(args, "plan"));
  const response = planId
    ? await requestJson(
        "PATCH",
        `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(planId)}`,
        {
          body: payload,
          requireAgentAuth: true,
          configPath,
        },
      )
    : await requestJson("POST", "/api/autolaunch/v1/agent/prelaunch/plans", {
        body: payload,
        requireAgentAuth: true,
        configPath,
      });

  let plan = response.plan as Record<string, unknown>;
  const uploaded = await uploadImageIfNeeded(args, configPath);
  if (uploaded.image_url || uploaded.image_asset_id) {
    const metadataResponse = await requestJson(
      "POST",
      `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(String(plan.plan_id))}/metadata`,
      {
        body: {
          metadata: {
            ...(plan.metadata_draft as Record<string, unknown> | undefined),
            title,
            subtitle,
            description,
            website_url: websiteUrl,
            image_url: uploaded.image_url,
            image_asset_id: uploaded.image_asset_id,
          },
        },
        requireAgentAuth: true,
        configPath,
      },
    );

    plan = metadataResponse.plan as Record<string, unknown>;
  }

  saveLocalPlan(plan, configPath);
  return plan;
};

const requestSiwaLaunchBundle = async (
  walletAddress: `0x${string}`,
  configPath?: string,
) => {
  const { identity } = requireAgentAuthState(configPath, {
    audience: "autolaunch",
  });
  const config = loadConfig(configPath);
  const signer = await configuredSigner(configPath);
  const derivedAddress = await signer.address();
  if (derivedAddress.toLowerCase() !== walletAddress.toLowerCase()) {
    throw new Error(
      `wallet mismatch: config signer ${derivedAddress} does not match ${walletAddress}`,
    );
  }

  if (identity.walletAddress.toLowerCase() !== walletAddress.toLowerCase()) {
    throw new Error(
      `wallet mismatch: saved Regent identity ${identity.walletAddress} does not match ${walletAddress}`,
    );
  }

  if (!identity.registryAddress || !identity.tokenId) {
    throw new Error("This launch needs a bound Regent identity. Run `regents identity ensure` again.");
  }

  const siwaClient = new SiwaClient(config.services.siwa.baseUrl, config.services.siwa.requestTimeoutMs, config);
  const noncePayload = await siwaClient.requestNonce({
    wallet_address: walletAddress,
    chain_id: AUTOLAUNCH_CHAIN_ID,
    registry_address: identity.registryAddress,
    token_id: identity.tokenId,
    audience: "autolaunch",
  });
  const nonce = noncePayload.data.nonce;
  const issuedAt = new Date().toISOString();
  const message = SiwaClient.defaultMessageInput({
    config,
    walletAddress,
    chainId: AUTOLAUNCH_CHAIN_ID,
    registryAddress: identity.registryAddress,
    tokenId: identity.tokenId,
    nonce,
    issuedAt,
    statement: "Authorize an Autolaunch launch.",
  });
  const signature = await signer.signMessage(message);

  return {
    wallet_address: walletAddress,
    registry_address: identity.registryAddress,
    token_id: identity.tokenId,
    nonce,
    message,
    signature,
    issued_at: issuedAt,
  };
};

const watchJobOnce = async (
  jobId: string,
  configPath?: string,
): Promise<Record<string, unknown>> =>
  requestJson("GET", `/api/autolaunch/v1/agent/launch/jobs/${encodeURIComponent(jobId)}`, {
    requireAgentAuth: true,
    configPath,
  });

const renderWorkflowPanel = (title: string, lines: string[]): void => {
  if (!isHumanTerminal()) {
    return;
  }

  printText(
    renderPanel(title, lines, {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
  );
};

const startProfileConnectionForPlan = async (
  plan: Record<string, unknown>,
  configPath?: string,
): Promise<AgentConnectionSessionEnvelope> => {
  const planId = String(plan.plan_id ?? "");
  const identity = plan.identity_snapshot as Record<string, unknown> | undefined;
  const label =
    normalizeText(String(identity?.name ?? "")) ??
    normalizeText(String(plan.agent_name ?? "")) ??
    normalizeText(String(plan.token_name ?? "")) ??
    normalizeText(String(plan.agent_id ?? ""));

  return createAutolaunchAgentConnection(
    {
      plan_id: planId,
      ...(label ? { agent_label: label } : {}),
    },
    configPath,
  );
};

const credibilityOrder = [
  "agent_identity",
  "human_profile",
  "ens",
  "erc8004_ensip25",
  "world_agentbook",
  "x",
] as const;

const renderCredibilityPanel = (validation: Record<string, unknown> | undefined): void => {
  if (!isHumanTerminal()) {
    return;
  }

  const credibility = validation?.credibility as Record<string, unknown> | undefined;
  if (!credibility) {
    return;
  }

  const statusColor = (status: string): string => {
    if (status === "ready") {
      return CLI_PALETTE.emphasis;
    }

    if (status === "skipped") {
      return CLI_PALETTE.secondary;
    }

    return CLI_PALETTE.accent;
  };

  const lines = credibilityOrder.map((key) => {
    const item = credibility[key] as Record<string, unknown> | undefined;
    const label = String(item?.label ?? key);
    const status = String(item?.status ?? "missing");
    const message = String(item?.message ?? "");

    return `${tone(status.padEnd(12), statusColor(status), status === "ready")} ${tone(label, CLI_PALETTE.primary, true)} ${message}`;
  });

  const warnings = Array.isArray(credibility.warnings)
    ? credibility.warnings.map((warning) => String(warning))
    : [];

  printText(
    renderPanel(
      "◆ CREDIBILITY",
      warnings.length > 0
        ? [...lines, "", ...warnings.map((warning) => tone(warning, CLI_PALETTE.secondary))]
        : lines,
      {
        borderColor: warnings.length > 0 ? CLI_PALETTE.accent : CLI_PALETTE.emphasis,
        titleColor: CLI_PALETTE.title,
      },
    ),
  );
};

export async function runAutolaunchPrelaunchWizard(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  assertPrelaunchWizardFlags(args);
  printAlphaFundsWarning();
  const plan = await createOrUpdateRemotePlan(args, configPath);
  const connection = getBooleanFlag(args, "connect-profile")
    ? await startProfileConnectionForPlan(plan, configPath)
    : null;

  if (connection && !getBooleanFlag(args, "json") && isHumanTerminal()) {
    printText(renderConnectionStartReceipt(connection, configPath));
  }

  const validation = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(String(plan.plan_id))}/validate`,
    { body: {}, requireAgentAuth: true, configPath },
  );

  saveLocalPlan(validation.plan as Record<string, unknown>, configPath);

  renderWorkflowPanel("◆ AUTOLAUNCH PRELAUNCH", [
    tone("saved locally", CLI_PALETTE.secondary),
    `${tone("plan", CLI_PALETTE.accent, true)} ${String(plan.plan_id)}`,
    `${tone("agent", CLI_PALETTE.secondary)} ${String((plan.identity_snapshot as Record<string, unknown> | undefined)?.agent_id ?? plan.agent_id)}`,
    `${tone("launchable", CLI_PALETTE.secondary)} ${String((validation.validation as Record<string, unknown> | undefined)?.launchable ?? false)}`,
  ]);

  renderCredibilityPanel(validation.validation as Record<string, unknown> | undefined);
  printJson(validation);
}

export async function runAutolaunchPrelaunchGet(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const planId = resolvePlanId(args, configPath);
  const payload = await requestJson(
    "GET",
    `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(planId)}`,
    {
      requireAgentAuth: true,
      configPath,
    },
  );
  saveLocalPlan(payload.plan as Record<string, unknown>, configPath);
  printJson(payload);
}

export async function runAutolaunchPrelaunchValidate(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const planId = resolvePlanId(args, configPath);
  const payload = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(planId)}/validate`,
    { body: {}, requireAgentAuth: true, configPath },
  );
  saveLocalPlan(payload.plan as Record<string, unknown>, configPath);
  printJson(payload);
}

export async function runAutolaunchPrelaunchPublish(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const planId = resolvePlanId(args, configPath);
  const payload = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(planId)}/publish`,
    { body: {}, requireAgentAuth: true, configPath },
  );
  saveLocalPlan(payload.plan as Record<string, unknown>, configPath);
  printJson(payload);
}

export async function runAutolaunchLaunchRun(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const planId = resolvePlanId(args, configPath);
  const planPayload = await requestJson(
    "GET",
    `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(planId)}`,
    { requireAgentAuth: true, configPath },
  );
  const plan = planPayload.plan as Record<string, unknown>;
  const validationPayload = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(planId)}/validate`,
    { body: {}, requireAgentAuth: true, configPath },
  );

  const validation = validationPayload.validation as
    | Record<string, unknown>
    | undefined;
  if (!validation?.launchable) {
    saveLocalPlan(
      validationPayload.plan as Record<string, unknown>,
      configPath,
    );
    printJson(validationPayload);
    return;
  }

  const walletAddress = await resolveWalletAddress(args, plan, configPath);
  const siwaBundle = await requestSiwaLaunchBundle(walletAddress, configPath);

  const payload = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/prelaunch/plans/${encodeURIComponent(planId)}/launch`,
    { body: siwaBundle, requireAgentAuth: true, configPath },
  );

  saveLocalPlan(payload.plan as Record<string, unknown>, configPath);

  const jobId = String(
    (payload.launch as Record<string, unknown>).job_id ?? "",
  );
  if (!jobId) {
    printJson(payload);
    return;
  }

  let current = await watchJobOnce(jobId, configPath);
  printJson(current);

  const shouldWatch = isHumanTerminal() || getBooleanFlag(args, "watch");
  if (!shouldWatch) {
    return;
  }

  const intervalSeconds = parsePollingIntervalSeconds(args);
  for (;;) {
    const job = current.job as Record<string, unknown> | undefined;
    const status = typeof job?.status === "string" ? job.status : "";
    if (["ready", "failed", "blocked"].includes(status)) {
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, intervalSeconds * 1000));
    current = await watchJobOnce(jobId, configPath);
    printJson(current);
  }
}

export async function runAutolaunchLaunchMonitor(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const jobId = requireArg(getFlag(args, "job"), "job");
  const watch = getBooleanFlag(args, "watch");
  const intervalSeconds = parsePollingIntervalSeconds(args);

  for (;;) {
    const payload = await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/lifecycle/jobs/${encodeURIComponent(jobId)}`,
      {
        requireAgentAuth: true,
        configPath,
      },
    );
    printJson(payload);

    if (!watch) {
      return;
    }

    const recommended = String(payload.recommended_action ?? "wait");
    if (recommended !== "wait") {
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, intervalSeconds * 1000));
  }
}

export async function runAutolaunchLaunchFinalize(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const jobId = requireArg(getFlag(args, "job"), "job");
  const prepared = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/lifecycle/jobs/${encodeURIComponent(jobId)}/finalize/prepare`,
    { body: {}, requireAgentAuth: true, configPath },
  );

  if (!getBooleanFlag(args, "submit")) {
    printJson(prepared);
    return;
  }

  const preparedAction = prepared.prepared as Record<string, unknown> | undefined;
  const txRequest = txRequestFromWalletAction(preparedAction?.wallet_action);
  if (!txRequest) {
    printJson(prepared);
    return;
  }

  const txHash = await submitPreparedTxRequest(txRequest, configPath);

  const registered = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/lifecycle/jobs/${encodeURIComponent(jobId)}/finalize/register`,
    { body: { tx_hash: txHash }, requireAgentAuth: true, configPath },
  );

  printJson(registered);
}

export async function runAutolaunchVestingStatus(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const jobId = requireArg(getFlag(args, "job"), "job");
  printJson(
    await requestJson(
      "GET",
      `/api/autolaunch/v1/agent/lifecycle/jobs/${encodeURIComponent(jobId)}/vesting`,
      {
        requireAgentAuth: true,
        configPath,
      },
    ),
  );
}

export async function runAutolaunchVestingRelease(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const jobId = requireArg(getFlag(args, "job"), "job");

  if (!getBooleanFlag(args, "submit")) {
    printJson(
      await requestJson(
        "POST",
        `/api/autolaunch/v1/agent/contracts/jobs/${encodeURIComponent(jobId)}/vesting/release/prepare`,
        { body: {}, requireAgentAuth: true, configPath },
      ),
    );
    return;
  }

  const prepared = await requestJson(
    "POST",
    `/api/autolaunch/v1/agent/contracts/jobs/${encodeURIComponent(jobId)}/vesting/release/prepare`,
    { body: {}, requireAgentAuth: true, configPath },
  );
  const preparedAction = prepared.prepared as Record<string, unknown> | undefined;
  const txRequest = txRequestFromWalletAction(preparedAction?.wallet_action);

  if (!txRequest) {
    printJson(prepared);
    return;
  }

  const txHash = await submitPreparedTxRequest(txRequest, configPath);

  printJson({ ok: true, tx_hash: txHash, mode: "submitted" });
}
