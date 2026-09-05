import { loadConfig } from "../../internal-runtime/config.js";
import type { SignerBackend } from "../../internal-runtime/agent/signer-backend.js";
import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../../parse.js";
import { createPromptBoundary } from "../../terminal/prompts.js";
import { configuredSigner as readConfiguredSigner } from "./shared.js";

export const WEBSITE_WALLET_ENV = "AUTOLAUNCH_WALLET_ADDRESS";

export type AddressSource = "config" | "flag" | "env" | "prompt" | "missing";

export interface SafeWizardSigner {
  readonly address: string | null;
  readonly source: AddressSource;
}

export const normalizeText = (value: string | undefined): string | undefined => {
  if (!value) {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
};

export const normalizeAddress = (value: string): string => value.trim().toLowerCase();

export const isAddress = (value: string): boolean =>
  /^0x[0-9a-fA-F]{40}$/u.test(value.trim());

export const requireAddress = (value: string, label: string): string => {
  if (!isAddress(value)) {
    throw new Error(`${label} must be a valid EVM address`);
  }

  return normalizeAddress(value);
};

export const configuredSigner = async (configPath?: string): Promise<SignerBackend> => {
  try {
    const signer = await readConfiguredSigner(configPath);
    // Resolve eagerly so a missing key surfaces here with the friendly message.
    await signer.address();
    return signer;
  } catch {
    const config = loadConfig(configPath);
    throw new Error(
      `Agent signer wallet is not ready. Set ${config.wallet.privateKeyEnv} or initialize the local wallet first.`,
    );
  }
};

export const resolveAgentSigner = async (
  configPath?: string,
): Promise<SafeWizardSigner> => {
  const address = await (await configuredSigner(configPath)).address();
  return { address, source: "config" };
};

export const resolveWebsiteSigner = async (
  args: ParsedCliArgs,
): Promise<SafeWizardSigner> => {
  const explicit = normalizeText(getFlag(args, "website-wallet-address"));
  if (explicit) {
    return {
      address: requireAddress(explicit, "Website wallet"),
      source: "flag",
    };
  }

  const fromEnv = normalizeText(process.env[WEBSITE_WALLET_ENV]);
  if (fromEnv) {
    return {
      address: requireAddress(fromEnv, "Website wallet"),
      source: "env",
    };
  }

  if (getBooleanFlag(args, "wait-for-website-wallet")) {
    return { address: null, source: "missing" };
  }

  const prompts = createPromptBoundary(args);
  if (!prompts.inputAllowed) {
    throw new Error(
      "Website wallet is required. Pass --website-wallet-address <wallet> or --wait-for-website-wallet.",
    );
  }

  const choice = await prompts.choice(
    "The website wallet is not ready yet.",
    [
      "Wait until the website login creates it",
      "Enter the website wallet address now",
    ],
    {
      unavailableMessage:
        "Website wallet is required. Pass --website-wallet-address <wallet> or --wait-for-website-wallet.",
    },
  );

  if (choice === 0) {
    return { address: null, source: "missing" };
  }

  const entered = await prompts.text("Website wallet address", {
    unavailableMessage: "Website wallet is required. Pass --website-wallet-address <wallet>.",
  });
  return {
    address: requireAddress(entered, "Website wallet"),
    source: "prompt",
  };
};

export const resolveBackupSigner = async (
  args: ParsedCliArgs,
): Promise<SafeWizardSigner> => {
  const explicit = normalizeText(getFlag(args, "backup-signer-address"));
  if (explicit) {
    return {
      address: requireAddress(explicit, "Backup signer"),
      source: "flag",
    };
  }

  const prompts = createPromptBoundary(args);
  if (!prompts.inputAllowed) {
    throw new Error(
      "Backup signer is required. Pass --backup-signer-address <wallet>.",
    );
  }

  const entered = await prompts.text("Backup signer address", {
    unavailableMessage: "Backup signer is required. Pass --backup-signer-address <wallet>.",
  });
  return {
    address: requireAddress(entered, "Backup signer"),
    source: "prompt",
  };
};

export const resolveSafeAddress = async (
  args: ParsedCliArgs,
): Promise<string | null> => {
  const explicit = normalizeText(getFlag(args, "agent-safe-address"));
  if (explicit) {
    return requireAddress(explicit, "Agent Safe");
  }

  const prompts = createPromptBoundary(args);
  if (!prompts.inputAllowed) {
    return null;
  }

  const entered = await prompts.text(
    "Agent Safe address (leave blank if you still need to create it)",
    {
      allowEmpty: true,
      unavailableMessage: "Agent Safe is required. Pass --agent-safe-address <safe>.",
    },
  );
  if (!entered) {
    return null;
  }

  return requireAddress(entered, "Agent Safe");
};
