import {
  encodeFunctionData,
  formatUnits,
  getAddress,
  parseAbi,
  parseUnits,
  type Abi,
  type Address,
  type Hex,
} from "viem"
import {base} from "viem/chains"

import chainManifest from "../../../contracts/base-mainnet.json"
import stakingAbiJson from "../../../contracts/abi/regent-revenue-staking.json"
import {
  activeEthereumWallet,
  type EthereumProvider,
  type SelectedWallet,
} from "./connected_wallet"

type ManifestAction = {id: string; value: string}
type Manifest = {
  chain: {id: number}
  contracts: {
    regent_revenue_staking: {
      address: string
      onchain_constants: {stake_token: string}
      prepared_actions: ManifestAction[]
    }
  }
}

const manifest = chainManifest as Manifest
const stakingManifest = manifest.contracts.regent_revenue_staking
const STAKING = getAddress(stakingManifest.address)
const STAKE_TOKEN = getAddress(stakingManifest.onchain_constants.stake_token)
const stakingAbi = stakingAbiJson as Abi
const approvalAbi = parseAbi(["function approve(address spender,uint256 amount)"])
const actionIds = new Set(stakingManifest.prepared_actions.map(action => action.id))
const zeroValueActions = new Set(
  stakingManifest.prepared_actions.filter(action => action.value === "0").map(action => action.id),
)
const maxUint256 = (1n << 256n) - 1n

const chainTimeoutMs = 5_000
const switchTimeoutMs = 15_000
const walletTimeoutMs = 120_000
const observationRequestTimeoutMs = 4_000
const observationOffsetsSeconds = [
  ...Array.from({length: 15}, (_, index) => (index + 1) * 2),
  ...Array.from({length: 9}, (_, index) => (index + 4) * 10),
]

export type StakingAction =
  | "stake"
  | "unstake"
  | "claim_usdc"
  | "claim_regent"
  | "claim_and_restake_regent"

const supportedActions = new Set<StakingAction>([
  "stake",
  "unstake",
  "claim_usdc",
  "claim_regent",
  "claim_and_restake_regent",
])

export type StakingTransactionRole = "approval" | "action"
export type StakingTimingPhase =
  | "click_to_local_ready"
  | "chain_check"
  | "chain_switch"
  | "wallet_handoff"
  | "provider_response"

export type StakingTiming = {
  trace_id: string
  action: StakingAction
  role: StakingTransactionRole
  phase: StakingTimingPhase
  milliseconds: number
}

export type StakingRuntime = {
  alive(): boolean
  registerCancellation(cancel: () => void): () => void
}

export type RenderedStakingClick = {
  action: string
  amount: string
  allowanceAtomic: string
  chainId: string
  expectedSigner: string
}

export type StakingTransaction = Readonly<{
  from: Address
  to: Address
  data: Hex
  value: "0x0"
}>

export type PreparedStakingClick = Readonly<{
  actionId: string
  traceId: string
  action: StakingAction
  provider: EthereumProvider
  signer: Address
  approval: StakingTransaction | null
  transaction: StakingTransaction
}>

export type SubmittedStakingTransaction = Readonly<{
  actionId: string
  traceId: string
  action: StakingAction
  role: StakingTransactionRole
  provider: EthereumProvider
  chainId: 8453
  signer: Address
  transaction: StakingTransaction
  hash: `0x${string}`
}>

export type ImmediateStakingResult = Readonly<{
  actionId: string
  action: StakingAction
  role: StakingTransactionRole
  kind: "canceled" | "submission_unknown" | "refused"
  message: string
}>

export type ObservedStakingResult = "success" | "reverted" | "delayed" | "unavailable"

export type StakingExecutionCallbacks = {
  claimRole(actionId: string, role: StakingTransactionRole): boolean
  timing(event: StakingTiming): void
  walletRequestStarted(actionId: string, role: StakingTransactionRole): void
  immediate(result: ImmediateStakingResult): void
  submitted(transaction: SubmittedStakingTransaction): void
}

export class StakingLocalRefusal extends Error {
  constructor(readonly displayMessage: string) {
    super("staking action refused")
  }
}

class RequestTimeout extends Error {}
class DeadGeneration extends Error {}

