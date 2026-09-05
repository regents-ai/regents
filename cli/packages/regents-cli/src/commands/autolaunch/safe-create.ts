import { randomBytes } from "node:crypto";

import { privateKeyToAccount } from "viem/accounts";

import { sendValidatedTransaction } from "../../internal-runtime/base-contract-client.js";
import { loadConfig } from "../../internal-runtime/config.js";
import { resolveRawPrivateKeyForExternalSdk } from "../../internal-runtime/agent/wallet-keystore.js";
import type { ParsedCliArgs } from "../../parse.js";
import { getFlag } from "../../parse.js";
import { printJson } from "../../printer.js";
import {
  normalizeText,
  resolveAgentSigner,
  resolveBackupSigner,
  resolveWebsiteSigner,
} from "./safe-shared.js";
import { printAgentSafeExplainer } from "./safe-explainer.js";

const BASE_MAINNET_RPC_ENV = "BASE_MAINNET_RPC_URL";

interface PredictedSafeKit {
  getAddress(): Promise<string>;
  isSafeDeployed(): Promise<boolean>;
  createSafeDeploymentTransaction(): Promise<{
    to: string;
    data: string;
    value: string;
  }>;
  getContractVersion(): unknown;
}

const requireBaseMainnetRpcUrl = (args: ParsedCliArgs): string => {
  const explicit = normalizeText(getFlag(args, "rpc-url"));
  const envValue = normalizeText(process.env[BASE_MAINNET_RPC_ENV]);
  const resolved = explicit ?? envValue;
  if (!resolved) {
    throw new Error(
      `Base mainnet RPC URL is required. Pass --rpc-url <url> or set ${BASE_MAINNET_RPC_ENV}.`,
    );
  }

  return resolved;
};

const resolveSaltNonce = (args: ParsedCliArgs): string => {
  const explicit = normalizeText(getFlag(args, "salt-nonce"));
  if (explicit) {
    if (!/^\d+$/u.test(explicit)) {
      throw new Error("salt-nonce must be an unsigned integer string");
    }

    return explicit;
  }

  return BigInt(`0x${randomBytes(16).toString("hex")}`).toString(10);
};

const nextSteps = (safeAddress: string): readonly string[] => [
  `Use ${safeAddress} as the Agent Safe in the Autolaunch launch flow.`,
  "After the launch is deployed, have the Safe submit one batch with the four ownership acceptances.",
];

export async function runAutolaunchSafeCreate(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  printAgentSafeExplainer();
  const agentSigner = await resolveAgentSigner(configPath);
  const websiteSigner = await resolveWebsiteSigner(args);
  const backupSigner = await resolveBackupSigner(args);

  if (!websiteSigner.address) {
    throw new Error(
      "Website wallet is not ready yet. Finish the website login first, then rerun with --website-wallet-address <wallet> or set AUTOLAUNCH_WALLET_ADDRESS.",
    );
  }

  const owners = [
    agentSigner.address,
    websiteSigner.address,
    backupSigner.address,
  ].filter((value): value is string => Boolean(value));

  const uniqueOwners = Array.from(new Set(owners.map((owner) => owner.toLowerCase())));
  if (uniqueOwners.length !== 3) {
    throw new Error("Safe owners must be three distinct wallet addresses.");
  }

  const rpcUrl = requireBaseMainnetRpcUrl(args);
  // Safe protocol-kit requires the raw private key string; it cannot take a
  // viem account or a signMessage callback (see resolveRawPrivateKeyForExternalSdk).
  const config = loadConfig(configPath);
  const privateKey = await resolveRawPrivateKeyForExternalSdk({
    privateKeyEnv: config.wallet.privateKeyEnv,
    keystorePath: config.wallet.keystorePath,
  });
  const account = privateKeyToAccount(privateKey);
  const saltNonce = resolveSaltNonce(args);
  const protocolKitModule = await import("@safe-global/protocol-kit");
  const SafeSdk = protocolKitModule.default as unknown as {
    init(config: unknown): Promise<PredictedSafeKit>;
  };
  const protocolKit = await SafeSdk.init({
    provider: rpcUrl,
    signer: privateKey,
    predictedSafe: {
      safeAccountConfig: {
        owners: uniqueOwners,
        threshold: 2,
      },
      safeDeploymentConfig: {
        saltNonce,
      },
    },
  });

  const safeAddress = (await protocolKit.getAddress()).toLowerCase();
  const alreadyDeployed = await protocolKit.isSafeDeployed();
  if (alreadyDeployed) {
    printJson({
      ok: true,
      status: "already_deployed",
      network: "base-mainnet",
      chain_id: 8453,
      threshold: "2-of-3",
      signer_wallet_address: account.address.toLowerCase(),
      owners: uniqueOwners,
      salt_nonce: saltNonce,
      safe_address: safeAddress,
      deployment_tx_hash: null,
      next_steps: nextSteps(safeAddress),
    });
    return;
  }

  const deploymentTx = await protocolKit.createSafeDeploymentTransaction();
  const { txHash, receipt } = await sendValidatedTransaction(account, {
    chain_id: 8453,
    to: deploymentTx.to as `0x${string}`,
    data: deploymentTx.data as `0x${string}`,
    value: deploymentTx.value,
    expected_signer: account.address,
    expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
  }, rpcUrl);

  const deployedSafeAddress = protocolKitModule.getSafeAddressFromDeploymentTx(
    receipt,
    protocolKit.getContractVersion() as never,
  ).toLowerCase();

  printJson({
    ok: true,
    status: "created",
    network: "base-mainnet",
    chain_id: 8453,
    threshold: "2-of-3",
    signer_wallet_address: account.address.toLowerCase(),
    owners: uniqueOwners,
    salt_nonce: saltNonce,
    safe_address: deployedSafeAddress,
    deployment_tx_hash: txHash,
    next_steps: nextSteps(deployedSafeAddress),
  });
}
