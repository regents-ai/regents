import {afterEach, describe, expect, it, vi} from "vitest"
import {
  encodeFunctionData,
  getAddress,
  parseAbi,
  type Abi,
  type Address,
  type Hash,
  type Hex,
} from "viem"

import chainManifest from "../../contracts/base-mainnet.json"
import redeemerAbiJson from "../../contracts/abi/animata-redeemer.json"
import {RedemptionWallet} from "../js/hooks/redemption_wallet"
import type {EthereumProvider} from "../js/wallet_actions/connected_wallet"
import {
  clientsForRedemption,
  executePreparedRedemptionAction,
  RedemptionExecutionFailure,
  type PreparedRedemptionAction,
  type RedemptionAction,
  type RedemptionClients,
  type RedemptionRuntime,
  type SubmittedRedemptionTransaction,
} from "../js/wallet_actions/redemption"

const manifest = chainManifest.contracts.animata_redeemer
const wallet = getAddress("0x1111111111111111111111111111111111111111")
const otherWallet = getAddress("0x2222222222222222222222222222222222222222")
const redeemer = getAddress(manifest.address)
const animataI = getAddress(manifest.onchain_constants.animata_i)
const animataII = getAddress(manifest.onchain_constants.animata_ii)
const usdc = getAddress(manifest.onchain_constants.usdc)
const price = BigInt(manifest.onchain_constants.usdc_price_atomic)
const redeemerAbi = redeemerAbiJson as Abi
const erc20Approval = parseAbi(["function approve(address spender,uint256 amount)"])
const erc721Approval = parseAbi([
  "function setApprovalForAll(address operator,bool approved)",
])
const hash = `0x${"ab".repeat(32)}` as Hash
const secondHash = `0x${"de".repeat(32)}` as Hash
const blockHash = `0x${"cd".repeat(32)}` as Hash
const provider = {request: vi.fn(async () => undefined)}
const otherProvider = {request: vi.fn(async () => undefined)}
const selected = () => ({address: wallet, provider})

const actionCases: Array<{
  action: RedemptionAction
  to: Address
  arguments: PreparedRedemptionAction["arguments"]
  data: Hex
}> = [
  {
    action: "approve_nft_collection",
    to: animataI,
    arguments: {collection: animataI, operator: redeemer, approved: true},
    data: encodeFunctionData({
      abi: erc721Approval,
      functionName: "setApprovalForAll",
      args: [redeemer, true],
    }),
  },
  {
    action: "approve_exact_usdc",
    to: usdc,
    arguments: {spender: redeemer, amount_atomic: price.toString(), mode: "exact"},
    data: encodeFunctionData({
      abi: erc20Approval,
      functionName: "approve",
      args: [redeemer, price],
    }),
  },
  {
    action: "redeem",
    to: redeemer,
    arguments: {collection: animataII, token_id: 42},
    data: encodeFunctionData({
      abi: redeemerAbi,
      functionName: "redeem",
      args: [animataII, 42n],
    }),
  },
  {
    action: "claim",
    to: redeemer,
    arguments: {},
    data: encodeFunctionData({abi: redeemerAbi, functionName: "claim"}),
  },
]

function envelope(action: RedemptionAction = "claim"): PreparedRedemptionAction {
  const shape = actionCases.find(candidate => candidate.action === action)!
  const actionId = crypto.randomUUID()
  return {
    action_id: actionId,
    idempotency_key: actionId,
    confirmation_token: "signed",
    resource: "animata_redemption",
    action,
    chain_id: 8453,
    to: shape.to,
    value: "0",
    data: shape.data,
    expected_signer: wallet,
    prepared_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Redeem",
    arguments: {...shape.arguments},
  }
}

function clients(overrides: Partial<RedemptionClients> = {}): RedemptionClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    simulate: vi.fn(async () => undefined),
    send: vi.fn(async () => hash),
    ...overrides,
  }
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  const promise = new Promise<T>(done => (resolve = done))
  return {promise, resolve}
}

