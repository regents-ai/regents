import {createWalletClient, custom, defineChain, type Address, type Hash, type Hex} from "viem"
import {getCapabilities, sendCalls, waitForCallsStatus} from "viem/actions"

import type {EthereumProvider, SelectedWallet} from "./connected_wallet"

/**
 * The chain a step goes to. The server's review also names it and its public
 * node; the wallet takes those from Privy's own list of networks instead.
 */
export type StepChain = {chain_id: number; name?: string; rpc_url?: string}

/** One transaction a button sends, built on the server. */
export type TransactionStep = {kind: "transaction"; step: string; to: Address; data: Hex; value: Hex}

/** One EIP-712 signature a button asks for, built on the server. */
export type SignatureStep = {kind: "signature"; step: string; typed_data: Record<string, unknown>}

export type Step = TransactionStep | SignatureStep

/** Nothing reached the wallet's send; the reason picks the words the server shows. */
export class NothingSent extends Error {
  constructor(readonly reason: "step_unknown" | "wallet_unavailable" | "switch_declined" | "network_mismatch") {
    super(reason)
  }
}

export type Failure = NothingSent["reason"] | "wallet_declined" | "insufficient_funds" | "send_unconfirmed"

/**
 * Sends one transaction from the signed-in wallet. Chain and account are read
 * again on every press, and `eth_chainId` is the last read before the send, so a
 * wallet that changes network part-way is refused before it sees the transaction.
 */
export async function sendStep(
  chain: StepChain,
  signer: Address,
  step: TransactionStep,
  wallet: () => SelectedWallet | null,
  sending: () => void,
): Promise<Hash> {
  const provider = await ready(chain, signer, wallet)

  sending()
  const hash = await provider.request({
    method: "eth_sendTransaction",
    params: [{
      from: signer,
      to: step.to,
      data: step.data,
      value: step.value,
      // A wallet that checks it refuses the send if it moved off the chain after the read above.
      chainId: `0x${chain.chain_id.toString(16)}`,
    }],
  })
  if (typeof hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(hash)) {
    throw new Error("The wallet did not return a transaction hash.")
  }
  return hash as Hash
}

export async function sendsAtomically(
  chain: StepChain,
  signer: Address,
  provider: EthereumProvider,
): Promise<boolean> {
  try {
    const capabilities = await getCapabilities(walletClient(provider, signer), {chainId: chain.chain_id})
    return capabilities.atomic?.status === "supported" || capabilities.atomic?.status === "ready"
  } catch {
    return false
  }
}

export async function sendSteps(
  chain: StepChain,
  signer: Address,
  steps: TransactionStep[],
  wallet: () => SelectedWallet | null,
  sending: () => void,
): Promise<{id: string; provider: EthereumProvider}> {
  const provider = await ready(chain, signer, wallet)
  const network = defineChain({
    id: chain.chain_id,
    name: chain.name ?? String(chain.chain_id),
    nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
    rpcUrls: {default: {http: chain.rpc_url ? [chain.rpc_url] : []}},
  })
  sending()
  const {id} = await sendCalls(walletClient(provider, signer), {
    chain: network,
    calls: steps.map(({to, data, value}) => ({to, data, value: BigInt(value)})),
    forceAtomic: true,
  })
  return {id, provider}
}

export async function landedCalls(
  signer: Address,
  provider: EthereumProvider,
  id: string,
  stop: AbortSignal,
): Promise<{status: "success" | "failure"; hashes: Hash[]} | undefined> {
  try {
    const {status, receipts} = await waitForCallsStatus(walletClient(provider, signer), {
      id,
      pollingInterval: 1_000,
      timeout: 180_000,
      status: ({statusCode}) => stop.aborted || statusCode === 200 || statusCode >= 300,
    })
    if (stop.aborted || (status !== "success" && status !== "failure")) return undefined
    return {status, hashes: [...new Set((receipts ?? []).map(receipt => receipt.transactionHash))]}
  } catch {
    return undefined
  }
}

