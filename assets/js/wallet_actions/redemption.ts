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
import redeemerAbiJson from "../../../contracts/abi/animata-redeemer.json"
import {
  activeEthereumWallet,
  type EthereumProvider,
  type SelectedWallet,
} from "./connected_wallet"

type Manifest = {
  contracts: {
    animata_redeemer: {
      address: string
      onchain_constants: {
        animata_i: string
        animata_ii: string
        result_collection: string
        usdc: string
        usdc_price_atomic: string
        max_source_token_id: number
      }
      prepared_actions: Array<{id: string}>
    }
  }
}

const manifest = (chainManifest as Manifest).contracts.animata_redeemer
const REDEEMER = getAddress(manifest.address)
const ANIMATA_I = getAddress(manifest.onchain_constants.animata_i)
const ANIMATA_II = getAddress(manifest.onchain_constants.animata_ii)
const RESULT_COLLECTION = getAddress(manifest.onchain_constants.result_collection)
const USDC = getAddress(manifest.onchain_constants.usdc)
const PRICE = BigInt(manifest.onchain_constants.usdc_price_atomic)
const MAX_TOKEN_ID = BigInt(manifest.onchain_constants.max_source_token_id)
const eligibleCollections = new Set<Address>([ANIMATA_I, ANIMATA_II])
const actionIds = new Set(manifest.prepared_actions.map(action => action.id))
const redeemerAbi = redeemerAbiJson as Abi
const erc20ApprovalAbi = parseAbi(["function approve(address spender,uint256 amount)"])
const erc721ApprovalAbi = parseAbi(["function setApprovalForAll(address operator,bool approved)"])
const observationRequestTimeoutMs = 4_000
const observationOffsetsSeconds = [
  ...Array.from({length: 15}, (_, index) => (index + 1) * 2),
  ...Array.from({length: 9}, (_, index) => (index + 4) * 10),
]

export type RedemptionAction =
  | "approve_nft_collection"
  | "approve_exact_usdc"
  | "redeem"
  | "claim"

export type PreparedRedemptionAction = {
  action_id: string
  idempotency_key: string
  confirmation_token: string
  resource: "animata_redemption"
  action: RedemptionAction
  chain_id: 8453
  to: Address
  value: "0"
  data: Hex
  expected_signer: Address
  prepared_at: string
  expires_at: string
  risk_copy: string
  arguments: {
    collection?: Address
    token_id?: number
    operator?: Address
    approved?: boolean
    spender?: Address
    amount_atomic?: string
    mode?: "exact"
  }
}

export type RedemptionClients = {
  addresses(): Promise<Address[]>
  chainId(): Promise<number>
  switchToBase(): Promise<void>
  simulate(request: {account: Address; to: Address; data: Hex; value: bigint}): Promise<void>
  send(request: {account: Address; to: Address; data: Hex; value: bigint}): Promise<Hash>
}

export type SubmittedRedemptionTransaction = Readonly<{
  actionId: string
  action: RedemptionAction
  provider: EthereumProvider
  chainId: 8453
  signer: Address
  transaction: Readonly<{from: Address; to: Address; data: Hex; value: "0x0"}>
  hash: Hash
}>

export type ObservedRedemptionResult = "success" | "reverted" | "delayed" | "unavailable"

export type RedemptionRuntime = {
  alive(): boolean
  registerCancellation(cancel: () => void): () => void
}

const deadObservations = new WeakSet<object>()
class ObservationTimeout extends Error {}
class DeadObservation extends Error {
  constructor() {
    super("redemption observation ended")
    deadObservations.add(this)
  }
}

export type CurrentRedemptionWallet = () => SelectedWallet | null

export function clientsForRedemption(provider: EthereumProvider): RedemptionClients {
  const transport = custom(provider)
  const publicClient = createPublicClient({chain: base, transport})
  const walletClient = createWalletClient({chain: base, transport})

  return {
    addresses: () => walletClient.getAddresses(),
    chainId: () => walletClient.getChainId(),
    switchToBase: async () => {
      await walletClient.switchChain({id: base.id})
    },
    simulate: async request => {
      await publicClient.call(request)
    },
    send: request => walletClient.sendTransaction(request),
  }
}

