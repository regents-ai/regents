import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { promisify } from "node:util";

import type { RegentConfig, RegentIdentityNetwork } from "../internal-types/index.js";

import { CommandExitError } from "./errors.js";
import { receiptMatchesRequest } from "./identity/cache.js";
import { readIdentityReceipt } from "./identity/cache.js";
import { writeJsonFileAtomicSync } from "./paths.js";

const execFileAsync = promisify(execFile);
const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/u;
const CDP_BIN = "cdp";
const DEFAULT_ACCOUNT_NAME = "main";
const COINBASE_PROVIDER = "coinbase-cdp" as const;

export interface CoinbaseWalletAccount {
  name: string;
  address: `0x${string}`;
}

export interface CoinbaseWalletStatus {
  ok: boolean;
  provider: typeof COINBASE_PROVIDER;
  cli_available: boolean;
  api_key_present: boolean;
  wallet_secret_present: boolean;
  account: CoinbaseWalletAccount | null;
  identity_ready: boolean;
  receipt_expires_at?: string;
  next_action?: {
    reason: string;
    command: string;
  };
}

interface CoinbaseAccountResolutionInput {
  walletHint?: string;
  expectedAddress?: `0x${string}`;
}

type CoinbaseStatusBase = Omit<CoinbaseWalletStatus, "next_action">;

const normalizeAddress = (value: unknown): `0x${string}` | null => {
  if (typeof value !== "string" || !ADDRESS_REGEX.test(value)) {
    return null;
  }
  return value.toLowerCase() as `0x${string}`;
};

const walletStatePath = (config: RegentConfig): string =>
  path.join(config.runtime.stateDir, "coinbase-wallet.json");

const readWalletState = (config: RegentConfig): CoinbaseWalletAccount | null => {
  const filePath = walletStatePath(config);
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, "utf8")) as { name?: unknown; address?: unknown };
    const name = typeof parsed.name === "string" && parsed.name ? parsed.name : null;
    const address = normalizeAddress(parsed.address);
    return name && address ? { name, address } : null;
  } catch {
    return null;
  }
};

const writeWalletState = (config: RegentConfig, account: CoinbaseWalletAccount): string => {
  const filePath = walletStatePath(config);
  writeJsonFileAtomicSync(filePath, account);
  return filePath;
};

const parseAccountPayload = (payload: unknown): CoinbaseWalletAccount | null => {
  if (typeof payload !== "object" || payload === null) {
    return null;
  }
  const record = payload as Record<string, unknown>;
  const name = typeof record.name === "string" && record.name ? record.name : null;
  const address = normalizeAddress(record.address);
  return name && address ? { name, address } : null;
};

const parseAccountsList = (payload: unknown): CoinbaseWalletAccount[] => {
  const items =
    Array.isArray(payload)
      ? payload
      : typeof payload === "object" && payload !== null && Array.isArray((payload as { accounts?: unknown[] }).accounts)
        ? (payload as { accounts: unknown[] }).accounts
        : [];
  return items
    .map((item) => parseAccountPayload(item))
    .filter((item): item is CoinbaseWalletAccount => item !== null);
};

const runCdpJsonCommand = async (args: string[], timeoutMs: number): Promise<unknown> => {
  try {
    const { stdout } = await execFileAsync(CDP_BIN, args, {
      encoding: "utf8",
      timeout: timeoutMs,
    });
    const trimmed = stdout.trim();
    return trimmed === "" ? {} : JSON.parse(trimmed);
  } catch (error) {
    const cause = error instanceof Error ? error.message : String(error);
    throw new CommandExitError(
      "COINBASE_CDP_MISSING",
      "Coinbase wallet setup is not ready on this machine.", { details: { cause, command: `${CDP_BIN} ${args.join(" ")}` } },
    );
  }
};

const tryRunCdpJsonCommand = async (
  args: string[],
  timeoutMs: number,
): Promise<unknown | null> => {
  try {
    return await runCdpJsonCommand(args, timeoutMs);
  } catch {
    return null;
  }
};

const accountForSelector = (accounts: CoinbaseWalletAccount[], selector: string): CoinbaseWalletAccount | null => {
  const requestedAddress = normalizeAddress(selector);
  return accounts.find((account) => account.name === selector || account.address === requestedAddress) ?? null;
};

const fetchNamedAccount = async (
  selector: string,
  timeoutMs: number,
): Promise<CoinbaseWalletAccount | null> => {
  return parseAccountPayload(
    await tryRunCdpJsonCommand(["evm", "accounts", "by-name", selector], timeoutMs),
  );
};

const fetchListedAccounts = async (timeoutMs: number): Promise<CoinbaseWalletAccount[]> => {
  return parseAccountsList(await tryRunCdpJsonCommand(["evm", "accounts", "list"], timeoutMs));
};

