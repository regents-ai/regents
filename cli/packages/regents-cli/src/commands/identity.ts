import type { IdentityEnsureFailure, IdentityStatusResponse, RegentIdentityNetwork } from "../internal-types/index.js";

import { coinbaseStatus, ensureIdentity, IdentityServiceClient, loadConfig } from "../internal-runtime/index.js";
import { CommandExitError } from "../internal-runtime/errors.js";
import { exitCodeForError } from "../exit-codes.js";
import { readIdentityReceipt } from "../internal-runtime/identity/cache.js";
import { getBooleanFlag, getFlag, parseIntegerFlag, type ParsedCliArgs } from "../parse.js";
import { CLI_PALETTE, printError, printJson, printText, renderKeyValuePanel, renderPanel, renderTablePanel, tone } from "../printer.js";

const parseNetwork = (value: string | undefined): RegentIdentityNetwork => {
  if (!value || value === "base") {
    return "base";
  }
  if (value === "base-sepolia") {
    return "base-sepolia";
  }
  throw new CommandExitError("UNSUPPORTED_NETWORK", `Unsupported network: ${value}`);
};

const failurePayload = (error: CommandExitError): IdentityEnsureFailure => ({
  status: "error",
  code: error.code as IdentityEnsureFailure["code"],
  message: error.message,
  details: (error.details as Record<string, unknown> | undefined) ?? undefined,
});