export async function executePreparedRedemptionAction(
  envelope: PreparedRedemptionAction,
  provider: EthereumProvider,
  clients: RedemptionClients = clientsForRedemption(provider),
  currentWallet: CurrentRedemptionWallet = activeEthereumWallet,
): Promise<SubmittedRedemptionTransaction> {
  assertRedemptionEnvelope(envelope)
  assertActiveWallet(envelope.expected_signer, provider, currentWallet)

  let chainId = await clients.chainId()
  if (chainId !== base.id) {
    await clients.switchToBase()
    chainId = await clients.chainId()
  }
  if (chainId !== base.id) throw new Error("Switch to Base before continuing.")

  const account = await currentAccount(envelope.expected_signer, provider, clients, currentWallet)

  const transaction = {account, to: getAddress(envelope.to), data: envelope.data, value: 0n}
  await clients.simulate(transaction)
  const hash = await sendWithCurrentWallet(envelope, provider, clients, currentWallet, transaction)
  if (!validHash(hash)) throw new Error("The wallet did not return a transaction hash.")

  return Object.freeze({
    actionId: envelope.action_id,
    action: envelope.action,
    provider,
    chainId: base.id,
    signer: account,
    transaction: Object.freeze({
      from: account,
      to: transaction.to,
      data: transaction.data,
      value: "0x0",
    }),
    hash,
  })
}

async function currentAccount(
  expectedSigner: Address,
  provider: EthereumProvider,
  clients: RedemptionClients,
  currentWallet: CurrentRedemptionWallet,
): Promise<Address> {
  assertActiveWallet(expectedSigner, provider, currentWallet)
  const [account] = await clients.addresses()
  assertActiveWallet(expectedSigner, provider, currentWallet)

  if (!account || getAddress(account) !== getAddress(expectedSigner)) {
    throw new Error("Use the connected wallet shown on this account.")
  }

  return getAddress(account)
}

async function sendWithCurrentWallet(
  envelope: PreparedRedemptionAction,
  provider: EthereumProvider,
  clients: RedemptionClients,
  currentWallet: CurrentRedemptionWallet,
  transaction: {to: Address; data: Hex; value: bigint},
): Promise<Hash> {
  assertActiveWallet(envelope.expected_signer, provider, currentWallet)
  if (await clients.chainId() !== base.id) throw new Error("Switch to Base before continuing.")

  const account = await currentAccount(
    envelope.expected_signer,
    provider,
    clients,
    currentWallet,
  )

  assertActiveWallet(envelope.expected_signer, provider, currentWallet)
  return clients.send({...transaction, account})
}

export function observeRedemptionTransaction(
  submitted: SubmittedRedemptionTransaction,
  runtime: RedemptionRuntime,
  settle: (result: ObservedRedemptionResult) => void,
): void {
  const returnedAt = performance.now()
  let settled = false
  const observationCancellations = new Set<() => void>()
  const observationRuntime: RedemptionRuntime = {
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

  const finish = (result: ObservedRedemptionResult): void => {
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
        if (!isDeadObservation(error)) finish("unavailable")
      }
    })
  }
}

async function sampleReceipt(
  submitted: SubmittedRedemptionTransaction,
  runtime: RedemptionRuntime,
): Promise<ObservedRedemptionResult | "pending"> {
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
  runtime: RedemptionRuntime,
): Promise<unknown> {
  const before = await rawRequest(provider, {method: "eth_chainId"}, runtime)
  if (!baseChain(before)) throw new Error("wrong chain")
  const result = await rawRequest(provider, {method, params}, runtime)
  const after = await rawRequest(provider, {method: "eth_chainId"}, runtime)
  if (!baseChain(after)) throw new Error("wrong chain")
  return result
}

function rawRequest(
  provider: EthereumProvider,
  args: {method: string; params?: unknown[]},
  runtime: RedemptionRuntime,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    if (!runtime.alive()) {
      reject(new DeadObservation())
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
    const timer = globalThis.setTimeout(
      () => finish(() => reject(new ObservationTimeout())),
      observationRequestTimeoutMs,
    )
    unregister = runtime.registerCancellation(() => finish(() => reject(new DeadObservation())))

    try {
      const request = provider.request(args)
      request.then(
        value => finish(() => (runtime.alive() ? resolve(value) : reject(new DeadObservation()))),
        error => finish(() => reject(error)),
      )
    } catch {
      finish(() => reject(new Error("provider request failed")))
    }
  })
}

function schedule(runtime: RedemptionRuntime, delay: number, run: () => Promise<void>): void {
  let unregister = (): void => undefined
  const timer = globalThis.setTimeout(() => {
    unregister()
    if (runtime.alive()) void run()
  }, delay)
  unregister = runtime.registerCancellation(() => clearTimeout(timer))
}

