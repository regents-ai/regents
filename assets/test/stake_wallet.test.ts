import {afterEach, describe, expect, it, vi} from "vitest"
import {encodeFunctionData, getAddress, parseAbi, type Abi, type Address, type Hex} from "viem"

import chainManifest from "../../contracts/base-mainnet.json"
import stakingAbiJson from "../../contracts/abi/regent-revenue-staking.json"
import {StakeWallet} from "../js/hooks/stake_wallet"
import type {EthereumProvider, SelectedWallet} from "../js/wallet_actions/connected_wallet"
import {
  executeStakingClick,
  observeStakingTransaction,
  prepareStakingClick,
  StakingLocalRefusal,
  type ImmediateStakingResult,
  type ObservedStakingResult,
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
const blockHash = `0x${"cd".repeat(32)}` as const

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
  return {alive: () => true, registerCancellation: () => () => undefined}
}

function callbackRecorder() {
  const claims = new Set<string>()
  const timing: StakingTiming[] = []
  const immediate: ImmediateStakingResult[] = []
  const submitted: SubmittedStakingTransaction[] = []
  const started: string[] = []
  const callbacks: StakingExecutionCallbacks = {
    claimRole: (actionId, role) => {
      const key = `${actionId}:${role}`
      if (claims.has(key)) return false
      claims.add(key)
      return true
    },
    timing: event => timing.push(event),
    walletRequestStarted: (actionId, role) => started.push(`${actionId}:${role}`),
    immediate: result => immediate.push(result),
    submitted: transaction => submitted.push(transaction),
  }
  return {callbacks, timing, immediate, submitted, started}
}

function selected(provider: EthereumProvider, address: Address = wallet): SelectedWallet {
  return {address, provider}
}

function stakingHookProvider(options: {
  chainResponses?: Array<string | Promise<string> | "hang">
  sendResponses?: Array<`0x${string}` | "hang">
} = {}): {provider: EthereumProvider; requests: ProviderRequest[]} {
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
          transactions.set(response, transaction)
          return response
        }
        case "eth_getTransactionByHash": {
          const requestedHash = request.params?.[0]
          const transaction =
            typeof requestedHash === "string" ? transactions.get(requestedHash) : undefined
          if (!transaction) return null
          return {
            hash: requestedHash,
            from: transaction.from,
            to: transaction.to,
            input: transaction.data,
            value: "0x0",
            blockHash,
            blockNumber: "0x10",
          }
        }
        case "eth_getTransactionReceipt": {
          const requestedHash = request.params?.[0]
          const transaction =
            typeof requestedHash === "string" ? transactions.get(requestedHash) : undefined
          if (!transaction) return null
          return {
            transactionHash: requestedHash,
            from: transaction.from,
            to: transaction.to,
            status: "0x1",
            blockHash,
            blockNumber: "0x10",
          }
        }
        case "eth_getBlockByHash":
          return {hash: blockHash, number: "0x10", transactions: [...transactions.keys()]}
        default:
          return "0x"
      }
    },
  }
  return {provider, requests}
}

type StakeHookHarness = {
  provider: EthereumProvider
  requests: ProviderRequest[]
  rootListeners: Map<string, (event: Event) => void>
  windowListeners: Map<string, () => void>
  fakeWindow: {
    location: {origin: string}
    __ashPlatformTestWallet: {address: string; provider: EthereumProvider}
  }
  click(action: StakingAction): void
  editAmountActionAndFill(): void
  setWallet(address: string, provider: EthereumProvider): void
  destroy(): void
  dialog: {open: boolean; close: () => void; showModal: ReturnType<typeof vi.fn>}
  text: {textContent: string}
}

