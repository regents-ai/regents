import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"
import {encodeFunctionData, getAddress, parseAbi, type Address, type Hash} from "viem"

import chainManifest from "../../contracts/base-mainnet.json"
import redeemerAbiJson from "../../contracts/abi/animata-redeemer.json"
import {connectedEthereumWallet} from "../js/wallet_actions/connected_wallet"
import {
  recordSubmittedRedemption,
  RedemptionWallet,
  userRejected,
} from "../js/hooks/redemption_wallet"
import {
  assertRedemptionEnvelope,
  executePreparedRedemptionAction,
  type PreparedRedemptionAction,
  type RedemptionClients,
} from "../js/wallet_actions/redemption"

vi.mock("../js/wallet_actions/connected_wallet", () => ({
  connectedEthereumWallet: vi.fn(() => ({
    address: "0x1111111111111111111111111111111111111111",
    provider: {request: vi.fn()},
  })),
}))

// Only the hook's own call is steered; every other test in this file keeps the
// real executor, so the envelope and ABI assertions below still bind it.
vi.mock("../js/wallet_actions/redemption", async importOriginal => {
  const actual = await importOriginal<typeof import("../js/wallet_actions/redemption")>()
  return {...actual, executePreparedRedemptionAction: vi.fn(actual.executePreparedRedemptionAction)}
})

const manifest = chainManifest.contracts.animata_redeemer
const wallet = getAddress("0x1111111111111111111111111111111111111111")
const other = getAddress("0x2222222222222222222222222222222222222222")
const redeemer = getAddress(manifest.address)
const animataI = getAddress(manifest.onchain_constants.animata_i)
const resultCollection = getAddress(manifest.onchain_constants.result_collection)
const usdc = getAddress(manifest.onchain_constants.usdc)
const hash = `0x${"ab".repeat(32)}` as Hash
const redeemAbi = redeemerAbiJson
const erc20 = parseAbi(["function approve(address spender,uint256 amount)"])
const erc721 = parseAbi(["function setApprovalForAll(address operator,bool approved)"])

function baseEnvelope(overrides: Partial<PreparedRedemptionAction> = {}): PreparedRedemptionAction {
  return {
    action_id: "action",
    idempotency_key: "action",
    confirmation_token: "signed",
    resource: "animata_redemption",
    action: "claim",
    chain_id: 8453,
    to: redeemer,
    value: "0",
    data: encodeFunctionData({abi: redeemAbi, functionName: "claim"}),
    expected_signer: wallet,
    prepared_at: new Date(Date.now() - 1000).toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Claim unlocked REGENT.",
    arguments: {},
    ...overrides,
  }
}

function clients(overrides: Partial<RedemptionClients> = {}): RedemptionClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    simulate: vi.fn(async () => undefined),
    send: vi.fn(async () => hash),
    receipt: vi.fn(async () => ({status: "success" as const})),
    ...overrides,
  }
}