const renderHumanSuccess = (result: Awaited<ReturnType<typeof ensureIdentity>>): string =>
  [
    renderKeyValuePanel("◆ IDENTITY READY", [
      { label: "provider", value: result.provider, valueColor: CLI_PALETTE.primary },
      { label: "network", value: result.network, valueColor: CLI_PALETTE.primary },
      { label: "address", value: result.address, valueColor: CLI_PALETTE.primary },
      { label: "agent id", value: String(result.agent_id), valueColor: CLI_PALETTE.emphasis },
      { label: "verified until", value: result.receipt_expires_at, valueColor: CLI_PALETTE.primary },
      { label: "cache", value: result.cache_path, valueColor: CLI_PALETTE.primary },
    ], {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
    renderPanel("◆ NEXT STEP", [
      `${tone("regents auth login --audience platform", CLI_PALETTE.emphasis, true)} to save a Platform sign-in.`,
      `${tone("regents run", CLI_PALETTE.emphasis, true)} to start the local runtime.`,
    ], {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
  ].join("\n\n");

const renderHumanStatus = (result: {
  ok: boolean;
  provider: "coinbase-cdp";
  network: RegentIdentityNetwork;
  wallet_ready: boolean;
  identity_ready: boolean;
  address?: `0x${string}`;
  next_action?: { command: string; reason?: string };
}): string =>
  [
    renderKeyValuePanel("◆ COINBASE IDENTITY", [
      { label: "status", value: result.ok ? "ready" : "not ready", valueColor: result.ok ? CLI_PALETTE.emphasis : CLI_PALETTE.error },
      { label: "network", value: result.network, valueColor: CLI_PALETTE.primary },
      { label: "wallet", value: result.wallet_ready ? "ready" : "missing", valueColor: result.wallet_ready ? CLI_PALETTE.emphasis : CLI_PALETTE.error },
      { label: "identity", value: result.identity_ready ? "ready" : "missing", valueColor: result.identity_ready ? CLI_PALETTE.emphasis : CLI_PALETTE.error },
      ...(result.address ? [{ label: "address", value: result.address, valueColor: CLI_PALETTE.primary }] : []),
    ], {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
    ...(result.next_action
      ? [
          renderPanel("◆ NEXT STEP", [
            ...(result.next_action.reason ? [`${tone("why", CLI_PALETTE.secondary)} ${tone(result.next_action.reason, CLI_PALETTE.primary)}`] : []),
            `Run ${tone(result.next_action.command, CLI_PALETTE.emphasis, true)} to refresh the Regent identity once the wallet is ready.`,
          ], {
            borderColor: CLI_PALETTE.chrome,
            titleColor: CLI_PALETTE.title,
          }),
        ]
      : []),
  ].join("\n\n");

export async function runIdentityStatus(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<number> {
  const json = getBooleanFlag(args, "json");

  try {
    const timeoutSeconds = parseIntegerFlag(args, "timeout") ?? 120;
    const network = parseNetwork(getFlag(args, "network"));
    const walletHint = getFlag(args, "wallet");
    const config = loadConfig(configPath);
    const wallet = await coinbaseStatus(config, {
      walletHint,
      network,
      timeoutMs: timeoutSeconds * 1000,
    });

    const cachedReceipt = readIdentityReceipt();

    if (!wallet.account) {
      const payload = {
        ok: false,
        provider: "coinbase-cdp" as const,
        network,
        wallet_ready: false,
        identity_ready: wallet.identity_ready,
        wallet,
        ...(wallet.next_action ? { next_action: wallet.next_action } : {}),
      };
      if (json) {
        printJson(payload);
      } else {
        printText(renderHumanStatus(payload));
      }
      return 1;
    }

    if (wallet.identity_ready) {
      const payload = {
        ok: true,
        provider: "coinbase-cdp" as const,
        network,
        wallet_ready: true,
        identity_ready: true,
        address: wallet.account.address,
        wallet,
        ...(cachedReceipt &&
        cachedReceipt.provider === "coinbase-cdp" &&
        cachedReceipt.network === network &&
        cachedReceipt.address === wallet.account.address
          ? {
              identity: {
                network: cachedReceipt.network,
                address: cachedReceipt.address,
                provider: cachedReceipt.provider,
                registered: true,
                verified: cachedReceipt.verified,
                agent_id: cachedReceipt.agent_id,
                token_id: cachedReceipt.token_id,
                agent_registry: cachedReceipt.agent_registry,
                receipt_expires_at: cachedReceipt.receipt_expires_at,
              },
            }
          : {}),
      };
      if (json) {
        printJson(payload);
      } else {
        printText(renderHumanStatus(payload));
      }
      return 0;
    }

    const client = new IdentityServiceClient(config.services.siwa.baseUrl, timeoutSeconds * 1000, config);
    const remoteStatus: IdentityStatusResponse = await client.status({
      network,
      address: wallet.account.address,
      provider: "coinbase-cdp",
      ...(walletHint ? { wallet_hint: walletHint } : {}),
    });

    const identityReady =
      remoteStatus.data.verified === "onchain" && Boolean(remoteStatus.data.receipt_expires_at ?? wallet.receipt_expires_at);
    const payload = {
      ok: wallet.ok && identityReady,
      provider: "coinbase-cdp" as const,
      network,
      wallet_ready: true,
      identity_ready: identityReady,
      address: wallet.account.address,
      wallet,
      identity: remoteStatus.data,
      ...(identityReady
        ? {}
        : {
            next_action: {
              reason: "The wallet is ready, but the Regent identity still needs to be refreshed.",
              command: "regents identity ensure",
            },
          }),
    };

    if (json) {
      printJson(payload);
    } else {
      printText(renderHumanStatus(payload));
    }
    return payload.ok ? 0 : 1;
  } catch (error) {
    const failure =
      error instanceof CommandExitError
        ? error
        : new CommandExitError(
            "SERVICE_UNAVAILABLE",
            error instanceof Error ? error.message : "Coinbase identity status failed.",
          );

    if (json) {
      printJson(failurePayload(failure));
    } else {
      printError(failure);
    }
    return exitCodeForError(failure);
  }
}

export async function runIdentityEnsure(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<number> {
  const json = getBooleanFlag(args, "json");

  try {
    const timeoutSeconds = parseIntegerFlag(args, "timeout") ?? 120;
    const result = await ensureIdentity({
      network: parseNetwork(getFlag(args, "network")),
      forceRefresh: getBooleanFlag(args, "force-refresh"),
      walletHint: getFlag(args, "wallet"),
      timeoutSeconds,
      config: loadConfig(configPath),
    });

    if (json) {
      printJson({
        ...result,
        next_steps: [
          "regents auth login --audience platform",
          "regents run",
        ],
      });
    } else {
      printText(renderHumanSuccess(result));
    }
    return 0;
  } catch (error) {
    const failure =
      error instanceof CommandExitError
        ? error
        : new CommandExitError(
            "SERVICE_UNAVAILABLE",
            error instanceof Error ? error.message : "Regent identity setup failed.",
          );

    if (json) {
      printJson(failurePayload(failure));
    } else {
      printError(failure);
    }
    return exitCodeForError(failure);
  }
}