describe("all four direct redemption calldata shapes", () => {
  it.each(actionCases)("sends exact $action bytes with zero value", async shape => {
    const rpc = clients()

    await executePreparedRedemptionAction(envelope(shape.action), provider, rpc, selected)

    expect(rpc.send).toHaveBeenCalledOnce()
    expect(rpc.send).toHaveBeenCalledWith({
      account: wallet,
      to: shape.to,
      data: shape.data,
      value: 0n,
    })
  })

  it("returns immutable evidence for the exact wallet submission", async () => {
    const prepared = envelope("redeem")
    const submitted = await executePreparedRedemptionAction(prepared, provider, clients(), selected)

    expect(submitted).toEqual({
      actionId: prepared.action_id,
      action: "redeem",
      provider,
      chainId: 8453,
      signer: wallet,
      transaction: {
        from: wallet,
        to: prepared.to,
        data: prepared.data,
        value: "0x0",
      },
      hash,
    })
    expect(Object.isFrozen(submitted)).toBe(true)
    expect(Object.isFrozen(submitted.transaction)).toBe(true)
  })

  it("uses one exact direct EIP-1193 send request with no fallback", async () => {
    const prepared = envelope("redeem")
    const request = vi.fn(async (payload: {method: string; params?: unknown[]}) => {
      if (payload.method !== "eth_sendTransaction") throw new Error("unexpected wallet method")
      return hash
    })
    const directProvider: EthereumProvider = {request}

    await expect(clientsForRedemption(directProvider).send({
      account: wallet,
      to: prepared.to,
      data: prepared.data,
      value: 0n,
    })).resolves.toBe(hash)

    expect(request).toHaveBeenCalledOnce()
    expect(request).toHaveBeenCalledWith({
      method: "eth_sendTransaction",
      params: [{
        from: wallet,
        to: prepared.to,
        data: prepared.data,
        value: "0x0",
      }],
    })
    expect(request.mock.calls.map(([payload]) => payload.method)).not.toContain("wallet_sendTransaction")
  })
})