describe("prepared Animata redemption actions", () => {
  it("submits exactly one reviewed action from the expected wallet", async () => {
    const rpc = clients()
    const submitted = vi.fn()
    const result = await executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, rpc, submitted)

    expect(result).toBe(hash)
    expect(rpc.simulate).toHaveBeenCalledOnce()
    expect(rpc.send).toHaveBeenCalledOnce()
    expect(rpc.receipt).toHaveBeenCalledWith(hash)
    expect(submitted).toHaveBeenCalledWith(hash)
    expect(vi.mocked(rpc.send).mock.calls[0]?.[0]).toEqual({
      account: wallet,
      to: redeemer,
      data: baseEnvelope().data,
      value: 0n,
    })
  })

  it("re-encodes and validates all four separate action shapes", () => {
    const nft = baseEnvelope({
      action: "approve_nft_collection",
      to: animataI,
      arguments: {collection: animataI, operator: redeemer, approved: true},
      data: encodeFunctionData({abi: erc721, functionName: "setApprovalForAll", args: [redeemer, true]}),
    })
    const approval = baseEnvelope({
      action: "approve_exact_usdc",
      to: usdc,
      arguments: {spender: redeemer, amount_atomic: "80000000", mode: "exact"},
      data: encodeFunctionData({abi: erc20, functionName: "approve", args: [redeemer, 80_000_000n]}),
    })
    const redeem = baseEnvelope({
      action: "redeem",
      arguments: {collection: animataI, token_id: 42},
      data: encodeFunctionData({abi: redeemAbi, functionName: "redeem", args: [animataI, 42n]}),
    })

    for (const envelope of [nft, approval, redeem, baseEnvelope()]) {
      expect(() => assertRedemptionEnvelope(envelope)).not.toThrow()
    }
  })

  it("rejects signer, chain, target, value, collection, token, approval and calldata drift", async () => {
    const mutations: PreparedRedemptionAction[] = [
      baseEnvelope({chain_id: 1 as 8453}),
      baseEnvelope({to: other}),
      baseEnvelope({value: "1" as "0"}),
      baseEnvelope({data: "0xdeadbeef"}),
      baseEnvelope({resource: "other" as "animata_redemption"}),
      baseEnvelope({idempotency_key: "other"}),
      baseEnvelope({expires_at: new Date(Date.now() - 1000).toISOString()}),
      baseEnvelope({
        action: "redeem",
        arguments: {collection: resultCollection, token_id: 42},
        data: encodeFunctionData({abi: redeemAbi, functionName: "redeem", args: [resultCollection, 42n]}),
      }),
      baseEnvelope({
        action: "redeem",
        arguments: {collection: animataI, token_id: 1000},
        data: encodeFunctionData({abi: redeemAbi, functionName: "redeem", args: [animataI, 1000n]}),
      }),
      baseEnvelope({
        action: "approve_exact_usdc",
        to: usdc,
        arguments: {spender: redeemer, amount_atomic: "80000001", mode: "exact"},
        data: encodeFunctionData({abi: erc20, functionName: "approve", args: [redeemer, 80_000_001n]}),
      }),
    ]

    for (const envelope of mutations) {
      await expect(executePreparedRedemptionAction(envelope, {request: vi.fn()}, clients())).rejects.toBeInstanceOf(Error)
    }

    await expect(
      executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, clients({addresses: vi.fn(async () => [other])})),
    ).rejects.toThrow("connected wallet")
  })

  it("switches to Base then fails closed if the wallet stays on another chain", async () => {
    const chainId = vi.fn().mockResolvedValueOnce(1).mockResolvedValueOnce(1)
    const rpc = clients({chainId})
    await expect(executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, rpc)).rejects.toThrow("Switch to Base")
    expect(rpc.switchToBase).toHaveBeenCalledOnce()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("captures a reverted hash for server verification without resubmitting", async () => {
    const rpc = clients({receipt: vi.fn(async () => ({status: "reverted" as const}))})
    const submitted = vi.fn()

    await expect(
      executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, rpc, submitted),
    ).rejects.toMatchObject({
      code: "action_reverted",
      transactionHash: hash,
    })
    expect(submitted).toHaveBeenCalledOnce()
    expect(rpc.send).toHaveBeenCalledOnce()
  })

  it("notifies the server before best-effort session storage", () => {
    const order: string[] = []
    const storage = {setItem: vi.fn(() => order.push("storage"))}
    const push = vi.fn(() => order.push("server"))
    const stored = recordSubmittedRedemption(baseEnvelope(), hash, push, storage)

    expect(order).toEqual(["server", "storage"])
    expect(stored.transaction_hash).toBe(hash)
    expect(push).toHaveBeenCalledWith({action_id: "action", transaction_hash: hash})
  })

  it("keeps the submitted hash when session storage fails after server notification", () => {
    const push = vi.fn()
    const storage = {setItem: vi.fn(() => { throw new Error("quota") })}

    const stored = recordSubmittedRedemption(baseEnvelope(), hash, push, storage)

    expect(push).toHaveBeenCalledOnce()
    expect(stored.transaction_hash).toBe(hash)
    expect(stored.envelope.action_id).toBe("action")
  })
})

describe("CLAIM_BEFORE_WALLET_HANDOFF: the not-sent signal", () => {
  it("recognises the exact EIP-1193 rejection code however viem wrapped it", () => {
    expect(userRejected({code: 4001})).toBe(true)
    expect(userRejected({cause: {cause: {code: 4001}}})).toBe(true)
  })

  it("treats every other failure as uncertainty rather than a rejection", () => {
    expect(userRejected(new Error("User rejected the request."))).toBe(false)
    expect(userRejected({code: -32603})).toBe(false)
    expect(userRejected({code: "4001"})).toBe(false)
    expect(userRejected(null)).toBe(false)
  })
})

