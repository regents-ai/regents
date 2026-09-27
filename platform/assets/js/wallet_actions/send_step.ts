import {getAddress, type Address, type Hash, type Hex} from "viem"

import type {EthereumProvider, SelectedWallet} from "./connected_wallet"

/** The chain a step goes to, as the server names it for the wallet's prompt. */
export type StepChain = {chain_id: number; name: string; rpc_url: string}

/** One transaction a button sends, built on the server. */
export type Step = {step: string; to: Address; data: Hex; value: Hex}

/** Nothing reached the wallet's send; the reason picks the words the server shows. */
export class NothingSent extends Error {
  constructor(readonly reason: "step_unknown" | "wallet_unavailable" | "network_mismatch") {
    super(reason)
  }
}

export type Failure = NothingSent["reason"] | "wallet_declined" | "send_unconfirmed"

/**
 * Sends one step from the signed-in wallet. Chain and account are read again on
 * every press, and `eth_chainId` is the last read before the send, so a wallet
 * that changes network part-way is refused before it sees the transaction.
 */
export async function sendStep(
  chain: StepChain,
  signer: Address,
  step: Step,
  wallet: () => SelectedWallet | null,
  sending: () => void,
): Promise<Hash> {
  const selected = wallet()
  if (!selected) throw new NothingSent("wallet_unavailable")
  const {provider} = selected

  if ((await chainId(provider)) !== chain.chain_id) await switchChain(provider, chain)

  const [account] = await accounts(provider)
  if (!account || getAddress(account) !== getAddress(signer)) throw new NothingSent("wallet_unavailable")
  if ((await chainId(provider)) !== chain.chain_id) throw new NothingSent("network_mismatch")
  // Privy may have swapped the wallet during those reads; this check makes no request.
  if (wallet()?.provider !== provider) throw new NothingSent("wallet_unavailable")

  sending()
  const hash = await provider.request({
    method: "eth_sendTransaction",
    params: [{from: getAddress(signer), to: getAddress(step.to), data: step.data, value: step.value}],
  })
  if (typeof hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(hash)) {
    throw new Error("The wallet did not return a transaction hash.")
  }
  return hash as Hash
}

/** Why a press ended without a hash. After `sending`, the wallet may have sent it. */
export function failure(sending: boolean, error: unknown): Failure {
  if (!sending) return error instanceof NothingSent ? error.reason : "wallet_unavailable"
  return hasCode(error, 4001) ? "wallet_declined" : "send_unconfirmed"
}

async function switchChain(provider: EthereumProvider, chain: StepChain): Promise<void> {
  const chainId = `0x${chain.chain_id.toString(16)}`
  try {
    try {
      await provider.request({method: "wallet_switchEthereumChain", params: [{chainId}]})
    } catch (error) {
      if (!hasCode(error, 4902)) throw error
      await provider.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId,
          chainName: chain.name,
          nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
          rpcUrls: [chain.rpc_url],
        }],
      })
      await provider.request({method: "wallet_switchEthereumChain", params: [{chainId}]})
    }
  } catch {
    throw new NothingSent("network_mismatch")
  }
}

async function chainId(provider: EthereumProvider): Promise<number> {
  const value = await provider.request({method: "eth_chainId"})
  return typeof value === "string" && /^0x[0-9a-f]+$/i.test(value) ? Number(BigInt(value)) : -1
}

async function accounts(provider: EthereumProvider): Promise<string[]> {
  const value = await provider.request({method: "eth_accounts"})
  return Array.isArray(value) ? value.filter((a): a is string => typeof a === "string") : []
}

// Wallets wrap the EIP-1193 code in `cause` chains of their own.
function hasCode(error: unknown, code: number): boolean {
  for (let e = error, seen = 0; e && typeof e === "object" && seen < 8; e = (e as {cause?: unknown}).cause, seen++) {
    if ((e as {code?: unknown}).code === code) return true
  }
  return false
}
