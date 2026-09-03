import {afterEach, describe, expect, it, vi} from "vitest"
import {encodeFunctionData, getAddress, parseAbi, type Abi, type Address, type Hex} from "viem"

import chainManifest from "../../contracts/base-mainnet.json"
import stakingAbiJson from "../../contracts/abi/regent-revenue-staking.json"
import {StakeWallet} from "../js/hooks/stake_wallet"
import type {EthereumProvider, SelectedWallet} from "../js/wallet_actions/connected_wallet"
import {
  executeStakingClick,
  prepareStakingClick,
  StakingLocalRefusal,
  type ImmediateStakingResult,
  type PreparedStakingClick,
  type StakingAction,
  type StakingExecutionCallbacks,
  type StakingRuntime,
  type StakingTiming,
  type SubmittedStakingTransaction,
} from "../js/wallet_actions/staking"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const otherWallet = getAddress("0x2222222222222222222222222222222222222222")
const staking = getAddress(chainManifest.contracts.regent_revenue_staking.address)
const token = getAddress(
  chainManifest.contracts.regent_revenue_staking.onchain_constants.stake_token,
)
const stakingAbi = stakingAbiJson as Abi
const approvalAbi = parseAbi(["function approve(address spender,uint256 amount)"])
const amount = 1_500_000_000_000_000_000n
const hash = `0x${"ab".repeat(32)}` as const
const secondHash = `0x${"de".repeat(32)}` as const
const approvalIncomplete =
  "The wallet token approval step has not been completed yet, check popup windows or try again"
type ProviderRequest = {method: string; params?: unknown[]}

afterEach(() => {
  vi.useRealTimers()
})

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  const promise = new Promise<T>(done => (resolve = done))
  return {promise, resolve}
}

function fakeProvider(
  handler: (request: ProviderRequest) => unknown | Promise<unknown>,
): {provider: EthereumProvider; requests: ProviderRequest[]} {
  const requests: ProviderRequest[] = []
  return {
    requests,
    provider: {
      request: async request => {
        requests.push(request)
        return handler(request)
      },
    },
  }
}

function rendered(
  action: StakingAction,
  overrides: Partial<{
    amount: string
    allowanceAtomic: string
    chainId: string
    expectedSigner: string
  }> = {},
) {
  return {
    action,
    amount: "1.5",
    allowanceAtomic: amount.toString(),
    chainId: "8453",
    expectedSigner: wallet,
    ...overrides,
  }
}

function prepare(
  action: StakingAction,
  walletSelection: SelectedWallet,
  overrides: Parameters<typeof rendered>[1] = {},
  actionId = crypto.randomUUID(),
): PreparedStakingClick {
  return prepareStakingClick(rendered(action, overrides), walletSelection, {
    actionId,
    traceId: crypto.randomUUID(),
  })
}

function liveRuntime(): StakingRuntime {
  return {alive: () => true, hostAlive: () => true, registerCancellation: () => () => undefined}
}

function callbackRecorder() {
  const claims = new Set<string>()
  const timing: StakingTiming[] = []
  const immediate: ImmediateStakingResult[] = []
  const submitted: SubmittedStakingTransaction[] = []
  const started: string[] = []
  const timedOut: string[] = []
  const callbacks: StakingExecutionCallbacks = {
    claimRole: (actionId, role) => {
      const key = `${actionId}:${role}`
      if (claims.has(key)) return false
      claims.add(key)
      return true
    },
    timing: event => timing.push(event),
    walletRequestStarted: (actionId, role) => started.push(`${actionId}:${role}`),
    handoffTimedOut: (actionId, role) => timedOut.push(`${actionId}:${role}`),
    immediate: result => immediate.push(result),
    submitted: transaction => submitted.push(transaction),
  }
  return {callbacks, timing, immediate, submitted, started, timedOut}
}

function selected(provider: EthereumProvider, address: Address = wallet): SelectedWallet {
  return {address, provider}
}

function stakingHookProvider(options: {
  chainResponses?: Array<string | Promise<string> | "hang">
  sendResponses?: Array<`0x${string}` | Promise<`0x${string}`> | "hang" | "reject" | "fail">
  observation?: "pending" | "unavailable" | "manual"
} = {}): {
  provider: EthereumProvider
  requests: ProviderRequest[]
  observation?: "pending" | "unavailable" | "manual"
} {
  const chainResponses = [...(options.chainResponses ?? [])]
  const sendResponses = [...(options.sendResponses ?? [])]
  const transactions = new Map<string, {from: string; to: string; data: string}>()
  const requests: ProviderRequest[] = []
  const provider: EthereumProvider = {
    request: async request => {
      requests.push(request)
      switch (request.method) {
        case "eth_chainId": {
          const response = chainResponses.shift() ?? "0x2105"
          if (response === "hang") return new Promise<never>(() => undefined)
          return response
        }
        case "eth_accounts":
          return [wallet]
        case "eth_estimateGas":
          return "0x5208"
        case "wallet_switchEthereumChain":
          return null
        case "eth_sendTransaction": {
          const transaction = request.params?.[0] as {
            from: string
            to: string
            data: string
          }
          const response = sendResponses.shift() ?? secondHash
          if (response === "hang") return new Promise<never>(() => undefined)
          if (response === "reject") throw {code: 4001}
          if (response === "fail") throw new Error("wallet transport unavailable")
          const resolved = await response
          transactions.set(resolved, transaction)
          return resolved
        }
        default:
          return "0x"
      }
    },
  }
  return {provider, requests, observation: options.observation}
}