export function refusedAtomic(error: unknown): boolean {
  return [4200, 5700, 5710, 5760].some(code => hasCode(error, code)) ||
    causes(error).some(candidate => (candidate as {name?: unknown}).name === "AtomicityNotSupportedError")
}

function walletClient(provider: EthereumProvider, signer: Address) {
  return createWalletClient({account: signer, transport: custom(provider, {retryCount: 0})})
}

/**
 * Asks the signed-in wallet to sign the server's typed data, after the same
 * chain and account reads as a send. Returns the signature only; the server
 * keeps the typed data it built.
 */
export async function signStep(
  chain: StepChain,
  signer: Address,
  step: SignatureStep,
  wallet: () => SelectedWallet | null,
  sending: () => void,
): Promise<Hex> {
  const provider = await ready(chain, signer, wallet)

  sending()
  const signature = await provider.request({
    method: "eth_signTypedData_v4",
    params: [signer, JSON.stringify(step.typed_data)],
  })
  if (typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) {
    throw new Error("The wallet did not return a signature.")
  }
  return signature as Hex
}

/** Why a press ended without a hash. After `sending`, the wallet may have sent it. */
export function failure(sending: boolean, error: unknown): Failure {
  if (!sending) return error instanceof NothingSent ? error.reason : "wallet_unavailable"
  if (hasCode(error, 4001)) return "wallet_declined"
  // No EIP-1193 code names this; wallets and nodes all say it in these words.
  return hasMessage(error, /insufficient funds/i) ? "insufficient_funds" : "send_unconfirmed"
}

// The wallet is on the step's chain and account, and still the one Privy holds.
// A wallet on another chain is asked to switch on every press, through Privy's
// own switch: a person who says no hears that they did, and any other failure,
// or a wallet still elsewhere afterwards, is told to change network in the app.
async function ready(
  chain: StepChain,
  signer: Address,
  wallet: () => SelectedWallet | null,
): Promise<EthereumProvider> {
  const selected = wallet()
  if (!selected) throw new NothingSent("wallet_unavailable")
  const {provider} = selected

  if ((await chainId(provider)) !== chain.chain_id) {
    await selected.switchChain(chain.chain_id).catch((error: unknown) => {
      throw new NothingSent(hasCode(error, 4001) ? "switch_declined" : "network_mismatch")
    })
  }

  const [account] = await accounts(provider)
  // Wallets answer addresses in any letter case.
  if (account?.toLowerCase() !== signer.toLowerCase()) throw new NothingSent("wallet_unavailable")
  if ((await chainId(provider)) !== chain.chain_id) throw new NothingSent("network_mismatch")
  // Privy may have swapped the wallet during those reads; this check makes no request.
  if (wallet()?.provider !== provider) throw new NothingSent("wallet_unavailable")
  return provider
}

/** The chain the wallet is on now; -1 when it does not say. */
async function chainId(provider: EthereumProvider): Promise<number> {
  const value = await provider.request({method: "eth_chainId"})
  return typeof value === "string" && /^0x[0-9a-f]+$/i.test(value) ? Number(BigInt(value)) : -1
}

async function accounts(provider: EthereumProvider): Promise<string[]> {
  const value = await provider.request({method: "eth_accounts"})
  return Array.isArray(value) ? value.filter((a): a is string => typeof a === "string") : []
}

// Wallets wrap the EIP-1193 error in `cause` chains of their own.
function hasCode(error: unknown, code: number): boolean {
  return causes(error).some(e => (e as {code?: unknown}).code === code)
}

function hasMessage(error: unknown, words: RegExp): boolean {
  return causes(error).some(e => {
    const message = (e as {message?: unknown}).message
    return typeof message === "string" && words.test(message)
  })
}

function causes(error: unknown): object[] {
  const chain: object[] = []
  for (let e = error; e && typeof e === "object" && chain.length < 8; e = (e as {cause?: unknown}).cause) chain.push(e)
  return chain
}
