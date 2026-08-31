import {beforeEach, describe, expect, it, vi} from "vitest"
import {getAddress, type Hash} from "viem"

import manifest from "../../contracts/base-mainnet.json"
import type {EthereumProvider, SelectedWallet} from "../js/wallet_actions/connected_wallet"
import {
  assertExactMetadataTransactionRequest,
  beginMetadataAttempt,
  executePreparedMetadataAction,
  exactMetadataCalldata,
  MetadataExecutionFailure,
  type PreparedMetadataAction,
} from "../js/wallet_actions/regents_club_metadata"

const manifestOwner = getAddress(manifest.contracts.regents_club.onchain_constants.owner)
const signer = getAddress("0x1111111111111111111111111111111111111111")
const wrongSigner = getAddress("0x3333333333333333333333333333333333333333")
const target = getAddress(manifest.contracts.regents_club.address)
const hash = `0x${"ab".repeat(32)}` as Hash
const attemptId = "c56a4180-65aa-42ec-a945-5fd21dec0538"

function provider(result: unknown = hash): EthereumProvider {
  return {
    request: vi.fn(async ({method}) => {
      if (method === "eth_chainId") return "0x2105"
      if (method === "eth_accounts") return [signer]
      if (method === "eth_sendTransaction") return result
      throw new Error(`unexpected ${method}`)
    }),
  }
}

function wallet(rpc: EthereumProvider): SelectedWallet {
  return {address: signer, provider: rpc}
}

function envelope(): PreparedMetadataAction {
  const preparedAt = new Date()

  return {
    action_id: "signed-action",
    idempotency_key: "signed-action",
    resource: "regents_club_metadata",
    confirmation_token: "signed",
    action: "set_base_uri",
    chain_id: 8453,
    to: target,
    value: "0",
    data: exactMetadataCalldata(),
    expected_signer: signer,
    prepared_at: preparedAt.toISOString(),
    expires_at: new Date(preparedAt.getTime() + 60_000).toISOString(),
    risk_copy:
      "Collection-wide metadata cutover for Regents Club tokens 1 through 1998. No prepared rollback exists.",
    arguments: {
      attempt_id: attemptId,
      new_base_uri: manifest.contracts.regents_club.onchain_constants.cutover_base_uri,
    },
    metadata: {
      anchor_block_number: 42,
      anchor_block_hash: `0x${"42".repeat(32)}`,
      current_base_uri: manifest.contracts.regents_club.onchain_constants.current_base_uri,
      boundary_token_uris: {
        first: `${manifest.contracts.regents_club.onchain_constants.current_base_uri}1`,
        last: `${manifest.contracts.regents_club.onchain_constants.current_base_uri}1998`,
      },
      total_supply: 1998,
      erc4906_supported: true,
      owner_simulation: "success",
      non_owner_simulation: "revert",
      gas_estimate: "81189",
      runtime_keccak256: manifest.contracts.regents_club.runtime_code.keccak256 as Hash,
      calldata_keccak256: manifest.contracts.regents_club.onchain_constants.calldata_keccak256 as Hash,
      observation_deadline: new Date(preparedAt.getTime() + 2_700_000).toISOString(),
    },
  }
}

