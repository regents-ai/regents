import {beforeEach, describe, expect, it, vi} from "vitest"
import {getAddress, type Hash} from "viem"

import manifest from "../../contracts/base-mainnet.json"
import type {EthereumProvider, SelectedWallet} from "../js/wallet_actions/connected_wallet"
import {
  beginMetadataAttempt,
  executePreparedMetadataAction,
  exactMetadataCalldata,
  MetadataExecutionFailure,
  type PreparedMetadataAction,
} from "../js/wallet_actions/regents_club_metadata"

const owner = getAddress(manifest.contracts.regents_club.onchain_constants.owner)
const target = getAddress(manifest.contracts.regents_club.address)
const hash = `0x${"ab".repeat(32)}` as Hash
const attemptId = "c56a4180-65aa-42ec-a945-5fd21dec0538"

function provider(result: unknown = hash): EthereumProvider {
  return {
    request: vi.fn(async ({method}) => {
      if (method === "eth_chainId") return "0x2105"
      if (method === "eth_accounts") return [owner]
      if (method === "eth_sendTransaction") return result
      throw new Error(`unexpected ${method}`)
    }),
  }
}

function wallet(rpc: EthereumProvider): SelectedWallet {
  return {address: owner, provider: rpc}
}

function envelope(): PreparedMetadataAction {
  return {
    attempt_id: attemptId,
    action: "set_base_uri",
    chain_id: 8453,
    to: target,
    value: "0",
    data: exactMetadataCalldata(),
    expected_signer: owner,
    prepared_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Reviewed metadata cutover",
    metadata: {
      anchor_block_number: 42,
      anchor_block_hash: `0x${"42".repeat(32)}`,
      current_base_uri: manifest.contracts.regents_club.onchain_constants.current_base_uri,
      gas_estimate: "81189",
      runtime_keccak256: manifest.contracts.regents_club.runtime_code.keccak256 as Hash,
    },
  }
}

describe("Regents Club metadata wallet action", () => {
  beforeEach(() => vi.restoreAllMocks())

  it("recomputes and sends one exact zero-value Base transaction", async () => {
    const rpc = provider()
    const selected = () => wallet(rpc)
    const attempt = await beginMetadataAttempt(attemptId, wallet(rpc), selected)

    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).resolves.toBe(hash)
    expect(rpc.request).toHaveBeenLastCalledWith({
      method: "eth_sendTransaction",
      params: [{from: owner, to: target, data: exactMetadataCalldata(), value: "0x0"}],
    })

    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).rejects.toMatchObject({
      kind: "refused",
    })
    expect(vi.mocked(rpc.request).mock.calls.filter(([call]) => call.method === "eth_sendTransaction"))
      .toHaveLength(1)
  })

  it.each([
    ["target", (value: PreparedMetadataAction) => (value.to = owner)],
    ["value", (value: PreparedMetadataAction) => (value.value = "1" as "0")],
    ["calldata", (value: PreparedMetadataAction) => (value.data = "0xdeadbeef")],
    ["expiry", (value: PreparedMetadataAction) => (value.expires_at = new Date(0).toISOString())],
  ])("refuses a changed %s before opening the wallet", async (_name, mutate) => {
    const rpc = provider()
    const selected = () => wallet(rpc)
    const attempt = await beginMetadataAttempt(attemptId, wallet(rpc), selected)
    const prepared = envelope()
    mutate(prepared)

    await expect(executePreparedMetadataAction(attempt, prepared, selected)).rejects.toMatchObject({
      kind: "refused",
    })
    expect(vi.mocked(rpc.request).mock.calls.map(([call]) => call.method)).not.toContain(
      "eth_sendTransaction",
    )
  })

  it("refuses provider or account drift after server preflight", async () => {
    const rpc = provider()
    const attempt = await beginMetadataAttempt(attemptId, wallet(rpc), () => wallet(rpc))

    await expect(
      executePreparedMetadataAction(attempt, envelope(), () => wallet(provider())),
    ).rejects.toMatchObject({kind: "refused"})
    expect(vi.mocked(rpc.request).mock.calls.map(([call]) => call.method)).not.toContain(
      "eth_sendTransaction",
    )
  })

  it("consumes cancellation and an absent hash without retrying", async () => {
    for (const [result, kind] of [
      [{code: 4001}, "cancelled"],
      [undefined, "submission_unknown"],
    ] as const) {
      const rpc = provider()
      vi.mocked(rpc.request).mockImplementation(async ({method}) => {
        if (method === "eth_chainId") return "0x2105"
        if (method === "eth_accounts") return [owner]
        if (method === "eth_sendTransaction") {
          if (kind === "cancelled") throw result
          return result
        }
      })
      const selected = () => wallet(rpc)
      const attempt = await beginMetadataAttempt(crypto.randomUUID(), wallet(rpc), selected)
      const prepared = envelope()
      prepared.attempt_id = attempt.attemptId

      await expect(executePreparedMetadataAction(attempt, prepared, selected)).rejects.toEqual(
        new MetadataExecutionFailure(kind),
      )
      expect(
        vi.mocked(rpc.request).mock.calls.filter(([call]) => call.method === "eth_sendTransaction"),
      ).toHaveLength(1)
    }
  })
})
