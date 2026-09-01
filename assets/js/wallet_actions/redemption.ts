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
const chainRequestTimeoutMs = 5_000
const switchRequestTimeoutMs = 15_000
const simulationRequestTimeoutMs = 15_000
const sendRequestTimeoutMs = 120_000

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

export type RedemptionRuntime = {
  alive(): boolean
  hostAlive(): boolean
  registerCancellation(cancel: () => void): () => void
}

export type RedemptionFailureKind = "canceled" | "submission_unknown" | "refused"

export class RedemptionExecutionFailure extends Error {
  constructor(readonly kind: RedemptionFailureKind, readonly displayMessage: string) {
    super(displayMessage)
  }
}

const deadGenerations = new WeakSet<object>()
const walletDrifts = new WeakSet<object>()
class RequestTimeout extends Error {}

class DeadGeneration extends Error {
  constructor() {
    super("redemption hook generation ended")
    deadGenerations.add(this)
  }
}

class WalletDrift extends Error {
  constructor() {
    super("redemption wallet changed")
    walletDrifts.add(this)
  }
}

const alwaysAliveRuntime: RedemptionRuntime = {
  alive: () => true,
  hostAlive: () => true,
  registerCancellation: () => () => undefined,
}

export type CurrentRedemptionWallet = () => SelectedWallet | null

export function clientsForRedemption(provider: EthereumProvider): RedemptionClients {
  const transport = custom(provider, {retryCount: 0})
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
    send: async request => {
      const response = await provider.request({
        method: "eth_sendTransaction",
        params: [{
          from: getAddress(request.account),
          to: getAddress(request.to),
          data: request.data,
          value: "0x0",
        }],
      })
      if (!validHash(response)) throw new Error("The wallet did not return a transaction hash.")
      return response
    },
  }
}

export async function executePreparedRedemptionAction(
  envelope: PreparedRedemptionAction,
  provider: EthereumProvider,
  clients: RedemptionClients = clientsForRedemption(provider),
  currentWallet: CurrentRedemptionWallet = activeEthereumWallet,
  runtime: RedemptionRuntime = alwaysAliveRuntime,
  onWalletRequestStarted: () => void = () => undefined,
  onSubmissionUnknown: () => void = () => undefined,
): Promise<SubmittedRedemptionTransaction> {
  let walletRequestStarted = false

  try {
    assertRedemptionEnvelope(envelope)
    assertActiveWallet(envelope.expected_signer, provider, currentWallet)

    let chainId = await boundRequest(() => clients.chainId(), chainRequestTimeoutMs, runtime)
    if (chainId !== base.id) {
      await boundRequest(() => clients.switchToBase(), switchRequestTimeoutMs, runtime)
      chainId = await boundRequest(() => clients.chainId(), chainRequestTimeoutMs, runtime)
    }
    if (chainId !== base.id) throw new Error("Switch to Base before continuing.")

    const account = await currentAccount(envelope.expected_signer, provider, clients, currentWallet, runtime)

    const transaction = {account, to: getAddress(envelope.to), data: envelope.data, value: 0n}
    await boundRequest(() => clients.simulate(transaction), simulationRequestTimeoutMs, runtime)
    const hash = await sendWithCurrentWallet(
      envelope,
      provider,
      clients,
      currentWallet,
      transaction,
      runtime,
      () => {
        walletRequestStarted = true
        onWalletRequestStarted()
      },
      onSubmissionUnknown,
    )
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
  } catch (error) {
    if (isDeadGeneration(error) || isRedemptionWalletDrift(error)) throw error
    if (userRejected(error)) {
      throw new RedemptionExecutionFailure("canceled", "Request canceled.")
    }
    if (walletRequestStarted) {
      throw new RedemptionExecutionFailure(
        "submission_unknown",
        "The submission outcome is unknown.",
      )
    }
    throw new RedemptionExecutionFailure("refused", "Switch to Base before continuing.")
  }
}

async function currentAccount(
  expectedSigner: Address,
  provider: EthereumProvider,
  clients: RedemptionClients,
  currentWallet: CurrentRedemptionWallet,
  runtime: RedemptionRuntime,
): Promise<Address> {
  assertActiveWallet(expectedSigner, provider, currentWallet)
  const [account] = await boundRequest(() => clients.addresses(), chainRequestTimeoutMs, runtime)
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
  runtime: RedemptionRuntime,
  onHandoff: () => void,
  onHandoffTimeout?: () => void,
): Promise<Hash> {
  assertActiveWallet(envelope.expected_signer, provider, currentWallet)
  if (await boundRequest(() => clients.chainId(), chainRequestTimeoutMs, runtime) !== base.id) {
    throw new Error("Switch to Base before continuing.")
  }

  const account = await currentAccount(
    envelope.expected_signer,
    provider,
    clients,
    currentWallet,
    runtime,
  )

  assertActiveWallet(envelope.expected_signer, provider, currentWallet)
  return boundRequest(
    () => clients.send({...transaction, account}),
    sendRequestTimeoutMs,
    runtime,
    onHandoff,
    onHandoffTimeout,
  )
}

function boundRequest<T>(
  operation: () => Promise<T>,
  timeoutMs: number,
  runtime: RedemptionRuntime,
  onHandoff?: () => void,
  onHandoffTimeout?: () => void,
): Promise<T> {
  return new Promise((resolve, reject) => {
    if (!runtime.alive()) {
      reject(new DeadGeneration())
      return
    }

    let active = true
    let handedToWallet = false
    let unregister = (): void => undefined
    const finish = (result: () => void): void => {
      if (!active) return
      active = false
      clearTimeout(timer)
      unregister()
      result()
    }
    const timer = globalThis.setTimeout(() => {
      if (handedToWallet && onHandoffTimeout && runtime.hostAlive()) {
        onHandoffTimeout()
        return
      }
      finish(() => reject(new RequestTimeout()))
    }, timeoutMs)
    unregister = runtime.registerCancellation(() => {
      if (handedToWallet && runtime.hostAlive()) return
      finish(() => reject(new DeadGeneration()))
    })
    if (!active) return

    try {
      if (onHandoff) {
        handedToWallet = true
        onHandoff()
      }
      operation().then(
        value => finish(() => (
          runtime.alive() || (handedToWallet && runtime.hostAlive())
            ? resolve(value)
            : reject(new DeadGeneration())
        )),
        error => finish(() => reject(error)),
      )
    } catch (error) {
      finish(() => reject(error))
    }
  })
}

function validHash(value: unknown): value is Hash {
  return typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)
}

function isDeadGeneration(error: unknown): boolean {
  return typeof error === "object" && error !== null && deadGenerations.has(error)
}

export function isRedemptionWalletDrift(error: unknown): boolean {
  return typeof error === "object" && error !== null && walletDrifts.has(error)
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
    throw new WalletDrift()
  }
}

function userRejected(error: unknown): boolean {
  if ((typeof error !== "object" || error === null) && typeof error !== "function") return false
  try {
    return Reflect.get(error, "code") === 4001
  } catch {
    return false
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