function transactionIdentity(
  value: unknown,
  expected: SubmittedRedemptionTransaction,
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
  expected: SubmittedRedemptionTransaction,
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
  hash: Hash,
): boolean {
  if (!record(value) || !Array.isArray(value.transactions)) return false
  return (
    sameHash(value.hash, identity.blockHash) &&
    validQuantity(value.number) &&
    BigInt(value.number) === BigInt(identity.blockNumber) &&
    value.transactions.some(transaction => sameHash(transaction, hash))
  )
}

function validHash(value: unknown): value is Hash {
  return typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)
}

function validQuantity(value: unknown): value is string {
  return typeof value === "string" && /^0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)$/.test(value)
}

function zeroQuantity(value: unknown): boolean {
  return validQuantity(value) && BigInt(value) === 0n
}

function baseChain(value: unknown): boolean {
  return validQuantity(value) && BigInt(value) === BigInt(base.id)
}

function sameAddress(value: unknown, expected: Address): boolean {
  if (typeof value !== "string") return false
  try {
    return getAddress(value) === expected
  } catch {
    return false
  }
}

function sameHash(value: unknown, expected: Hash): boolean {
  return validHash(value) && value.toLowerCase() === expected.toLowerCase()
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function isDeadObservation(error: unknown): boolean {
  return typeof error === "object" && error !== null && deadObservations.has(error)
}

function assertActiveWallet(
  expectedSigner: Address,
  provider: EthereumProvider,
  currentWallet: CurrentRedemptionWallet,
): void {
  const active = currentWallet()
  if (
    !active ||
    active.provider !== provider ||
    getAddress(active.address) !== getAddress(expectedSigner)
  ) {
    throw new Error("Use the connected wallet shown on this account.")
  }
}

export function assertRedemptionEnvelope(envelope: PreparedRedemptionAction): void {
  if (envelope.chain_id !== base.id) throw new Error("This action is not for Base.")
  if (envelope.value !== "0") throw new Error("This action cannot send native currency.")
  if (envelope.resource !== "animata_redemption" || !actionIds.has(envelope.action)) {
    throw new Error("The redemption action is invalid.")
  }
  if (!envelope.action_id || envelope.idempotency_key !== envelope.action_id || !envelope.confirmation_token) {
    throw new Error("The redemption action is incomplete.")
  }
  const expiry = Date.parse(envelope.expires_at)
  if (!Number.isFinite(expiry) || expiry <= Date.now()) {
    throw new Error("This action expired. Prepare it again.")
  }

  const expectedData = encodeAction(envelope)
  if (envelope.data.toLowerCase() !== expectedData.toLowerCase()) {
    throw new Error("The redemption action data changed.")
  }
}

function encodeAction(envelope: PreparedRedemptionAction): Hex {
  switch (envelope.action) {
    case "approve_nft_collection": {
      const collection = requiredCollection(envelope.arguments.collection)
      if (getAddress(envelope.to) !== collection || getAddress(envelope.arguments.operator!) !== REDEEMER || envelope.arguments.approved !== true) {
        throw new Error("The NFT approval changed.")
      }
      return encodeFunctionData({
        abi: erc721ApprovalAbi,
        functionName: "setApprovalForAll",
        args: [REDEEMER, true],
      })
    }
    case "approve_exact_usdc": {
      if (
        getAddress(envelope.to) !== USDC ||
        getAddress(envelope.arguments.spender!) !== REDEEMER ||
        envelope.arguments.amount_atomic !== PRICE.toString() ||
        envelope.arguments.mode !== "exact"
      ) {
        throw new Error("The USDC approval changed.")
      }
      return encodeFunctionData({
        abi: erc20ApprovalAbi,
        functionName: "approve",
        args: [REDEEMER, PRICE],
      })
    }
    case "redeem": {
      if (getAddress(envelope.to) !== REDEEMER) throw new Error("The redeemer changed.")
      const collection = requiredCollection(envelope.arguments.collection)
      const tokenId = BigInt(envelope.arguments.token_id ?? 0)
      if (tokenId < 1n || tokenId > MAX_TOKEN_ID) throw new Error("The token ID changed.")
      return encodeFunctionData({
        abi: redeemerAbi,
        functionName: "redeem",
        args: [collection, tokenId],
      })
    }
    case "claim":
      if (getAddress(envelope.to) !== REDEEMER) throw new Error("The redeemer changed.")
      return encodeFunctionData({abi: redeemerAbi, functionName: "claim"})
  }
}

function requiredCollection(value?: Address): Address {
  if (!value) throw new Error("The Animata collection changed.")
  const collection = getAddress(value)
  if (collection === RESULT_COLLECTION || !eligibleCollections.has(collection)) {
    throw new Error("The Animata collection changed.")
  }
  return collection
}
