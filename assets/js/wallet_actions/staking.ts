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

import chainManifest from "../../../contracts/base-mainnet.json"
import stakingAbiJson from "../../../contracts/abi/regent-revenue-staking.json"
import type {EthereumProvider} from "./connected_wallet"

type Manifest = {
  contracts: {
    regent_revenue_staking: {
      address: string
      onchain_constants: {stake_token: string}
      prepared_actions: Array<{id: string}>
    }
  }
}

const stakingManifest = (chainManifest as Manifest).contracts.regent_revenue_staking
const STAKING = getAddress(stakingManifest.address)
const STAKE_TOKEN = getAddress(stakingManifest.onchain_constants.stake_token)
const stakingAbi = stakingAbiJson as Abi
const actionIds = new Set(stakingManifest.prepared_actions.map(action => action.id))
const erc20Abi = parseAbi(["function allowance(address owner,address spender) view returns (uint256)"])
const approvalAbi = parseAbi(["function approve(address spender,uint256 amount)"])

export type StakingAction =
  | "stake"
  | "unstake"
  | "claim_usdc"
  | "claim_regent"
  | "claim_and_restake_regent"

export type PreparedStakingAction = {
  action_id: string
  idempotency_key: string
  confirmation_token: string
  resource: "regent_staking"
  action: StakingAction
  chain_id: 8453
  to: Address
  value: "0"
  data: Hex
  expected_signer: Address
  prepared_at: string
  expires_at: string
  risk_copy: string
  arguments: {amount_atomic?: string; receiver?: Address; recipient?: Address}
  approval?: null | {
    token: Address
    spender: Address
    amount: string
    data: Hex
    mode: "exact"
  }
}

export type StakingClients = {
  addresses(): Promise<Address[]>
  chainId(): Promise<number>
  switchToBase(): Promise<void>
  allowance(owner: Address, spender: Address): Promise<bigint>
  simulate(request: {account: Address; to: Address; data: Hex; value: bigint}): Promise<void>
  send(request: {account: Address; to: Address; data: Hex; value: bigint}): Promise<Hash>
}

export type SubmissionPhase = "approval" | "action"
export type ExecutionOptions = {
  existingApprovalHash?: Hash
  onSubmitted?: (phase: SubmissionPhase, hash: Hash) => void
  // Called synchronously immediately before each wallet send, and required, so
  // every caller can tell a failure that never asked the wallet for anything
  // from one that may already have put a transaction on Base.
  onSendStarted: () => void
}

export function clientsFor(provider: EthereumProvider): StakingClients {
  const transport = custom(provider)
  const publicClient = createPublicClient({chain: base, transport})
  const walletClient = createWalletClient({chain: base, transport})

  return {
    addresses: () => walletClient.getAddresses(),
    chainId: () => walletClient.getChainId(),
    switchToBase: async () => {
      await walletClient.switchChain({id: base.id})
    },
    allowance: (owner, spender) =>
      publicClient.readContract({
        address: STAKE_TOKEN,
        abi: erc20Abi,
        functionName: "allowance",
        args: [owner, spender],
      }),
    simulate: async request => {
      await publicClient.call(request)
    },
    send: request => walletClient.sendTransaction(request),
  }
}

export async function executePreparedStakingAction(
  envelope: PreparedStakingAction,
  provider: EthereumProvider,
  clients: StakingClients = clientsFor(provider),
  options: ExecutionOptions,
): Promise<void> {
  assertEnvelope(envelope)

  let chainId = await clients.chainId()
  if (chainId !== base.id) {
    await clients.switchToBase()
    chainId = await clients.chainId()
  }
  if (chainId !== base.id) throw new Error("Switch to Base before continuing.")

  const [account] = await clients.addresses()
  if (!account || getAddress(account) !== getAddress(envelope.expected_signer)) {
    throw new Error("Use the connected wallet shown on this account.")
  }

  // An approval this attempt has to send is the whole attempt: the stake follows
  // only once the server has verified that approval and invited it back.
  if (envelope.approval) {
    assertApproval(envelope.approval, envelope)
    if (!options.existingApprovalHash) {
      const approval = {account, to: STAKE_TOKEN, data: envelope.approval.data, value: 0n}
      await clients.simulate(approval)
      options.onSendStarted()
      const approvalHash = await clients.send(approval)
      options.onSubmitted?.("approval", approvalHash)
      return
    }
  }

  const transaction = {account, to: STAKING, data: envelope.data, value: 0n}
  await clients.simulate(transaction)
  options.onSendStarted()
  const transactionHash = await clients.send(transaction)

  // The hash is durably reported and the server owns every read after it, so
  // the browser never waits on a receipt and never decides an outcome.
  options.onSubmitted?.("action", transactionHash)
}

