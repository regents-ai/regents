import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
  type Chain,
  type Hex,
  type LocalAccount,
} from "viem";
import { base, baseSepolia, mainnet } from "viem/chains";

export type SupportedTransactionChainId = 1 | 8453 | 84532;

export interface TransactionRequest {
  readonly chain_id: SupportedTransactionChainId;
  readonly to: Address;
  readonly data: Hex;
  readonly expected_signer: Address;
  readonly expires_at: string;
  readonly value?: string | number | bigint | null;
}

export interface BaseContractClients {
  readonly chain: Chain;
  readonly publicClient: ReturnType<typeof createPublicClient>;
  readonly walletClient: ReturnType<typeof createWalletClient>;
}

interface ResolvedChain {
  readonly chain: Chain;
  readonly rpcUrl: string;
}

const rpcUrlForChain = (chainId: SupportedTransactionChainId): string => {
  if (chainId === 1) {
    const rpcUrl =
      process.env.ETH_MAINNET_RPC_URL ?? process.env.ETHEREUM_RPC_URL;
    if (!rpcUrl) {
      throw new Error(
        "missing ETH_MAINNET_RPC_URL or ETHEREUM_RPC_URL for Ethereum mainnet submit mode",
      );
    }

    return rpcUrl;
  }

  if (chainId === 8453) {
    const rpcUrl = process.env.BASE_MAINNET_RPC_URL ?? process.env.BASE_RPC_URL;
    if (!rpcUrl) {
      throw new Error(
        "missing BASE_MAINNET_RPC_URL or BASE_RPC_URL for Base mainnet submit mode",
      );
    }

    return rpcUrl;
  }

  const rpcUrl = process.env.BASE_SEPOLIA_RPC_URL;
  if (!rpcUrl) {
    throw new Error("missing BASE_SEPOLIA_RPC_URL for Base Sepolia submit mode");
  }

  return rpcUrl;
};

const resolveTransactionChain = (
  chainId: SupportedTransactionChainId,
  rpcUrlOverride?: string,
): ResolvedChain => {
  if (chainId === 1) {
    return { chain: mainnet, rpcUrl: rpcUrlOverride ?? rpcUrlForChain(chainId) };
  }

  if (chainId === 8453) {
    return { chain: base, rpcUrl: rpcUrlOverride ?? rpcUrlForChain(chainId) };
  }

  return {
    chain: baseSepolia,
    rpcUrl: rpcUrlOverride ?? rpcUrlForChain(chainId),
  };
};

const transactionValue = (value: TransactionRequest["value"]): bigint =>
  BigInt(String(value ?? "0x0"));

const sameAddress = (left: Address, right: Address): boolean =>
  left.toLowerCase() === right.toLowerCase();

const assertExpectedSigner = (
  account: LocalAccount,
  txRequest: TransactionRequest,
): void => {
  if (!sameAddress(account.address, txRequest.expected_signer)) {
    throw new Error(
      "This prepared transaction is for a different wallet. Switch to the expected wallet before submitting.",
    );
  }
};

const assertNotExpired = (txRequest: TransactionRequest): void => {
  const expiresAt = Date.parse(txRequest.expires_at);
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new Error("This prepared wallet action has expired. Start it again before signing.");
  }
};

export const assertSuccessfulReceipt = (
  receipt: { readonly status?: string | null },
): void => {
  if (receipt.status !== "success") {
    throw new Error("The transaction was not confirmed successfully.");
  }
};

export const submitValidatedTransaction = async (
  account: LocalAccount,
  txRequest: TransactionRequest,
): Promise<`0x${string}`> => {
  const result = await sendValidatedTransaction(account, txRequest);
  return result.txHash;
};

export const createBaseContractClients = (
  account: LocalAccount,
  chainId: SupportedTransactionChainId,
  rpcUrlOverride?: string,
): BaseContractClients => {
  const { chain, rpcUrl } = resolveTransactionChain(chainId, rpcUrlOverride);
  const walletClient = createWalletClient({
    account,
    chain,
    transport: http(rpcUrl),
  });
  const publicClient = createPublicClient({
    chain,
    transport: http(rpcUrl),
  });

  return { chain, publicClient, walletClient };
};

export const sendValidatedTransaction = async (
  account: LocalAccount,
  txRequest: TransactionRequest,
  rpcUrlOverride?: string,
): Promise<{
  readonly txHash: `0x${string}`;
  readonly receipt: Awaited<
    ReturnType<ReturnType<typeof createPublicClient>["waitForTransactionReceipt"]>
  >;
}> => {
  assertExpectedSigner(account, txRequest);
  assertNotExpired(txRequest);

  const { chain, publicClient, walletClient } = createBaseContractClients(
    account,
    txRequest.chain_id,
    rpcUrlOverride,
  );
  const value = transactionValue(txRequest.value);
  const request = {
    account: account.address,
    to: txRequest.to,
    data: txRequest.data,
    value,
  } as const;

  await publicClient.call(request);
  await publicClient.estimateGas(request);

  const txHash = await walletClient.sendTransaction({
    account,
    chain,
    to: txRequest.to,
    data: txRequest.data,
    value,
  });

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  assertSuccessfulReceipt(receipt);
  return { txHash, receipt };
};