export function prepareStakingClick(
  rendered: RenderedStakingClick,
  selected: SelectedWallet | null,
  identity: {actionId: string; traceId: string} = {
    actionId: crypto.randomUUID(),
    traceId: crypto.randomUUID(),
  },
): PreparedStakingClick {
  const action = requiredAction(rendered.action)
  if (manifest.chain.id !== base.id || rendered.chainId !== String(base.id)) {
    throw new StakingLocalRefusal("This staking snapshot is not for Base. Refresh and try again.")
  }
  if (!zeroValueActions.has(action)) {
    throw new StakingLocalRefusal("That staking action is unavailable. Refresh and try again.")
  }

  const signer = normalizedAddress(rendered.expectedSigner)
  assertSelectedWallet(selected, signer)
  const amount = action === "stake" || action === "unstake" ? exactAmount(rendered.amount) : null
  const data = exactActionData(action, signer, amount)
  const transaction = exactTransaction(signer, STAKING, data)
  assertExactTransaction(transaction, STAKING, data)

  let approval: StakingTransaction | null = null
  if (action === "stake") {
    const allowance = exactUint(rendered.allowanceAtomic)
    if (allowance < requiredAmount(amount)) {
      const approvalData = encodeFunctionData({
        abi: approvalAbi,
        functionName: "approve",
        args: [STAKING, requiredAmount(amount)],
      })
      approval = exactTransaction(signer, STAKE_TOKEN, approvalData)
      assertExactTransaction(approval, STAKE_TOKEN, approvalData)
    }
  }

  return Object.freeze({
    actionId: identity.actionId,
    traceId: identity.traceId,
    action,
    provider: selected!.provider,
    signer,
    approval,
    transaction,
  })
}

export async function executeStakingClick(
  click: PreparedStakingClick,
  callbacks: StakingExecutionCallbacks,
  runtime: StakingRuntime,
  currentWallet: () => SelectedWallet | null = activeEthereumWallet,
): Promise<void> {
  if (click.approval) {
    const approval = await sendRole(click, "approval", click.approval, callbacks, runtime, currentWallet)
    if (!approval) return
  }
  await sendRole(click, "action", click.transaction, callbacks, runtime, currentWallet)
}

export function observeStakingTransaction(
  submitted: SubmittedStakingTransaction,
  runtime: StakingRuntime,
  settle: (result: ObservedStakingResult) => void,
): void {
  const returnedAt = performance.now()
  let settled = false
  const observationCancellations = new Set<() => void>()
  const observationRuntime: StakingRuntime = {
    alive: () => !settled && runtime.alive(),
    registerCancellation: cancel => {
      if (settled || !runtime.alive()) {
        cancel()
        return () => undefined
      }

      let active = true
      let unregisterParent = (): void => undefined
      const cancelOnce = (): void => {
        if (!active) return
        active = false
        observationCancellations.delete(cancelOnce)
        unregisterParent()
        cancel()
      }
      observationCancellations.add(cancelOnce)
      unregisterParent = runtime.registerCancellation(cancelOnce)
      return () => {
        if (!active) return
        active = false
        observationCancellations.delete(cancelOnce)
        unregisterParent()
      }
    },
  }

  const finish = (result: ObservedStakingResult): void => {
    if (settled || !runtime.alive()) return
    settled = true
    for (const cancel of [...observationCancellations]) cancel()
    observationCancellations.clear()
    settle(result)
  }

  for (const offset of observationOffsetsSeconds) {
    schedule(observationRuntime, Math.max(0, returnedAt + offset * 1_000 - performance.now()), async () => {
      if (settled) return
      try {
        const result = await sampleReceipt(submitted, observationRuntime)
        if (result === "success" || result === "reverted" || result === "unavailable") {
          finish(result)
        } else if (offset === 120) {
          finish("delayed")
        }
      } catch (error) {
        if (!(error instanceof DeadGeneration)) finish("unavailable")
      }
    })
  }
}