describe("Regents Club metadata wallet action", () => {
  beforeEach(() => vi.restoreAllMocks())

  it("lets an arbitrary selected signer send one exact zero-value Base transaction", async () => {
    const rpc = provider()
    const selected = () => wallet(rpc)
    const attempt = await beginMetadataAttempt(attemptId, wallet(rpc), selected)

    expect(signer).not.toBe(manifestOwner)
    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).resolves.toBe(hash)
    expect(vi.mocked(rpc.request).mock.calls.at(-1)?.[0]).toEqual({
      method: "eth_sendTransaction",
      params: [
        {
          chainId: "0x2105",
          from: signer,
          to: target,
          data: exactMetadataCalldata(),
          value: "0x0",
        },
      ],
    })
    expect(vi.mocked(rpc.request).mock.calls.at(-2)?.[0]).toEqual({method: "eth_accounts"})

    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).rejects.toMatchObject({
      kind: "refused",
    })
    expect(vi.mocked(rpc.request).mock.calls.filter(([call]) => call.method === "eth_sendTransaction"))
      .toHaveLength(1)
  })

  it.each([
    ["signer", (value: PreparedMetadataAction) => (value.expected_signer = wrongSigner)],
    ["target", (value: PreparedMetadataAction) => (value.to = wrongSigner)],
    ["value", (value: PreparedMetadataAction) => (value.value = "1" as "0")],
    ["calldata", (value: PreparedMetadataAction) => (value.data = "0xdeadbeef")],
    ["runtime", (value: PreparedMetadataAction) => (value.metadata.runtime_keccak256 = hash)],
    ["supply", (value: PreparedMetadataAction) => (value.metadata.total_supply = 1 as 1998)],
    ["risk copy", (value: PreparedMetadataAction) => (value.risk_copy = "changed")],
    ["expiry", (value: PreparedMetadataAction) => (value.expires_at = new Date(0).toISOString())],
    [
      "observation deadline",
      (value: PreparedMetadataAction) =>
        (value.metadata.observation_deadline = new Date(Date.now() + 60_000).toISOString()),
    ],
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

  it.each([
    ["missing", undefined],
    ["wrong", "0x1"],
    ["non-canonical", "0x02105"],
  ])("refuses a %s transaction chainId", (_name, chainId) => {
    const transaction: Record<string, unknown> = {
      chainId,
      from: signer,
      to: target,
      data: exactMetadataCalldata(),
      value: "0x0",
    }

    expect(() => assertExactMetadataTransactionRequest(signer, [transaction])).toThrow(
      expect.objectContaining({kind: "refused"}),
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

  it("refuses account drift between chain and account checks without a send", async () => {
    let accountReads = 0
    const rpc: EthereumProvider = {
      request: vi.fn(async ({method}) => {
        if (method === "eth_chainId") return "0x2105"
        if (method === "eth_accounts") {
          accountReads += 1
          return [accountReads === 1 ? signer : wrongSigner]
        }
        if (method === "eth_sendTransaction") return hash
      }),
    }
    const selected = () => wallet(rpc)
    const attempt = await beginMetadataAttempt(attemptId, wallet(rpc), selected)

    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).rejects.toMatchObject({
      kind: "refused",
    })
    expect(vi.mocked(rpc.request).mock.calls.map(([call]) => call.method)).not.toContain(
      "eth_sendTransaction",
    )
  })

  it("Base-bound transport catches chain drift immediately before submission", async () => {
    let chainReads = 0
    const rpc: EthereumProvider = {
      request: vi.fn(async ({method}) => {
        if (method === "eth_chainId") {
          chainReads += 1
          return chainReads < 4 ? "0x2105" : "0x1"
        }
        if (method === "eth_accounts") return [signer]
        if (method === "eth_sendTransaction") return hash
      }),
    }
    const selected = () => wallet(rpc)
    const attempt = await beginMetadataAttempt(attemptId, wallet(rpc), selected)

    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).rejects.toMatchObject({
      kind: "refused",
    })
    expect(vi.mocked(rpc.request).mock.calls.map(([call]) => call.method)).not.toContain(
      "eth_sendTransaction",
    )

    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).rejects.toMatchObject({
      kind: "refused",
    })
  })

  it("catches account drift at the final provider boundary without a send", async () => {
    let accountReads = 0
    const rpc: EthereumProvider = {
      request: vi.fn(async ({method}) => {
        if (method === "eth_chainId") return "0x2105"
        if (method === "eth_accounts") {
          accountReads += 1
          return [accountReads < 4 ? signer : wrongSigner]
        }
        if (method === "eth_sendTransaction") return hash
      }),
    }
    const selected = () => wallet(rpc)
    const attempt = await beginMetadataAttempt(attemptId, wallet(rpc), selected)

    await expect(executePreparedMetadataAction(attempt, envelope(), selected)).rejects.toMatchObject({
      kind: "refused",
    })
    expect(vi.mocked(rpc.request).mock.calls.map(([call]) => call.method)).not.toContain(
      "eth_sendTransaction",
    )
  })

  it("lets two distinct deliberate attempts reach the fake wallet independently", async () => {
    const rpc = provider()
    const selected = () => wallet(rpc)
    const first = await beginMetadataAttempt(crypto.randomUUID(), wallet(rpc), selected)
    const second = await beginMetadataAttempt(crypto.randomUUID(), wallet(rpc), selected)
    const firstEnvelope = envelope()
    const secondEnvelope = envelope()
    firstEnvelope.arguments.attempt_id = first.attemptId
    secondEnvelope.arguments.attempt_id = second.attemptId

    await expect(executePreparedMetadataAction(first, firstEnvelope, selected)).resolves.toBe(hash)
    await expect(executePreparedMetadataAction(second, secondEnvelope, selected)).resolves.toBe(hash)

    expect(
      vi.mocked(rpc.request).mock.calls.filter(([call]) => call.method === "eth_sendTransaction"),
    ).toHaveLength(2)
  })

  it("consumes cancellation and an absent hash without retrying", async () => {
    for (const [result, kind] of [
      [{code: 4001}, "cancelled"],
      [undefined, "submission_unknown"],
    ] as const) {
      const rpc = provider()
      vi.mocked(rpc.request).mockImplementation(async ({method}) => {
        if (method === "eth_chainId") return "0x2105"
        if (method === "eth_accounts") return [signer]
        if (method === "eth_sendTransaction") {
          if (kind === "cancelled") throw result
          return result
        }
      })
      const selected = () => wallet(rpc)
      const attempt = await beginMetadataAttempt(crypto.randomUUID(), wallet(rpc), selected)
      const prepared = envelope()
      prepared.arguments.attempt_id = attempt.attemptId

      await expect(executePreparedMetadataAction(attempt, prepared, selected)).rejects.toEqual(
        new MetadataExecutionFailure(kind),
      )
      expect(
        vi.mocked(rpc.request).mock.calls.filter(([call]) => call.method === "eth_sendTransaction"),
      ).toHaveLength(1)
    }
  })

  it("does not retry when the provider loses the submitted transaction hash", async () => {
    const rpc = provider()
    vi.mocked(rpc.request).mockImplementation(async ({method}) => {
      if (method === "eth_chainId") return "0x2105"
      if (method === "eth_accounts") return [signer]
      if (method === "eth_sendTransaction") throw new Error("provider lost hash")
    })
    const selected = () => wallet(rpc)
    const attempt = await beginMetadataAttempt(crypto.randomUUID(), wallet(rpc), selected)
    const prepared = envelope()
    prepared.arguments.attempt_id = attempt.attemptId

    await expect(executePreparedMetadataAction(attempt, prepared, selected)).rejects.toEqual(
      new MetadataExecutionFailure("submission_unknown"),
    )
    expect(
      vi.mocked(rpc.request).mock.calls.filter(([call]) => call.method === "eth_sendTransaction"),
    ).toHaveLength(1)
  })
})
