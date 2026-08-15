import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"
import {encodeFunctionData, parseAbi, type Address, type Hash} from "viem"

import {connectedEthereumWallet} from "../js/wallet_actions/connected_wallet"
import {
  executePreparedStakingAction,
  type PreparedStakingAction,
  type StakingClients,
  WalletExecutionError,
} from "../js/wallet_actions/staking"
import {recordSubmittedAction, StakeWallet, userRejected} from "../js/hooks/stake_wallet"

vi.mock("../js/wallet_actions/connected_wallet", () => ({
  connectedEthereumWallet: vi.fn(() => ({
    address: "0x1111111111111111111111111111111111111111",
    provider: {request: vi.fn()},
  })),
}))

// Only the hook's own call is steered; every other test in this file keeps the
// real executor, so the envelope and ABI assertions below still bind it.
vi.mock("../js/wallet_actions/staking", async importOriginal => {
  const actual = await importOriginal<typeof import("../js/wallet_actions/staking")>()
  return {...actual, executePreparedStakingAction: vi.fn(actual.executePreparedStakingAction)}
})

const wallet = "0x1111111111111111111111111111111111111111" as Address
const staking = "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5" as Address
const token = "0x6f89bcA4eA5931EdFCB09786267b251DeE752b07" as Address
const mainHash = `0x${"ab".repeat(32)}` as Hash
const approvalHash = `0x${"cd".repeat(32)}` as Hash

function envelope(overrides: Partial<PreparedStakingAction> = {}): PreparedStakingAction {
  const amount = 1_500_000_000_000_000_000n
  const data = encodeFunctionData({
    abi: parseAbi(["function stake(uint256 amount,address receiver)"]),
    functionName: "stake",
    args: [amount, wallet],
  })
  const approvalData = encodeFunctionData({
    abi: parseAbi(["function approve(address spender,uint256 amount)"]),
    functionName: "approve",
    args: [staking, amount],
  })

  return {
    action_id: "action",
    idempotency_key: "action",
    confirmation_token: "signed",
    resource: "regent_staking",
    action: "stake",
    chain_id: 8453,
    to: staking,
    value: "0",
    data,
    expected_signer: wallet,
    prepared_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Review this action.",
    arguments: {amount_atomic: amount.toString(), receiver: wallet},
    approval: {token, spender: staking, amount: amount.toString(), data: approvalData, mode: "exact"},
    ...overrides,
  }
}

function clients(overrides: Partial<StakingClients> = {}): StakingClients {
  let sends = 0
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    allowance: vi.fn(async () => 0n),
    simulate: vi.fn(async () => undefined),
    send: vi.fn(async () => (++sends === 1 ? approvalHash : mainHash)),
    receipt: vi.fn(async () => ({status: "success" as const})),
    ...overrides,
  }
}

const provider = {request: vi.fn(async () => undefined)}

