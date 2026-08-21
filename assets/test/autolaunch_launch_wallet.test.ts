import {getAddress, type Hash, type Hex} from "viem"
import {describe, expect, it, vi} from "vitest"

import {
  addressedTo,
  releaseHash,
  rememberOperation,
  retainHash,
  retainedHash,
} from "../js/hooks/autolaunch_launch_wallet"
import {
  sendLaunchStep,
  sendableStep,
  userRejected,
  type LaunchClients,
  type LaunchOperation,
} from "../js/wallet_actions/autolaunch_launch"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const other = getAddress("0x9999999999999999999999999999999999999999")
const factory = getAddress("0x7777777777777777777777777777777777777777")
const regent = getAddress("0x6f89bcA4eA5931EdFCB09786267b251DeE752b07")
const launchHash = `0x${"cd".repeat(32)}` as Hash

// The reviewed launch calldata is a dynamic tuple the server encoded once. The
// browser only ever forwards it, so this fixture is opaque bytes on purpose.
const launchData = "0x783eed5300000000000000000000000000000000000000000000000000000000000000ff" as Hex

function operation(overrides: Partial<LaunchOperation> = {}): LaunchOperation {
  return {
    action_id: "launch-action",
    signer: wallet,
    chain_id: 8453,
    terminal: false,
    steps: [
      {step: "approval", to: regent, data: "0x095ea7b3ff" as Hex},
      {step: "launch", to: factory, data: launchData},
    ],
    ...overrides,
  }
}

function clients(overrides: Partial<LaunchClients> = {}): LaunchClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    send: vi.fn(async () => launchHash),
    ...overrides,
  }
}

const provider = {request: vi.fn(async () => null)}

describe("the browser sends only the step the server claimed", () => {
  it("returns the reviewed step for this exact launch", () => {
    const held = operation()

    expect(sendableStep(held, "launch-action", "approval")).toEqual(held.steps[0])
    expect(sendableStep(held, "launch-action", "launch")).toEqual(held.steps[1])
  })

  it("refuses a different launch, a finished one, and another chain", () => {
    expect(() => sendableStep(operation(), "elsewhere", "launch")).toThrow(
      "This is a different launch.",
    )
    expect(() => sendableStep(operation({terminal: true}), "launch-action", "launch")).toThrow(
      "This launch has already finished.",
    )
    expect(() => sendableStep(operation({chain_id: 1}), "launch-action", "launch")).toThrow(
      "This launch is not for Base.",
    )
  })

  it("refuses a step the reviewed sequence does not contain", () => {
    const single = operation({steps: [{step: "launch", to: factory, data: launchData}]})

    expect(() => sendableStep(single, "launch-action", "approval")).toThrow(
      "This step is not part of the reviewed launch.",
    )
  })

  it("refuses bytes that are not the reviewed lowercase calldata", () => {
    const tampered = operation({
      steps: [{step: "launch", to: factory, data: "0x783EED53FF" as Hex}],
    })

    expect(() => sendableStep(tampered, "launch-action", "launch")).toThrow(
      "The reviewed transaction changed.",
    )
  })
})

describe("the browser rechecks the wallet immediately before it sends", () => {
  it("sends the reviewed bytes to the reviewed factory with zero value", async () => {
    const held = operation()
    const bound = clients()

    const hash = await sendLaunchStep(held, held.steps[1], provider, () => undefined, bound)

    expect(hash).toBe(launchHash)
    expect(bound.send).toHaveBeenCalledWith({
      account: wallet,
      to: factory,
      data: launchData,
      value: 0n,
    })
  })

  it("switches to Base once and refuses if the wallet stays elsewhere", async () => {
    const held = operation()
    const stuck = clients({chainId: vi.fn(async () => 1)})

    await expect(
      sendLaunchStep(held, held.steps[1], provider, () => undefined, stuck),
    ).rejects.toThrow("Switch to Base before continuing.")

    expect(stuck.switchToBase).toHaveBeenCalledTimes(1)
    expect(stuck.send).not.toHaveBeenCalled()
  })

  it("refuses when the wallet's own account is no longer the reviewed signer", async () => {
    const held = operation()
    const moved = clients({addresses: vi.fn(async () => [other])})

    await expect(
      sendLaunchStep(held, held.steps[1], provider, () => undefined, moved),
    ).rejects.toThrow("Use the wallet this launch was reviewed for.")

    expect(moved.send).not.toHaveBeenCalled()
  })

  it("marks the send as started only immediately before the wallet is asked", async () => {
    const held = operation()
    const order: string[] = []

    const watched = clients({
      send: vi.fn(async () => {
        order.push("send")
        return launchHash
      }),
    })

    await sendLaunchStep(held, held.steps[1], provider, () => order.push("marked"), watched)

    expect(order).toEqual(["marked", "send"])
  })

  it("never marks a send that failed its own preflight", async () => {
    const held = operation()
    const moved = clients({addresses: vi.fn(async () => [other])})
    const marked = vi.fn()

    await expect(sendLaunchStep(held, held.steps[1], provider, marked, moved)).rejects.toThrow()

    expect(marked).not.toHaveBeenCalled()
  })

  // The launch tuple is the only dynamic call this product has, and it is
  // encoded once on the server. Nothing in the browser can rebuild it.
  it("contains no encoder: the bytes it sends are exactly the bytes it was given", async () => {
    const held = operation()
    const bound = clients()

    await sendLaunchStep(held, held.steps[1], provider, () => undefined, bound)

    const [request] = (bound.send as ReturnType<typeof vi.fn>).mock.calls[0]
    expect(request.data).toBe(launchData)
  })
})

