import {encodeFunctionData, getAddress, type Hash} from "viem"
import {afterEach, describe, expect, it, vi} from "vitest"

import buybackAbiJson from "../../contracts/abi/regent-staking-revenue-router-buyback.json"
import {recordAutolaunchBuybackSubmission} from "../js/hooks/autolaunch_buyback_wallet"
import {
  assertAutolaunchBuybackEnvelope,
  executePreparedAutolaunchBuyback,
  type AutolaunchBuybackClients,
  type PreparedAutolaunchBuyback,
} from "../js/wallet_actions/autolaunch_buybacks"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const router = getAddress("0x2222222222222222222222222222222222222222")
const treasury = getAddress("0x3333333333333333333333333333333333333333")
const subjectId = `0x${"42".repeat(32)}` as const
const actionHash = `0x${"ab".repeat(32)}` as Hash

function envelope(
  overrides: Partial<PreparedAutolaunchBuyback> = {},
): PreparedAutolaunchBuyback {
  const args = {
    subject_id: subjectId,
    revenue_router: router,
    treasury,
    amount_usdc_atomic: "11000000",
    minimum_regent_output_atomic: "10000000000000000000",
    source_ref: subjectId,
  }

  const data = encodeFunctionData({
    abi: buybackAbiJson,
    functionName: "settleTreasuryBuyback",
    args: [subjectId, treasury, 11_000_000n, 10_000_000_000_000_000_000n, subjectId],
  })

  return {
    action_id: "action",
    idempotency_key: "action",
    confirmation_token: "signed",
    resource: "autolaunch_buyback",
    action: "settle_treasury_buyback",
    chain_id: 8453,
    to: router,
    value: "0",
    data,
    expected_signer: wallet,
    prepared_at: new Date(Date.now() - 1000).toISOString(),
    expires_at: new Date(Date.now() + 120_000).toISOString(),
    risk_copy: "Review this settlement.",
    approval: null,
    arguments: args,
    ...overrides,
  }
}

function clients(
  overrides: Partial<AutolaunchBuybackClients> = {},
): AutolaunchBuybackClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    send: vi.fn(async () => actionHash),
    receipt: vi.fn(async () => ({status: "success" as const})),
    ...overrides,
  }
}

afterEach(() => vi.useRealTimers())

describe("Autolaunch buyback wallet action", () => {
  it("submits only the exact reviewed router call and records its hash first", async () => {
    const boundary = clients()
    const submitted = vi.fn()

    await expect(
      executePreparedAutolaunchBuyback(
        envelope(),
        {request: vi.fn()},
        boundary,
        submitted,
      ),
    ).resolves.toBe(actionHash)

    expect(boundary.send).toHaveBeenCalledWith({
      account: wallet,
      to: router,
      data: envelope().data,
      value: 0n,
    })
    expect(submitted).toHaveBeenCalledWith(actionHash)
    expect(submitted.mock.invocationCallOrder[0]).toBeLessThan(
      (boundary.receipt as ReturnType<typeof vi.fn>).mock.invocationCallOrder[0],
    )
  })

  it("fails closed on signer, expiry, calldata and stored-identity drift", async () => {
    const other = getAddress("0x4444444444444444444444444444444444444444")

    await expect(
      executePreparedAutolaunchBuyback(
        envelope(),
        {request: vi.fn()},
        clients({addresses: vi.fn(async () => [other])}),
      ),
    ).rejects.toThrow("connected wallet")

    for (const changed of [
      envelope({expires_at: new Date(Date.now() - 1000).toISOString()}),
      envelope({data: "0xdeadbeef"}),
      envelope({to: other}),
      envelope({arguments: {...envelope().arguments, treasury: other}}),
      envelope({idempotency_key: "changed"}),
    ]) {
      expect(() => assertAutolaunchBuybackEnvelope(changed)).toThrow()
    }
  })

  it("requires more than 60 seconds before opening the signing flow", async () => {
    vi.useFakeTimers()

    for (const remaining of [60_000, 59_999, 0]) {
      const boundary = clients()

      await expect(
        executePreparedAutolaunchBuyback(
          envelope({expires_at: new Date(Date.now() + remaining).toISOString()}),
          {request: vi.fn()},
          boundary,
        ),
      ).rejects.toThrow("Prepare it again")

      expect(boundary.chainId).not.toHaveBeenCalled()
      expect(boundary.addresses).not.toHaveBeenCalled()
      expect(boundary.send).not.toHaveBeenCalled()
    }
  })

  it("keeps the submitted hash when receipt waiting reports a revert", async () => {
    const submitted = vi.fn()

    await expect(
      executePreparedAutolaunchBuyback(
        envelope(),
        {request: vi.fn()},
        clients({receipt: vi.fn(async () => ({status: "reverted" as const}))}),
        submitted,
      ),
    ).rejects.toThrow("reverted")

    expect(submitted).toHaveBeenCalledWith(actionHash)
  })

  it("stores the submitted envelope and hash for refresh recovery", () => {
    const storage = {setItem: vi.fn()}
    const submission = recordAutolaunchBuybackSubmission(
      envelope(),
      actionHash,
      storage,
    )

    expect(submission.transaction_hash).toBe(actionHash)
    expect(storage.setItem).toHaveBeenCalledWith(
      "regent:autolaunch-buyback:submitted",
      expect.stringContaining(actionHash),
    )
  })
})
