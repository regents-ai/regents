import {beforeEach, describe, expect, it, vi} from "vitest"

const rpc = vi.hoisted(() => ({
  getEnsName: vi.fn(),
  getEnsAddress: vi.fn(),
  getEnsAvatar: vi.fn(),
}))

vi.mock("viem", () => ({
  createPublicClient: vi.fn(() => rpc),
  getAddress: (address: string) => address.toLowerCase(),
  http: vi.fn(() => ({type: "http"})),
  isAddress: (address: string) => /^0x[0-9a-fA-F]{40}$/.test(address),
}))

vi.mock("viem/chains", () => ({mainnet: {id: 1, name: "Ethereum"}}))

import {
  AccountIdentity,
  resolveEnsIdentity,
  shortenAddress,
} from "../js/hooks/account_identity"

const walletA = "0x1111111111111111111111111111111111111111"
const walletB = "0x2222222222222222222222222222222222222222"

class FakeElement {
  dataset: Record<string, string> = {}
  textContent = ""
  src = ""
  isConnected = true
  listeners = new Map<string, (event: Event) => void>()

  addEventListener(type: string, listener: EventListener) {
    this.listeners.set(type, listener as (event: Event) => void)
  }

  removeEventListener(type: string) {
    this.listeners.delete(type)
  }

  closest(_selector: string): FakeElement | null {
    return null
  }
}

class AccountRoot extends FakeElement {
  labels = [new FakeElement(), new FakeElement()]
  avatars = [new FakeElement(), new FakeElement()]
  address = new FakeElement()
  copyLabel = new FakeElement()

  querySelectorAll(selector: string) {
    if (selector === "[data-account-identity-label]") return this.labels
    if (selector === "[data-account-identity-avatar]") return this.avatars
    return []
  }

  querySelector(selector: string) {
    if (selector === "[data-account-identity-address]") return this.address
    if (selector === "[data-account-copy-label]") return this.copyLabel
    return null
  }
}

class CopyTarget extends FakeElement {
  closest(selector: string) {
    return selector === "[data-account-copy-address]" ? this : null
  }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>(resolver => (resolve = resolver))
  return {promise, resolve}
}

async function settled() {
  for (let turn = 0; turn < 10; turn += 1) await Promise.resolve()
}

function context(root: AccountRoot) {
  return {el: root} as never
}

describe("ENS-backed account presentation", () => {
  beforeEach(() => {
    rpc.getEnsName.mockReset()
    rpc.getEnsAddress.mockReset()
    rpc.getEnsAvatar.mockReset()
    vi.useRealTimers()
    vi.stubGlobal("Element", FakeElement)
    vi.stubGlobal("HTMLElement", FakeElement)
    vi.stubGlobal("window", {setTimeout, clearTimeout})
    vi.stubGlobal("navigator", {clipboard: {writeText: vi.fn().mockResolvedValue(undefined)}})
  })

  it("uses ENS only after reverse and forward resolution name the same wallet", async () => {
    rpc.getEnsName.mockResolvedValue("seanwbren.eth")
    rpc.getEnsAddress.mockResolvedValue(walletA)
    rpc.getEnsAvatar.mockResolvedValue("https://images.example.test/sean.png")

    await expect(resolveEnsIdentity(walletA as `0x${string}`, rpc as never)).resolves.toEqual({
      name: "seanwbren.eth",
      avatar: "https://images.example.test/sean.png",
    })

    expect(rpc.getEnsName).toHaveBeenCalledWith({address: walletA})
    expect(rpc.getEnsAddress).toHaveBeenCalledWith({name: "seanwbren.eth"})
  })

  it("rejects reverse-only and reverse/forward mismatch identities", async () => {
    rpc.getEnsName.mockResolvedValueOnce(null)
    await expect(resolveEnsIdentity(walletA as `0x${string}`, rpc as never)).resolves.toBeNull()
    expect(rpc.getEnsAddress).not.toHaveBeenCalled()

    rpc.getEnsName.mockResolvedValueOnce("wrong.eth")
    rpc.getEnsAddress.mockResolvedValueOnce(walletB)
    await expect(resolveEnsIdentity(walletA as `0x${string}`, rpc as never)).resolves.toBeNull()
    expect(rpc.getEnsAvatar).not.toHaveBeenCalled()
  })

  it("keeps the newer wallet display when an older ENS lookup finishes late", async () => {
    const firstName = deferred<string | null>()
    const secondName = deferred<string | null>()

    rpc.getEnsName.mockImplementation(({address}: {address: string}) =>
      address === walletA ? firstName.promise : secondName.promise,
    )
    rpc.getEnsAddress.mockImplementation(({name}: {name: string}) =>
      Promise.resolve(name === "new.eth" ? walletB : walletA),
    )
    rpc.getEnsAvatar.mockImplementation(({name}: {name: string}) =>
      Promise.resolve(`https://images.example.test/${name}`),
    )

    const root = new AccountRoot()
    root.dataset.walletAddress = walletA
    root.dataset.fallbackLabel = "First wallet"
    root.dataset.fallbackAvatar = "first.svg"
    const hook = context(root)

    AccountIdentity.mounted?.call(hook)
    root.dataset.walletAddress = walletB
    root.dataset.fallbackLabel = "Second wallet"
    root.dataset.fallbackAvatar = "second.svg"
    AccountIdentity.updated?.call(hook)

    secondName.resolve("new.eth")
    await settled()
    expect(root.labels.map(label => label.textContent)).toEqual(["new.eth", "new.eth"])

    firstName.resolve("old.eth")
    await settled()
    expect(root.labels.map(label => label.textContent)).toEqual(["new.eth", "new.eth"])
    expect(root.avatars.map(avatar => avatar.src)).toEqual([
      "https://images.example.test/new.eth",
      "https://images.example.test/new.eth",
    ])
  })

  it("copies the full verified wallet while rendering its short form without a wallet provider", async () => {
    rpc.getEnsName.mockResolvedValue(null)
    const root = new AccountRoot()
    root.dataset.walletAddress = walletA
    root.dataset.fallbackLabel = "Wallet account"
    root.dataset.fallbackAvatar = "wallet.svg"
    const hook = context(root)

    Object.defineProperty(window, "ethereum", {
      configurable: true,
      get: () => {
        throw new Error("selected wallet provider must not be read")
      },
    })

    AccountIdentity.mounted?.call(hook)
    await settled()

    expect(root.address.textContent).toBe(shortenAddress(walletA))
    root.listeners.get("click")?.({target: new CopyTarget()} as unknown as Event)
    await settled()
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(walletA)
    expect(root.copyLabel.textContent).toBe("Copied")

    AccountIdentity.destroyed?.call(hook)
  })
})
