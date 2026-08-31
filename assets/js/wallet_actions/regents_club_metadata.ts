import {
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

import manifestJson from "../../../contracts/base-mainnet.json"
import abiJson from "../../../contracts/abi/regents-club.json"
import {activeEthereumWallet, type EthereumProvider, type SelectedWallet} from "./connected_wallet"

const contract = manifestJson.contracts.regents_club
const abi = abiJson as Abi
const target = getAddress(contract.address)
const owner = getAddress(contract.onchain_constants.owner)
const riskCopy =
  "Collection-wide metadata cutover for Regents Club tokens 1 through 1998. No prepared rollback exists."
const calldata = encodeFunctionData({
  abi,
  functionName: "setBaseURI",
  args: [contract.onchain_constants.cutover_base_uri],
})

export type PreparedMetadataAction = {
  action_id: string
  idempotency_key: string
  resource: "regents_club_metadata"
  confirmation_token: string
  action: "set_base_uri"
  chain_id: 8453
  to: Address
  value: "0"
  data: Hex
  expected_signer: Address
  prepared_at: string
  expires_at: string
  risk_copy: string
  arguments: {attempt_id: string; new_base_uri: string}
  metadata: {
    anchor_block_number: number
    anchor_block_hash: Hash
    current_base_uri: string
    boundary_token_uris: {first: string; last: string}
    total_supply: 1998
    erc4906_supported: true
    owner_simulation: "success"
    non_owner_simulation: "revert"
    gas_estimate: string
    runtime_keccak256: Hash
    calldata_keccak256: Hash
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
  verifySelected(attempt, selected())

  // Consume before any wallet-owned await. A duplicate LiveView response can
  // never produce a second request for this attempt.
  consumed.add(attempt)

  try {
    const client = createWalletClient({
      account: owner,
      chain: base,
      transport: custom(chainBoundProvider(attempt, selected)),
    })

    const result = await client.sendTransaction({
      account: owner,
      chain: base,
      to: target,
      data: calldata,
      value: 0n,
    })
    if (!validHash(result)) throw unknown()
    return result
  } catch (error) {
    const classified = classifiedFailure(error)
    if (classified) throw classified
    throw unknown()
  }
}

function chainBoundProvider(
  attempt: MetadataAttempt,
  selected: () => SelectedWallet | null,
): EthereumProvider {
  return {
    async request(args) {
      if (args.method === "eth_sendTransaction") {
        await verifyProvider(attempt, selected)
        verifySelected(attempt, selected())
        assertForwardedTransaction(attempt, args.params)
      }
      return attempt.provider.request(args)
    },
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
  const accounts = await attempt.provider.request({method: "eth_accounts"})
  verifySelected(attempt, selected())
  if (!Array.isArray(accounts) || typeof accounts[0] !== "string") throw refused()
  if (getAddress(accounts[0]) !== attempt.signer) throw refused()

  const chain = await attempt.provider.request({method: "eth_chainId"})
  if (typeof chain !== "string" || chain.toLowerCase() !== "0x2105") throw refused()
  verifySelected(attempt, selected())
}

function verifySelected(attempt: MetadataAttempt, wallet: SelectedWallet | null): void {
  if (!wallet || wallet.provider !== attempt.provider || getAddress(wallet.address) !== attempt.signer) {
    throw refused()
  }
}

function assertEnvelope(attempt: MetadataAttempt, envelope: PreparedMetadataAction): void {
  const preparedAt = Date.parse(envelope.prepared_at)
  const expiresAt = Date.parse(envelope.expires_at)
  const expected = contract.onchain_constants

  if (
    !nonempty(envelope.action_id) ||
    envelope.idempotency_key !== envelope.action_id ||
    !nonempty(envelope.confirmation_token) ||
    envelope.arguments.attempt_id !== attempt.attemptId ||
    envelope.resource !== "regents_club_metadata" ||
    envelope.action !== attempt.action ||
    envelope.chain_id !== 8453 ||
    !sameAddress(envelope.to, target) ||
    envelope.value !== "0" ||
    envelope.data.toLowerCase() !== calldata.toLowerCase() ||
    !sameAddress(envelope.expected_signer, attempt.signer) ||
    envelope.risk_copy !== riskCopy ||
    envelope.arguments.new_base_uri !== expected.cutover_base_uri ||
    envelope.metadata.current_base_uri !== expected.current_base_uri ||
    envelope.metadata.runtime_keccak256.toLowerCase() !== contract.runtime_code.keccak256.toLowerCase() ||
    envelope.metadata.calldata_keccak256.toLowerCase() !== expected.calldata_keccak256.toLowerCase() ||
    envelope.metadata.total_supply !== 1998 ||
    envelope.metadata.erc4906_supported !== true ||
    envelope.metadata.owner_simulation !== "success" ||
    envelope.metadata.non_owner_simulation !== "revert" ||
    envelope.metadata.boundary_token_uris.first !== `${expected.current_base_uri}1` ||
    envelope.metadata.boundary_token_uris.last !== `${expected.current_base_uri}1998` ||
    !/^[1-9][0-9]*$/.test(envelope.metadata.gas_estimate) ||
    !Number.isSafeInteger(envelope.metadata.anchor_block_number) ||
    envelope.metadata.anchor_block_number < 0 ||
    !validHash(envelope.metadata.anchor_block_hash) ||
    !Number.isFinite(preparedAt) ||
    !Number.isFinite(expiresAt) ||
    expiresAt <= preparedAt ||
    expiresAt - preparedAt > 600_000 ||
    expiresAt <= Date.now()
  ) {
    throw refused()
  }
}

function assertForwardedTransaction(attempt: MetadataAttempt, params: unknown[] | undefined): void {
  if (!Array.isArray(params) || params.length !== 1) throw refused()
  const transaction = params[0]
  if (!transaction || typeof transaction !== "object") throw refused()

  const request = transaction as Record<string, unknown>
  if (
    !sameAddress(request.from, attempt.signer) ||
    !sameAddress(request.to, target) ||
    typeof request.data !== "string" ||
    request.data.toLowerCase() !== calldata.toLowerCase() ||
    request.value !== "0x0" ||
    base.id !== 8453
  ) {
    throw refused()
  }
}

function validHash(value: unknown): value is Hash {
  return typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)
}

function classifiedFailure(error: unknown): MetadataExecutionFailure | null {
  let candidate = error
  for (let depth = 0; depth < 6; depth += 1) {
    if (candidate instanceof MetadataExecutionFailure) return candidate
    if (!candidate || typeof candidate !== "object") return null
    if ("code" in candidate && (candidate as {code: unknown}).code === 4001) {
      return new MetadataExecutionFailure("cancelled")
    }
    candidate = "cause" in candidate ? (candidate as {cause: unknown}).cause : null
  }
  return null
}

function sameAddress(value: unknown, expected: Address): boolean {
  try {
    return typeof value === "string" && getAddress(value) === expected
  } catch {
    return false
  }
}

function nonempty(value: unknown): value is string {
  return typeof value === "string" && value.length > 0
}

function refused(): MetadataExecutionFailure {
  return new MetadataExecutionFailure("refused")
}

function unknown(): MetadataExecutionFailure {
  return new MetadataExecutionFailure("submission_unknown")
}
