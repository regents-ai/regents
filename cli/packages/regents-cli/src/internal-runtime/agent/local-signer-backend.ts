import type { LocalAccount, TransactionSerializable, TypedDataDefinition } from "viem";
import { privateKeyToAccount } from "viem/accounts";

import type { RegentConfig } from "../../internal-types/index.js";
import { loadConfig } from "../config.js";
import { RegentError } from "../errors.js";
import type { SignerBackend } from "./signer-backend.js";
import { readEncryptedKeystore } from "./wallet-keystore.js";

/** How the active signer resolved its key, for status reporting (never the key). */
export type KeySource = "env" | "keystore";

const PRIVATE_KEY_REGEX = /^0x[0-9a-fA-F]{64}$/;

/**
 * Local signer backed by a raw env private key or an encrypted keystore file.
 * The key is resolved lazily on first use and cached for the backend's lifetime.
 * All signing is delegated to a viem account, so `toViemAccount()` is exact.
 */
export class LocalKeySignerBackend implements SignerBackend {
  private readonly privateKeyEnv: string;
  private readonly keystorePath: string;
  private accountPromise: Promise<LocalAccount> | null = null;
  private resolvedKeySource: KeySource | null = null;

  constructor(input: { privateKeyEnv: string; keystorePath: string }) {
    this.privateKeyEnv = input.privateKeyEnv;
    this.keystorePath = input.keystorePath;
  }

  /** Which source the key came from once resolved (null until first use). */
  get keySource(): KeySource | null {
    return this.resolvedKeySource;
  }

  private async account(): Promise<LocalAccount> {
    // Cache only a successful resolution: a transient failure (missing key,
    // unavailable DEK) must not permanently poison the backend, so a retry
    // after the condition is fixed can succeed.
    if (!this.accountPromise) {
      const pending = this.loadAccount();
      pending.catch(() => {
        if (this.accountPromise === pending) {
          this.accountPromise = null;
        }
      });
      this.accountPromise = pending;
    }

    return this.accountPromise;
  }

  private async loadAccount(): Promise<LocalAccount> {
    const fromEnv = process.env[this.privateKeyEnv];
    if (fromEnv) {
      const trimmed = fromEnv.trim();
      if (!PRIVATE_KEY_REGEX.test(trimmed)) {
        throw new RegentError(
          "wallet_private_key_invalid",
          `environment variable ${this.privateKeyEnv} does not contain a valid 32-byte hex private key`,
        );
      }
      this.resolvedKeySource = "env";
      return privateKeyToAccount(trimmed as `0x${string}`);
    }

    const key = await readEncryptedKeystore(this.keystorePath);
    this.resolvedKeySource = "keystore";
    return privateKeyToAccount(key);
  }

  async address(): Promise<`0x${string}`> {
    return (await this.account()).address as `0x${string}`;
  }

  async signMessage(message: string): Promise<`0x${string}`> {
    return (await this.account()).signMessage({ message });
  }

  async signTypedData(data: TypedDataDefinition): Promise<`0x${string}`> {
    return (await this.account()).signTypedData(data);
  }

  async signTransaction(tx: TransactionSerializable): Promise<`0x${string}`> {
    return (await this.account()).signTransaction(tx);
  }

  /**
   * Resolve the key (fail-closed if unavailable) and return the concrete viem
   * `LocalAccount`, so existing `createWalletClient({ account })` / x402
   * consumers keep working unchanged once they are cut over. Async because the
   * account (and its address) is only known after decryption.
   */
  async toViemAccount(): Promise<LocalAccount> {
    return this.account();
  }
}

/**
 * Returns the active signer backend for the current config.
 */
export const getActiveSigner = async (config?: RegentConfig): Promise<SignerBackend> => {
  const resolved = config ?? loadConfig();
  const backend = new LocalKeySignerBackend({
    privateKeyEnv: resolved.wallet.privateKeyEnv,
    keystorePath: resolved.wallet.keystorePath,
  });
  // Resolve eagerly so callers get the fail-closed error at construction time
  // rather than on first sign.
  await backend.address();
  return backend;
};