async function sendRole(
  click: PreparedStakingClick,
  role: StakingTransactionRole,
  transaction: StakingTransaction,
  callbacks: StakingExecutionCallbacks,
  runtime: StakingRuntime,
  currentWallet: () => SelectedWallet | null,
): Promise<SubmittedStakingTransaction | null> {
  if (!callbacks.claimRole(click.actionId, role) || !runtime.alive()) return null

  let walletRequestStarted = false
  try {
    assertSelectedWallet(currentWallet(), click.signer, click.provider)
    await ensureBase(click, role, callbacks, runtime)
    assertSelectedWallet(currentWallet(), click.signer, click.provider)

    const requestStarted = performance.now()
    callbacks.walletRequestStarted(click.actionId, role)
    walletRequestStarted = true
    const pending = rawRequest(
      click.provider,
      {method: "eth_sendTransaction", params: [transaction]},
      walletTimeoutMs,
      runtime,
      () =>
        callbacks.timing(
          timing(click, role, "wallet_handoff", performance.now() - requestStarted),
        ),
    )
    let response: unknown
    try {
      response = await pending
    } finally {
      if (runtime.alive()) {
        callbacks.timing(timing(click, role, "provider_response", performance.now() - requestStarted))
      }
    }

    if (!validHash(response)) {
      callbacks.immediate(immediate(click, role, "submission_unknown"))
      return null
    }

    const submitted = Object.freeze({
      actionId: click.actionId,
      traceId: click.traceId,
      action: click.action,
      role,
      provider: click.provider,
      chainId: base.id,
      signer: click.signer,
      transaction,
      hash: response,
    })
    callbacks.submitted(submitted)
    return submitted
  } catch (error) {
    if (error instanceof DeadGeneration) return null
    const result = userRejected(error)
      ? immediate(click, role, "canceled")
      : walletRequestStarted
        ? immediate(click, role, "submission_unknown")
        : immediate(click, role, "refused", preSendRefusal(error))
    callbacks.immediate(result)
    return null
  }
}

async function ensureBase(
  click: PreparedStakingClick,
  role: StakingTransactionRole,
  callbacks: StakingExecutionCallbacks,
  runtime: StakingRuntime,
): Promise<void> {
  const checkedAt = performance.now()
  let chainId: unknown
  try {
    chainId = await rawRequest(click.provider, {method: "eth_chainId"}, chainTimeoutMs, runtime)
  } finally {
    if (runtime.alive()) {
      callbacks.timing(timing(click, role, "chain_check", performance.now() - checkedAt))
    }
  }
  if (baseChain(chainId)) return
  if (!validChainId(chainId)) throw new Error("invalid chain")

  const switchedAt = performance.now()
  try {
    await rawRequest(
      click.provider,
      {method: "wallet_switchEthereumChain", params: [{chainId: "0x2105"}]},
      switchTimeoutMs,
      runtime,
    )
    chainId = await rawRequest(click.provider, {method: "eth_chainId"}, chainTimeoutMs, runtime)
    if (!baseChain(chainId)) throw new Error("wrong chain")
  } finally {
    if (runtime.alive()) {
      callbacks.timing(timing(click, role, "chain_switch", performance.now() - switchedAt))
    }
  }
}

async function sampleReceipt(
  submitted: SubmittedStakingTransaction,
  runtime: StakingRuntime,
): Promise<ObservedStakingResult | "pending"> {
  const transaction = await baseBoundRequest(
    submitted.provider,
    "eth_getTransactionByHash",
    [submitted.hash],
    runtime,
  )
  const transactionBlock =
    transaction === null ? null : transactionIdentity(transaction, submitted)
  if (transaction !== null && !transactionBlock) return "unavailable"

  const receipt = await baseBoundRequest(
    submitted.provider,
    "eth_getTransactionReceipt",
    [submitted.hash],
    runtime,
  )
  if (receipt === null) return "pending"
  if (!transactionBlock || transactionBlock.state !== "included") return "unavailable"
  const identity = receiptIdentity(receipt, submitted, transactionBlock)
  if (!identity) return "unavailable"

  const block = await baseBoundRequest(
    submitted.provider,
    "eth_getBlockByHash",
    [identity.blockHash, false],
    runtime,
  )
  if (!validBlock(block, identity, submitted.hash)) return "unavailable"
  return identity.status
}

async function baseBoundRequest(
  provider: EthereumProvider,
  method: string,
  params: unknown[],
  runtime: StakingRuntime,
): Promise<unknown> {
  const before = await rawRequest(provider, {method: "eth_chainId"}, observationRequestTimeoutMs, runtime)
  if (!baseChain(before)) throw new Error("wrong chain")
  const result = await rawRequest(provider, {method, params}, observationRequestTimeoutMs, runtime)
  const after = await rawRequest(provider, {method: "eth_chainId"}, observationRequestTimeoutMs, runtime)
  if (!baseChain(after)) throw new Error("wrong chain")
  return result
}

