import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"

import {
  activeEthereumWallet,
  connectedEthereumWallet,
  disconnectEveryEthereumWallet,
  eligibleActiveWallet,
  forgetWalletDisconnected,
  replaceActiveEthereumWallet,
  replaceConnectedEthereumWallets,
  walletDisconnected,
  type ConnectedEthereumWallet,
  type EthereumProvider,
} from "../js/wallet_actions/connected_wallet"

const first = "0x1111111111111111111111111111111111111111"
const second = "0x2222222222222222222222222222222222222222"

function provider(): EthereumProvider {
  return {request: vi.fn(async () => undefined)}
}

function connected(walletProvider: EthereumProvider = provider()): ConnectedEthereumWallet {
  return {provider: walletProvider, disconnect: vi.fn()}
}

function memoryStorage() {
  const values = new Map<string, string>()
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => void values.set(key, value),
    removeItem: (key: string) => void values.delete(key),
  }
}

function stubWindow(origin = "https://regents.sh") {
  const dispatched: string[] = []
  vi.stubGlobal("window", {
    location: {origin},
    localStorage: memoryStorage(),
    dispatchEvent: (event: Event) => void dispatched.push(event.type),
  })
  return dispatched
}

beforeEach(() => {
  stubWindow()
  replaceConnectedEthereumWallets([])
  replaceActiveEthereumWallet(null)
})

afterEach(() => vi.unstubAllGlobals())

describe("P1_ACTIVE_WALLET_ONLY: Privy's selection is the Stake wallet", () => {
  it("publishes the selected wallet under its lowercased address", () => {
    const selected = provider()
    replaceActiveEthereumWallet({address: first.toUpperCase(), provider: selected})

    expect(activeEthereumWallet()).toEqual({address: first, provider: selected})

    replaceActiveEthereumWallet(null)
    expect(activeEthereumWallet()).toBeNull()
  })

  it("accepts only an Ethereum selection that is still connected", () => {
    const wallets = [{address: first}, {address: second}]

    expect(eligibleActiveWallet({address: second, type: "ethereum"}, wallets)).toEqual({
      address: second,
      type: "ethereum",
    })

    // A Solana selection, an absent one, and one the provider has dropped are
    // each no wallet at all rather than a reason to pick a different one.
    expect(eligibleActiveWallet({address: second, type: "solana"}, wallets)).toBeNull()
    expect(eligibleActiveWallet(undefined, wallets)).toBeNull()
    expect(eligibleActiveWallet(null, wallets)).toBeNull()
    expect(
      eligibleActiveWallet({address: "0x3333333333333333333333333333333333333333", type: "ethereum"}, wallets),
    ).toBeNull()
    expect(eligibleActiveWallet({address: second, type: "ethereum"}, [])).toBeNull()
  })

  // Redeem and Autolaunch keep reading the connected set by expected signer.
  // Publishing an active wallet changes neither answer.
  it("leaves the shared connected-wallet lookup untouched", () => {
    const one = provider()
    const two = provider()
    replaceConnectedEthereumWallets([
      [first, connected(one)],
      [second, connected(two)],
    ])
    replaceActiveEthereumWallet({address: second, provider: two})

    expect(connectedEthereumWallet(first)?.provider).toBe(one)
    expect(connectedEthereumWallet(second)?.provider).toBe(two)
    expect(connectedEthereumWallet()?.provider).toBe(one)
    expect(connectedEthereumWallet("0x3333333333333333333333333333333333333333")).toBeNull()
  })

  it("has no active wallet before the bridge publishes one", () => {
    replaceConnectedEthereumWallets([[first, connected()]])

    expect(activeEthereumWallet()).toBeNull()
  })
})

describe("DISCONNECT_RELEASES_EVERY_WALLET: Disconnect ends the wallet connection", () => {
  it("lets go of every wallet, asks each app to drop the site, and stays disconnected", async () => {
    const dispatched = stubWindow()
    const walletEvents = new EventTarget()
    const announced: string[] = []
    walletEvents.addEventListener("ash:wallet-state", event => announced.push(event.type))

    const one = connected()
    // A wallet app that has never heard of the revoke request is revoked as far
    // as this page can take it, and never stops the wallet beside it.
    const refusing = provider()
    refusing.request = vi.fn(async () => {
      throw new Error("Unsupported method: wallet_revokePermissions")
    })
    const two = connected(refusing)

    replaceConnectedEthereumWallets([
      [first, one],
      [second, two],
    ])
    replaceActiveEthereumWallet({address: first, provider: one.provider})

    await disconnectEveryEthereumWallet(walletEvents)

    expect(one.disconnect).toHaveBeenCalledOnce()
    expect(two.disconnect).toHaveBeenCalledOnce()
    for (const wallet of [one, two]) {
      expect(wallet.provider.request).toHaveBeenCalledWith({
        method: "wallet_revokePermissions",
        params: [{eth_accounts: {}}],
      })
    }

    expect(activeEthereumWallet()).toBeNull()
    expect(connectedEthereumWallet()).toBeNull()
    expect(connectedEthereumWallet(first)).toBeNull()
    expect(announced).toEqual(["ash:wallet-state"])
    expect(dispatched).toEqual([])
    expect(walletDisconnected()).toBe(true)
  })

  // A wallet app that never answers must not hold the page on a connection the
  // visitor has already ended.
  it("is disconnected before any wallet app answers", async () => {
    const walletEvents = new EventTarget()
    const silent = connected({request: () => new Promise(() => undefined)})
    replaceConnectedEthereumWallets([[first, silent]])
    replaceActiveEthereumWallet({address: first, provider: silent.provider})

    const releasing = disconnectEveryEthereumWallet(walletEvents)
    await Promise.resolve()

    expect(activeEthereumWallet()).toBeNull()
    expect(walletDisconnected()).toBe(true)
    expect(releasing).toBeInstanceOf(Promise)
  })

  it("keeps the browser test wallet gone until the visitor connects again", async () => {
    stubWindow("http://127.0.0.1:4002")
    const testWallet = {address: first, provider: provider()}
    window.__ashPlatformTestWallet = testWallet

    expect(activeEthereumWallet()).toEqual(testWallet)

    await disconnectEveryEthereumWallet(new EventTarget())
    expect(activeEthereumWallet()).toBeNull()
    expect(connectedEthereumWallet(first)).toBeNull()

    forgetWalletDisconnected()
    expect(activeEthereumWallet()).toEqual(testWallet)
  })

  it("stays connected for a browser that refuses storage", async () => {
    vi.stubGlobal("window", {
      location: {origin: "https://regents.sh"},
      get localStorage(): Storage {
        throw new Error("storage is unavailable")
      },
    })

    expect(walletDisconnected()).toBe(false)
    await expect(disconnectEveryEthereumWallet(new EventTarget())).resolves.toBeUndefined()
    expect(walletDisconnected()).toBe(false)
  })
})
