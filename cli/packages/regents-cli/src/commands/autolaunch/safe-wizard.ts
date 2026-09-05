import type { ParsedCliArgs } from "../../parse.js";
import { printJson } from "../../printer.js";
import { printAlphaFundsWarning } from "./alpha-warning.js";
import { printAgentSafeExplainer } from "./safe-explainer.js";
import {
  WEBSITE_WALLET_ENV,
  type SafeWizardSigner,
  resolveAgentSigner,
  resolveBackupSigner,
  resolveSafeAddress,
  resolveWebsiteSigner,
} from "./safe-shared.js";

type SafeWizardStatus =
  | "waiting_for_website_wallet"
  | "ready_to_create_safe"
  | "ready_for_launch";

interface SafeWizardResult {
  readonly ok: true;
  readonly status: SafeWizardStatus;
  readonly launch_ready: boolean;
  readonly threshold: "2-of-3";
  readonly agent_safe_address: string | null;
  readonly signers: {
    readonly agent: SafeWizardSigner;
    readonly website: SafeWizardSigner;
    readonly backup: SafeWizardSigner;
  };
  readonly next_steps: readonly string[];
  readonly post_launch_safe_batch: readonly string[];
}

const postLaunchSafeBatch = (): readonly string[] => [
  "Have the Safe accept ownership of the revenue splitter.",
  "Have the Safe accept ownership of the fee registry.",
  "Have the Safe accept ownership of the fee vault.",
  "Have the Safe accept ownership of the hook.",
];

const buildResult = (
  signers: SafeWizardResult["signers"],
  agentSafeAddress: string | null,
): SafeWizardResult => {
  if (!signers.website.address) {
    return {
      ok: true,
      status: "waiting_for_website_wallet",
      launch_ready: false,
      threshold: "2-of-3",
      agent_safe_address: agentSafeAddress,
      signers,
      next_steps: [
        "Open the website and finish the Privy login so the website wallet exists.",
        `Come back with --website-wallet-address <wallet> or set ${WEBSITE_WALLET_ENV}.`,
        "Create the Safe only after the website wallet is known.",
      ],
      post_launch_safe_batch: postLaunchSafeBatch(),
    };
  }

  if (!agentSafeAddress) {
    return {
      ok: true,
      status: "ready_to_create_safe",
      launch_ready: false,
      threshold: "2-of-3",
      agent_safe_address: null,
      signers,
      next_steps: [
        "Create one Safe with these three signer wallets and a 2-of-3 threshold.",
        "Use `regents autolaunch safe create` to deploy that Safe on Base.",
        "Once the Safe exists, rerun this wizard with --agent-safe-address <safe> or pass that Safe into the launch wizard.",
      ],
      post_launch_safe_batch: postLaunchSafeBatch(),
    };
  }

  return {
    ok: true,
    status: "ready_for_launch",
    launch_ready: true,
    threshold: "2-of-3",
    agent_safe_address: agentSafeAddress,
    signers,
    next_steps: [
      "Use this Safe as the Agent Safe in the Autolaunch prelaunch wizard.",
      "After the launch is deployed, have the Safe submit one batch with the four ownership acceptances.",
    ],
    post_launch_safe_batch: postLaunchSafeBatch(),
  };
};

export async function runAutolaunchSafeWizard(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printAlphaFundsWarning();
  printAgentSafeExplainer();
  const agent = await resolveAgentSigner(configPath);
  const website = await resolveWebsiteSigner(args);
  const backup = await resolveBackupSigner(args);
  const agentSafeAddress = await resolveSafeAddress(args);

  printJson(
    buildResult(
      {
        agent,
        website,
        backup,
      },
      agentSafeAddress,
    ),
  );
}