const preferredAccountSelectors = (
  config: RegentConfig,
  input?: CoinbaseAccountResolutionInput,
): string[] => {
  const storedWallet = readWalletState(config);

  return [
    input?.walletHint,
    ...(input?.walletHint ? [] : [storedWallet?.name, storedWallet?.address]),
    input?.expectedAddress,
  ].filter(
    (value, index, values): value is string =>
      Boolean(value) && values.indexOf(value) === index,
  );
};

const resolveAccountFromSelectors = async (
  selectors: string[],
  timeoutMs: number,
): Promise<CoinbaseWalletAccount | null> => {
  if (selectors.length === 0) {
    return null;
  }

  const directMatch = await fetchNamedAccount(selectors[0], timeoutMs);
  if (directMatch) {
    return directMatch;
  }

  const listedAccounts = await fetchListedAccounts(timeoutMs);
  for (const selector of selectors) {
    const matchedAccount = accountForSelector(listedAccounts, selector);
    if (matchedAccount) {
      return matchedAccount;
    }
  }

  return null;
};

const resolveDefaultAccount = async (timeoutMs: number): Promise<CoinbaseWalletAccount | null> => {
  const defaultAccount = await fetchNamedAccount(DEFAULT_ACCOUNT_NAME, timeoutMs);
  if (defaultAccount) {
    return defaultAccount;
  }

  const listedAccounts = await fetchListedAccounts(timeoutMs);
  return accountForSelector(listedAccounts, DEFAULT_ACCOUNT_NAME) ?? listedAccounts[0] ?? null;
};

const resolveStoredOrNamedAccount = async (
  config: RegentConfig,
  timeoutMs: number,
  input?: CoinbaseAccountResolutionInput,
): Promise<CoinbaseWalletAccount | null> => {
  const selectors = preferredAccountSelectors(config, input);

  if (selectors.length > 0) {
    return resolveAccountFromSelectors(selectors, timeoutMs);
  }

  return resolveDefaultAccount(timeoutMs);
};

export const resolveCoinbaseAccount = async (
  config: RegentConfig,
  input?: { walletHint?: string; expectedAddress?: `0x${string}`; timeoutMs?: number },
): Promise<CoinbaseWalletAccount | null> => {
  const timeoutMs = input?.timeoutMs ?? config.services.siwa.requestTimeoutMs;
  return resolveStoredOrNamedAccount(config, timeoutMs, input);
};

const nextActionForStatus = (status: Omit<CoinbaseWalletStatus, "next_action">): CoinbaseWalletStatus["next_action"] => {
  if (!status.cli_available) {
    return {
      reason: "The Coinbase command line tool is not installed yet.",
      command: "npm install -g @coinbase/cdp-cli && regents wallet setup",
    };
  }
  if (!status.api_key_present) {
    return {
      reason: "The Coinbase API key is missing.",
      command: "Set CDP_KEY_ID and CDP_KEY_SECRET, then run regents wallet setup",
    };
  }
  if (!status.wallet_secret_present) {
    return {
      reason: "The Coinbase wallet secret is missing.",
      command: "Set CDP_WALLET_SECRET, then run regents wallet setup",
    };
  }
  if (!status.account) {
    return {
      reason: "No Coinbase wallet account has been prepared for this machine.",
      command: "regents wallet setup",
    };
  }
  if (!status.identity_ready) {
    return {
      reason: "The wallet is ready, but the Regent identity receipt is missing or expired.",
      command: "regents identity ensure",
    };
  }
  return undefined;
};

const matchingReceiptForStatus = (
  config: RegentConfig,
  account: CoinbaseWalletAccount | null,
  input?: { network?: RegentIdentityNetwork },
) => {
  const receipt = readIdentityReceipt();

  if (
    receipt?.provider !== COINBASE_PROVIDER ||
    !account ||
    !receiptMatchesRequest({
      receipt,
      network: input?.network ?? receipt.network,
      regentBaseUrl: config.services.siwa.baseUrl,
      walletHint: account.address,
    })
  ) {
    return null;
  }

  return receipt;
};

const buildCoinbaseStatusBase = (input: {
  account: CoinbaseWalletAccount | null;
  cliAvailable: boolean;
  receiptExpiresAt?: string;
}): CoinbaseStatusBase => {
  return {
    ok: false,
    provider: COINBASE_PROVIDER,
    cli_available: input.cliAvailable,
    api_key_present: Boolean(process.env.CDP_KEY_ID) && Boolean(process.env.CDP_KEY_SECRET),
    wallet_secret_present: Boolean(process.env.CDP_WALLET_SECRET),
    account: input.account,
    identity_ready: Boolean(input.receiptExpiresAt),
    ...(input.receiptExpiresAt ? { receipt_expires_at: input.receiptExpiresAt } : {}),
  };
};

