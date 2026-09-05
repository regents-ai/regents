import type { ParsedCliArgs } from "../parse.js";

import { coinbaseStatus, loadConfig, setupCoinbaseWallet } from "../internal-runtime/index.js";
import { CommandExitError, RegentError } from "../internal-runtime/errors.js";
import { exitCodeForError } from "../exit-codes.js";
import { getBooleanFlag, getFlag } from "../parse.js";
import { printJson, printText } from "../printer.js";
import { writeEncryptedKeystore } from "../internal-runtime/agent/wallet-keystore.js";
import { deriveWalletAddress } from "../internal-runtime/agent/wallet.js";

const PRIVATE_KEY_REGEX = /^0x[0-9a-fA-F]{64}$/;

const readPrivateKeyFromStdin = async (): Promise<string> => {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks).toString("utf8").trim();
};

const renderWalletStatus = (status: Awaited<ReturnType<typeof coinbaseStatus>>): string => {
  if (status.ok && status.account) {
    return [
      "Coinbase wallet ready.",
      `wallet: ${status.account.name}`,
      `address: ${status.account.address}`,
      `identity_ready: ${status.identity_ready ? "yes" : "no"}`,
      `next: ${status.identity_ready ? "regents identity status" : "regents identity ensure"}`,
    ].join("\n");
  }

  return [
    "Coinbase wallet is not ready.",
    ...(status.next_action ? [`next: ${status.next_action.command}`] : []),
  ].join("\n");
};

const failurePayload = (error: CommandExitError) => ({
  ok: false,
  provider: "coinbase-cdp",
  code: error.code,
  message: error.message,
  details: (error.details as Record<string, unknown> | undefined) ?? undefined,
});

export async function runWalletImport(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<number> {
  const json = getBooleanFlag(args, "json");

  try {
    // Refuse when the plaintext env key is set: the runtime signer reads
    // REGENT_WALLET_PRIVATE_KEY first, so the encrypted keystore we are about to
    // write would be ignored. Fail closed and write nothing.
    if ((process.env.REGENT_WALLET_PRIVATE_KEY ?? "").trim().length > 0) {
      throw new RegentError(
        "wallet_import_env_conflict",
        "REGENT_WALLET_PRIVATE_KEY is set. The runtime signer reads that plaintext env key first, so the encrypted keystore would be ignored. Unset REGENT_WALLET_PRIVATE_KEY, then run `regents wallet import` again.",
      );
    }

    // The private key is read from standard input only, never from a flag value
    // or an environment variable, so it cannot leak into shell history or be
    // silently shadowed by a stale env key.
    const privateKey = await readPrivateKeyFromStdin();

    if (!PRIVATE_KEY_REGEX.test(privateKey)) {
      throw new RegentError(
        "wallet_private_key_invalid",
        "Provide a 32-byte hex private key (0x + 64 hex) on standard input.",
      );
    }

    const config = loadConfig(configPath);
    const address = await deriveWalletAddress(privateKey as `0x${string}`);
    const { dekSource } = await writeEncryptedKeystore(config.wallet.keystorePath, privateKey);

    const result = {
      ok: true as const,
      address,
      keystore_path: config.wallet.keystorePath,
      encrypted: true as const,
      dek_source: dekSource,
      next_steps: ["regents wallet status"],
    };
    if (json) {
      printJson(result);
    } else {
      printText(
        [
          "Wallet key imported and encrypted at rest.",
          `address: ${address}`,
          `keystore: ${config.wallet.keystorePath}`,
          `encryption key: ${dekSource === "env" ? "environment (REGENTS_WALLET_KEY)" : "OS keychain"}`,
          "next: regents wallet status",
        ].join("\n"),
      );
    }
    return 0;
  } catch (error) {
    const regentError =
      error instanceof RegentError
        ? error
        : new RegentError("wallet_import_failed", error instanceof Error ? error.message : "Wallet import failed.");
    if (json) {
      printJson({ ok: false, code: regentError.code, message: regentError.message });
    } else {
      printText(regentError.message);
    }
    return exitCodeForError(regentError);
  }
}

export async function runWalletStatus(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<number> {
  const json = getBooleanFlag(args, "json");

  try {
    const config = loadConfig(configPath);
    const status = await coinbaseStatus(config, {
      walletHint: getFlag(args, "wallet"),
    });
    if (json) {
      printJson(status);
    } else {
      printText(renderWalletStatus(status));
    }
    return status.ok ? 0 : 1;
  } catch (error) {
    const failure =
      error instanceof CommandExitError
        ? error
        : new CommandExitError("COINBASE_CDP_MISSING", error instanceof Error ? error.message : "Wallet status failed.");
    if (json) {
      printJson(failurePayload(failure));
    } else {
      printText(failure.message);
    }
    return exitCodeForError(failure);
  }
}

export async function runWalletSetup(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<number> {
  const json = getBooleanFlag(args, "json");

  try {
    const config = loadConfig(configPath);
    const result = await setupCoinbaseWallet(config, {
      walletName: getFlag(args, "wallet") ?? undefined,
    });
    if (json) {
      printJson({ ...result, next_steps: ["regents identity ensure"] });
    } else {
      printText(["Coinbase wallet ready.", `wallet: ${result.wallet.name}`, `address: ${result.wallet.address}`, "next: regents identity ensure"].join("\n"));
    }
    return 0;
  } catch (error) {
    const failure =
      error instanceof CommandExitError
        ? error
        : new CommandExitError("COINBASE_CDP_MISSING", error instanceof Error ? error.message : "Wallet setup failed.");
    if (json) {
      printJson(failurePayload(failure));
    } else {
      printText(failure.message);
    }
    return exitCodeForError(failure);
  }
}
