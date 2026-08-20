import {getAddress, type Address, type Hash, type Hex} from "viem"
import {describe, expect, it, vi} from "vitest"

import {rememberOperation} from "../js/hooks/autolaunch_bid_wallet"
import {
  sendBidStep,
  sendableStep,
  userRejected,
  type BidClients,
  type BidOperation,
} from "../js/wallet_actions/autolaunch_bids"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const other = getAddress("0x4444444444444444444444444444444444444444")
const auction = getAddress("0x2222222222222222222222222222222222222222")
const regent = getAddress("0x6f89bcA4eA5931EdFCB09786267b251DeE752b07")
const permit2 = getAddress("0x000000000022D473030F116dDEE9F6B43aC78BA3")
const approvalHash = `0x${"cd".repeat(32)}` as Hash

function operation(overrides: Partial<BidOperation> = {}): BidOperation {
  return {
    action_id: "bid",
    signer: wallet,
    chain_id: 8453,
    terminal: false,
    steps: [
      {step: "token_approval", to: regent, data: "0x095ea7b3ff" as Hex},
      {step: "permit2_approval", to: permit2, data: "0x87517c45ff" as Hex},
      {step: "bid", to: auction, data: "0xa52c8728ff" as Hex},
    ],
    ...overrides,
  }
}

function clients(overrides: Partial<BidClients> = {}): BidClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    send: vi.fn(async () => approvalHash),
    ...overrides,
  }
}

describe("the browser sends only the step the server claimed", () => {
  it("hands the wallet the exact reviewed bytes and reports the hash once", async () => {
    const held = operation()
    const boundary = clients()
    const onSendStarted = vi.fn()

    const hash = await sendBidStep(
      held,
      sendableStep(held, "bid", "token_approval"),
      {request: vi.fn()},
      onSendStarted,
      boundary,
    )

    expect(hash).toBe(approvalHash)
    expect(boundary.send).toHaveBeenCalledWith({
      account: wallet,
      to: regent,
      data: "0x095ea7b3ff",
      value: 0n,
    })
    expect(onSendStarted).toHaveBeenCalledOnce()
  })

  it("refuses another operation, a terminal one, an unknown step and a foreign chain", () => {
    expect(() => sendableStep(operation(), "other", "bid")).toThrow("different bid")
    expect(() => sendableStep(operation({terminal: true}), "bid", "bid")).toThrow("already finished")
    expect(() => sendableStep(operation(), "bid", "exit_bid")).toThrow("not part of the reviewed bid")
    expect(() => sendableStep(operation({chain_id: 1}), "bid", "bid")).toThrow("not for Base")
  })

  it("never sends from a wallet other than the reviewed signer", async () => {
    const held = operation()
    const onSendStarted = vi.fn()

    await expect(
      sendBidStep(
        held,
        sendableStep(held, "bid", "bid"),
        {request: vi.fn()},
        onSendStarted,
        clients({addresses: vi.fn(async () => [other])}),
      ),
    ).rejects.toThrow("wallet this bid was reviewed for")

    expect(onSendStarted).not.toHaveBeenCalled()
  })

  it("never sends while the wallet is on another chain", async () => {
    const held = operation()
    const boundary = clients({chainId: vi.fn(async () => 1), switchToBase: vi.fn(async () => undefined)})

    await expect(
      sendBidStep(held, sendableStep(held, "bid", "bid"), {request: vi.fn()}, vi.fn(), boundary),
    ).rejects.toThrow("Switch to Base")

    expect(boundary.send).not.toHaveBeenCalled()
  })

  it("stores only the operation identity, and forgets it once the bid ends", () => {
    const storage = {setItem: vi.fn(), removeItem: vi.fn()}

    rememberOperation(operation(), storage)
    expect(storage.setItem).toHaveBeenCalledWith("regent:autolaunch-bid:open", "bid")

    rememberOperation(operation({terminal: true}), storage)
    expect(storage.removeItem).toHaveBeenCalledWith("regent:autolaunch-bid:open")
    expect(storage.setItem).toHaveBeenCalledOnce()
  })

  it("treats only the exact EIP-1193 rejection code as a rejection", () => {
    expect(userRejected({code: 4001})).toBe(true)
    expect(userRejected({cause: {cause: {code: 4001}}})).toBe(true)
    expect(userRejected(new Error("User rejected the request."))).toBe(false)
    expect(userRejected({code: 4100})).toBe(false)
  })
})