export const coinbaseStatus = async (
  config: RegentConfig,
  input?: { walletHint?: string; network?: RegentIdentityNetwork; timeoutMs?: number },
): Promise<CoinbaseWalletStatus> => {
  const timeoutMs = input?.timeoutMs ?? config.services.siwa.requestTimeoutMs;
  let cliAvailable = true;
  let account: CoinbaseWalletAccount | null = null;
  try {
    account = await resolveStoredOrNamedAccount(config, timeoutMs, input);
  } catch {
    cliAvailable = false;
  }

  const receipt = matchingReceiptForStatus(config, account, input);
  const baseStatus = buildCoinbaseStatusBase({
    account,
    cliAvailable,
    receiptExpiresAt: receipt?.receipt_expires_at,
  });

  const nextAction = nextActionForStatus(baseStatus);
  return {
    ...baseStatus,
    ok: nextAction === undefined,
    ...(nextAction ? { next_action: nextAction } : {}),
  };
};

const requireCdpReadyForWrites = (): void => {
  if (!process.env.CDP_KEY_ID || !process.env.CDP_KEY_SECRET || !process.env.CDP_WALLET_SECRET) {
    throw new CommandExitError(
      "COINBASE_CDP_MISSING",
      "Coinbase credentials are not ready for wallet setup.", {
        details: {
          api_key_present: Boolean(process.env.CDP_KEY_ID) && Boolean(process.env.CDP_KEY_SECRET),
          wallet_secret_present: Boolean(process.env.CDP_WALLET_SECRET),
        },
      },
    );
  }
};

export const setupCoinbaseWallet = async (
  config: RegentConfig,
  input?: { walletName?: string; timeoutMs?: number },
): Promise<{
  ok: true;
  provider: typeof COINBASE_PROVIDER;
  wallet: CoinbaseWalletAccount;
  created: boolean;
  state_path: string;
}> => {
  requireCdpReadyForWrites();
  const timeoutMs = input?.timeoutMs ?? config.services.siwa.requestTimeoutMs;
  const walletName = input?.walletName || DEFAULT_ACCOUNT_NAME;

  let wallet = await resolveStoredOrNamedAccount(config, timeoutMs, { walletHint: walletName });
  let created = false;
  if (!wallet) {
    wallet = parseAccountPayload(
      await runCdpJsonCommand(["evm", "accounts", "create", `name=${walletName}`], timeoutMs),
    );
    created = true;
  }
  if (!wallet) {
    throw new CommandExitError("COINBASE_CDP_MISSING", "Coinbase did not return a wallet account.");
  }

  const statePath = writeWalletState(config, wallet);
  return {
    ok: true,
    provider: COINBASE_PROVIDER,
    wallet,
    created,
    state_path: statePath,
  };
};

export const signMessageWithCoinbase = async (
  config: RegentConfig,
  input: { message: string; walletHint?: string; timeoutMs?: number; expectedAddress?: `0x${string}` },
): Promise<{ provider: typeof COINBASE_PROVIDER; address: `0x${string}`; walletHint?: string; signature: `0x${string}` }> => {
  requireCdpReadyForWrites();
  const timeoutMs = input.timeoutMs ?? config.services.siwa.requestTimeoutMs;
  const wallet = await resolveStoredOrNamedAccount(config, timeoutMs, {
    walletHint: input.walletHint,
    expectedAddress: input.expectedAddress,
  });
  if (!wallet) {
    throw new CommandExitError("COINBASE_CDP_MISSING", "No Coinbase wallet account is ready on this machine.");
  }
  if (input.expectedAddress && wallet.address.toLowerCase() !== input.expectedAddress.toLowerCase()) {
    throw new CommandExitError(
      "COINBASE_CDP_MISSING",
      "The saved Regent identity no longer matches the current Coinbase wallet.", { details: { expectedAddress: input.expectedAddress, address: wallet.address } },
    );
  }

  const payload = await runCdpJsonCommand(
    ["evm", "accounts", "sign", "message", wallet.address, `message=${input.message}`],
    timeoutMs,
  );
  const record = (typeof payload === "object" && payload !== null ? payload : {}) as Record<string, unknown>;
  const signature =
    (typeof record.signature === "string" && record.signature.startsWith("0x") && record.signature) ||
    (typeof record.signedMessage === "string" && record.signedMessage.startsWith("0x") && record.signedMessage);
  if (!signature) {
    throw new CommandExitError("COINBASE_CDP_MISSING", "Coinbase did not return a message signature.");
  }

  return {
    provider: COINBASE_PROVIDER,
    address: wallet.address,
    ...(wallet.name ? { walletHint: wallet.name } : {}),
    signature: signature as `0x${string}`,
  };
};

export const coinbaseProviderName = (): typeof COINBASE_PROVIDER => COINBASE_PROVIDER;