describe("only an exact EIP-1193 rejection is a rejection", () => {
  it("finds the code through whatever wrapper it arrived in", () => {
    expect(userRejected({code: 4001})).toBe(true)
    expect(userRejected({cause: {cause: {code: 4001}}})).toBe(true)
  })

  it("never treats message text or another code as a rejection", () => {
    expect(userRejected({message: "User rejected the request."})).toBe(false)
    expect(userRejected({code: -32000})).toBe(false)
    expect(userRejected(null)).toBe(false)

    const circular: {cause?: unknown} = {}
    circular.cause = circular
    expect(userRejected(circular)).toBe(false)
  })
})

// A founder with several saved drafts has one card each, and a pushed event
// reaches every hook in the LiveView. Only the card an event names may act on
// it, or one claimed dispatch would open every other card's wallet as well.
describe("a pushed event belongs to exactly one card", () => {
  it("names the card it was pushed for", () => {
    expect(addressedTo({card: "autolaunch-launch-wallet-a", action_id: "x"})).toBe(
      "autolaunch-launch-wallet-a",
    )
  })

  it("names nothing at all for a payload carrying no card", () => {
    expect(addressedTo({action_id: "x"})).toBeNull()
    expect(addressedTo({card: 7})).toBeNull()
    expect(addressedTo(null)).toBeNull()
    expect(addressedTo("autolaunch-launch-wallet-a")).toBeNull()
  })
})

describe("browser storage holds a hint and a hash, never authority", () => {
  function storage() {
    const items = new Map<string, string>()

    return {
      items,
      getItem: (key: string) => items.get(key) ?? null,
      setItem: (key: string, value: string) => void items.set(key, value),
      removeItem: (key: string) => void items.delete(key),
    }
  }

  it("remembers only a launch id, and forgets a terminal one", () => {
    const store = storage()

    rememberOperation(operation(), store)
    expect([...store.items.values()]).toEqual(["launch-action"])

    rememberOperation(operation({terminal: true}), store)
    expect(store.items.size).toBe(0)
  })

  it("stores no signer, calldata, chain or outcome", () => {
    const store = storage()
    rememberOperation(operation(), store)

    const stored = [...store.items.values()].join(" ")
    expect(stored).not.toContain(wallet)
    expect(stored).not.toContain(launchData)
    expect(stored).not.toContain("8453")
  })

  it("replays a reported hash until the server acknowledges that exact one", () => {
    const store = storage()
    const reported = {action_id: "launch-action", step: "launch", transaction_hash: launchHash}

    retainHash(reported, store)
    expect(retainedHash(store)).toEqual(reported)

    // A different launch, step or hash leaves the report exactly where it is.
    releaseHash({...reported, action_id: "elsewhere"}, store)
    releaseHash({...reported, step: "approval"}, store)
    releaseHash({...reported, transaction_hash: `0x${"11".repeat(32)}`}, store)
    expect(retainedHash(store)).toEqual(reported)

    // The same hash in another case is still the same transaction.
    releaseHash({...reported, transaction_hash: launchHash.toUpperCase()}, store)
    expect(retainedHash(store)).toBeNull()
  })

  it("treats a partial or unreadable report as nothing at all", () => {
    const store = storage()

    store.setItem("regent:autolaunch-launch:hash", "{not json")
    expect(retainedHash(store)).toBeNull()

    store.setItem("regent:autolaunch-launch:hash", JSON.stringify({action_id: "a"}))
    expect(retainedHash(store)).toBeNull()
  })

  it("survives a browser that refuses storage entirely", () => {
    const refusing = {
      getItem: () => {
        throw new Error("denied")
      },
      setItem: () => {
        throw new Error("denied")
      },
      removeItem: () => {
        throw new Error("denied")
      },
    }

    expect(() => rememberOperation(operation(), refusing)).not.toThrow()
    expect(() =>
      retainHash({action_id: "a", step: "launch", transaction_hash: "0x1"}, refusing),
    ).not.toThrow()
    expect(retainedHash(refusing)).toBeNull()
    expect(() =>
      releaseHash({action_id: "a", step: "launch", transaction_hash: "0x1"}, refusing),
    ).not.toThrow()
  })
})