describe("CLAIM_BEFORE_WALLET_HANDOFF: a rejection after an earlier success", () => {
  const execute = vi.mocked(executePreparedRedemptionAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  // The server claimed the second dispatch before the wallet opened. If the
  // browser withheld the rejection because a previous action left a hash in
  // memory, that claim could never be closed and the account's one Redeem slot
  // would be consumed for good.
  it("reports the exact 4001 for the second action even though the first one succeeded", async () => {
    const hook = mountRedemptionWallet()

    execute.mockImplementationOnce(async (_envelope, _provider, _clients, onSubmitted) => {
      onSubmitted?.(hash)
      return hash
    })
    await hook.emit("redemption:prepared", {envelope: baseEnvelope({action_id: "first"})})
    expect(hook.pushed).toContainEqual({
      event: "confirm_redemption",
      payload: {action_id: "first", transaction_hash: hash},
    })

    await hook.emit("redemption:confirmed", {})

    execute.mockImplementationOnce(async () => {
      throw Object.assign(new Error("User rejected the request."), {code: 4001})
    })
    await hook.emit("redemption:prepared", {envelope: baseEnvelope({action_id: "second"})})

    expect(hook.pushed).toContainEqual({
      event: "redemption_wallet_rejected",
      payload: {action_id: "second", code: 4001},
    })
  })
})

describe("U1_BOUNDED_WALLET_COPY: only closed reason keys leave the browser", () => {
  const execute = vi.mocked(executePreparedRedemptionAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  it("reports the unknown key instead of the provider's own message", async () => {
    const hook = mountRedemptionWallet()
    execute.mockImplementationOnce(async () => {
      throw new Error("execution reverted: allowance 0xdeadbeef (Safe transaction service)")
    })

    await hook.emit("redemption:prepared", {envelope: baseEnvelope({action_id: "failed"})})

    expect(hook.pushed).toContainEqual({
      event: "redemption_wallet_failed",
      payload: {reason: "unknown"},
    })
    expect(JSON.stringify(hook.pushed)).not.toContain("execution reverted")
  })

  it("reports the unavailable review wallet without naming any provider", async () => {
    vi.mocked(connectedEthereumWallet).mockReturnValueOnce(null)
    const hook = mountRedemptionWallet()

    await hook.emit("redemption:prepared", {envelope: baseEnvelope({action_id: "absent"})})

    expect(hook.pushed).toEqual([
      {event: "redemption_wallet_failed", payload: {reason: "wallet_unavailable"}},
    ])
  })
})

describe("U2_NEUTRAL_REJECTION: the rejection is the whole outcome", () => {
  const execute = vi.mocked(executePreparedRedemptionAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  // A failure event after the rejection would replace the neutral "nothing was
  // sent" notice with an error the customer did not cause.
  it("sends the rejection and nothing that could overwrite its neutral notice", async () => {
    const hook = mountRedemptionWallet()
    execute.mockImplementationOnce(async () => {
      throw Object.assign(new Error("User rejected the request."), {code: 4001})
    })

    await hook.emit("redemption:prepared", {envelope: baseEnvelope({action_id: "rejected"})})

    expect(hook.pushed).toEqual([
      {event: "redemption_wallet_rejected", payload: {action_id: "rejected", code: 4001}},
    ])
  })
})

describe("U5_EXPECTED_SIGNER_TRUTH: the copy button carries the reviewed signer", () => {
  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  it("copies the exact address the review rendered and says so on that button", async () => {
    const writeText = vi.fn(async () => undefined)
    vi.stubGlobal("navigator", {clipboard: {writeText}})
    const hook = mountRedemptionWallet()
    const button = copyButton(wallet)

    await hook.click(button)
    expect(writeText).toHaveBeenCalledWith(wallet)
    expect(button.textContent).toBe("Copied")

    await hook.click({closest: () => null})
    expect(writeText).toHaveBeenCalledOnce()
  })

  // An absent Clipboard API and a refused write are one fixed outcome on the
  // clicked button; the browser's own reason never becomes customer copy.
  it("reports one fixed failure when the clipboard is absent or refuses", async () => {
    const hook = mountRedemptionWallet()

    vi.stubGlobal("navigator", {})
    const absent = copyButton(wallet)
    await hook.click(absent)
    expect(absent.textContent).toBe("Copy failed")

    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: async () => {
          throw new DOMException("Write permission denied.", "NotAllowedError")
        },
      },
    })
    const refused = copyButton(wallet)
    await hook.click(refused)
    expect(refused.textContent).toBe("Copy failed")
  })
})

type Emitted = {event: string; payload: unknown}
type CopyButton = {textContent: string; dataset: {copySigner: string}; closest: () => CopyButton}

function mountRedemptionWallet(): {
  pushed: Emitted[]
  emit(event: string, payload: unknown): unknown
  click(target: unknown): Promise<unknown[]>
} {
  const pushed: Emitted[] = []
  const handlers = new Map<string, (payload: unknown) => unknown>()
  const clicks: Array<(event: Event) => unknown> = []
  const buttons = [] as unknown as NodeListOf<HTMLButtonElement>
  const hook = {
    el: {
      dataset: {} as DOMStringMap,
      querySelectorAll: () => buttons,
      addEventListener: (_type: string, listener: (event: Event) => unknown) =>
        clicks.push(listener),
    },
    handleEvent: (event: string, callback: (payload: unknown) => unknown) =>
      handlers.set(event, callback),
    pushEvent: (event: string, payload: unknown) => pushed.push({event, payload}),
  }

  ;(RedemptionWallet.mounted as (this: typeof hook) => void).call(hook)

  return {
    pushed,
    emit: (event, payload) => handlers.get(event)?.(payload),
    click: target => Promise.all(clicks.map(listener => listener({target} as unknown as Event))),
  }
}

// The reviewed markup puts the signer on the button itself, so the clicked
// element is its own `closest` match and carries the text the copy replaces.
function copyButton(signer: string): CopyButton {
  const button: CopyButton = {
    textContent: "Copy",
    dataset: {copySigner: signer},
    closest: () => button,
  }

  return button
}

function stubSessionStorage(): void {
  const entries = new Map<string, string>()
  vi.stubGlobal("sessionStorage", {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => entries.set(key, value),
    removeItem: (key: string) => entries.delete(key),
  })
}
