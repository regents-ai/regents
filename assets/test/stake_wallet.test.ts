import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"
import {encodeFunctionData, parseAbi, type Address, type Hash} from "viem"

import {activeEthereumWallet} from "../js/wallet_actions/connected_wallet"
import {
  executePreparedStakingAction,
  type ExecutionOptions,
  type PreparedStakingAction,
  type StakingClients,
} from "../js/wallet_actions/staking"
import {
  activeSigner,
  recordSubmittedAction,
  StakeWallet,
  userRejected,
} from "../js/hooks/stake_wallet"

// The active wallet stub answers `eth_accounts` with the reviewed signer, so a
// test that wants a failed preflight has to say so explicitly.
const walletStub = vi.hoisted(() => {
  const address = "0x1111111111111111111111111111111111111111"
  return {
    address,
    accounts: [address] as unknown,
    selected: address as string | null,
  }
})

vi.mock("../js/wallet_actions/connected_wallet", () => ({
  activeEthereumWallet: vi.fn(() => activeWalletStub()),
}))

function activeWalletStub() {
  return walletStub.selected
    ? {
        address: walletStub.selected,
        provider: {
          request: vi.fn(async ({method}: {method: string}) =>
            method === "eth_accounts" ? walletStub.accounts : undefined,
          ),
        },
      }
    : null
}

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
    ...overrides,
  }
}

const provider = {request: vi.fn(async () => undefined)}

// The executor demands its send boundary at every call site, so a caller can
// never lose the one fact that separates "never asked" from "may have sent".
const sendBoundary: ExecutionOptions = {onSendStarted: () => undefined}

// The same boundary with the marker a test can read back.
function markedBoundary(): {marker: {started: boolean}} & ExecutionOptions {
  const marker = {started: false}
  return {marker, onSendStarted: () => (marker.started = true)}
}

beforeEach(() => {
  walletStub.selected = walletStub.address
  walletStub.accounts = [walletStub.address]
})

describe("staking wallet action", () => {
  it("matches viem ABI bytes and completes exact approval before the stake", async () => {
    const prepared = envelope()
    expect(prepared.data).toBe(
      "0x7acb775700000000000000000000000000000000000000000000000014d1120d7b1600000000000000000000000000001111111111111111111111111111111111111111",
    )

    // The approval send is the whole attempt: the stake is not also sent, and it
    // follows only once an already-sent approval is carried back in.
    const approvalBoundary = clients()
    const approvalSubmitted = vi.fn()
    await executePreparedStakingAction(prepared, provider, approvalBoundary, {
      ...sendBoundary,
      onSubmitted: approvalSubmitted,
    })

    expect(approvalBoundary.send).toHaveBeenCalledOnce()
    expect(approvalSubmitted).toHaveBeenCalledExactlyOnceWith("approval", approvalHash)

    const mainBoundary = clients({send: vi.fn(async () => mainHash)})
    const mainSubmitted = vi.fn()
    await executePreparedStakingAction(prepared, provider, mainBoundary, {
      ...sendBoundary,
      existingApprovalHash: approvalHash,
      onSubmitted: mainSubmitted,
    })

    expect(mainBoundary.send).toHaveBeenCalledOnce()
    expect(mainSubmitted).toHaveBeenCalledExactlyOnceWith("action", mainHash)
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

    await executePreparedStakingAction(envelope(), provider, boundary, sendBoundary)

    expect(boundary.switchToBase).toHaveBeenCalledOnce()
    expect(chainId).toHaveBeenCalledTimes(2)
  })

  it("fails closed on signer, chain, stale envelope, calldata and target", async () => {
    await expect(
      executePreparedStakingAction(
        envelope(),
        provider,
        clients({
          addresses: vi.fn(async () => [
            "0x2222222222222222222222222222222222222222" as Address,
          ]),
        }),
        sendBoundary,
      ),
    ).rejects.toThrow("connected wallet")

    await expect(
      executePreparedStakingAction(
        envelope(),
        provider,
        clients({chainId: vi.fn(async () => 1)}),
        sendBoundary,
      ),
    ).rejects.toThrow("Switch to Base")

    await expect(
      executePreparedStakingAction(
        envelope({expires_at: new Date(0).toISOString()}),
        provider,
        clients(),
        sendBoundary,
      ),
    ).rejects.toThrow("expired")

    await expect(
      executePreparedStakingAction(envelope({data: "0xdeadbeef"}), provider, clients(), sendBoundary),
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
        sendBoundary,
      ),
    ).rejects.toThrow("approval changed")

    await expect(
      executePreparedStakingAction(
        envelope({arguments: {amount_atomic: "1500000000000000000", receiver: "0x2222222222222222222222222222222222222222"}}),
        provider,
        clients(),
        sendBoundary,
      ),
    ).rejects.toThrow("recipient changed")

    await expect(
      executePreparedStakingAction(
        envelope({expires_at: "not-a-date"}),
        provider,
        clients(),
        sendBoundary,
      ),
    ).rejects.toThrow("expired")

    await expect(
      executePreparedStakingAction(
        envelope({to: "0x2222222222222222222222222222222222222222"}),
        provider,
        clients(),
        sendBoundary,
      ),
    ).rejects.toThrow("target changed")

    const badApproval = envelope().approval!
    await expect(
      executePreparedStakingAction(
        envelope({approval: {...badApproval, spender: "0x2222222222222222222222222222222222222222"}}),
        provider,
        clients(),
        sendBoundary,
      ),
    ).rejects.toThrow("approval changed")
  })
})