type StakeHookHarness = {
  provider: EthereumProvider
  requests: ProviderRequest[]
  rootListeners: Map<string, (event: Event) => void>
  windowListeners: Map<string, () => void>
  dispatched: string[]
  fakeWindow: {
    location: {origin: string}
    __ashPlatformTestWallet?: {address: string; provider: EthereumProvider}
  }
  click(action: StakingAction): void
  editAmountActionAndFill(): void
  setWallet(address: string, provider: EthereumProvider): void
  releaseWallet(): void
  destroy(): void
  dialog: {open: boolean; close: () => void; showModal: ReturnType<typeof vi.fn>}
  dialogTitle: {textContent: string}
  text: {textContent: string}
  detail: {textContent: string}
  link: {hidden: boolean; href: string}
  pushEvent: ReturnType<typeof vi.fn>
  settleNext(result: "success" | "reverted" | "delayed" | "unavailable"): void
}

function stakingHookHarness(
  source: ReturnType<typeof stakingHookProvider>,
  allowanceAtomic = amount.toString(),
): StakeHookHarness {
  const provider = source.provider
  const windowListeners = new Map<string, () => void>()
  const dispatched: string[] = []
  const fakeWindow: {
    location: {origin: string}
    __ashPlatformTestWallet?: {address: string; provider: EthereumProvider}
    addEventListener: (event: string, listener: () => void) => void
    removeEventListener: (event: string) => void
    dispatchEvent: (event: Event) => void
  } = {
    location: {origin: "http://127.0.0.1:4002"},
    __ashPlatformTestWallet: {address: wallet, provider},
    addEventListener: (event, listener) => void windowListeners.set(event, listener),
    removeEventListener: event => void windowListeners.delete(event),
    dispatchEvent: event => void dispatched.push(event.type),
  }
  vi.stubGlobal("window", fakeWindow)

  const text = {textContent: ""}
  const dialogTitle = {textContent: ""}
  const detail = {textContent: ""}
  const walletText = {textContent: ""}
  const link = {
    textContent: "",
    hidden: true,
    href: "",
    target: "",
    rel: "",
    removeAttribute: vi.fn(),
  }
  const dialogListeners = new Map<string, () => void>()
  const dialog = {
    open: false,
    isConnected: true,
    dataset: {},
    querySelector: (selector: string) => {
      if (selector === "[data-staking-result-title]") return dialogTitle
      if (selector === "[data-staking-result-text]") return text
      if (selector === "[data-staking-result-detail]") return detail
      if (selector === "[data-staking-result-wallet]") return walletText
      return link
    },
    addEventListener: vi.fn((event: string, listener: () => void) => dialogListeners.set(event, listener)),
    removeEventListener: vi.fn((event: string) => dialogListeners.delete(event)),
    showModal: vi.fn(() => {
      dialog.open = true
    }),
    close: vi.fn(() => {
      dialog.open = false
      dialogListeners.get("close")?.()
    }),
  }
  const input = {value: "1.5"}
  const heading = {focus: vi.fn(), isConnected: true, closest: () => null, hasAttribute: () => false}
  const rootListeners = new Map<string, (event: Event) => void>()
  const root = {
    isConnected: true,
    dataset: {
      stakingAllowance: allowanceAtomic,
      stakingChainId: "8453",
      stakingSigner: wallet,
    },
    querySelector: (selector: string) => {
      if (selector === "#staking-result-dialog") return dialog
      if (selector === "#staking-amount") return input
      return heading
    },
    addEventListener: vi.fn((event: string, listener: (event: Event) => void) =>
      rootListeners.set(event, listener)),
    removeEventListener: vi.fn((event: string) => rootListeners.delete(event)),
  }
  let transactionResult!: (payload: unknown) => void
  const pendingObservations: string[] = []
  const pushEvent = vi.fn((event: string, payload: {observation_id?: string}) => {
    if (event !== "observe_staking_transaction" || !payload.observation_id) return
    if (source.observation === "manual") {
      pendingObservations.push(payload.observation_id)
      return
    }
    const result = source.observation === "pending" ? "delayed" : source.observation ?? "success"
    queueMicrotask(() => transactionResult({observation_id: payload.observation_id, result}))
  })
  const hook = {
    el: root,
    pushEvent,
    handleEvent: vi.fn((event: string, listener: (payload: unknown) => void) => {
      if (event === "staking:transaction-result") transactionResult = listener
    }),
  }
  StakeWallet.mounted!.call(hook as never)

  const click = (action: StakingAction): void => {
    const initiator = {
      dataset: {stakingAction: action},
      focus: vi.fn(),
      isConnected: true,
      closest: (selector: string) => selector === "[data-staking-action]" ? initiator : null,
      hasAttribute: () => false,
    }
    rootListeners.get("click")!({
      target: {closest: (selector: string) =>
        selector === "[data-staking-action]" ? initiator : null},
      preventDefault: vi.fn(),
    } as unknown as MouseEvent)
  }
  const editAmountActionAndFill = (): void => {
    for (const eventName of ["select_staking_action", "fill_staking_amount"]) {
      const target = {
        closest: (selector: string) => selector.includes(eventName) ? target : null,
      }
      rootListeners.get("click")!({target} as unknown as MouseEvent)
    }

    const amountTarget = {
      closest: (selector: string) => selector.includes("#staking-amount") ? amountTarget : null,
    }
    rootListeners.get("input")?.({target: amountTarget} as unknown as Event)
    rootListeners.get("change")?.({target: amountTarget} as unknown as Event)
  }
  const setWallet = (address: string, nextProvider: EthereumProvider): void => {
    fakeWindow.__ashPlatformTestWallet = {address, provider: nextProvider}
    windowListeners.get("ash:wallet-state")?.()
  }
  const releaseWallet = (): void => {
    delete fakeWindow.__ashPlatformTestWallet
    windowListeners.get("ash:wallet-state")?.()
  }
  const destroy = (): void => {
    StakeWallet.destroyed!.call(hook as never)
  }

  return {
    provider,
    requests: source.requests,
    rootListeners,
    windowListeners,
    fakeWindow,
    dispatched,
    click,
    editAmountActionAndFill,
    setWallet,
    releaseWallet,
    destroy,
    dialog,
    dialogTitle,
    text,
    detail,
    link,
    pushEvent,
    settleNext: result => {
      const observationId = pendingObservations.shift()
      if (observationId) transactionResult({observation_id: observationId, result})
    },
  }
}

