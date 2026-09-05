import type {
  RegentConfig,
  RegentIdentityNetwork,
  RegentIdentityProvider,
  RegentIdentityReceipt,
  RegentResolvedIdentityProvider,
} from "../../internal-types/index.js";

import { coinbaseProviderName, signMessageWithCoinbase } from "../coinbase.js";
import { CommandExitError } from "../errors.js";

export interface IdentitySigner {
  provider: RegentResolvedIdentityProvider;
  address: `0x${string}`;
  walletHint?: string;
  signerType: string;
  signMessage(message: string): Promise<`0x${string}`>;
}

interface ProviderResolutionOptions {
  provider: RegentIdentityProvider;
  network: RegentIdentityNetwork;
  walletHint?: string;
  config?: RegentConfig;
  timeoutMs: number;
  expectedAddress?: `0x${string}`;
}

export const resolveIdentitySigner = async (options: ProviderResolutionOptions): Promise<IdentitySigner> => {
  if (!options.config) {
    throw new CommandExitError("COINBASE_CDP_MISSING", "Regents CLI config is required for Coinbase identity.");
  }

  const probe = await signMessageWithCoinbase(options.config, {
    message: "__regents_identity_probe__",
    walletHint: options.walletHint,
    timeoutMs: options.timeoutMs,
    expectedAddress: options.expectedAddress,
  });

  return {
    provider: coinbaseProviderName(),
    address: probe.address,
    walletHint: probe.walletHint,
    signerType: "evm_personal_sign",
    signMessage: async (message) => {
      const result = await signMessageWithCoinbase(options.config as RegentConfig, {
        message,
        walletHint: options.walletHint,
        timeoutMs: options.timeoutMs,
        expectedAddress: options.expectedAddress,
      });
      return result.signature;
    },
  };
};

export const resolveSignerFromReceipt = async (
  receipt: RegentIdentityReceipt,
  input: { config?: RegentConfig; timeoutMs: number; walletSecretSource?: unknown },
): Promise<IdentitySigner> => {
  return resolveIdentitySigner({
    provider: receipt.provider,
    network: receipt.network,
    walletHint: receipt.wallet_hint,
    config: input.config,
    timeoutMs: input.timeoutMs,
    expectedAddress: receipt.address,
  });
};
