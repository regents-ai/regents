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
import {
  executePreparedRedemptionAction,
  observeRedemptionTransaction,
  type ObservedRedemptionResult,
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
    querySelector: (selector: string) =>
      selector === "[data-redemption-result-text]" ? text : link,
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
    querySelector: (selector: string) =>
      selector === "#redemption-result-dialog" ? dialog : heading,
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
    target: {closest: (selector: string) => selector.includes("prepare_redemption") ? initiator : null},
  } as unknown as MouseEvent)

  fakeWindow.__ashPlatformTestWallet = {address: otherWallet, provider: {request}}
  listeners.get("ash:wallet-state")!()
  walletAction({envelope: envelope("claim")})

  expect(request).not.toHaveBeenCalled()
  expect(showModal).not.toHaveBeenCalled()
})

function submittedTransaction(
  observationProvider: SubmittedRedemptionTransaction["provider"],
): SubmittedRedemptionTransaction {
  const prepared = envelope("redeem")
  return Object.freeze({
    actionId: prepared.action_id,
    action: prepared.action,
    provider: observationProvider,
    chainId: 8453,
    signer: wallet,
    transaction: Object.freeze({
      from: wallet,
      to: prepared.to,
      data: prepared.data,
      value: "0x0" as const,
    }),
    hash,
  })
}

function liveRuntime(): RedemptionRuntime {
  return {alive: () => true, registerCancellation: () => () => undefined}
}

async function observe(
  transaction: SubmittedRedemptionTransaction,
  milliseconds: number,
): Promise<ObservedRedemptionResult[]> {
  const results: ObservedRedemptionResult[] = []
  observeRedemptionTransaction(transaction, liveRuntime(), result => results.push(result))
  await vi.advanceTimersByTimeAsync(milliseconds)
  return results
}

function includedProvider(status: "0x0" | "0x1") {
  let expected!: SubmittedRedemptionTransaction
  const receiptProvider = {
    request: vi.fn(async ({method}: {method: string}) => {
      switch (method) {
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
          throw new Error(`unexpected ${method}`)
      }
    }),
  }
  expected = submittedTransaction(receiptProvider)
  return expected
}

