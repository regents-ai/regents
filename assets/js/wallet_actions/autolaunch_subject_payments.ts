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

import paymentLinkAbiJson from "../../../contracts/abi/payment-link-factory.json"
import ingressAbiJson from "../../../contracts/abi/revenue-ingress-account.json"
import splitterAbiJson from "../../../contracts/abi/revenue-share-splitter-v2.json"
import type {EthereumProvider} from "./connected_wallet"

const paymentLinkAbi = paymentLinkAbiJson as Abi
const ingressAbi = ingressAbiJson as Abi
const splitterAbi = splitterAbiJson as Abi
const approvalAbi = parseAbi(["function approve(address spender,uint256 amount)"])
const walletOpenMinimumMs = 60_000

export type SubjectPaymentAction =
  | "create_payment_link"
  | "create_canonical_payment_link"
  | "set_payment_link_canonical"
  | "set_payment_link_receiver_state"
  | "sweep_usdc"
  | "stake"
  | "unstake"
  | "claim_usdc"

export type PreparedSubjectPaymentAction = {
  action_id: string
  idempotency_key: string
  confirmation_token: string
  resource:
    | "autolaunch_payment_link"
    | "autolaunch_ingress"
    | "autolaunch_subject_staking"
  action: SubjectPaymentAction
  chain_id: 8453
  to: Address
  value: "0"
  data: Hex
  expected_signer: Address
  prepared_at: string
  expires_at: string
  risk_copy: string
  arguments: {
    subject_id: Hex
    factory?: Address
    label?: string
    canonical?: boolean
    salt?: Hex
    receiver?: Address
    active?: boolean
    replacement?: Address
    ingress_account?: Address
    source_ref?: Hex
    splitter?: Address
    token?: Address
    amount_atomic?: string
    recipient?: Address
  }
  approval?: null | {
    token: Address
    spender: Address
    amount: string
    data: Hex
    mode: "exact"
  }
}

export type SubjectPaymentClients = {
  addresses(): Promise<Address[]>
  chainId(): Promise<number>
  switchToBase(): Promise<void>
  send(request: {account: Address; to: Address; data: Hex; value: bigint}): Promise<Hash>
  receipt(hash: Hash): Promise<{status: "success" | "reverted"}>
}

export type SubjectPaymentExecutionOptions = {
  existingApprovalHash?: Hash
  onSubmitted?: (phase: "approval" | "action", hash: Hash) => void
}

export class SubjectPaymentExecutionError extends Error {
  constructor(
    readonly code: "approval_reverted" | "action_reverted",
    message: string,
  ) {
    super(message)
  }
}

export function clientsFor(provider: EthereumProvider): SubjectPaymentClients {
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

export async function executePreparedSubjectPaymentAction(
  envelope: PreparedSubjectPaymentAction,
  provider: EthereumProvider,
  clients: SubjectPaymentClients = clientsFor(provider),
  options: SubjectPaymentExecutionOptions = {},
): Promise<{transactionHash: Hash; approvalHash?: Hash}> {
  assertWalletOpenWindow(envelope)
  assertSubjectPaymentEnvelope(envelope)
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
      throw new SubjectPaymentExecutionError(
        "approval_reverted",
        "The exact subject-token approval reverted.",
      )
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
    throw new SubjectPaymentExecutionError(
      "action_reverted",
      "The subject transaction reverted.",
    )
  }

  return {transactionHash, approvalHash}
}

export function assertSubjectPaymentEnvelope(
  envelope: PreparedSubjectPaymentAction,
): void {
  if (envelope.chain_id !== base.id) throw new Error("This action is not for Base.")
  if (envelope.value !== "0") throw new Error("This action unexpectedly sends native value.")
  if (envelope.idempotency_key !== envelope.action_id) {
    throw new Error("The action identity changed.")
  }
  if (!envelope.confirmation_token) throw new Error("The action confirmation is missing.")

  getAddress(envelope.to)
  getAddress(envelope.expected_signer)
  assertBytes32(envelope.arguments.subject_id)
  assertFresh(envelope)

  const expectedData = expectedCalldata(envelope)
  if (envelope.data.toLowerCase() !== expectedData.toLowerCase()) {
    throw new Error("The subject action calldata changed.")
  }
}