function stakingHookHarness(
  source: {provider: EthereumProvider; requests: ProviderRequest[]},
  allowanceAtomic = amount.toString(),
): StakeHookHarness {
  const provider = source.provider
  const windowListeners = new Map<string, () => void>()
  const fakeWindow: {
    location: {origin: string}
    __ashPlatformTestWallet: {address: string; provider: EthereumProvider}
    addEventListener: (event: string, listener: () => void) => void
    removeEventListener: (event: string) => void
    dispatchEvent: (event: Event) => void
  } = {
    location: {origin: "http://127.0.0.1:4002"},
    __ashPlatformTestWallet: {address: wallet, provider},
    addEventListener: (event, listener) => void windowListeners.set(event, listener),
    removeEventListener: event => void windowListeners.delete(event),
    dispatchEvent: () => undefined,
  }
  vi.stubGlobal("window", fakeWindow)

  const text = {textContent: ""}
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
    querySelector: (selector: string) => selector === "[data-staking-result-text]" ? text : link,
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
  const hook = {
    el: root,
    pushEvent: vi.fn(),
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
  const destroy = (): void => {
    StakeWallet.destroyed!.call(hook as never)
  }

  return {
    provider,
    requests: source.requests,
    rootListeners,
    windowListeners,
    fakeWindow,
    click,
    editAmountActionAndFill,
    setWallet,
    destroy,
    dialog,
    text,
  }
}

async function flushStakeHookPromises(): Promise<void> {
  for (let index = 0; index < 8; index += 1) await Promise.resolve()
}

describe("stake hook ownership and result ordering", () => {
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
    ["claim", "claim_regent" as const, "REGENT claim succeeded on Base."],
    ["stake", "stake" as const, "Stake succeeded on Base."],
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

  it("suppresses an approval result and invalidates its main send across A-to-B-to-A", async () => {
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
    expect(harness.dialog.showModal).not.toHaveBeenCalled()
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
    expect(harness.text.textContent).toBe("USDC claim succeeded on Base.")
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

  it("reports exact rejection and makes late timed-out wallet responses inert", async () => {
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
    await execution
    expect(timedOutRecorder.immediate).toMatchObject([{kind: "submission_unknown"}])
    resolveWallet(hash)
    await Promise.resolve()
    expect(timedOutRecorder.submitted).toEqual([])
    expect(timedOutRecorder.immediate).toHaveLength(1)
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

function submitted(provider: EthereumProvider): SubmittedStakingTransaction {
  const click = prepare("unstake", selected(provider))
  return Object.freeze({
    actionId: click.actionId,
    traceId: click.traceId,
    action: click.action,
    role: "action",
    provider,
    chainId: 8453,
    signer: click.signer,
    transaction: click.transaction,
    hash,
  })
}

function receiptProvider(status: "0x0" | "0x1") {
  let expected!: SubmittedStakingTransaction
  const fake = fakeProvider(request => {
    switch (request.method) {
      case "eth_chainId":
        return "0x2105"
      case "eth_getTransactionByHash":
        return {
          hash: expected.hash,
          from: expected.signer,
          to: expected.transaction.to,
          input: expected.transaction.data,
          value: "0x0",
          blockHash,
          blockNumber: "0x10",
        }
      case "eth_getTransactionReceipt":
        return {
          transactionHash: expected.hash,
          from: expected.signer,
          to: expected.transaction.to,
          status,
          blockHash,
          blockNumber: "0x10",
        }
      case "eth_getBlockByHash":
        return {hash: blockHash, number: "0x10", transactions: [expected.hash]}
      default:
        throw new Error(`unexpected ${request.method}`)
    }
  })
  expected = submitted(fake.provider)
  return {expected}
}

async function observe(
  transaction: SubmittedStakingTransaction,
  milliseconds: number,
): Promise<ObservedStakingResult[]> {
  const results: ObservedStakingResult[] = []
  observeStakingTransaction(transaction, liveRuntime(), result => results.push(result))
  await vi.advanceTimersByTimeAsync(milliseconds)
  return results
}

describe("chain-authoritative receipt observation", () => {
  it.each([
    ["0x1", "success"],
    ["0x0", "reverted"],
  ] as const)("maps validated receipt status %s to %s", async (status, outcome) => {
    vi.useFakeTimers()
    const {expected} = receiptProvider(status)

    expect(await observe(expected, 2_000)).toEqual([outcome])
    expect(vi.getTimerCount()).toBe(0)
  })

  it("reports delayed inclusion only after the 120 second sample", async () => {
    vi.useFakeTimers()
    const fake = fakeProvider(request => (request.method === "eth_chainId" ? "0x2105" : null))
    const transaction = submitted(fake.provider)
    const results: ObservedStakingResult[] = []
    observeStakingTransaction(transaction, liveRuntime(), result => results.push(result))

    await vi.advanceTimersByTimeAsync(119_999)
    expect(results).toEqual([])
    await vi.advanceTimersByTimeAsync(1)
    expect(results).toEqual(["delayed"])
  })

  it("reports malformed, wrong-chain, and hung evidence as unavailable once", async () => {
    vi.useFakeTimers()
    const wrongChain = fakeProvider(() => "0x1")
    expect(await observe(submitted(wrongChain.provider), 2_000)).toEqual(["unavailable"])

    vi.clearAllTimers()
    const malformed = fakeProvider(request => (request.method === "eth_chainId" ? "0x2105" : {}))
    expect(await observe(submitted(malformed.provider), 2_000)).toEqual(["unavailable"])

    vi.clearAllTimers()
    let resolveHung!: (value: unknown) => void
    const hung = fakeProvider(request => {
      if (request.method === "eth_chainId") return "0x2105"
      return new Promise(resolve => (resolveHung = resolve))
    })
    const results = await observe(submitted(hung.provider), 6_000)
    expect(results).toEqual(["unavailable"])
    resolveHung(null)
    await Promise.resolve()
    expect(results).toEqual(["unavailable"])
  })

  it("keeps a valid pending transaction neutral and rejects contradictory block evidence", async () => {
    vi.useFakeTimers()
    let pendingTransaction!: SubmittedStakingTransaction
    const pending = fakeProvider(request => {
      if (request.method === "eth_chainId") return "0x2105"
      if (request.method === "eth_getTransactionReceipt") return null
      return {
        hash: pendingTransaction.hash,
        from: pendingTransaction.signer,
        to: pendingTransaction.transaction.to,
        input: pendingTransaction.transaction.data,
        value: "0x0",
        blockHash: null,
        blockNumber: null,
      }
    })
    pendingTransaction = submitted(pending.provider)
    expect(await observe(pendingTransaction, 120_000)).toEqual(["delayed"])

    vi.clearAllTimers()
    let contradictoryTransaction!: SubmittedStakingTransaction
    const contradictory = fakeProvider(request => {
      if (request.method === "eth_chainId") return "0x2105"
      if (request.method === "eth_getTransactionByHash") {
        return {
          hash: contradictoryTransaction.hash,
          from: contradictoryTransaction.signer,
          to: contradictoryTransaction.transaction.to,
          input: contradictoryTransaction.transaction.data,
          value: "0x0",
          blockHash,
          blockNumber: "0x10",
        }
      }
      return {
        transactionHash: contradictoryTransaction.hash,
        from: contradictoryTransaction.signer,
        to: contradictoryTransaction.transaction.to,
        status: "0x1",
        blockHash: `0x${"ef".repeat(32)}`,
        blockNumber: "0x10",
      }
    })
    contradictoryTransaction = submitted(contradictory.provider)
    expect(await observe(contradictoryTransaction, 2_000)).toEqual(["unavailable"])
  })
})