async function flushStakeHookPromises(): Promise<void> {
  for (let index = 0; index < 8; index += 1) await Promise.resolve()
}

describe("stake hook ownership and result ordering", () => {
  it("asks the wallet bridge for Privy's wallets as soon as it mounts", () => {
    const harness = stakingHookHarness(stakingHookProvider())

    expect(harness.dispatched).toEqual(["ash:wallet-sync"])
    harness.destroy()
  })

  // Disconnect leaves this page with no wallet at all, and the server is told
  // exactly that rather than being left holding the last one.
  it("tells the server it has no wallet once every wallet is released", () => {
    const harness = stakingHookHarness(stakingHookProvider())

    harness.releaseWallet()

    expect(harness.pushEvent).toHaveBeenCalledWith("staking_active_wallet", {address: null})
    harness.destroy()
  })

  it("cancels a hung pre-send phase on teardown before it can send", async () => {
    const chain = deferred<string>()
    const source = stakingHookProvider({chainResponses: [chain.promise]})
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    await vi.waitFor(() => expect(harness.requests.map(request => request.method)).toContain("eth_chainId"))
    harness.destroy()
    chain.resolve("0x2105")
    await flushStakeHookPromises()

    expect(harness.requests.map(request => request.method)).not.toContain("eth_sendTransaction")
    expect(harness.dialog.showModal).not.toHaveBeenCalled()
  })

  it.each([
    ["claim", "claim_regent" as const, amount.toString()],
    ["allowance-sufficient stake", "stake" as const, amount.toString()],
  ])("invalidates a %s click across A-to-B-to-A and permits a fresh A click", async (_name, action, allowance) => {
    const chain = deferred<string>()
    const source = stakingHookProvider({chainResponses: [chain.promise]})
    const other = stakingHookProvider()
    const harness = stakingHookHarness(source, allowance)

    harness.click(action)
    await vi.waitFor(() => expect(harness.requests).toHaveLength(1))
    harness.setWallet(otherWallet, other.provider)
    harness.setWallet(wallet, source.provider)
    chain.resolve("0x2105")
    await flushStakeHookPromises()
    expect(harness.requests.map(request => request.method)).not.toContain("eth_sendTransaction")

    harness.click(action)
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    harness.destroy()
  })

  it.each([
    ["claim", "claim_regent" as const, "Your available REGENT rewards were claimed."],
    ["stake", "stake" as const, "1.5 REGENT was staked successfully."],
  ])("preserves a handed-off %s and its result across amount, action, and fill edits", async (_name, action, message) => {
    vi.useFakeTimers()
    const source = stakingHookProvider()
    const harness = stakingHookHarness(source)

    harness.click(action)
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    harness.editAmountActionAndFill()

    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe(message)

    harness.editAmountActionAndFill()
    expect(harness.dialog.open).toBe(true)
    expect(harness.text.textContent).toBe(message)
    harness.destroy()
  })

  it("presents a submitted approval and invalidates its main send across A-to-B-to-A", async () => {
    const actionChain = deferred<string>()
    const source = stakingHookProvider({chainResponses: ["0x2105", actionChain.promise]})
    const other = stakingHookProvider()
    const harness = stakingHookHarness(source, "0")

    harness.click("stake")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    harness.setWallet(otherWallet, other.provider)
    harness.setWallet(wallet, source.provider)
    actionChain.resolve("0x2105")
    await flushStakeHookPromises()

    expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    harness.destroy()
  })

  it("keeps a signed approval visible when the following stake request is canceled", async () => {
    const source = stakingHookProvider({sendResponses: [hash, "reject"]})
    const harness = stakingHookHarness(source, "0")

    harness.click("stake")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(2),
    )

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("REGENT spending was approved successfully.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${hash}`)

    harness.dialog.close()
    expect(harness.dialog.showModal).toHaveBeenCalledTimes(2)
    expect(harness.text.textContent).toBe("Request canceled.")
    harness.destroy()
  })

  // A stake whose approval never gets confirmed is the same dead end however the
  // approval ended, and the customer is told so instead of being left with a
  // page that did nothing.
  it.each([
    ["a rejected", "reject" as const],
    ["a failed", "fail" as const],
    ["an unusable", "0x1" as const],
  ])("names the unfinished approval step after %s approval and clears it on the next attempt", async (_name, response) => {
    const source = stakingHookProvider({sendResponses: [response, hash, secondHash]})
    const harness = stakingHookHarness(source, "0")

    harness.click("stake")
    await vi.waitFor(() => expect(harness.dialog.showModal).toHaveBeenCalledOnce())

    expect(harness.dialogTitle.textContent).toBe("Stake not completed")
    expect(harness.text.textContent).toBe(approvalIncomplete)
    expect(harness.detail.textContent)
      .toBe("No confirmed Base transaction changed your staking position.")
    expect(harness.link.hidden).toBe(true)
    // The stake behind the approval is still never sent.
    expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1)

    harness.dialog.close()
    harness.click("stake")
    await vi.waitFor(() => expect(harness.dialog.showModal).toHaveBeenCalledTimes(2))

    expect(harness.text.textContent).toBe("REGENT spending was approved successfully.")
    harness.destroy()
  })

  // A wrong network or a wallet that no longer matches the signer is named, and
  // sending never gets as far as a popup to go looking for.
  it("keeps the instruction for an approval that never reached the wallet", async () => {
    const source = stakingHookProvider({chainResponses: ["0x1", "0x1"]})
    const harness = stakingHookHarness(source, "0")

    harness.click("stake")
    await vi.waitFor(() => expect(harness.dialog.showModal).toHaveBeenCalledOnce())

    expect(harness.dialogTitle.textContent).toBe("Stake not completed")
    expect(harness.text.textContent).toBe("Switch to Base before continuing.")
    expect(harness.text.textContent).not.toBe(approvalIncomplete)
    expect(harness.requests.map(request => request.method)).not.toContain("eth_sendTransaction")
    harness.destroy()
  })

  // The wallet still holds the prompt when the wait runs out. The notice stands
  // until the prompt is answered, and the transaction it produces takes the
  // dialog over in place — no closing, and nothing left blank while Base is
  // still being asked about it.
  it("hands the unfinished approval step over to the transaction the wallet finally sends", async () => {
    vi.useFakeTimers()
    const heldApproval = deferred<`0x${string}`>()
    const source = stakingHookProvider({
      sendResponses: [heldApproval.promise],
      observation: "manual",
    })
    const harness = stakingHookHarness(source, "0")

    harness.click("stake")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    await vi.advanceTimersByTimeAsync(120_000)

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe(approvalIncomplete)

    heldApproval.resolve(hash)
    await flushStakeHookPromises()

    expect(harness.dialog.open).toBe(true)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.dialogTitle.textContent).toBe("Transaction submitted")
    expect(harness.text.textContent)
      .toBe("Privy returned the transaction hash. Alchemy is checking its Base result.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${hash}`)

    harness.settleNext("success")

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("REGENT spending was approved successfully.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${hash}`)
    harness.destroy()
  })

  // The customer put the notice away before the wallet answered. A rejection
  // arriving afterwards says nothing they have not already been told, and a
  // modal reopening minutes later would read as the attempt they made since.
  it("retires a dismissed approval step notice instead of reopening it on a late rejection", async () => {
    vi.useFakeTimers()
    let rejectApproval!: (reason: unknown) => void
    const heldApproval = new Promise<`0x${string}`>((_resolve, reject) => (rejectApproval = reject))
    const source = stakingHookProvider({sendResponses: [heldApproval]})
    const harness = stakingHookHarness(source, "0")

    harness.click("stake")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    await vi.advanceTimersByTimeAsync(120_000)

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe(approvalIncomplete)

    harness.dialog.close()
    rejectApproval({code: 4001})
    await flushStakeHookPromises()

    expect(harness.dialog.open).toBe(false)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    harness.destroy()
  })

  it("keeps a submitted result under its original signer after the active wallet changes", async () => {
    const source = stakingHookProvider({observation: "manual"})
    const other = stakingHookProvider()
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    harness.setWallet(otherWallet, other.provider)
    harness.settleNext("success")

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("Your available REGENT rewards were claimed.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${secondHash}`)
    harness.destroy()
  })

  it("names the latest Base block and refreshes the position once a send confirms", async () => {
    const source = stakingHookProvider({observation: "manual"})
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    expect(harness.pushEvent.mock.calls.map(([event]) => event)).not.toContain("refresh_staking")

    harness.settleNext("success")

    expect(harness.detail.textContent)
      .toBe("Your position is refreshing in place from the latest Base block.")
    expect(harness.pushEvent).toHaveBeenCalledWith("refresh_staking", {})
    harness.destroy()
  })

  it("fully retires a dismissed canonical result before the wallet changes", async () => {
    const source = stakingHookProvider({observation: "manual"})
    const other = stakingHookProvider()
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    harness.settleNext("success")
    expect(harness.dialogTitle.textContent).toBe("REGENT claim confirmed")

    harness.dialog.close()
    harness.setWallet(otherWallet, other.provider)

    expect(harness.dialog.open).toBe(false)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    harness.destroy()
  })

  it("keeps a Privy send when the wallet changes before Privy returns its hash", async () => {
    vi.useFakeTimers()
    const pendingHash = deferred<`0x${string}`>()
    const source = stakingHookProvider({sendResponses: [pendingHash.promise]})
    const other = stakingHookProvider()
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
    )
    harness.setWallet(otherWallet, other.provider)
    await vi.advanceTimersByTimeAsync(120_000)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("The submission outcome is unknown.")
    harness.dialog.close()

    pendingHash.resolve(hash)
    await flushStakeHookPromises()

    expect(harness.dialog.showModal).toHaveBeenCalledTimes(2)
    expect(harness.text.textContent).toBe("Your available REGENT rewards were claimed.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${hash}`)
    harness.destroy()
  })

  it("advances to a retained result when a wallet change removes the visible error", async () => {
    const source = stakingHookProvider({sendResponses: ["reject", secondHash]})
    const other = stakingHookProvider()
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    await vi.waitFor(() => expect(harness.dialog.showModal).toHaveBeenCalledOnce())
    expect(harness.text.textContent).toBe("Request canceled.")

    harness.click("claim_usdc")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(2),
    )
    harness.setWallet(otherWallet, other.provider)

    await vi.waitFor(() => expect(harness.dialog.showModal).toHaveBeenCalledTimes(2))
    expect(harness.text.textContent).toBe("Your available USDC rewards were claimed.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${secondHash}`)
    harness.destroy()
  })

  it("keeps a settled second result behind a hung first send until FIFO advances", async () => {
    vi.useFakeTimers()
    const source = stakingHookProvider({sendResponses: ["hang", secondHash]})
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    harness.click("claim_usdc")
    await vi.waitFor(() =>
      expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(2),
    )

    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.dialog.showModal).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(118_000)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("The submission outcome is unknown.")

    harness.dialog.close()
    expect(harness.dialog.showModal).toHaveBeenCalledTimes(2)
    expect(harness.text.textContent).toBe("Your available USDC rewards were claimed.")
    harness.destroy()
  })

  it.each([
    ["delayed", "pending" as const, 120_000, "Confirmation is taking longer"],
    ["unavailable", "unavailable" as const, 2_000, "Confirmation unavailable"],
  ])("keeps BaseScan and the outcome title available when confirmation is %s", async (_result, observation, wait, title) => {
    vi.useFakeTimers()
    const source = stakingHookProvider({observation})
    const harness = stakingHookHarness(source)

    harness.click("claim_regent")
    await vi.waitFor(() =>
      expect(harness.requests.map(request => request.method)).toContain("eth_sendTransaction"),
    )
    await vi.advanceTimersByTimeAsync(wait)

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.link.hidden).toBe(false)
    expect(harness.link.href).toBe(`https://basescan.org/tx/${secondHash}`)
    expect(harness.dialogTitle.textContent).toBe(title)
    harness.destroy()
  })
})