function expectedCalldata(envelope: PreparedSubjectPaymentAction): Hex {
  const args = envelope.arguments

  if (
    envelope.action === "create_payment_link" ||
    envelope.action === "create_canonical_payment_link"
  ) {
    if (
      envelope.resource !== "autolaunch_payment_link" ||
      !args.factory ||
      !args.label ||
      !args.salt ||
      args.canonical !== (envelope.action === "create_canonical_payment_link") ||
      envelope.approval ||
      getAddress(args.factory) !== getAddress(envelope.to)
    ) {
      throw new Error("The payment-link review is incomplete.")
    }
    assertBytes32(args.salt)

    return encodeFunctionData({
      abi: paymentLinkAbi,
      functionName:
        envelope.action === "create_canonical_payment_link"
          ? "createCanonicalPaymentLink"
          : "createPaymentLink",
      args: [args.subject_id, args.label, args.salt],
    })
  }

  if (envelope.action === "set_payment_link_canonical") {
    if (
      envelope.resource !== "autolaunch_payment_link" ||
      !args.factory ||
      !args.receiver ||
      typeof args.canonical !== "boolean" ||
      envelope.approval ||
      getAddress(args.factory) !== getAddress(envelope.to)
    ) {
      throw new Error("The payment-link canonical review is incomplete.")
    }

    return encodeFunctionData({
      abi: paymentLinkAbi,
      functionName: "setPaymentLinkCanonical",
      args: [getAddress(args.receiver), args.canonical],
    })
  }

  if (envelope.action === "set_payment_link_receiver_state") {
    if (
      envelope.resource !== "autolaunch_payment_link" ||
      !args.factory ||
      !args.receiver ||
      !args.replacement ||
      typeof args.active !== "boolean" ||
      envelope.approval ||
      getAddress(args.factory) !== getAddress(envelope.to)
    ) {
      throw new Error("The payment-link state review is incomplete.")
    }

    return encodeFunctionData({
      abi: paymentLinkAbi,
      functionName: "setPaymentLinkReceiverState",
      args: [getAddress(args.receiver), args.active, getAddress(args.replacement)],
    })
  }

  if (envelope.action === "sweep_usdc") {
    if (
      envelope.resource !== "autolaunch_ingress" ||
      !args.ingress_account ||
      !args.source_ref ||
      envelope.approval ||
      getAddress(args.ingress_account) !== getAddress(envelope.to)
    ) {
      throw new Error("The ingress review is incomplete.")
    }
    assertBytes32(args.source_ref)

    return encodeFunctionData({
      abi: ingressAbi,
      functionName: "sweepUSDC",
      args: [args.source_ref],
    })
  }

  if (envelope.resource !== "autolaunch_subject_staking" || !args.splitter) {
    throw new Error("The subject staking review is incomplete.")
  }
  if (getAddress(args.splitter) !== getAddress(envelope.to)) {
    throw new Error("The subject splitter changed.")
  }

  if (envelope.action === "stake") {
    if (!args.amount_atomic || !args.receiver || !args.token || !envelope.approval) {
      throw new Error("The subject stake review is incomplete.")
    }

    assertExactApproval(envelope)
    return encodeFunctionData({
      abi: splitterAbi,
      functionName: "stake",
      args: [BigInt(args.amount_atomic), getAddress(args.receiver)],
    })
  }

  if (envelope.action === "unstake") {
    if (
      !args.amount_atomic ||
      !args.recipient ||
      envelope.approval ||
      getAddress(args.recipient) !== getAddress(envelope.expected_signer)
    ) {
      throw new Error("The subject unstake review is incomplete.")
    }

    return encodeFunctionData({
      abi: splitterAbi,
      functionName: "unstake",
      args: [BigInt(args.amount_atomic), getAddress(args.recipient)],
    })
  }

  if (
    envelope.action !== "claim_usdc" ||
    !args.recipient ||
    envelope.approval ||
    getAddress(args.recipient) !== getAddress(envelope.expected_signer)
  ) {
    throw new Error("The subject claim review is incomplete.")
  }

  return encodeFunctionData({
    abi: splitterAbi,
    functionName: "claimUSDC",
    args: [getAddress(args.recipient)],
  })
}

function assertExactApproval(envelope: PreparedSubjectPaymentAction): void {
  const approval = envelope.approval
  const args = envelope.arguments
  if (!approval || !args.token || !args.amount_atomic) {
    throw new Error("The exact subject-token approval is missing.")
  }
  if (
    approval.mode !== "exact" ||
    getAddress(approval.token) !== getAddress(args.token) ||
    getAddress(approval.spender) !== getAddress(envelope.to) ||
    approval.amount !== args.amount_atomic
  ) {
    throw new Error("The exact subject-token approval changed.")
  }

  const expected = encodeFunctionData({
    abi: approvalAbi,
    functionName: "approve",
    args: [getAddress(envelope.to), BigInt(args.amount_atomic)],
  })
  if (approval.data.toLowerCase() !== expected.toLowerCase()) {
    throw new Error("The exact subject-token approval changed.")
  }
}

function assertWalletOpenWindow(envelope: PreparedSubjectPaymentAction): void {
  const expiresAt = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiresAt) || expiresAt - Date.now() <= walletOpenMinimumMs) {
    throw new Error("This wallet review is too close to expiry. Prepare it again.")
  }
}

async function requireBase(clients: SubjectPaymentClients): Promise<void> {
  let chainId = await clients.chainId()
  if (chainId !== base.id) {
    await clients.switchToBase()
    chainId = await clients.chainId()
  }
  if (chainId !== base.id) throw new Error("Switch to Base before continuing.")
}

function assertFresh(envelope: PreparedSubjectPaymentAction): void {
  const expiresAt = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new Error("This wallet review expired. Prepare it again.")
  }
}

function assertBytes32(value: Hex): void {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error("The subject identity changed.")
  }
}
