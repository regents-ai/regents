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
import type {EthereumProvider} from "./connected_wallet"

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
  receipt(hash: Hash): Promise<{status: "success" | "reverted"}>
}

export class RedemptionExecutionError extends Error {
  constructor(
    readonly code: "action_reverted",
    readonly transactionHash: Hash,
    message: string,
  ) {
    super(message)
  }
}

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
    receipt: hash => publicClient.waitForTransactionReceipt({hash, timeout: 60_000}),
  }
}

export async function executePreparedRedemptionAction(
  envelope: PreparedRedemptionAction,
  provider: EthereumProvider,
  clients: RedemptionClients = clientsForRedemption(provider),
  onSubmitted: (hash: Hash) => void = () => undefined,
): Promise<Hash> {
  assertRedemptionEnvelope(envelope)

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

  const transaction = {account, to: getAddress(envelope.to), data: envelope.data, value: 0n}
  await clients.simulate(transaction)
  const hash = await clients.send(transaction)
  onSubmitted(hash)
  const receipt = await clients.receipt(hash)
  if (receipt.status !== "success") {
    throw new RedemptionExecutionError(
      "action_reverted",
      hash,
      "The redemption transaction was reverted.",
    )
  }
  return hash
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