const actionCases: Array<{action: StakingAction; expectedData: Hex}> = [
  {
    action: "stake",
    expectedData: encodeFunctionData({
      abi: stakingAbi,
      functionName: "stake",
      args: [amount, wallet],
    }),
  },
  {
    action: "unstake",
    expectedData: encodeFunctionData({
      abi: stakingAbi,
      functionName: "unstake",
      args: [amount, wallet],
    }),
  },
  {
    action: "claim_usdc",
    expectedData: encodeFunctionData({abi: stakingAbi, functionName: "claimUSDC", args: [wallet]}),
  },
  {
    action: "claim_regent",
    expectedData: encodeFunctionData({abi: stakingAbi, functionName: "claimRegent", args: [wallet]}),
  },
  {
    action: "claim_and_restake_regent",
    expectedData: encodeFunctionData({abi: stakingAbi, functionName: "claimAndRestakeRegent"}),
  },
]

describe("local transaction construction", () => {
  it.each(actionCases)("encodes exact $action calldata with zero native value", ({action, expectedData}) => {
    const {provider, requests} = fakeProvider(() => undefined)
    const click = prepare(action, selected(provider))

    expect(click.transaction).toEqual({from: wallet, to: staking, data: expectedData, value: "0x0"})
    expect(requests).toEqual([])
  })

  it("uses the rendered allowance only to route an exact approval", () => {
    const {provider} = fakeProvider(() => undefined)
    const click = prepare("stake", selected(provider), {allowanceAtomic: "0"})

    expect(click.approval).toEqual({
      from: wallet,
      to: token,
      data: encodeFunctionData({
        abi: approvalAbi,
        functionName: "approve",
        args: [staking, amount],
      }),
      value: "0x0",
    })
  })

  it.each([
    "",
    "0",
    "0.0",
    "+1",
    "-1",
    "1e3",
    "1,000",
    "NaN",
    "Infinity",
    "1.0000000000000000001",
    (1n << 256n).toString(),
  ])("refuses invalid amount %s before any provider request", invalid => {
    const {provider, requests} = fakeProvider(() => undefined)

    expect(() => prepare("stake", selected(provider), {amount: invalid})).toThrowError(
      StakingLocalRefusal,
    )
    expect(requests).toEqual([])
  })

  it("refuses stale chain, signer, and malformed allowance data in memory", () => {
    const first = fakeProvider(() => undefined)
    const second = fakeProvider(() => undefined)

    expect(() => prepare("stake", selected(first.provider), {chainId: "1"})).toThrowError(
      StakingLocalRefusal,
    )
    expect(() => prepare("stake", selected(first.provider, otherWallet))).toThrowError(
      StakingLocalRefusal,
    )
    expect(() => prepare("stake", selected(second.provider), {allowanceAtomic: "-1"})).toThrowError(
      StakingLocalRefusal,
    )
    expect(first.requests).toEqual([])
    expect(second.requests).toEqual([])
  })
})

