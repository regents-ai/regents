import {
  createPublicClient,
  createWalletClient,
  custom,
  encodeFunctionData,
  getAddress,
  parseAbi,
  type Abi,
  type Address,
  type Hash,
  type Hex,
} from "viem"
import {base} from "viem/chains"

import auctionAbiJson from "../../../contracts/abi/continuous-clearing-auction.json"
import type {EthereumProvider} from "./connected_wallet"

const auctionAbi = auctionAbiJson as Abi
const approvalAbi = parseAbi(["function approve(address spender,uint256 amount)"])
const walletOpenMinimumMs = 60_000

export type AuctionBidAction =
  | "submit_bid"
  | "exit_bid"
  | "return_quote_token"
  | "claim_bid"

export type PreparedAuctionBidAction = {
  action_id: string
  idempotency_key: string
  confirmation_token: string
  resource: "autolaunch_auction" | "autolaunch_bid"
  action: AuctionBidAction
  chain_id: 8453
  to: Address
  value: "0"
  data: Hex
  expected_signer: Address
  prepared_at: string
  expires_at: string
  risk_copy: string
  arguments: {
    auction_id: string
    bid_id?: string
    amount_atomic?: string
    max_price_q96?: string
    onchain_bid_id?: string
    recipient: Address
  }
  approval?: null | {
    token: Address
    spender: Address
    amount: string
    data: Hex
    mode: "exact"
  }
}

export type AuctionBidClients = {
  addresses(): Promise<Address[]>
  chainId(): Promise<number>
  switchToBase(): Promise<void>
  send(request: {account: Address; to: Address; data: Hex; value: bigint}): Promise<Hash>
  receipt(hash: Hash): Promise<{status: "success" | "reverted"}>
}

export type AuctionBidExecutionOptions = {
  existingApprovalHash?: Hash
  onSubmitted?: (phase: "approval" | "action", hash: Hash) => void
}

export class AuctionBidExecutionError extends Error {
  constructor(
    readonly code: "approval_reverted" | "action_reverted",
    message: string,
  ) {
    super(message)
  }
}

export function clientsFor(provider: EthereumProvider): AuctionBidClients {
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

export async function executePreparedAuctionBidAction(
  envelope: PreparedAuctionBidAction,
  provider: EthereumProvider,
  clients: AuctionBidClients = clientsFor(provider),
  options: AuctionBidExecutionOptions = {},
): Promise<{transactionHash: Hash; approvalHash?: Hash}> {
  assertWalletOpenWindow(envelope)
  assertAuctionBidEnvelope(envelope)
  await requireBase(clients)

  const [account] = await clients.addresses()
  if (!account || getAddress(account) !== getAddress(envelope.expected_signer)) {
    throw new Error("Use the connected wallet shown on this account.")
  }

  let approvalHash = options.existingApprovalHash
  if (envelope.approval) {
    assertFresh(envelope)
    if (!approvalHash) {
      approvalHash = await clients.send({
        account,
        to: getAddress(envelope.approval.token),
        data: envelope.approval.data,
        value: 0n,
      })
      options.onSubmitted?.("approval", approvalHash)
    }

    const approvalReceipt = await clients.receipt(approvalHash)
    if (approvalReceipt.status !== "success") {
      throw new AuctionBidExecutionError("approval_reverted", "The quote-token approval reverted.")
    }
  }

  assertFresh(envelope)
  const transactionHash = await clients.send({
    account,
    to: getAddress(envelope.to),
    data: envelope.data,
    value: 0n,
  })
  options.onSubmitted?.("action", transactionHash)

  const receipt = await clients.receipt(transactionHash)
  if (receipt.status !== "success") {
    throw new AuctionBidExecutionError("action_reverted", "The auction transaction reverted.")
  }

  return {transactionHash, approvalHash}
}

/*
 * Opening a wallet requires more than 60 seconds of envelope lifetime. Once send() opens
 * the wallet, the user can still hold that prompt past expiry; a transaction submitted
 * from it remains the exact authenticated review, and server confirmation intentionally
 * remains valid after expiry.
 */
function assertWalletOpenWindow(envelope: PreparedAuctionBidAction): void {
  const expiresAt = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiresAt) || expiresAt - Date.now() <= walletOpenMinimumMs) {
    throw new Error("This wallet review is too close to expiry. Prepare it again.")
  }
}

export function assertAuctionBidEnvelope(envelope: PreparedAuctionBidAction): void {
  if (envelope.chain_id !== base.id) throw new Error("This action is not for Base.")
  if (envelope.value !== "0") throw new Error("This action unexpectedly sends native value.")
  if (envelope.idempotency_key !== envelope.action_id) throw new Error("The action identity changed.")
  if (!envelope.confirmation_token) throw new Error("The action confirmation is missing.")
  getAddress(envelope.to)
  getAddress(envelope.expected_signer)
  assertFresh(envelope)

  const args = envelope.arguments
  let expectedData: Hex

  if (envelope.action === "submit_bid") {
    if (
      envelope.resource !== "autolaunch_auction" ||
      !args.amount_atomic ||
      !args.max_price_q96 ||
      !envelope.approval
    ) {
      throw new Error("The bid review is incomplete.")
    }

    expectedData = encodeFunctionData({
      abi: auctionAbi,
      functionName: "submitBid",
      args: [
        BigInt(args.max_price_q96),
        BigInt(args.amount_atomic),
        getAddress(envelope.expected_signer),
        "0x",
      ],
    })

    const approval = envelope.approval
    if (
      approval.mode !== "exact" ||
      getAddress(approval.spender) !== getAddress(envelope.to) ||
      approval.amount !== args.amount_atomic
    ) {
      throw new Error("The exact quote-token approval changed.")
    }

    const expectedApproval = encodeFunctionData({
      abi: approvalAbi,
      functionName: "approve",
      args: [getAddress(envelope.to), BigInt(args.amount_atomic)],
    })
    if (approval.data.toLowerCase() !== expectedApproval.toLowerCase()) {
      throw new Error("The exact quote-token approval changed.")
    }
  } else {
    if (
      envelope.resource !== "autolaunch_bid" ||
      !args.bid_id ||
      !args.onchain_bid_id ||
      envelope.approval
    ) {
      throw new Error("The bid-position review is incomplete.")
    }

    const functionName = envelope.action === "claim_bid" ? "claimTokens" : "exitBid"
    expectedData = encodeFunctionData({
      abi: auctionAbi,
      functionName,
      args: [BigInt(args.onchain_bid_id)],
    })
  }

  if (envelope.data.toLowerCase() !== expectedData.toLowerCase()) {
    throw new Error("The auction calldata changed.")
  }
}

async function requireBase(clients: AuctionBidClients): Promise<void> {
  let chainId = await clients.chainId()
  if (chainId !== base.id) {
    await clients.switchToBase()
    chainId = await clients.chainId()
  }
  if (chainId !== base.id) throw new Error("Switch to Base before continuing.")
}

function assertFresh(envelope: PreparedAuctionBidAction): void {
  const expiresAt = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new Error("This wallet review expired. Prepare it again.")
  }
}