describe("redemption drift fails before a wallet prompt", () => {
  it.each([
    [
      "expired envelope",
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.expires_at = new Date(Date.now() - 1_000).toISOString()),
    ],
    ["target", (prepared: PreparedRedemptionAction): void => void (prepared.to = otherWallet)],
    [
      "native value",
      (prepared: PreparedRedemptionAction): void => void (prepared.value = "1" as "0"),
    ],
    [
      "signer",
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.expected_signer = otherWallet),
    ],
    [
      "calldata",
      (prepared: PreparedRedemptionAction): void => void (prepared.data = "0xdeadbeef"),
    ],
  ] as const)("refuses changed $0", async (_name, mutate) => {
    const prepared = envelope()
    mutate(prepared)
    const rpc = clients()

    await expect(
      executePreparedRedemptionAction(prepared, provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it.each([
    [
      "NFT collection",
      "approve_nft_collection" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.collection = otherWallet),
    ],
    [
      "NFT approval",
      "approve_nft_collection" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.approved = false),
    ],
    [
      "USDC approval",
      "approve_exact_usdc" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.amount_atomic = "1"),
    ],
    [
      "redeem collection",
      "redeem" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.collection = otherWallet),
    ],
    [
      "token ID",
      "redeem" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.token_id = 1_000),
    ],
  ] as const)("refuses changed $0", async (_name, action, mutate) => {
    const prepared = envelope(action)
    mutate(prepared)
    const rpc = clients()

    await expect(
      executePreparedRedemptionAction(prepared, provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("switches once, then refuses a chain that drifts during simulation", async () => {
    const chainId = vi
      .fn<RedemptionClients["chainId"]>()
      .mockResolvedValueOnce(1)
      .mockResolvedValueOnce(8453)
      .mockResolvedValueOnce(1)
    const rpc = clients({chainId})

    await expect(
      executePreparedRedemptionAction(envelope(), provider, rpc, selected),
    ).rejects.toThrow("Switch to Base")
    expect(rpc.switchToBase).toHaveBeenCalledOnce()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("requires the current Privy selection to retain the exact provider", async () => {
    const rpc = clients()

    await expect(
      executePreparedRedemptionAction(envelope(), provider, rpc, () => ({
        address: wallet,
        provider: otherProvider,
      })),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("requires the selected provider's current account to remain the signer", async () => {
    const rpc = clients({addresses: vi.fn(async () => [otherWallet])})

    await expect(
      executePreparedRedemptionAction(envelope(), provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("rechecks the Privy provider after a deferred simulation", async () => {
    const simulation = deferred<void>()
    const rpc = clients({simulate: vi.fn(async () => simulation.promise)})
    let active = {address: wallet, provider}

    const execution = executePreparedRedemptionAction(envelope(), provider, rpc, () => active)
    await vi.waitFor(() => expect(rpc.simulate).toHaveBeenCalledOnce())

    active = {address: wallet, provider: otherProvider}
    simulation.resolve()

    await expect(execution).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })
})

describe("bounded redemption wallet phases", () => {
  it.each([
    ["chain", 5_000, {chainId: vi.fn(() => new Promise<number>(() => undefined))}],
    [
      "switch",
      15_000,
      {
        chainId: vi.fn(async () => 1),
        switchToBase: vi.fn(() => new Promise<void>(() => undefined)),
      },
    ],
    ["account", 5_000, {addresses: vi.fn(() => new Promise<Address[]>(() => undefined))}],
    ["simulation", 15_000, {simulate: vi.fn(() => new Promise<void>(() => undefined))}],
  ] as const)("refuses a hung pre-send %s phase after its bound", async (_phase, timeout, overrides) => {
    vi.useFakeTimers()
    const rpc = clients(overrides)
    const execution = executePreparedRedemptionAction(envelope(), provider, rpc, selected)
    const refusal = expect(execution).rejects.toMatchObject({
      kind: "refused",
      displayMessage: "Switch to Base before continuing.",
    })

    await vi.advanceTimersByTimeAsync(timeout)
    await refusal
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("reports a slow handoff without discarding its late transaction hash", async () => {
    vi.useFakeTimers()
    let resolveSend!: (value: Hash) => void
    const rpc = clients({send: vi.fn(() => new Promise<Hash>(resolve => (resolveSend = resolve)))})
    const submissionUnknown = vi.fn()
    const execution = executePreparedRedemptionAction(
      envelope(),
      provider,
      rpc,
      selected,
      undefined,
      undefined,
      submissionUnknown,
    )

    await vi.advanceTimersByTimeAsync(119_999)
    expect(rpc.send).toHaveBeenCalledOnce()
    expect(submissionUnknown).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1)
    expect(submissionUnknown).toHaveBeenCalledOnce()

    resolveSend(hash)
    await expect(execution).resolves.toMatchObject({hash})
    expect(rpc.send).toHaveBeenCalledOnce()
  })

  it.each([
    ["before send", clients({chainId: vi.fn(async () => { throw {code: 4001} })})],
    ["after handoff", clients({send: vi.fn(async () => { throw {code: 4001} })})],
  ] as const)("treats an exact 4001 as cancellation %s", async (_phase, rpc) => {
    await expect(executePreparedRedemptionAction(envelope(), provider, rpc, selected)).rejects.toMatchObject({
      kind: "canceled",
      displayMessage: "Request canceled.",
    } satisfies Pick<RedemptionExecutionFailure, "kind" | "displayMessage">)
  })
})

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

it("discards a prepared action that arrives after the wallet generation changed", () => {
  const request = vi.fn(async () => undefined)
  const listeners = new Map<string, () => void>()
  const fakeWindow = {
    location: {origin: "http://127.0.0.1:4002"},
    __ashPlatformTestWallet: {address: wallet, provider: {request}},
    addEventListener: vi.fn((event: string, listener: () => void) => listeners.set(event, listener)),
    removeEventListener: vi.fn((event: string) => listeners.delete(event)),
    dispatchEvent: vi.fn(),
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
  const showModal = vi.fn()
  const dialogListeners = new Map<string, () => void>()
  const dialog = {
    open: false,
    isConnected: true,
    dataset: {},
    querySelector: (selector: string) => {
      if (selector === "[data-redemption-result-title]") return dialogTitle
      if (selector === "[data-redemption-result-text]") return text
      if (selector === "[data-redemption-result-detail]") return detail
      if (selector === "[data-redemption-result-wallet]") return walletText
      return link
    },
    addEventListener: vi.fn((event: string, listener: () => void) =>
      dialogListeners.set(event, listener)
    ),
    removeEventListener: vi.fn((event: string) => dialogListeners.delete(event)),
    showModal,
    close: vi.fn(),
  }
  const rootListeners = new Map<string, (event: MouseEvent) => void>()
  const heading = {focus: vi.fn(), isConnected: true, closest: () => null, hasAttribute: () => false}
  const root = {
    isConnected: true,
    querySelector: (selector: string) => {
      if (selector === "#redemption-result-dialog") return dialog
      return heading
    },
    addEventListener: vi.fn((event: string, listener: (event: MouseEvent) => void) =>
      rootListeners.set(event, listener)
    ),
    removeEventListener: vi.fn((event: string) => rootListeners.delete(event)),
  }
  let walletAction!: (payload: unknown) => void
  const hook = {
    el: root,
    pushEvent: vi.fn(),
    handleEvent: vi.fn((event: string, listener: (payload: unknown) => void) => {
      if (event === "redemption:wallet-action") walletAction = listener
    }),
  }

  RedemptionWallet.mounted!.call(hook)
  const initiator = {
    getAttribute: () => "claim",
    focus: vi.fn(),
    isConnected: true,
    closest: () => null,
    hasAttribute: () => false,
  }
  rootListeners.get("click")!({
    preventDefault: vi.fn(),
    target: {closest: (selector: string) => selector === "[data-redemption-action]" ? initiator : null},
  } as unknown as MouseEvent)
  const attemptId = (hook.pushEvent.mock.calls.at(-1)?.[1] as {attempt_id: string}).attempt_id

  fakeWindow.__ashPlatformTestWallet = {address: otherWallet, provider: {request}}
  listeners.get("ash:wallet-state")!()
  walletAction({attempt_id: attemptId, envelope: envelope("claim")})

  expect(request).not.toHaveBeenCalled()
  expect(showModal).not.toHaveBeenCalled()
})

type RedemptionHookHarness = {
  provider: EthereumProvider
  requests: ReturnType<typeof vi.fn>
  rootListeners: Map<string, (event: Event) => void>
  windowListeners: Map<string, () => void>
  dispatched: string[]
  fakeWindow: {
    location: {origin: string}
    __ashPlatformTestWallet: {address: string; provider: EthereumProvider}
  }
  walletAction(attemptId: string, envelope: PreparedRedemptionAction): void
  walletRefusal(attemptId: string): void
  click(action?: RedemptionAction): string
  changeSelection(): void
  setWallet(address: string, provider: EthereumProvider): void
  destroy(): void
  dialog: {open: boolean; close: () => void; showModal: ReturnType<typeof vi.fn>}
  dialogTitle: {textContent: string}
  text: {textContent: string}
  detail: {textContent: string}
  link: {hidden: boolean; href: string}
  pushEvent: ReturnType<typeof vi.fn>
  settleNext(result: "success" | "reverted" | "delayed" | "unavailable"): void
}

function redemptionHookProvider(options: {
  chainResponses?: Array<string | Promise<string>>
  sendResponse?: (transaction: unknown) => Hash | Promise<Hash> | "hang"
  observation?: "pending" | "unavailable" | "manual"
} = {}): {
  provider: EthereumProvider
  requests: ReturnType<typeof vi.fn>
  observation?: "pending" | "unavailable" | "manual"
} {
  const chainResponses = [...(options.chainResponses ?? [])]
  const transactions = new Map<string, {from: string; to: string; data: string}>()
  const requests = vi.fn(async (request: {method: string; params?: unknown[]}) => {
    switch (request.method) {
      case "eth_chainId":
        return chainResponses.shift() ?? "0x2105"
      case "eth_accounts":
        return [wallet]
      case "eth_call":
        return "0x"
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
        const response = options.sendResponse?.(transaction) ?? hash
        if (response === "hang") return new Promise<never>(() => undefined)
        const resolved = await response
        transactions.set(resolved, transaction)
        return resolved
      }
      case "eth_getTransactionByHash": {
        const requestedHash = request.params?.[0]
        const transaction = typeof requestedHash === "string" ? transactions.get(requestedHash) : undefined
        if (!transaction) return null
        if (options.observation === "unavailable") {
          return {
            hash: requestedHash,
            from: transaction.from,
            to: transaction.to,
            input: "0xdeadbeef",
            value: "0x0",
            blockHash: null,
            blockNumber: null,
          }
        }
        const pending = options.observation === "pending"
        return {
          hash: requestedHash,
          from: transaction.from,
          to: transaction.to,
          input: transaction.data,
          value: "0x0",
          blockHash: pending ? null : blockHash,
          blockNumber: pending ? null : "0x10",
        }
      }
      case "eth_getTransactionReceipt": {
        if (options.observation === "pending") return null
        const requestedHash = request.params?.[0]
        const transaction = typeof requestedHash === "string" ? transactions.get(requestedHash) : undefined
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
  })
  return {provider: {request: requests}, requests, observation: options.observation}
}

function redemptionHookHarness(source: EthereumProvider | ReturnType<typeof redemptionHookProvider>): RedemptionHookHarness {
  const provider = "provider" in source ? source.provider : source
  const observationMode = "provider" in source ? source.observation : undefined
  const windowListeners = new Map<string, () => void>()
  const dispatched: string[] = []
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
      if (selector === "[data-redemption-result-title]") return dialogTitle
      if (selector === "[data-redemption-result-text]") return text
      if (selector === "[data-redemption-result-detail]") return detail
      if (selector === "[data-redemption-result-wallet]") return walletText
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
  const heading = {focus: vi.fn(), isConnected: true, closest: () => null, hasAttribute: () => false}
  const rootListeners = new Map<string, (event: Event) => void>()
  const root = {
    isConnected: true,
    querySelector: (selector: string) => {
      if (selector === "#redemption-result-dialog") return dialog
      return heading
    },
    addEventListener: vi.fn((event: string, listener: (event: Event) => void) =>
      rootListeners.set(event, listener)),
    removeEventListener: vi.fn((event: string) => rootListeners.delete(event)),
  }
  let walletAction!: (payload: unknown) => void
  let walletRefusal!: (payload: unknown) => void
  let transactionResult!: (payload: unknown) => void
  const pendingObservations: string[] = []
  const pushEvent = vi.fn((event: string, payload: {observation_id?: string}) => {
    if (event !== "observe_redemption_transaction" || !payload.observation_id) return
    if (observationMode === "manual") {
      pendingObservations.push(payload.observation_id)
      return
    }
    const result = observationMode === "pending" ? "delayed" : observationMode ?? "success"
    queueMicrotask(() => transactionResult({observation_id: payload.observation_id, result}))
  })
  const hook = {
    el: root,
    pushEvent,
    handleEvent: vi.fn((event: string, listener: (payload: unknown) => void) => {
      if (event === "redemption:wallet-action") walletAction = listener
      if (event === "redemption:wallet-refusal") walletRefusal = listener
      if (event === "redemption:transaction-result") transactionResult = listener
    }),
  }

  RedemptionWallet.mounted!.call(hook as never)

  const click = (action: RedemptionAction = "claim"): string => {
    const initiator = {
      getAttribute: (attribute: string) =>
        attribute === "data-redemption-action" ? action : null,
      focus: vi.fn(),
      isConnected: true,
      closest: (selector: string) =>
        selector === "[data-redemption-action]" ? initiator : null,
      hasAttribute: () => false,
    }
    const preventDefault = vi.fn()
    rootListeners.get("click")!({
      preventDefault,
      target: {closest: (selector: string) =>
        selector === "[data-redemption-action]" ? initiator : null},
    } as unknown as MouseEvent)
    expect(preventDefault).toHaveBeenCalledOnce()
    const [event, payload] = pushEvent.mock.calls.at(-1) as [string, {attempt_id: string}]
    expect(event).toBe("prepare_redemption")
    return payload.attempt_id
  }
  const changeSelection = (): void => {
    const selection = {
      closest: (selector: string) => selector === "#redemption-selection" ? selection : null,
    }
    rootListeners.get("change")!({target: selection} as unknown as Event)
  }
  const setWallet = (address: string, nextProvider: EthereumProvider): void => {
    fakeWindow.__ashPlatformTestWallet = {address, provider: nextProvider}
    windowListeners.get("ash:wallet-state")?.()
  }
  const destroy = (): void => {
    RedemptionWallet.destroyed!.call(hook as never)
  }

  return {
    provider,
    requests: (provider as unknown as {request: ReturnType<typeof vi.fn>}).request,
    rootListeners,
    windowListeners,
    fakeWindow,
    dispatched,
    walletAction: (attemptId, prepared) => walletAction({attempt_id: attemptId, envelope: prepared}),
    walletRefusal: attemptId => walletRefusal({attempt_id: attemptId}),
    click,
    changeSelection,
    setWallet,
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

async function flushHookPromises(): Promise<void> {
  for (let index = 0; index < 8; index += 1) await Promise.resolve()
}

describe("redemption hook ownership and result ordering", () => {
  it("asks the wallet bridge for Privy's wallets as soon as it mounts", () => {
    const harness = redemptionHookHarness(redemptionHookProvider())

    expect(harness.dispatched).toEqual(["ash:wallet-sync"])
    harness.destroy()
  })

  it("cancels a hung pre-send phase on teardown before it can send", async () => {
    const chain = deferred<string>()
    const walletProvider = redemptionHookProvider({chainResponses: [chain.promise]})
    const harness = redemptionHookHarness(walletProvider)

    const attemptId = harness.click()
    harness.walletAction(attemptId, envelope("claim"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.map(([request]) => request.method)).toContain("eth_chainId"),
    )
    harness.destroy()
    chain.resolve("0x2105")
    await flushHookPromises()

    expect(walletProvider.requests.mock.calls.map(([request]) => request.method)).not.toContain(
      "eth_sendTransaction",
    )
    expect(harness.dialog.showModal).not.toHaveBeenCalled()
  })

  it("invalidates A-to-B-to-A callbacks while allowing a fresh A click", async () => {
    const chain = deferred<string>()
    const walletProvider = redemptionHookProvider({chainResponses: [chain.promise]})
    const other = redemptionHookProvider()
    const harness = redemptionHookHarness(walletProvider)

    const staleAttempt = harness.click()
    harness.walletAction(staleAttempt, envelope("claim"))
    await vi.waitFor(() => expect(walletProvider.requests).toHaveBeenCalled())
    harness.setWallet(otherWallet, other.provider)
    harness.setWallet(wallet, walletProvider.provider)
    chain.resolve("0x2105")
    await flushHookPromises()
    expect(walletProvider.requests.mock.calls.map(([request]) => request.method)).not.toContain(
      "eth_sendTransaction",
    )

    const freshAttempt = harness.click()
    harness.walletAction(freshAttempt, envelope("claim"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.map(([request]) => request.method)).toContain(
        "eth_sendTransaction",
      ),
    )
    expect(walletProvider.requests.mock.calls.filter(([request]) => request.method === "eth_sendTransaction"))
      .toHaveLength(1)
    harness.destroy()
  })

  it("keeps a submitted result under its original signer after the active wallet changes", async () => {
    const walletProvider = redemptionHookProvider({observation: "manual"})
    const other = redemptionHookProvider()
    const harness = redemptionHookHarness(walletProvider)

    const attemptId = harness.click("claim")
    harness.walletAction(attemptId, envelope("claim"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(1),
    )
    harness.setWallet(otherWallet, other.provider)
    harness.settleNext("success")

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("Your unlocked REGENT was claimed successfully.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${hash}`)
    harness.destroy()
  })

  it("names the latest Base block and refreshes the collection once a send confirms", async () => {
    const walletProvider = redemptionHookProvider({observation: "manual"})
    const harness = redemptionHookHarness(walletProvider)

    const attemptId = harness.click("claim")
    harness.walletAction(attemptId, envelope("claim"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(1),
    )
    expect(harness.pushEvent.mock.calls.map(([event]) => event)).not.toContain("refresh_redemption")

    harness.settleNext("success")

    expect(harness.detail.textContent)
      .toBe("Your collection and vest are refreshing in place from the latest Base block.")
    expect(harness.pushEvent).toHaveBeenCalledWith("refresh_redemption", {refresh_owned: false})
    harness.destroy()
  })

  it("keeps a Privy send when the wallet changes before Privy returns its hash", async () => {
    vi.useFakeTimers()
    const pendingHash = deferred<Hash>()
    const walletProvider = redemptionHookProvider({sendResponse: () => pendingHash.promise})
    const other = redemptionHookProvider()
    const harness = redemptionHookHarness(walletProvider)

    const attemptId = harness.click("claim")
    harness.walletAction(attemptId, envelope("claim"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(1),
    )
    harness.setWallet(otherWallet, other.provider)
    await vi.advanceTimersByTimeAsync(120_000)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("The submission outcome is unknown.")
    harness.dialog.close()

    pendingHash.resolve(hash)
    await flushHookPromises()

    expect(harness.dialog.showModal).toHaveBeenCalledTimes(2)
    expect(harness.text.textContent).toBe("Your unlocked REGENT was claimed successfully.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${hash}`)
    harness.destroy()
  })

  it("advances to a retained result when a wallet change removes the visible error", async () => {
    let sends = 0
    const walletProvider = redemptionHookProvider({
      sendResponse: () => {
        sends += 1
        if (sends === 1) throw {code: 4001}
        return secondHash
      },
    })
    const other = redemptionHookProvider()
    const harness = redemptionHookHarness(walletProvider)

    const canceledAttempt = harness.click("claim")
    harness.walletAction(canceledAttempt, envelope("claim"))
    await vi.waitFor(() => expect(harness.dialog.showModal).toHaveBeenCalledOnce())
    expect(harness.text.textContent).toBe("Request canceled.")

    const redeemAttempt = harness.click("redeem")
    harness.walletAction(redeemAttempt, envelope("redeem"))
    await vi.waitFor(() => expect(sends).toBe(2))
    harness.setWallet(otherWallet, other.provider)

    await vi.waitFor(() => expect(harness.dialog.showModal).toHaveBeenCalledTimes(2))
    expect(harness.text.textContent).toBe("Animata #42 was redeemed successfully.")
    expect(harness.link.href).toBe(`https://basescan.org/tx/${secondHash}`)
    harness.destroy()
  })

  it("preserves a pending Claim while retiring only selection-derived attempts", async () => {
    const walletProvider = redemptionHookProvider()
    const harness = redemptionHookHarness(walletProvider)

    const claimAttempt = harness.click("claim")
    const nftAttempt = harness.click("approve_nft_collection")
    const usdcAttempt = harness.click("approve_exact_usdc")
    const redeemAttempt = harness.click("redeem")
    harness.changeSelection()
    harness.walletAction(nftAttempt, envelope("approve_nft_collection"))
    harness.walletAction(usdcAttempt, envelope("approve_exact_usdc"))
    harness.walletAction(redeemAttempt, envelope("redeem"))
    harness.walletAction(claimAttempt, envelope("claim"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(1),
    )

    const send = walletProvider.requests.mock.calls.find(([request]) =>
      request.method === "eth_sendTransaction"
    )?.[0]
    expect(send.params?.[0]).toMatchObject({data: envelope("claim").data})
    harness.destroy()
  })

  it("preserves a handed-off redemption and its result across selection changes", async () => {
    vi.useFakeTimers()
    const walletProvider = redemptionHookProvider()
    const harness = redemptionHookHarness(walletProvider)

    const attemptId = harness.click("redeem")
    harness.walletAction(attemptId, envelope("redeem"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(1),
    )

    harness.changeSelection()
    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("Animata #42 was redeemed successfully.")

    harness.changeSelection()
    expect(harness.dialog.open).toBe(true)
    expect(harness.text.textContent).toBe("Animata #42 was redeemed successfully.")
    harness.destroy()
  })

  it("keeps a settled second result behind a hung first send until FIFO advances", async () => {
    vi.useFakeTimers()
    const provider = redemptionHookProvider({
      sendResponse: transaction =>
        transaction && (transaction as {data: string}).data === actionCases.find(caseItem => caseItem.action === "claim")!.data
          ? "hang"
          : secondHash,
    })
    const harness = redemptionHookHarness(provider)

    const claimAttempt = harness.click("claim")
    harness.walletAction(claimAttempt, envelope("claim"))
    const redeemAttempt = harness.click("redeem")
    harness.walletAction(redeemAttempt, envelope("redeem"))
    await vi.waitFor(() =>
      expect(provider.requests.mock.calls.filter(([request]) => request.method === "eth_sendTransaction"))
        .toHaveLength(2),
    )

    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.dialog.showModal).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(118_000)
    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.text.textContent).toBe("The submission outcome is unknown.")

    harness.dialog.close()
    expect(harness.dialog.showModal).toHaveBeenCalledTimes(2)
    expect(harness.text.textContent).toBe("Animata #42 was redeemed successfully.")
    harness.destroy()
  })

  it("keeps FIFO healthy when an earlier preparation refuses and a later one arrives slowly", async () => {
    vi.useFakeTimers()
    const provider = redemptionHookProvider({
      sendResponse: transaction =>
        (transaction as {data: string}).data === envelope("claim").data ? hash : secondHash,
    })
    const harness = redemptionHookHarness(provider)

    const refusedAttempt = harness.click("redeem")
    const claimAttempt = harness.click("claim")
    const slowAttempt = harness.click("redeem")

    harness.walletRefusal(refusedAttempt)
    harness.walletAction(refusedAttempt, envelope("redeem"))
    harness.walletAction(claimAttempt, envelope("claim"))
    await vi.waitFor(() =>
      expect(provider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(1),
    )
    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.text.textContent).toBe("Your unlocked REGENT was claimed successfully.")

    harness.walletAction(slowAttempt, envelope("redeem"))
    await vi.waitFor(() =>
      expect(provider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(2),
    )
    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.text.textContent).toBe("Your unlocked REGENT was claimed successfully.")

    harness.dialog.close()
    expect(harness.dialog.showModal).toHaveBeenCalledTimes(2)
    expect(harness.text.textContent).toBe("Animata #42 was redeemed successfully.")
    harness.destroy()
  })

  it("removes the visible result by identity when an older preparation arrives behind it", async () => {
    vi.useFakeTimers()
    const provider = redemptionHookProvider({
      sendResponse: transaction =>
        (transaction as {data: string}).data === envelope("claim").data ? hash : secondHash,
    })
    const harness = redemptionHookHarness(provider)

    const olderAttempt = harness.click("redeem")
    const visibleAttempt = harness.click("claim")
    harness.walletAction(visibleAttempt, envelope("claim"))
    await vi.waitFor(() =>
      expect(provider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(1),
    )
    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.text.textContent).toBe("Your unlocked REGENT was claimed successfully.")

    harness.walletAction(olderAttempt, envelope("redeem"))
    await vi.waitFor(() =>
      expect(provider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(2),
    )
    await vi.advanceTimersByTimeAsync(2_000)

    harness.dialog.close()
    expect(harness.text.textContent).toBe("Animata #42 was redeemed successfully.")
    harness.dialog.close()

    const laterAttempt = harness.click("claim")
    harness.walletAction(laterAttempt, envelope("claim"))
    await vi.waitFor(() =>
      expect(provider.requests.mock.calls.filter(([request]) =>
        request.method === "eth_sendTransaction"
      )).toHaveLength(3),
    )
    await vi.advanceTimersByTimeAsync(2_000)
    expect(harness.dialog.showModal).toHaveBeenCalledTimes(3)
    expect(harness.text.textContent).toBe("Your unlocked REGENT was claimed successfully.")
    harness.destroy()
  })

  it.each([
    ["delayed", "pending" as const, 120_000, "Confirmation is taking longer"],
    ["unavailable", "unavailable" as const, 2_000, "Confirmation unavailable"],
  ])("keeps BaseScan and the outcome title available when confirmation is %s", async (_result, observation, wait, title) => {
    vi.useFakeTimers()
    const walletProvider = redemptionHookProvider({observation})
    const harness = redemptionHookHarness(walletProvider)

    const attemptId = harness.click("claim")
    harness.walletAction(attemptId, envelope("claim"))
    await vi.waitFor(() =>
      expect(walletProvider.requests.mock.calls.map(([request]) => request.method)).toContain(
        "eth_sendTransaction",
      ),
    )
    await vi.advanceTimersByTimeAsync(wait)

    expect(harness.dialog.showModal).toHaveBeenCalledOnce()
    expect(harness.link.hidden).toBe(false)
    expect(harness.link.href).toBe(`https://basescan.org/tx/${hash}`)
    expect(harness.dialogTitle.textContent).toBe(title)
    harness.destroy()
  })
})