function assertEnvelope(envelope: PreparedStakingAction): void {
  if (envelope.chain_id !== base.id) throw new Error("This action is not for Base.")
  if (getAddress(envelope.to) !== STAKING) throw new Error("The staking target changed.")
  if (envelope.value !== "0") throw new Error("This action cannot send native currency.")
  if (envelope.resource !== "regent_staking" || !actionIds.has(envelope.action)) {
    throw new Error("The staking action is invalid.")
  }
  if (!envelope.action_id || envelope.idempotency_key !== envelope.action_id || !envelope.confirmation_token) {
    throw new Error("The staking action is incomplete.")
  }
  const expiry = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiry) || expiry <= Date.now()) {
    throw new Error("This action expired. Prepare it again.")
  }

  const recipient = envelope.arguments.receiver ?? envelope.arguments.recipient
  if (recipient && getAddress(recipient) !== getAddress(envelope.expected_signer)) {
    throw new Error("The staking recipient changed.")
  }

  if (envelope.data.toLowerCase() !== encodeAction(envelope).toLowerCase()) {
    throw new Error("The staking action data changed.")
  }
}

function assertApproval(
  approval: NonNullable<PreparedStakingAction["approval"]>,
  envelope: PreparedStakingAction,
): void {
  const expectedAmount = envelope.arguments.amount_atomic
  if (
    getAddress(approval.token) !== STAKE_TOKEN ||
    getAddress(approval.spender) !== STAKING ||
    approval.mode !== "exact" ||
    BigInt(approval.amount) <= 0n ||
    !expectedAmount ||
    approval.amount !== expectedAmount
  ) {
    throw new Error("The REGENT approval changed.")
  }

  const expected = encodeFunctionData({
    abi: approvalAbi,
    functionName: "approve",
    args: [STAKING, BigInt(approval.amount)],
  })
  if (approval.data.toLowerCase() !== expected.toLowerCase()) {
    throw new Error("The REGENT approval changed.")
  }
}

function encodeAction(envelope: PreparedStakingAction): Hex {
  switch (envelope.action) {
    case "stake":
      return encodeFunctionData({
        abi: stakingAbi,
        functionName: "stake",
        args: [requiredAmount(envelope), requiredAddress(envelope.arguments.receiver)],
      })
    case "unstake":
      return encodeFunctionData({
        abi: stakingAbi,
        functionName: "unstake",
        args: [requiredAmount(envelope), requiredAddress(envelope.arguments.recipient)],
      })
    case "claim_usdc":
      return encodeFunctionData({
        abi: stakingAbi,
        functionName: "claimUSDC",
        args: [requiredAddress(envelope.arguments.recipient)],
      })
    case "claim_regent":
      return encodeFunctionData({
        abi: stakingAbi,
        functionName: "claimRegent",
        args: [requiredAddress(envelope.arguments.recipient)],
      })
    case "claim_and_restake_regent":
      return encodeFunctionData({abi: stakingAbi, functionName: "claimAndRestakeRegent"})
  }
}

function requiredAmount(envelope: PreparedStakingAction): bigint {
  const amount = envelope.arguments.amount_atomic
  if (!amount || !/^\d+$/.test(amount) || BigInt(amount) <= 0n) {
    throw new Error("The staking amount changed.")
  }
  return BigInt(amount)
}

function requiredAddress(address?: Address): Address {
  if (!address) throw new Error("The staking recipient changed.")
  return getAddress(address)
}
