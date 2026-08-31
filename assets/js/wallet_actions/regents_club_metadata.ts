import {encodeFunctionData, getAddress, type Abi, type Address, type Hash, type Hex} from "viem"

import manifestJson from "../../../contracts/base-mainnet.json"
import abiJson from "../../../contracts/abi/regents-club.json"
import {activeEthereumWallet, type EthereumProvider, type SelectedWallet} from "./connected_wallet"

const contract = manifestJson.contracts.regents_club
const abi = abiJson as Abi
const target = getAddress(contract.address)
const owner = getAddress(contract.onchain_constants.owner)
const calldata = encodeFunctionData({
  abi,
  functionName: "setBaseURI",
  args: [contract.onchain_constants.cutover_base_uri],
})

export type PreparedMetadataAction = {
  attempt_id: string
  action: "set_base_uri"
  chain_id: 8453
  to: Address
  value: "0"
  data: Hex
  expected_signer: Address
  prepared_at: string
  expires_at: string
  risk_copy: string
  metadata: {
    anchor_block_number: number
    anchor_block_hash: Hash
    current_base_uri: string
    gas_estimate: string
    runtime_keccak256: Hash
  }
}

export type MetadataAttempt = Readonly<{
  attemptId: string
  action: "set_base_uri"
  signer: Address
  provider: EthereumProvider
}>

export class MetadataExecutionFailure extends Error {
  constructor(readonly kind: "cancelled" | "refused" | "submission_unknown") {
    super(kind)
  }
}

const consumed = new WeakSet<object>()

export async function beginMetadataAttempt(
  attemptId: string,
  wallet: SelectedWallet,
  selected: () => SelectedWallet | null = activeEthereumWallet,
): Promise<MetadataAttempt> {
  const attempt = Object.freeze({
    attemptId,
    action: "set_base_uri" as const,
    signer: getAddress(wallet.address),
    provider: wallet.provider,
  })
  if (attempt.signer !== owner) throw refused()
  await verifyProvider(attempt, selected)
  return attempt
}

export async function executePreparedMetadataAction(
  attempt: MetadataAttempt,
  envelope: PreparedMetadataAction,
  selected: () => SelectedWallet | null = activeEthereumWallet,
): Promise<Hash> {
  if (consumed.has(attempt)) throw refused()
  assertEnvelope(attempt, envelope)
  await verifyProvider(attempt, selected)

  // Consume before opening the wallet. Duplicate LiveView responses cannot
  // cause a second send for the same browser attempt.
  consumed.add(attempt)

  try {
    const result = await attempt.provider.request({
      method: "eth_sendTransaction",
      params: [{from: owner, to: target, data: calldata, value: "0x0"}],
    })
    if (!validHash(result)) throw unknown()
    return result
  } catch (error) {
    if (error instanceof MetadataExecutionFailure) throw error
    if (cancelled(error)) throw new MetadataExecutionFailure("cancelled")
    throw unknown()
  }
}

export function exactMetadataCalldata(): Hex {
  return calldata
}

async function verifyProvider(
  attempt: MetadataAttempt,
  selected: () => SelectedWallet | null,
): Promise<void> {
  verifySelected(attempt, selected())
  const chain = await attempt.provider.request({method: "eth_chainId"})
  if (typeof chain !== "string" || chain.toLowerCase() !== "0x2105") throw refused()
  const accounts = await attempt.provider.request({method: "eth_accounts"})
  verifySelected(attempt, selected())
  if (!Array.isArray(accounts) || typeof accounts[0] !== "string") throw refused()
  if (getAddress(accounts[0]) !== attempt.signer) throw refused()
}

function verifySelected(attempt: MetadataAttempt, wallet: SelectedWallet | null): void {
  if (!wallet || wallet.provider !== attempt.provider || getAddress(wallet.address) !== attempt.signer) {
    throw refused()
  }
}

function assertEnvelope(attempt: MetadataAttempt, envelope: PreparedMetadataAction): void {
  if (
    envelope.attempt_id !== attempt.attemptId ||
    envelope.action !== attempt.action ||
    envelope.chain_id !== 8453 ||
    getAddress(envelope.to) !== target ||
    envelope.value !== "0" ||
    envelope.data.toLowerCase() !== calldata.toLowerCase() ||
    getAddress(envelope.expected_signer) !== attempt.signer ||
    !Number.isSafeInteger(envelope.metadata.anchor_block_number) ||
    envelope.metadata.anchor_block_number < 0 ||
    !validHash(envelope.metadata.anchor_block_hash) ||
    !Number.isFinite(Date.parse(envelope.expires_at)) ||
    Date.parse(envelope.expires_at) <= Date.now()
  ) {
    throw refused()
  }
}

function validHash(value: unknown): value is Hash {
  return typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)
}

function cancelled(error: unknown): boolean {
  return Boolean(error && typeof error === "object" && "code" in error && (error as {code: unknown}).code === 4001)
}

function refused(): MetadataExecutionFailure {
  return new MetadataExecutionFailure("refused")
}

function unknown(): MetadataExecutionFailure {
  return new MetadataExecutionFailure("submission_unknown")
}