describe("R1_SEND_MARKER_IS_THE_BOUNDARY: the executor marks each send before making it", () => {
  it("marks the boundary before an approval send and before an action send that both throw", async () => {
    for (const prepared of [envelope(), envelope({approval: null})]) {
      const marked = markedBoundary()
      const boundary = clients({
        send: vi.fn(async () => {
          expect(marked.marker.started).toBe(true)
          throw new Error("the wallet closed")
        }),
      })

      await expect(
        executePreparedStakingAction(prepared, provider, boundary, marked),
      ).rejects.toThrow("the wallet closed")

      expect(marked.marker.started).toBe(true)
      expect(boundary.send).toHaveBeenCalledOnce()
    }
  })

  it("leaves the boundary unmarked for every failure that precedes the send", async () => {
    const rejectedSwitch = Object.assign(new Error("User rejected the request."), {code: 4001})
    const cases = [
      // An envelope that crossed its expiry in the server-to-browser gap.
      {prepared: envelope({expires_at: new Date(0).toISOString()}), boundary: clients()},
      // A chain switch the customer rejected: a prompt, never a transaction.
      {
        prepared: envelope(),
        boundary: clients({
          chainId: vi.fn(async () => 1),
          switchToBase: vi.fn(async () => {
            throw rejectedSwitch
          }),
        }),
      },
      // The provider's account is no longer the reviewed signer.
      {prepared: envelope(), boundary: clients({addresses: vi.fn(async () => [])})},
      // Simulation refused the call before it could be signed.
      {
        prepared: envelope(),
        boundary: clients({
          simulate: vi.fn(async () => {
            throw new Error("execution reverted")
          }),
        }),
      },
    ]

    for (const {prepared, boundary} of cases) {
      const marked = markedBoundary()

      await expect(
        executePreparedStakingAction(prepared, provider, boundary, marked),
      ).rejects.toThrow()

      expect(marked.marker.started).toBe(false)
      expect(boundary.send).not.toHaveBeenCalled()
    }
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
      options.onSendStarted()
      options.onSubmitted?.("action", mainHash)
    })
    await hook.emit("staking:prepared", {envelope: envelope({action_id: "first", approval: null})})
    expect(hook.pushed).toContainEqual({
      event: "staking_submitted",
      payload: {action_id: "first", phase: "action", transaction_hash: mainHash},
    })

    await hook.emit("staking:confirmed", {})

    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options.onSendStarted()
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

    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options.onSendStarted()
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
    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options.onSendStarted()
      throw new Error("execution reverted: allowance 0xdeadbeef (Safe transaction service)")
    })

    await hook.emit("staking:prepared", {envelope: envelope({action_id: "failed", approval: null})})

    expect(hook.pushed).toContainEqual({
      event: "staking_wallet_failed",
      payload: {reason: "unknown"},
    })
    expect(JSON.stringify(hook.pushed)).not.toContain("execution reverted")
  })

  // The claim is already durable and the wallet was never asked for anything,
  // so this releases the exact phase instead of describing a failure. The event
  // names only the action and the phase: no provider text can ride out on it.
  it("reports the unavailable review wallet without naming any provider", async () => {
    const hook = mountStakeWallet()
    vi.mocked(activeEthereumWallet).mockReturnValueOnce(null)

    await hook.emit("staking:prepared", {envelope: envelope({action_id: "absent"})})

    expect(hook.pushed).toEqual([
      {event: "staking_dispatch_not_started", payload: {action_id: "absent", phase: "approval"}},
    ])
  })
})

