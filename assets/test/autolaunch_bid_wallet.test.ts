import {encodeFunctionData, getAddress, parseAbi, type Address, type Hash} from "viem"
import {afterEach, describe, expect, it, vi} from "vitest"

import auctionAbiJson from "../../contracts/abi/continuous-clearing-auction.json"
import {recordAutolaunchBidSubmission} from "../js/hooks/autolaunch_bid_wallet"
import {
  assertAuctionBidEnvelope,
  executePreparedAuctionBidAction,
  type AuctionBidClients,
  type PreparedAuctionBidAction,
} from "../js/wallet_actions/autolaunch_bids"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const auction = getAddress("0x2222222222222222222222222222222222222222")
const token = getAddress("0x3333333333333333333333333333333333333333")
const approvalHash = `0x${"cd".repeat(32)}` as Hash
const actionHash = `0x${"ab".repeat(32)}` as Hash
const amount = 12_500_000n
const price = 3n * 79_228_162_514_264_337_593_543_950_336n
const approvalAbi = parseAbi(["function approve(address spender,uint256 amount)"])

function envelope(overrides: Partial<PreparedAuctionBidAction> = {}): PreparedAuctionBidAction {
  const data = encodeFunctionData({
    abi: auctionAbiJson,
    functionName: "submitBid",
    args: [price, amount, wallet, "0x"],
  })
  const approvalData = encodeFunctionData({
    abi: approvalAbi,
    functionName: "approve",
    args: [auction, amount],
  })

  return {
    action_id: "action",
    idempotency_key: "action",
    confirmation_token: "signed",
    resource: "autolaunch_auction",
    action: "submit_bid",
    chain_id: 8453,
    to: auction,
    value: "0",
    data,
    expected_signer: wallet,
    prepared_at: new Date(Date.now() - 1000).toISOString(),
    expires_at: new Date(Date.now() + 120_000).toISOString(),
    risk_copy: "Review this bid.",
    arguments: {
      auction_id: "auction",
      amount_atomic: amount.toString(),
      max_price_q96: price.toString(),
      recipient: wallet,
    },
    approval: {
      token,
      spender: auction,
      amount: amount.toString(),
      data: approvalData,
      mode: "exact",
    },
    ...overrides,
  }
}

function clients(overrides: Partial<AuctionBidClients> = {}): AuctionBidClients {
  let sends = 0
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    send: vi.fn(async () => (++sends === 1 ? approvalHash : actionHash)),
    receipt: vi.fn(async () => ({status: "success" as const})),
    ...overrides,
  }
}

afterEach(() => vi.useRealTimers())

describe("Autolaunch bid wallet action", () => {
  it("waits for the exact approval before submitting the reviewed bid", async () => {
    const boundary = clients()
    const submitted = vi.fn()

    await expect(
      executePreparedAuctionBidAction(envelope(), {request: vi.fn()}, boundary, {
        onSubmitted: submitted,
      }),
    ).resolves.toEqual({approvalHash, transactionHash: actionHash})

    expect(boundary.send).toHaveBeenNthCalledWith(1, {
      account: wallet,
      to: token,
      data: envelope().approval!.data,
      value: 0n,
    })
    expect(boundary.send).toHaveBeenNthCalledWith(2, {
      account: wallet,
      to: auction,
      data: envelope().data,
      value: 0n,
    })
    expect(submitted.mock.calls.map(call => call[0])).toEqual(["approval", "action"])
  })

  it("fails closed on signer, expiry, calldata and approval drift", async () => {
    const other = getAddress("0x4444444444444444444444444444444444444444")

    await expect(
      executePreparedAuctionBidAction(
        envelope(),
        {request: vi.fn()},
        clients({addresses: vi.fn(async () => [other])}),
      ),
    ).rejects.toThrow("connected wallet")

    for (const changed of [
      envelope({expires_at: new Date(Date.now() - 1000).toISOString()}),
      envelope({data: "0xdeadbeef"}),
      envelope({to: other}),
      envelope({approval: {...envelope().approval!, amount: "1"}}),
      envelope({idempotency_key: "changed"}),
    ]) {
      expect(() => assertAuctionBidEnvelope(changed)).toThrow()
    }
  })

  it("does not submit the action if approval confirmation outlives the envelope", async () => {
    vi.useFakeTimers()
    const prepared = envelope({expires_at: new Date(Date.now() + 61_000).toISOString()})
    const boundary = clients({
      receipt: vi.fn(async () => {
        vi.setSystemTime(Date.now() + 62_000)
        return {status: "success" as const}
      }),
    })

    await expect(
      executePreparedAuctionBidAction(prepared, {request: vi.fn()}, boundary),
    ).rejects.toThrow("expired")
    expect(boundary.send).toHaveBeenCalledTimes(1)
  })

  it("requires more than 60 seconds before opening the signing flow", async () => {
    vi.useFakeTimers()

    for (const remaining of [60_000, 59_999, 0]) {
      const boundary = clients()

      await expect(
        executePreparedAuctionBidAction(
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

  it("stores both submitted hashes for refresh recovery", () => {
    const storage = {setItem: vi.fn()}
    const prepared = envelope()

    const approval = recordAutolaunchBidSubmission(
      null,
      prepared,
      "approval",
      approvalHash,
      storage,
    )
    const action = recordAutolaunchBidSubmission(
      approval,
      prepared,
      "action",
      actionHash,
      storage,
    )

    expect(action).toMatchObject({
      approval_transaction_hash: approvalHash,
      transaction_hash: actionHash,
    })
    expect(storage.setItem).toHaveBeenCalledTimes(2)
  })
})