describe("claims the page hinted against", () => {
  it.each(actionCases.filter(({action}) => action.startsWith("claim")))(
    "sends exact $action calldata from a control the reading argued against",
    async ({action, expectedData}) => {
      // The page renders every claim control whatever the last reading from
      // Base said about it, so the browser has nothing to gate on and builds
      // the same calldata it would at any other reading.
      const source = stakingHookProvider({sendResponses: [hash]})
      const harness = stakingHookHarness(source, "0")

      harness.click(action)
      await vi.waitFor(() =>
        expect(harness.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(1),
      )

      const send = harness.requests.find(request => request.method === "eth_sendTransaction")
      expect(send?.params?.[0]).toEqual({
        from: wallet,
        to: staking,
        data: expectedData,
        value: "0x0",
      })
      harness.destroy()
    },
  )
})

describe("immediate wallet handoff", () => {
  it("performs only one Base chain read before a direct action send", async () => {
    const fake = fakeProvider(request => (request.method === "eth_chainId" ? "0x2105" : hash))
    const click = prepare("unstake", selected(fake.provider))
    const recorder = callbackRecorder()

    await executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider))

    expect(fake.requests).toEqual([
      {method: "eth_chainId"},
      {method: "eth_sendTransaction", params: [click.transaction]},
    ])
    expect(recorder.started).toEqual([`${click.actionId}:action`])
    expect(recorder.submitted).toHaveLength(1)
    expect(recorder.immediate).toEqual([])
  })

  it("switches a wrong chain once, rechecks once, then sends", async () => {
    const chains = ["0x1", "0x2105"]
    const fake = fakeProvider(request => {
      if (request.method === "eth_chainId") return chains.shift()
      if (request.method === "wallet_switchEthereumChain") return null
      return hash
    })
    const click = prepare("claim_usdc", selected(fake.provider))
    const recorder = callbackRecorder()

    await executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider))

    expect(fake.requests.map(request => request.method)).toEqual([
      "eth_chainId",
      "wallet_switchEthereumChain",
      "eth_chainId",
      "eth_sendTransaction",
    ])
    expect(fake.requests[1]?.params).toEqual([{chainId: "0x2105"}])
  })

  it("refuses a failed switch recheck without sending", async () => {
    const fake = fakeProvider(request => {
      if (request.method === "wallet_switchEthereumChain") return null
      return "0x1"
    })
    const click = prepare("claim_regent", selected(fake.provider))
    const recorder = callbackRecorder()

    await executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider))

    expect(fake.requests.map(request => request.method)).toEqual([
      "eth_chainId",
      "wallet_switchEthereumChain",
      "eth_chainId",
    ])
    expect(recorder.immediate).toMatchObject([{kind: "refused", role: "action"}])
  })

  it("refuses an active provider change after the chain check", async () => {
    const replacement = fakeProvider(() => hash)
    let active: SelectedWallet
    const original = fakeProvider(request => {
      if (request.method === "eth_chainId") {
        active = selected(replacement.provider)
        return "0x2105"
      }
      return hash
    })
    active = selected(original.provider)
    const click = prepare("claim_regent", active)
    const recorder = callbackRecorder()

    await executeStakingClick(click, recorder.callbacks, liveRuntime(), () => active)

    expect(original.requests.map(request => request.method)).toEqual(["eth_chainId"])
    expect(replacement.requests).toEqual([])
    expect(recorder.immediate).toMatchObject([{kind: "refused"}])
  })

  it("opens Stake immediately after a valid approval hash without receipt or allowance reads", async () => {
    const fake = fakeProvider(request => (request.method === "eth_chainId" ? "0x2105" : hash))
    const click = prepare("stake", selected(fake.provider), {allowanceAtomic: "0"})
    const recorder = callbackRecorder()

    await executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider))

    expect(fake.requests.map(request => request.method)).toEqual([
      "eth_chainId",
      "eth_sendTransaction",
      "eth_chainId",
      "eth_sendTransaction",
    ])
    expect(recorder.submitted.map(transaction => transaction.role)).toEqual(["approval", "action"])
  })

  it("does not open Stake after a malformed approval response", async () => {
    const fake = fakeProvider(request => (request.method === "eth_chainId" ? "0x2105" : "0x1"))
    const click = prepare("stake", selected(fake.provider), {allowanceAtomic: "0"})
    const recorder = callbackRecorder()

    await executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider))

    expect(fake.requests.map(request => request.method)).toEqual([
      "eth_chainId",
      "eth_sendTransaction",
    ])
    expect(recorder.immediate).toMatchObject([{role: "approval", kind: "submission_unknown"}])
    expect(recorder.submitted).toEqual([])
  })

  it("keeps distinct equivalent clicks independent and deduplicates only exact action-role replay", async () => {
    const fake = fakeProvider(request => (request.method === "eth_chainId" ? "0x2105" : hash))
    const first = prepare("claim_usdc", selected(fake.provider))
    const second = prepare("claim_usdc", selected(fake.provider))
    const recorder = callbackRecorder()

    await Promise.all([
      executeStakingClick(first, recorder.callbacks, liveRuntime(), () => selected(fake.provider)),
      executeStakingClick(second, recorder.callbacks, liveRuntime(), () => selected(fake.provider)),
      executeStakingClick(first, recorder.callbacks, liveRuntime(), () => selected(fake.provider)),
    ])

    expect(fake.requests.filter(request => request.method === "eth_sendTransaction")).toHaveLength(2)
    expect(recorder.submitted).toHaveLength(2)
  })

  it("reports exact rejection and accepts a wallet hash returned after the handoff timeout", async () => {
    const rejected = fakeProvider(request => {
      if (request.method === "eth_chainId") return "0x2105"
      throw {code: 4001, message: "private provider text"}
    })
    const rejectedClick = prepare("claim_regent", selected(rejected.provider))
    const rejectedRecorder = callbackRecorder()
    await executeStakingClick(
      rejectedClick,
      rejectedRecorder.callbacks,
      liveRuntime(),
      () => selected(rejected.provider),
    )
    expect(rejectedRecorder.immediate).toMatchObject([
      {kind: "canceled", message: "Request canceled."},
    ])

    vi.useFakeTimers()
    let resolveWallet!: (value: unknown) => void
    const timedOut = fakeProvider(request => {
      if (request.method === "eth_chainId") return "0x2105"
      return new Promise(resolve => (resolveWallet = resolve))
    })
    const timedOutClick = prepare("claim_usdc", selected(timedOut.provider))
    const timedOutRecorder = callbackRecorder()
    const execution = executeStakingClick(
      timedOutClick,
      timedOutRecorder.callbacks,
      liveRuntime(),
      () => selected(timedOut.provider),
    )
    await vi.advanceTimersByTimeAsync(120_000)
    expect(timedOutRecorder.timedOut).toEqual([`${timedOutClick.actionId}:action`])
    expect(timedOutRecorder.immediate).toEqual([])
    resolveWallet(hash)
    await execution
    expect(timedOutRecorder.submitted).toMatchObject([{hash}])
    expect(timedOutRecorder.immediate).toEqual([])
  })

  it("preserves an exact 4001 from a synchronous provider request throw", async () => {
    const requests: ProviderRequest[] = []
    const synchronousProvider: EthereumProvider = {
      request(request) {
        requests.push(request)
        if (request.method === "eth_chainId") return Promise.resolve("0x2105")
        throw {code: 4001, message: "private provider text"}
      },
    }
    const click = prepare("claim_regent", selected(synchronousProvider))
    const recorder = callbackRecorder()

    await executeStakingClick(
      click,
      recorder.callbacks,
      liveRuntime(),
      () => selected(synchronousProvider),
    )

    expect(requests.map(request => request.method)).toEqual([
      "eth_chainId",
      "eth_sendTransaction",
    ])
    expect(recorder.immediate).toMatchObject([
      {kind: "canceled", message: "Request canceled."},
    ])
  })

  it.each([
    [
      "throwing proxy",
      () =>
        new Proxy(
          {},
          {
            get: () => {
              throw new Error("hostile code getter")
            },
            getPrototypeOf: () => {
              throw new Error("hostile prototype trap")
            },
          },
        ),
    ],
    [
      "throwing accessor",
      () =>
        Object.defineProperty({}, "code", {
          get: () => {
            throw new Error("hostile code accessor")
          },
        }),
    ],
    [
      "revoked proxy",
      () => {
        const {proxy, revoke} = Proxy.revocable({}, {})
        revoke()
        return proxy
      },
    ],
  ] as const)("turns a post-handoff %s rejection into one unknown result", async (_name, error) => {
    const fake = fakeProvider(request => {
      if (request.method === "eth_chainId") return "0x2105"
      throw error()
    })
    const click = prepare("claim_usdc", selected(fake.provider))
    const recorder = callbackRecorder()

    await expect(
      executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider)),
    ).resolves.toBeUndefined()

    expect(recorder.immediate).toMatchObject([
      {
        role: "action",
        kind: "submission_unknown",
        message: "The submission outcome is unknown.",
      },
    ])
    expect(recorder.immediate).toHaveLength(1)
    expect(recorder.submitted).toEqual([])
  })

  it("turns an uninspectable pre-send provider rejection into one fixed refusal", async () => {
    const hostile = new Proxy(
      {},
      {
        get: () => {
          throw new Error("hostile code getter")
        },
        getPrototypeOf: () => {
          throw new Error("hostile prototype trap")
        },
      },
    )
    const fake = fakeProvider(() => {
      throw hostile
    })
    const click = prepare("claim_regent", selected(fake.provider))
    const recorder = callbackRecorder()

    await expect(
      executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider)),
    ).resolves.toBeUndefined()

    expect(recorder.immediate).toMatchObject([
      {kind: "refused", message: "Switch to Base before continuing."},
    ])
    expect(recorder.immediate).toHaveLength(1)
  })

  it("logs only allowlisted timing fields", async () => {
    const fake = fakeProvider(request => (request.method === "eth_chainId" ? "0x2105" : hash))
    const click = prepare("claim_and_restake_regent", selected(fake.provider))
    const recorder = callbackRecorder()

    await executeStakingClick(click, recorder.callbacks, liveRuntime(), () => selected(fake.provider))

    expect(recorder.timing.map(event => event.phase)).toEqual([
      "chain_check",
      "wallet_handoff",
      "provider_response",
    ])
    for (const event of recorder.timing) {
      expect(Object.keys(event).sort()).toEqual([
        "action",
        "milliseconds",
        "phase",
        "role",
        "trace_id",
      ])
      expect(JSON.stringify(event)).not.toContain(wallet.toLowerCase())
      expect(JSON.stringify(event)).not.toContain(hash)
    }
  })
})