describe("P1_ACTIVE_WALLET_ONLY: Stake follows Privy's selection", () => {
  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  it("reports the active wallet on mount and nothing when there is none", () => {
    expect(mountStakeWallet().mountPushed).toEqual([
      {event: "staking_active_wallet", payload: {address: walletStub.address}},
    ])

    walletStub.selected = null
    expect(mountStakeWallet().mountPushed).toEqual([
      {event: "staking_active_wallet", payload: {address: null}},
    ])
  })

  it("asks Privy's own chooser to open instead of picking a wallet itself", async () => {
    const hook = mountStakeWallet()

    await hook.click(stubElement({stakeConnect: ""}))

    expect(hook.windowEvents).toEqual(["ash:wallet-connect"])
    expect(hook.pushed).toEqual([])
  })
})

describe("P4_PREFLIGHT_IS_INPUT: nothing is claimed before the signer is proven", () => {
  const execute = vi.mocked(executePreparedStakingAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  it("recognises the reviewed signer only when the provider's account is exactly it", async () => {
    await expect(activeSigner(wallet)).resolves.toBe(wallet)

    walletStub.accounts = ["0x2222222222222222222222222222222222222222"]
    await expect(activeSigner(wallet)).resolves.toBeNull()

    walletStub.accounts = []
    await expect(activeSigner(wallet)).resolves.toBeNull()

    walletStub.accounts = "not-a-list"
    await expect(activeSigner(wallet)).resolves.toBeNull()

    walletStub.accounts = [wallet]
    walletStub.selected = "0x2222222222222222222222222222222222222222"
    await expect(activeSigner(wallet)).resolves.toBeNull()

    walletStub.selected = null
    await expect(activeSigner(wallet)).resolves.toBeNull()
  })

  it("asks for the dispatch only after a matching preflight", async () => {
    const hook = mountStakeWallet()

    await hook.click(stubElement({stakeConfirm: "reviewed", stakeSigner: wallet}))
    expect(hook.pushed).toEqual([
      {event: "sign_prepared_staking", payload: {"action-id": "reviewed", address: wallet}},
    ])

    // The wallet moved to another account: nothing is claimed, and the copy says
    // which wallet the review still needs.
    hook.pushed.length = 0
    walletStub.accounts = ["0x2222222222222222222222222222222222222222"]
    await hook.click(stubElement({stakeConfirm: "reviewed", stakeSigner: wallet}))
    expect(hook.pushed).toEqual([
      {event: "staking_wallet_failed", payload: {reason: "wallet_unavailable"}},
    ])
  })

  // The server verified the approval receipt and the exact allowance. The stake
  // follows through the same preflight and never reapproves.
  it("continues into the stake through the same preflight", async () => {
    const hook = mountStakeWallet()

    await hook.emit("staking:continue", {action_id: "reviewed", expected_signer: wallet})
    expect(hook.pushed).toEqual([
      {event: "sign_prepared_staking", payload: {"action-id": "reviewed", address: wallet}},
    ])
  })

  // The dispatch is already claimed. A wallet that moved in between never
  // reaches the executor at all, so nothing was signed and nothing was
  // broadcast: the claim is released and the same review stays retryable.
  it("preserves a claimed dispatch when the signer changed after the push", async () => {
    const hook = mountStakeWallet()
    const attempts = execute.mock.calls.length
    walletStub.accounts = ["0x2222222222222222222222222222222222222222"]

    await hook.emit("staking:prepared", {
      envelope: envelope({action_id: "claimed", approval: null}),
    })

    expect(hook.pushed).toEqual([
      {event: "staking_dispatch_not_started", payload: {action_id: "claimed", phase: "action"}},
    ])
    expect(execute.mock.calls).toHaveLength(attempts)
  })
})

describe("R1_SEND_MARKER_IS_THE_BOUNDARY: the marker alone decides what the page may claim", () => {
  const execute = vi.mocked(executePreparedStakingAction)

  beforeEach(() => stubSessionStorage())
  afterEach(() => vi.unstubAllGlobals())

  // Validation, chain, account and simulation failures all land here. None of
  // them is recognised by its message: the unmarked boundary is the whole proof.
  it("releases the claimed phase for any failure the wallet never saw", async () => {
    const hook = mountStakeWallet()
    execute.mockImplementationOnce(async () => {
      throw new Error("execution reverted: allowance 0xdeadbeef")
    })

    await hook.emit("staking:prepared", {envelope: envelope({action_id: "unsent", approval: null})})

    expect(hook.pushed).toEqual([
      {event: "staking_dispatch_not_started", payload: {action_id: "unsent", phase: "action"}},
    ])
  })

  // A rejected chain-switch prompt is still a rejection, but nothing was ever
  // offered to sign, so the review is retryable rather than closed.
  it("releases the claimed phase when the rejection came before the send", async () => {
    const hook = mountStakeWallet()
    execute.mockImplementationOnce(async () => {
      throw Object.assign(new Error("User rejected the request."), {code: 4001})
    })

    await hook.emit("staking:prepared", {
      envelope: envelope({action_id: "switch", approval: null}),
    })

    expect(hook.pushed).toEqual([
      {event: "staking_dispatch_not_started", payload: {action_id: "switch", phase: "action"}},
    ])
  })

  // The marker belongs to one dispatch, not to the page. An approval that was
  // really sent must not make the stake that follows it look sent too.
  it("starts the stake with a fresh marker after the approval was already sent", async () => {
    const hook = mountStakeWallet()

    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options.onSendStarted()
      options.onSubmitted?.("approval", approvalHash)
    })
    await hook.emit("staking:prepared", {envelope: envelope({action_id: "two-phase"})})

    expect(hook.pushed).toEqual([
      {
        event: "staking_submitted",
        payload: {action_id: "two-phase", phase: "approval", transaction_hash: approvalHash},
      },
    ])

    hook.pushed.length = 0
    execute.mockImplementationOnce(async () => {
      throw new Error("the account moved")
    })
    await hook.emit("staking:prepared", {
      envelope: envelope({action_id: "two-phase"}),
      approval_transaction_hash: approvalHash,
    })

    expect(hook.pushed).toEqual([
      {event: "staking_dispatch_not_started", payload: {action_id: "two-phase", phase: "action"}},
    ])
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
    execute.mockImplementationOnce(async (_envelope, _provider, _clients, options) => {
      options.onSendStarted()
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
type StubElement = {
  textContent: string
  dataset: Record<string, string>
  closest: (selector: string) => StubElement | null
}

function mountStakeWallet(): {
  pushed: Emitted[]
  mountPushed: Emitted[]
  windowEvents: string[]
  emit(event: string, payload: unknown): unknown
  click(target: unknown): Promise<unknown[]>
} {
  const pushed: Emitted[] = []
  const handlers = new Map<string, (payload: unknown) => unknown>()
  const clicks: Array<(event: Event) => unknown> = []
  const windowEvents: string[] = []
  const buttons = [] as unknown as NodeListOf<HTMLButtonElement>
  vi.stubGlobal("window", {
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
    dispatchEvent: (event: {type: string}) => windowEvents.push(event.type),
  })
  vi.stubGlobal("CustomEvent", class {
    constructor(readonly type: string) {}
  })
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
  const mountPushed = [...pushed]
  pushed.length = 0

  return {
    pushed,
    mountPushed,
    windowEvents,
    emit: (event, payload) => handlers.get(event)?.(payload),
    click: target => Promise.all(clicks.map(listener => listener({target} as unknown as Event))),
  }
}

// The reviewed markup puts each behaviour on the button itself, so the clicked
// element is its own `closest` match for exactly the selector it carries.
function stubElement(dataset: Record<string, string>): StubElement {
  const element: StubElement = {
    textContent: "Copy",
    dataset,
    closest: selector =>
      Object.keys(dataset).some(key => selector === `[${kebab(key)}]`) ? element : null,
  }

  return element
}

function copyButton(signer: string): StubElement {
  return stubElement({copySigner: signer})
}

function kebab(key: string): string {
  return `data-${key.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`)}`
}

function stubSessionStorage(): void {
  const entries = new Map<string, string>()
  vi.stubGlobal("sessionStorage", {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => entries.set(key, value),
    removeItem: (key: string) => entries.delete(key),
  })
}
