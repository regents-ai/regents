import type { LocalAccount, TransactionSerializable, TypedDataDefinition } from "viem";

/**
 * A signer backend is the single abstraction every signature path depends on.
 * It hides where the key lives (a raw env key, an encrypted local file, and in
 * the future a remote KMS/HSM) behind the four viem-native signing operations
 * plus a viem account adapter. Consumers never touch raw key material.
 */
export interface SignerBackend {
  /** The 0x EVM address this backend signs for. */
  address(): Promise<`0x${string}`>;
  /** Sign a personal message (EIP-191), matching viem `account.signMessage({ message })`. */
  signMessage(message: string): Promise<`0x${string}`>;
  /** Sign EIP-712 typed data, matching viem `account.signTypedData(data)`. */
  signTypedData(data: TypedDataDefinition): Promise<`0x${string}`>;
  /** Sign a transaction, matching viem `account.signTransaction(tx)`. */
  signTransaction(tx: TransactionSerializable): Promise<`0x${string}`>;
  /**
   * A viem `LocalAccount` view of this backend, so existing consumers that pass
   * a viem account into `createWalletClient`/x402 keep working unchanged. Async
   * because the account (and its address) is only known after the key resolves.
   */
  toViemAccount(): Promise<LocalAccount>;
}
