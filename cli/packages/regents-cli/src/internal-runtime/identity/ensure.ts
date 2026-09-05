import type {
  IdentityEnsureSuccess,
  RegentConfig,
  RegentIdentityNetwork,
  RegentIdentityReceipt,
} from "../../internal-types/index.js";

import { CommandExitError } from "../errors.js";
import { identityCachePath, normalizeRegentBaseUrl } from "./shared.js";
import { IdentityServiceClient } from "./service.js";
import { readIdentityReceipt, receiptMatchesRequest, writeIdentityReceipt } from "./cache.js";
import { resolveIdentitySigner } from "./providers.js";

export interface EnsureIdentityOptions {
  network: RegentIdentityNetwork;
  forceRefresh: boolean;
  walletHint?: string;
  timeoutSeconds: number;
  config: RegentConfig;
}

export const ensureIdentity = async (options: EnsureIdentityOptions): Promise<IdentityEnsureSuccess> => {
  const requestTimeoutMs = Math.max(1, options.timeoutSeconds) * 1000;
  const regentBaseUrl = normalizeRegentBaseUrl(options.config.services.siwa.baseUrl);
  const signer = await resolveIdentitySigner({
    provider: "coinbase-cdp",
    network: options.network,
    walletHint: options.walletHint,
    config: options.config,
    timeoutMs: requestTimeoutMs,
  });

  const cachedReceipt = readIdentityReceipt();
  if (
    cachedReceipt &&
    !options.forceRefresh &&
    receiptMatchesRequest({
      receipt: cachedReceipt,
      network: options.network,
      regentBaseUrl,
      walletHint: signer.address,
    })
  ) {
    return successFromReceipt(cachedReceipt, identityCachePath());
  }
  const client = new IdentityServiceClient(regentBaseUrl, requestTimeoutMs, options.config);

  const status = await client.status({
    network: options.network,
    address: signer.address,
    provider: signer.provider,
    ...(signer.walletHint ? { wallet_hint: signer.walletHint } : {}),
  });

  let agentId = status.data.agent_id;
  let tokenId = status.data.token_id;
  let agentRegistry = status.data.agent_registry;

  if (!status.data.registered || status.data.verified === "unregistered" || !agentId || !tokenId || !agentRegistry) {
    const registrationIntent = await client.registrationIntent({
      network: options.network,
      address: signer.address,
      provider: signer.provider,
      ...(signer.walletHint ? { wallet_hint: signer.walletHint } : {}),
    });

    let registrationSignature: `0x${string}`;
    try {
      registrationSignature = await signer.signMessage(registrationIntent.data.signing_payload.message);
    } catch (error) {
      throw new CommandExitError(
        "REGISTRATION_FAILED",
        "Regent could not complete ERC-8004 registration on Base for this signer. No SIWA session was created.", { cause: error },
      );
    }

    const completion = await client.registrationCompletion({
      intent_id: registrationIntent.data.intent_id,
      address: signer.address,
      message: registrationIntent.data.signing_payload.message,
      signature: registrationSignature,
    });
    agentId = completion.data.agent_id;
    tokenId = completion.data.token_id;
    agentRegistry = completion.data.agent_registry;
  }

  if (!agentId || !tokenId || !agentRegistry) {
    throw new CommandExitError(
      "REGISTRATION_FAILED",
      "Regent could not complete ERC-8004 registration on Base for this signer. No SIWA session was created.",
    );
  }

  const nonce = await client.siwaNonce({
    network: options.network,
    address: signer.address,
    token_id: tokenId,
    agent_registry: agentRegistry,
  });

  let siwaSignature: `0x${string}`;
  try {
    siwaSignature = await signer.signMessage(nonce.data.message);
  } catch (error) {
    throw new CommandExitError(
      "SIWA_VERIFY_FAILED",
      "ERC-8004 registration exists, but SIWA verification failed.", { cause: error },
    );
  }

  const verified = await client.siwaVerify({
    network: options.network,
    address: signer.address,
    token_id: tokenId,
    agent_registry: agentRegistry,
    message: nonce.data.message,
    signature: siwaSignature,
    nonce_token: nonce.data.nonce_token,
  });

  const cachedAt = new Date().toISOString();
  const receipt: RegentIdentityReceipt = {
    version: 1,
    regent_base_url: regentBaseUrl,
    network: options.network,
    provider: signer.provider,
    address: signer.address,
    agent_id: verified.data.agent_id,
    token_id: verified.data.token_id,
    agent_registry: verified.data.agent_registry,
    signer_type: verified.data.signer_type,
    verified: verified.data.verified,
    receipt: verified.data.receipt,
    receipt_issued_at: verified.data.receipt_issued_at,
    receipt_expires_at: verified.data.receipt_expires_at,
    cached_at: cachedAt,
    ...(signer.walletHint ? { wallet_hint: signer.walletHint } : {}),
  };

  const cachePath = writeIdentityReceipt(receipt);
  return successFromReceipt(receipt, cachePath);
};

const successFromReceipt = (
  receipt: RegentIdentityReceipt,
  cachePath: string,
): IdentityEnsureSuccess => ({
  status: "ok",
  provider: receipt.provider,
  network: receipt.network,
  address: receipt.address,
  agent_id: receipt.agent_id,
  token_id: receipt.token_id,
  agent_registry: receipt.agent_registry,
  verified: receipt.verified,
  receipt_expires_at: receipt.receipt_expires_at,
  cache_path: cachePath,
});