describe("staking wallet action", () => {
  it("matches viem ABI bytes and completes exact approval before the stake", async () => {
    const prepared = envelope()
    expect(prepared.data).toBe(
      "0x7acb775700000000000000000000000000000000000000000000000014d1120d7b1600000000000000000000000000001111111111111111111111111111111111111111",
    )

    const approvalBoundary = clients()
    await expect(executePreparedStakingAction(prepared, provider, approvalBoundary)).resolves.toEqual({
      phase: "approval",
      approvalHash,
    })
    expect(approvalBoundary.send).toHaveBeenCalledOnce()
    expect(approvalBoundary.receipt).not.toHaveBeenCalled()

    const mainBoundary = clients({send: vi.fn(async () => mainHash)})
    await expect(
      executePreparedStakingAction(prepared, provider, mainBoundary, {
        existingApprovalHash: approvalHash,
      }),
    ).resolves.toEqual({phase: "action", transactionHash: mainHash, approvalHash})
    expect(mainBoundary.send).toHaveBeenCalledOnce()
    expect(mainBoundary.receipt).toHaveBeenCalledOnce()
  })

  it("notifies the server and retains the hash in memory when session storage throws", () => {
    const push = vi.fn()
    const storage = {
      setItem: vi.fn(() => {
        throw new DOMException("quota", "QuotaExceededError")
      }),
    }

    const stored = recordSubmittedAction(null, envelope(), "action", mainHash, push, storage)

    expect(stored.transaction_hash).toBe(mainHash)
    expect(push).toHaveBeenCalledWith({
      action_id: "action",
      phase: "action",
      transaction_hash: mainHash,
    })
  })

  it("switches to Base and then rechecks the chain", async () => {
    const chainId = vi.fn().mockResolvedValueOnce(1).mockResolvedValueOnce(8453)
    const boundary = clients({chainId, allowance: vi.fn(async () => 2_000_000_000_000_000_000n)})

    await executePreparedStakingAction(envelope(), provider, boundary)

    expect(boundary.switchToBase).toHaveBeenCalledOnce()
    expect(chainId).toHaveBeenCalledTimes(2)
  })

  it("fails closed on signer, chain, stale envelope, calldata, target and reverted receipt", async () => {
    await expect(
      executePreparedStakingAction(
        envelope(),
        provider,
        clients({
          addresses: vi.fn(async () => [
            "0x2222222222222222222222222222222222222222" as Address,
          ]),
        }),
      ),
    ).rejects.toThrow("connected wallet")

    await expect(
      executePreparedStakingAction(envelope(), provider, clients({chainId: vi.fn(async () => 1)})),
    ).rejects.toThrow("Switch to Base")

    await expect(
      executePreparedStakingAction(envelope({expires_at: new Date(0).toISOString()}), provider, clients()),
    ).rejects.toThrow("expired")

    await expect(
      executePreparedStakingAction(envelope({data: "0xdeadbeef"}), provider, clients()),
    ).rejects.toThrow("data changed")

    const changedAmount = 2_000_000_000_000_000_000n
    const changedData = encodeFunctionData({
      abi: parseAbi(["function stake(uint256 amount,address receiver)"]),
      functionName: "stake",
      args: [changedAmount, wallet],
    })
    await expect(
      executePreparedStakingAction(
        envelope({data: changedData, arguments: {amount_atomic: changedAmount.toString(), receiver: wallet}}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("approval changed")

    await expect(
      executePreparedStakingAction(
        envelope({arguments: {amount_atomic: "1500000000000000000", receiver: "0x2222222222222222222222222222222222222222"}}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("recipient changed")

    await expect(
      executePreparedStakingAction(envelope({expires_at: "not-a-date"}), provider, clients()),
    ).rejects.toThrow("expired")

    await expect(
      executePreparedStakingAction(
        envelope({to: "0x2222222222222222222222222222222222222222"}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("target changed")

    const badApproval = envelope().approval!
    await expect(
      executePreparedStakingAction(
        envelope({approval: {...badApproval, spender: "0x2222222222222222222222222222222222222222"}}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("approval changed")

    await expect(
      executePreparedStakingAction(
        envelope({approval: null}),
        provider,
        clients({receipt: vi.fn(async () => ({status: "reverted" as const}))}),
      ),
    ).rejects.toThrow("staking transaction was reverted")
  })
})

describe("CLAIM_BEFORE_WALLET_HANDOFF: the not-sent signal", () => {
  it("recognises the exact EIP-1193 rejection code however viem wrapped it", () => {
    expect(userRejected({code: 4001})).toBe(true)
    expect(userRejected({cause: {code: 4001}})).toBe(true)
    expect(userRejected({cause: {cause: {name: "UserRejectedRequestError", code: 4001}}})).toBe(true)
  })

  it("treats every other failure as uncertainty rather than a rejection", () => {
    // Message text is never authority, and neither is a near-miss code.
    expect(userRejected(new Error("User rejected the request."))).toBe(false)
    expect(userRejected({message: "user rejected"})).toBe(false)
    expect(userRejected({code: -32603})).toBe(false)
    expect(userRejected({code: "4001"})).toBe(false)
    expect(userRejected({code: 4100})).toBe(false)
    expect(userRejected(undefined)).toBe(false)
    expect(userRejected(null)).toBe(false)
  })

  it("terminates on a cyclic error chain instead of hanging", () => {
    const cyclic: {code: number; cause?: unknown} = {code: -1}
    cyclic.cause = cyclic

    expect(userRejected(cyclic)).toBe(false)
  })
})

describe("CLAIM_BEFORE_WALLET_HANDOFF: a rejection after an earlier success", () => {
  const execute = vi.mocked(executePreparedStakingAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  // The server claimed the second dispatch before the wallet opened. If the
  // browser withheld the rejection because a previous action left a hash in
  // memory, that claim could never be closed and the account's one Stake slot
  // would be consumed for good.
  it("reports the exact 4001 for the second action even though the first one succeeded", async () => {
    const hook = mountStakeWallet()

    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options?.onSubmitted?.("action", mainHash)
      return {phase: "action", transactionHash: mainHash}
    })
    await hook.emit("staking:prepared", {envelope: envelope({action_id: "first", approval: null})})
    expect(hook.pushed).toContainEqual({
      event: "confirm_staking",
      payload: {action_id: "first", transaction_hash: mainHash, approval_transaction_hash: null},
    })

    await hook.emit("staking:confirmed", {})

    execute.mockImplementationOnce(async () => {
      throw Object.assign(new Error("User rejected the request."), {code: 4001})
    })
    await hook.emit("staking:prepared", {envelope: envelope({action_id: "second", approval: null})})

    expect(hook.pushed).toContainEqual({
      event: "staking_wallet_rejected",
      payload: {action_id: "second", phase: "action", code: 4001},
    })
  })

  it("reports the rejection for the approval phase the wallet was actually asked for", async () => {
    const hook = mountStakeWallet()

    execute.mockImplementationOnce(async () => {
      throw Object.assign(new Error("User rejected the request."), {code: 4001})
    })
    await hook.emit("staking:prepared", {envelope: envelope({action_id: "approval-only"})})

    expect(hook.pushed).toContainEqual({
      event: "staking_wallet_rejected",
      payload: {action_id: "approval-only", phase: "approval", code: 4001},
    })
  })
})

describe("U1_BOUNDED_WALLET_COPY: only closed reason keys leave the browser", () => {
  const execute = vi.mocked(executePreparedStakingAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  it("reports the unknown key instead of the provider's own message", async () => {
    const hook = mountStakeWallet()
    execute.mockImplementationOnce(async () => {
      throw new Error("execution reverted: allowance 0xdeadbeef (Safe transaction service)")
    })

    await hook.emit("staking:prepared", {envelope: envelope({action_id: "failed", approval: null})})

    expect(hook.pushed).toContainEqual({
      event: "staking_wallet_failed",
      payload: {reason: "unknown"},
    })
    expect(JSON.stringify(hook.pushed)).not.toContain("execution reverted")
  })

  it("reports the unavailable review wallet without naming any provider", async () => {
    vi.mocked(connectedEthereumWallet).mockReturnValueOnce(null)
    const hook = mountStakeWallet()

    await hook.emit("staking:prepared", {envelope: envelope({action_id: "absent"})})

    expect(hook.pushed).toEqual([
      {event: "staking_wallet_failed", payload: {reason: "wallet_unavailable"}},
    ])
  })
})

describe("U1_BOUNDED_WALLET_COPY: a precise revert is the whole outcome", () => {
  const execute = vi.mocked(executePreparedStakingAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  // A generic failure after a precise revert would replace the exact outcome
  // the server can still bind to the stored hash with copy nobody can act on.
  it("reports the reverted approval for its bound hash and nothing after it", async () => {
    const hook = mountStakeWallet()
    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options?.onSubmitted?.("approval", approvalHash)
      throw new WalletExecutionError("approval_reverted", "reverted")
    })

    await hook.emit("staking:prepared", {envelope: envelope({action_id: "approval-revert"})})

    expect(hook.pushed).toEqual([
      {
        event: "staking_submitted",
        payload: {action_id: "approval-revert", phase: "approval", transaction_hash: approvalHash},
      },
      {
        event: "staking_approval_reverted",
        payload: {action_id: "approval-revert", transaction_hash: approvalHash},
      },
    ])
  })

  it("reports the reverted action for its bound hash and nothing after it", async () => {
    const hook = mountStakeWallet()
    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options?.onSubmitted?.("action", mainHash)
      throw new WalletExecutionError("action_reverted", "reverted")
    })

    await hook.emit("staking:prepared", {
      envelope: envelope({action_id: "action-revert", approval: null}),
    })

    expect(hook.pushed).toEqual([
      {
        event: "staking_submitted",
        payload: {action_id: "action-revert", phase: "action", transaction_hash: mainHash},
      },
      {
        event: "confirm_staking",
        payload: {
          action_id: "action-revert",
          transaction_hash: mainHash,
          approval_transaction_hash: null,
        },
      },
    ])
  })

  it("keeps the fixed unknown failure when the revert has no bound hash", async () => {
    const hook = mountStakeWallet()
    execute.mockImplementationOnce(async () => {
      throw new WalletExecutionError("action_reverted", "reverted")
    })

    await hook.emit("staking:prepared", {envelope: envelope({action_id: "unbound", approval: null})})

    expect(hook.pushed).toEqual([{event: "staking_wallet_failed", payload: {reason: "unknown"}}])
  })
})

describe("U2_NEUTRAL_REJECTION: the rejection is the whole outcome", () => {
  const execute = vi.mocked(executePreparedStakingAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  // A failure event after the rejection would replace the neutral "nothing was
  // sent" notice with an error the customer did not cause.
  it("sends the rejection and nothing that could overwrite its neutral notice", async () => {
    const hook = mountStakeWallet()
    execute.mockImplementationOnce(async () => {
      throw Object.assign(new Error("User rejected the request."), {code: 4001})
    })

    await hook.emit("staking:prepared", {
      envelope: envelope({action_id: "rejected", approval: null}),
    })

    expect(hook.pushed).toEqual([
      {
        event: "staking_wallet_rejected",
        payload: {action_id: "rejected", phase: "action", code: 4001},
      },
    ])
  })
})

describe("U5_EXPECTED_SIGNER_TRUTH: the copy button carries the reviewed signer", () => {
  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  it("copies the exact address the review rendered and says so on that button", async () => {
    const writeText = vi.fn(async () => undefined)
    vi.stubGlobal("navigator", {clipboard: {writeText}})
    const hook = mountStakeWallet()
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
    const hook = mountStakeWallet()

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

function mountStakeWallet(): {
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

  ;(StakeWallet.mounted as (this: typeof hook) => void).call(hook)

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