describe("chain-authoritative redemption observation", () => {
  it.each([
    ["0x1", "success"],
    ["0x0", "reverted"],
  ] as const)("maps validated receipt status %s to %s", async (status, outcome) => {
    vi.useFakeTimers()
    expect(await observe(includedProvider(status), 2_000)).toEqual([outcome])
    expect(vi.getTimerCount()).toBe(0)
  })

  it("reports a still-pending transaction as delayed only at 120 seconds", async () => {
    vi.useFakeTimers()
    let expected!: SubmittedRedemptionTransaction
    const pendingProvider = {
      request: vi.fn(async ({method}: {method: string}) => {
        if (method === "eth_chainId") return "0x2105"
        if (method === "eth_getTransactionReceipt") return null
        return {
          hash: expected.hash,
          from: expected.signer,
          to: expected.transaction.to,
          input: expected.transaction.data,
          value: "0x0",
          blockHash: null,
          blockNumber: null,
        }
      }),
    }
    expected = submittedTransaction(pendingProvider)
    const results: ObservedRedemptionResult[] = []
    observeRedemptionTransaction(expected, liveRuntime(), result => results.push(result))

    await vi.advanceTimersByTimeAsync(119_999)
    expect(results).toEqual([])
    await vi.advanceTimersByTimeAsync(1)
    expect(results).toEqual(["delayed"])

    const methods = pendingProvider.request.mock.calls.map(([request]) => request.method)
    expect(methods.filter(method => method === "eth_chainId")).toHaveLength(96)
    expect(methods.filter(method => method === "eth_getTransactionByHash")).toHaveLength(24)
    expect(methods.filter(method => method === "eth_getTransactionReceipt")).toHaveLength(24)
    expect(methods).not.toContain("eth_getBlockByHash")
  })

  it("rejects wrong-chain and contradictory inclusion evidence", async () => {
    vi.useFakeTimers()
    const wrongChain = {request: vi.fn(async () => "0x1")}
    expect(await observe(submittedTransaction(wrongChain), 2_000)).toEqual(["unavailable"])

    vi.clearAllTimers()
    let expected!: SubmittedRedemptionTransaction
    const contradictory = {
      request: vi.fn(async ({method}: {method: string}) => {
        if (method === "eth_chainId") return "0x2105"
        if (method === "eth_getTransactionByHash") {
          return {
            hash: expected.hash,
            from: expected.signer,
            to: expected.transaction.to,
            input: expected.transaction.data,
            value: "0x0",
            blockHash,
            blockNumber: "0x10",
          }
        }
        return {
          transactionHash: expected.hash,
          from: expected.signer,
          to: expected.transaction.to,
          status: "0x1",
          blockHash: `0x${"ef".repeat(32)}`,
          blockNumber: "0x10",
        }
      }),
    }
    expected = submittedTransaction(contradictory)
    expect(await observe(expected, 2_000)).toEqual(["unavailable"])
  })

  it("rejects malformed transaction identity and a chain that drifts after a read", async () => {
    vi.useFakeTimers()
    let malformedExpected!: SubmittedRedemptionTransaction
    const malformed = {
      request: vi.fn(async ({method}: {method: string}) => {
        if (method === "eth_chainId") return "0x2105"
        if (method === "eth_getTransactionByHash") {
          return {
            hash: malformedExpected.hash,
            from: malformedExpected.signer,
            to: malformedExpected.transaction.to,
            input: malformedExpected.transaction.data,
            value: "0x1",
            blockHash: null,
            blockNumber: null,
          }
        }
        return null
      }),
    }
    malformedExpected = submittedTransaction(malformed)
    expect(await observe(malformedExpected, 2_000)).toEqual(["unavailable"])

    vi.clearAllTimers()
    let driftExpected!: SubmittedRedemptionTransaction
    let chainRead = 0
    const drift = {
      request: vi.fn(async ({method}: {method: string}) => {
        if (method === "eth_chainId") return ++chainRead === 1 ? "0x2105" : "0x1"
        return {
          hash: driftExpected.hash,
          from: driftExpected.signer,
          to: driftExpected.transaction.to,
          input: driftExpected.transaction.data,
          value: "0x0",
          blockHash: null,
          blockNumber: null,
        }
      }),
    }
    driftExpected = submittedTransaction(drift)
    expect(await observe(driftExpected, 2_000)).toEqual(["unavailable"])
  })

  it("reports a hung provider as unavailable after the bounded request timeout", async () => {
    vi.useFakeTimers()
    const hung = {request: vi.fn(() => new Promise<unknown>(() => undefined))}
    const results: ObservedRedemptionResult[] = []
    observeRedemptionTransaction(submittedTransaction(hung), liveRuntime(), result =>
      results.push(result)
    )

    await vi.advanceTimersByTimeAsync(5_999)
    expect(results).toEqual([])
    await vi.advanceTimersByTimeAsync(1)
    expect(results).toEqual(["unavailable"])
    expect(vi.getTimerCount()).toBe(0)
  })

  it("makes every scheduled callback inert when its wallet generation ends", async () => {
    vi.useFakeTimers()
    const pending = {request: vi.fn(async () => null)}
    const transaction = submittedTransaction(pending)
    const cancellations = new Set<() => void>()
    let alive = true
    const runtime: RedemptionRuntime = {
      alive: () => alive,
      registerCancellation: cancel => {
        cancellations.add(cancel)
        return () => cancellations.delete(cancel)
      },
    }
    const results: ObservedRedemptionResult[] = []
    observeRedemptionTransaction(transaction, runtime, result => results.push(result))

    alive = false
    for (const cancel of [...cancellations]) cancel()
    await vi.advanceTimersByTimeAsync(120_000)
    expect(results).toEqual([])
    expect(vi.getTimerCount()).toBe(0)
  })
})