function rawRequest(
  provider: EthereumProvider,
  args: {method: string; params?: unknown[]},
  timeoutMs: number,
  runtime: StakingRuntime,
  handedOff?: () => void,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    if (!runtime.alive()) {
      reject(new DeadGeneration())
      return
    }

    let active = true
    let unregister = (): void => undefined
    const finish = (result: () => void): void => {
      if (!active) return
      active = false
      clearTimeout(timer)
      unregister()
      result()
    }
    const timer = globalThis.setTimeout(() => finish(() => reject(new RequestTimeout())), timeoutMs)
    unregister = runtime.registerCancellation(() => finish(() => reject(new DeadGeneration())))

    try {
      handedOff?.()
      const request = provider.request(args)
      request.then(
        value => finish(() => (runtime.alive() ? resolve(value) : reject(new DeadGeneration()))),
        error => finish(() => reject(error)),
      )
    } catch {
      finish(() => reject(new Error("provider request failed")))
    }
  })
}

function schedule(runtime: StakingRuntime, delay: number, run: () => Promise<void>): void {
  let unregister = (): void => undefined
  const timer = globalThis.setTimeout(() => {
    unregister()
    if (runtime.alive()) void run()
  }, delay)
  unregister = runtime.registerCancellation(() => clearTimeout(timer))
}

function exactTransaction(signer: Address, to: Address, data: Hex): StakingTransaction {
  return Object.freeze({from: signer, to, data, value: "0x0"})
}

function exactActionData(action: StakingAction, signer: Address, amount: bigint | null): Hex {
  switch (action) {
    case "stake":
      return encodeFunctionData({abi: stakingAbi, functionName: "stake", args: [requiredAmount(amount), signer]})
    case "unstake":
      return encodeFunctionData({abi: stakingAbi, functionName: "unstake", args: [requiredAmount(amount), signer]})
    case "claim_usdc":
      return encodeFunctionData({abi: stakingAbi, functionName: "claimUSDC", args: [signer]})
    case "claim_regent":
      return encodeFunctionData({abi: stakingAbi, functionName: "claimRegent", args: [signer]})
    case "claim_and_restake_regent":
      return encodeFunctionData({abi: stakingAbi, functionName: "claimAndRestakeRegent"})
  }
}

function exactAmount(value: string): bigint {
  if (!/^\d+(?:\.\d{1,18})?$/.test(value)) {
    throw invalidAmount()
  }
  const [whole, fraction = ""] = value.split(".")
  const normalizedWhole = whole.replace(/^0+(?=\d)/, "")
  const normalizedFraction = fraction.replace(/0+$/, "")
  const normalized = normalizedFraction ? `${normalizedWhole}.${normalizedFraction}` : normalizedWhole
  const atomic = parseUnits(normalized, 18)
  if (atomic <= 0n || atomic > maxUint256 || formatUnits(atomic, 18) !== normalized) {
    throw invalidAmount()
  }
  return atomic
}

function invalidAmount(): StakingLocalRefusal {
  return new StakingLocalRefusal("Enter a positive REGENT amount with no more than 18 decimal places.")
}

function exactUint(value: string): bigint {
  if (!/^\d+$/.test(value)) {
    throw new StakingLocalRefusal("Refresh the staking snapshot and try again.")
  }
  const parsed = BigInt(value)
  if (parsed < 0n || parsed > maxUint256) {
    throw new StakingLocalRefusal("Refresh the staking snapshot and try again.")
  }
  return parsed
}

function requiredAction(action: string): StakingAction {
  if (!supportedActions.has(action as StakingAction) || !actionIds.has(action)) {
    throw new StakingLocalRefusal("That staking action is unavailable. Refresh and try again.")
  }
  return action as StakingAction
}

function requiredAmount(amount: bigint | null): bigint {
  if (amount === null) throw invalidAmount()
  return amount
}

function normalizedAddress(value: string): Address {
  try {
    return getAddress(value)
  } catch {
    throw new StakingLocalRefusal("Use the connected wallet shown on this account.")
  }
}

function assertSelectedWallet(
  selected: SelectedWallet | null,
  signer: Address,
  provider?: EthereumProvider,
): asserts selected is SelectedWallet {
  if (!selected || (provider && selected.provider !== provider) || normalizedAddress(selected.address) !== signer) {
    throw new StakingLocalRefusal("Use the connected wallet shown on this account.")
  }
}

function assertExactTransaction(transaction: StakingTransaction, destination: Address, data: Hex): void {
  if (
    transaction.from !== normalizedAddress(transaction.from) ||
    transaction.to !== destination ||
    transaction.value !== "0x0" ||
    transaction.data.toLowerCase() !== data.toLowerCase()
  ) {
    throw new StakingLocalRefusal("That staking action is unavailable. Refresh and try again.")
  }
}

