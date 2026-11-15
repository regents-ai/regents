// Invariant: after Disconnect, only a sign-in the visitor makes now signs them in.
// A Privy session the browser still remembers completes at once with
// wasAlreadyAuthenticated, even when a link carries privy_oauth_code; it must not
// sign the previous person back in or clear the Disconnect note (Sentinel,
// 12 Oct 2026). A real redirect return arrives signed out and still signs in.
import {beforeEach, expect, it, vi} from "vitest"
import type {PrivyEvents} from "@privy-io/react-auth"

vi.mock("@privy-io/react-auth", () => ({}))
vi.mock("react-dom/client", () => ({}))

const {createConnectWalletRequest, createPrivyLoginCallbacks, mainConnectedWallet, signOutOfProvider} =
  await import("../js/privy_bridge")

const disconnected = "regent:wallet-disconnected:v1"
const stored = new Map<string, string>()

beforeEach(() => {
  stored.clear()
  stored.set(disconnected, "true")
  const storage = {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => void stored.set(key, value),
    removeItem: (key: string) => void stored.delete(key),
  }
  vi.stubGlobal("window", {localStorage: storage, sessionStorage: storage})
  vi.stubGlobal("localStorage", storage)
  vi.stubGlobal("sessionStorage", storage)
})

function complete(wasAlreadyAuthenticated: boolean) {
  const completeLogin = vi.fn(async () => undefined)
  // A link carrying privy_oauth_code starts the page as if it opened sign-in.
  const callbacks = createPrivyLoginCallbacks({
    completeLogin,
    loginOpen: {current: true},
    showFailure: vi.fn(),
    reportFailure: vi.fn(),
  })
  const done = callbacks.onComplete as NonNullable<PrivyEvents["login"]["onComplete"]>
  done({
    user: {id: "did:privy:person"},
    isNewUser: false,
    wasAlreadyAuthenticated,
    loginMethod: "google",
    loginAccount: null,
  } as unknown as Parameters<typeof done>[0])
  return completeLogin
}

it("a remembered session never signs back in after Disconnect", () => {
  expect(complete(true)).not.toHaveBeenCalled()
  expect(stored.get(disconnected)).toBe("true")
})

it("a real redirect return after Disconnect signs in", () => {
  expect(complete(false)).toHaveBeenCalledOnce()
  expect(stored.has(disconnected)).toBe(false)
})

// Invariant (founder, 14 Nov 2026): signed in, only the account's main wallet,
// the one the account menu shows, sends. It is chosen whenever this tab has it
// connected, whichever wallet Privy remembers; no other wallet, linked to the
// account or not, ever takes its place.
it("signed in, only the account's main wallet is chosen", () => {
  const main = "0x0cb2000000000000000000000000000000003c37"
  const zerion = {address: "0x0cB2000000000000000000000000000000003C37", type: "ethereum"}
  const linked = {address: `0x5008${"0".repeat(32)}54d0`, type: "ethereum"}
  const regents = {address: "0x2c95000000000000000000000000000000008cf6", type: "ethereum"}

  // Privy remembers another linked wallet: the main one is chosen in its place.
  expect(mainConnectedWallet(main, linked, [linked, zerion, regents])).toBe(zerion)
  expect(mainConnectedWallet(main, null, [regents, zerion])).toBe(zerion)
  expect(mainConnectedWallet(main, zerion, [linked, zerion])).toBe(zerion)
  // The main wallet held twice, by two wallet apps: Privy's choice between them stands.
  const zerionAgain = {...zerion}
  expect(mainConnectedWallet(main, zerionAgain, [zerion, zerionAgain])).toBe(zerionAgain)
  // The main wallet not connected here: no wallet, never another one.
  expect(mainConnectedWallet(main, linked, [linked, regents])).toBeNull()
  expect(mainConnectedWallet(main, null, [])).toBeNull()
  expect(mainConnectedWallet(main, null, [{...zerion, type: "solana"}])).toBeNull()
})

it("signing out lets go of every wallet before Privy signs out, even one that refuses", async () => {
  const order: string[] = []
  const zerion = {disconnect: vi.fn(() => { order.push("zerion"); throw new Error("refused") })}
  const regents = {disconnect: vi.fn(() => { order.push("regents") })}

  await signOutOfProvider([zerion, regents], async () => { order.push("logout") })

  expect(order).toEqual(["zerion", "regents", "logout"])
})

it("a wallet that never answers its disconnect does not hold the sign-out open", async () => {
  const silent = {disconnect: vi.fn(() => new Promise<void>(() => {}))}
  const logout = vi.fn(async () => undefined)

  await signOutOfProvider([silent], logout)

  expect(silent.disconnect).toHaveBeenCalledOnce()
  expect(logout).toHaveBeenCalledOnce()
}, 1000)

// Invariant (regents.sh security note, 23 Oct 2026): when Privy's logout failed
// at sign-out, a wallet connected on the signed-out page must not sign the
// previous person back in. Their remembered session is logged out first, and if
// that fails too the connect window never opens.
function connectRequest(signedOut: boolean, logout: () => Promise<void>) {
  const order: string[] = []
  const request = createConnectWalletRequest({
    isCurrent: () => true,
    signedOut: () => signedOut,
    authenticated: () => true,
    providerLogout: async () => { order.push("logout"); await logout() },
    openConnect: async () => { order.push("connect") },
  })
  return {order, request}
}

it("signed out, a remembered Privy session is logged out before a wallet connects", async () => {
  const {order, request} = connectRequest(true, async () => undefined)
  await request()
  expect(order).toEqual(["logout", "connect"])
})

it("signed out, a logout that fails never opens the connect window", async () => {
  const {order, request} = connectRequest(true, async () => { throw new Error("logout failed") })
  await expect(request()).rejects.toThrow("logout failed")
  expect(order).toEqual(["logout"])
})

it("signed in, connecting a wallet keeps the visitor's own Privy session", async () => {
  const {order, request} = connectRequest(false, async () => undefined)
  await request()
  expect(order).toEqual(["connect"])
})
