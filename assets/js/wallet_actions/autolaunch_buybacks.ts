import {
  createPublicClient,
  createWalletClient,
  custom,
  encodeFunctionData,
  getAddress,
  type Abi,
  type Address,
  type Hash,
  type Hex,
} from "viem"
import {base} from "viem/chains"

import buybackAbiJson from "../../../contracts/abi/regent-staking-revenue-router-buyback.json"
import type {EthereumProvider} from "./connected_wallet"

const buybackAbi = buybackAbiJson as Abi
const walletOpenMinimumMs = 60_000

export type PreparedAutolaunchBuyback = {
  action_id: string
  idempotency_key: string
  confirmation_token: string
  resource: "autolaunch_buyback"
  action: "settle_treasury_buyback"
  chain_id: 8453
  to: Address
  value: "0"
  data: Hex
  expected_signer: Address
  prepared_at: string
  expires_at: string
  risk_copy: string
  approval?: null
  arguments: {
    subject_id: Hex
    revenue_router: Address
    treasury: Address
    amount_usdc_atomic: string
    minimum_regent_output_atomic: string
    source_ref: Hex
  }
}

export type AutolaunchBuybackClients = {
  addresses(): Promise<Address[]>
  chainId(): Promise<number>
  switchToBase(): Promise<void>
  send(request: {account: Address; to: Address; data: Hex; value: bigint}): Promise<Hash>
  receipt(hash: Hash): Promise<{status: "success" | "reverted"}>
}

export class AutolaunchBuybackExecutionError extends Error {
  constructor(message: string) {
    super(message)
  }
}

export function clientsFor(provider: EthereumProvider): AutolaunchBuybackClients {
  const transport = custom(provider)
  const publicClient = createPublicClient({chain: base, transport})
  const walletClient = createWalletClient({chain: base, transport})

  return {
    addresses: () => walletClient.getAddresses(),
    chainId: () => walletClient.getChainId(),
    switchToBase: async () => {
      await walletClient.switchChain({id: base.id})
    },
    send: request => walletClient.sendTransaction(request),
    receipt: hash => publicClient.waitForTransactionReceipt({hash, timeout: 60_000}),
  }
}

export async function executePreparedAutolaunchBuyback(
  envelope: PreparedAutolaunchBuyback,
  provider: EthereumProvider,
  clients: AutolaunchBuybackClients = clientsFor(provider),
  onSubmitted?: (hash: Hash) => void,
): Promise<Hash> {
  assertWalletOpenWindow(envelope)
  assertAutolaunchBuybackEnvelope(envelope)
  await requireBase(clients)

  const [account] = await clients.addresses()
  if (!account || getAddress(account) !== getAddress(envelope.expected_signer)) {
    throw new Error("Use the connected wallet shown on this account.")
  }

  assertFresh(envelope)
  const transactionHash = await clients.send({
    account,
    to: getAddress(envelope.to),
    data: envelope.data,
    value: 0n,
  })
  onSubmitted?.(transactionHash)

  const receipt = await clients.receipt(transactionHash)
  if (receipt.status !== "success") {
    throw new AutolaunchBuybackExecutionError("The buyback transaction reverted.")
  }

  return transactionHash
}

/*
 * Opening a wallet requires more than 60 seconds of envelope lifetime. A hash recorded
 * after send() remains eligible for read-only confirmation even if the receipt arrives
 * after expiry.
 */
function assertWalletOpenWindow(envelope: PreparedAutolaunchBuyback): void {
  const expiresAt = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiresAt) || expiresAt - Date.now() <= walletOpenMinimumMs) {
    throw new Error("This wallet review is too close to expiry. Prepare it again.")
  }
}

export function assertAutolaunchBuybackEnvelope(
  envelope: PreparedAutolaunchBuyback,
): void {
  if (envelope.resource !== "autolaunch_buyback") {
    throw new Error("The buyback resource changed.")
  }
  if (envelope.action !== "settle_treasury_buyback") {
    throw new Error("The buyback action changed.")
  }
  if (envelope.chain_id !== base.id) throw new Error("This action is not for Base.")
  if (envelope.value !== "0") throw new Error("This action unexpectedly sends native value.")
  if (envelope.approval) throw new Error("This settlement unexpectedly requests an approval.")
  if (envelope.idempotency_key !== envelope.action_id) {
    throw new Error("The action identity changed.")
  }
  if (!envelope.confirmation_token) throw new Error("The action confirmation is missing.")

  getAddress(envelope.to)
  getAddress(envelope.expected_signer)
  if (getAddress(envelope.arguments.revenue_router) !== getAddress(envelope.to)) {
    throw new Error("The revenue router changed.")
  }
  getAddress(envelope.arguments.treasury)
  assertBytes32(envelope.arguments.subject_id)
  assertBytes32(envelope.arguments.source_ref)
  assertFresh(envelope)

  const expectedData = encodeFunctionData({
    abi: buybackAbi,
    functionName: "settleTreasuryBuyback",
    args: [
      envelope.arguments.subject_id,
      getAddress(envelope.arguments.treasury),
      BigInt(envelope.arguments.amount_usdc_atomic),
      BigInt(envelope.arguments.minimum_regent_output_atomic),
      envelope.arguments.source_ref,
    ],
  })

  if (envelope.data.toLowerCase() !== expectedData.toLowerCase()) {
    throw new Error("The buyback calldata changed.")
  }
}

async function requireBase(clients: AutolaunchBuybackClients): Promise<void> {
  let chainId = await clients.chainId()
  if (chainId !== base.id) {
    await clients.switchToBase()
    chainId = await clients.chainId()
  }
  if (chainId !== base.id) throw new Error("Switch to Base before continuing.")
}

function assertFresh(envelope: PreparedAutolaunchBuyback): void {
  const expiresAt = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new Error("This wallet review expired. Prepare it again.")
  }
}

function assertBytes32(value: Hex): void {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new Error("The subject identity changed.")
}