function validHash(value: unknown): value is `0x${string}` {
  return typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)
}

function validChainId(value: unknown): value is string {
  return typeof value === "string" && /^0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)$/.test(value)
}

function baseChain(value: unknown): boolean {
  return validChainId(value) && BigInt(value) === BigInt(base.id)
}

function transactionIdentity(
  value: unknown,
  expected: SubmittedStakingTransaction,
):
  | {state: "pending"}
  | {state: "included"; blockHash: `0x${string}`; blockNumber: string}
  | null {
  if (!record(value)) return null
  const transaction = expected.transaction
  const exactTransaction =
    sameHash(value.hash, expected.hash) &&
    sameAddress(value.from, expected.signer) &&
    sameAddress(value.to, transaction.to) &&
    typeof value.input === "string" &&
    value.input.toLowerCase() === transaction.data.toLowerCase() &&
    zeroQuantity(value.value)
  if (!exactTransaction) return null
  if (value.blockHash === null && value.blockNumber === null) return {state: "pending"}
  if (validHash(value.blockHash) && validQuantity(value.blockNumber)) {
    return {state: "included", blockHash: value.blockHash, blockNumber: value.blockNumber}
  }
  return null
}

function receiptIdentity(
  value: unknown,
  expected: SubmittedStakingTransaction,
  transactionBlock: {state: "included"; blockHash: `0x${string}`; blockNumber: string},
): {status: "success" | "reverted"; blockHash: `0x${string}`; blockNumber: string} | null {
  if (!record(value)) return null
  const status = value.status === "0x1" ? "success" : value.status === "0x0" ? "reverted" : null
  if (
    !status ||
    !sameHash(value.transactionHash, expected.hash) ||
    !sameAddress(value.from, expected.signer) ||
    !sameAddress(value.to, expected.transaction.to) ||
    !validHash(value.blockHash) ||
    !validQuantity(value.blockNumber) ||
    !sameHash(value.blockHash, transactionBlock.blockHash) ||
    BigInt(value.blockNumber) !== BigInt(transactionBlock.blockNumber)
  ) {
    return null
  }
  return {status, blockHash: value.blockHash, blockNumber: value.blockNumber}
}

function validBlock(
  value: unknown,
  identity: {blockHash: `0x${string}`; blockNumber: string},
  hash: `0x${string}`,
): boolean {
  if (!record(value) || !Array.isArray(value.transactions)) return false
  return (
    sameHash(value.hash, identity.blockHash) &&
    validQuantity(value.number) &&
    BigInt(value.number) === BigInt(identity.blockNumber) &&
    value.transactions.some(transaction => sameHash(transaction, hash))
  )
}

function validQuantity(value: unknown): value is string {
  return typeof value === "string" && /^0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)$/.test(value)
}

function zeroQuantity(value: unknown): boolean {
  return validQuantity(value) && BigInt(value) === 0n
}

function sameAddress(value: unknown, expected: Address): boolean {
  if (typeof value !== "string") return false
  try {
    return getAddress(value) === expected
  } catch {
    return false
  }
}

function sameHash(value: unknown, expected: `0x${string}`): boolean {
  return validHash(value) && value.toLowerCase() === expected.toLowerCase()
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function userRejected(error: unknown): boolean {
  return record(error) && error.code === 4001
}

function immediate(
  click: PreparedStakingClick,
  role: StakingTransactionRole,
  kind: ImmediateStakingResult["kind"],
  refusedMessage?: string,
): ImmediateStakingResult {
  const message =
    kind === "canceled"
      ? "Request canceled."
      : kind === "refused"
        ? refusedMessage ?? "Switch to Base before continuing."
        : "The submission outcome is unknown."
  return Object.freeze({actionId: click.actionId, action: click.action, role, kind, message})
}

function preSendRefusal(error: unknown): string {
  return error instanceof StakingLocalRefusal
    ? error.displayMessage
    : "Switch to Base before continuing."
}

function timing(
  click: PreparedStakingClick,
  role: StakingTransactionRole,
  phase: StakingTimingPhase,
  elapsed: number,
): StakingTiming {
  return Object.freeze({
    trace_id: click.traceId,
    action: click.action,
    role,
    phase,
    milliseconds: Math.round(Math.max(0, elapsed) * 100) / 100,
  })
}
