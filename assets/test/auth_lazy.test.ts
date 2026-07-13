import {describe, expect, it, vi} from "vitest"

import {
  createBrowserPrivyBridgeImporter,
  createLazyAuthLoader,
  installAccountAuthLazyLoader,
  type AccountRequest,
  type PrivyBridgeModule,
} from "../js/auth_lazy"
import {createAccountRequestHandler} from "../js/privy_bridge"

class AccountElement {
  hidden = true
  textContent = ""

  constructor(readonly accountTarget?: string) {}

  closest(selector: string) {
    return selector === "[data-account-target]" && this.accountTarget ? this : null
  }

  get dataset() {
    return {accountTarget: this.accountTarget}
  }
}

function accountDocument({
  signedIn = false,
  bridgeSource = "/assets/js/privy_bridge.js",
}: {signedIn?: boolean; bridgeSource?: string | null} = {}) {
  let status = new AccountElement()
  const listeners = new Map<string, (event: Event) => void>()
  const documentRoot = {
    querySelector(selector: string) {
      if (selector === "meta[name='privy-app-id']") return {content: "public-app-id"}
      if (selector === "meta[name='privy-bridge-src']") {
        return bridgeSource === null ? null : {content: bridgeSource}
      }
      if (selector === "#account-auth-status") return status
      if (selector === "#account-control [data-account-target='identity']") {
        return signedIn ? new AccountElement("identity") : null
      }
      return null
    },
    addEventListener(type: string, listener: (event: Event) => void) {
      listeners.set(type, listener)
    },
    removeEventListener(type: string) {
      listeners.delete(type)
    },
  } as unknown as Document

  return {
    documentRoot,
    get status() {
      return status
    },
    replaceStatus() {
      status = new AccountElement()
      return status
    },
    click(accountTarget: "sign-in" | "sign-out") {
      listeners.get("click")?.({target: new AccountElement(accountTarget)} as unknown as Event)
    },
  }
}

describe("lazy browser authentication", () => {
  it("replaces pending sync with sign out until the bridge is ready", async () => {
    let resolveModule: ((module: PrivyBridgeModule) => void) | undefined
    let resolveHandle: ((handle: {request: (request: AccountRequest) => Promise<void>}) => void) |
      undefined
    const order: string[] = []
    const handleRequest = vi.fn(
      createAccountRequestHandler({
        requestLogin: vi.fn(),
        clearSession: vi.fn(async () => {
          order.push("local")
        }),
        providerLogout: vi.fn(async () => {
          order.push("provider")
        }),
        reload: vi.fn(() => order.push("reload")),
      }),
    )
    const startPrivyBridge = vi.fn(
      () =>
        new Promise<{request: (request: AccountRequest) => Promise<void>}>(resolve => {
          resolveHandle = resolve
        }),
    )
    const importer = vi.fn(
      () =>
        new Promise<PrivyBridgeModule>(resolve => {
          resolveModule = resolve
        }),
    )
    const loader = createLazyAuthLoader(importer)

    const sync = loader.request("sync")
    const signOut = loader.request("sign-out")
    resolveModule?.({startPrivyBridge} as never)
    await vi.waitFor(() => expect(startPrivyBridge).toHaveBeenCalledOnce())
    expect(handleRequest).not.toHaveBeenCalled()

    resolveHandle?.({request: handleRequest})
    await Promise.all([sync, signOut])

    expect(startPrivyBridge).toHaveBeenCalledWith()
    expect(handleRequest).toHaveBeenCalledOnce()
    expect(handleRequest).toHaveBeenCalledWith("sign-out")
    expect(order).toEqual(["local", "provider", "reload"])
  })

  it("retries the fixed server-owned bridge URL and starts exactly once", async () => {
    const handleRequest = vi.fn(async () => undefined)
    const startPrivyBridge = vi.fn(async () => ({request: handleRequest}))
    const runtimeImport = vi
      .fn<(url: string) => Promise<PrivyBridgeModule>>()
      .mockRejectedValueOnce(new Error("bridge unavailable"))
      .mockRejectedValueOnce(new Error("bridge still unavailable"))
      .mockResolvedValueOnce({startPrivyBridge})
    const loader = createLazyAuthLoader(
      createBrowserPrivyBridgeImporter({
        bridgeSource: "/assets/js/privy_bridge.js",
        runtimeImport,
        currentOrigin: "http://127.0.0.1:4002",
      }),
    )

    await expect(loader.request("sign-in")).rejects.toThrow("bridge unavailable")
    await expect(loader.request("sign-in")).rejects.toThrow("bridge still unavailable")
    const successfulRetry = loader.request("sign-in")
    const repeatedClick = loader.request("sign-in")
    await Promise.all([successfulRetry, repeatedClick])

    expect(runtimeImport).toHaveBeenNthCalledWith(
      1,
      "http://127.0.0.1:4002/assets/js/privy_bridge.js?regent_retry=0",
    )
    expect(runtimeImport).toHaveBeenNthCalledWith(
      2,
      "http://127.0.0.1:4002/assets/js/privy_bridge.js?regent_retry=1",
    )
    expect(runtimeImport).toHaveBeenNthCalledWith(
      3,
      "http://127.0.0.1:4002/assets/js/privy_bridge.js?regent_retry=2",
    )
    expect(startPrivyBridge).toHaveBeenCalledOnce()
    expect(startPrivyBridge).toHaveBeenCalledWith()
    expect(handleRequest).toHaveBeenCalledOnce()
    expect(handleRequest).toHaveBeenCalledWith("sign-in")
  })

  it.each([
    null,
    "https://attacker.example/assets/js/privy_bridge.js",
    "http://user@127.0.0.1:4002/assets/js/privy_bridge.js",
    "http://127.0.0.1:4002/assets/js/other.js",
    "http://127.0.0.1:4002/assets/js/privy_bridge-abc123.js",
    "http://127.0.0.1:4002/assets/js/privy_bridge.js?source=other",
    "http://127.0.0.1:4002/assets/js/privy_bridge.js#other",
  ])("does not runtime-import an unsafe server bridge URL: %s", async bridgeSource => {
    const runtimeImport = vi.fn<(url: string) => Promise<PrivyBridgeModule>>()
    const importer = createBrowserPrivyBridgeImporter({
      bridgeSource,
      runtimeImport,
      currentOrigin: "http://127.0.0.1:4002",
    })

    await expect(importer()).rejects.toThrow("Privy bridge source is unavailable")
    expect(runtimeImport).not.toHaveBeenCalled()
  })

  it.each([
    "/assets/js/privy_bridge.js",
    "/assets/js/privy_bridge-0123456789abcdef0123456789abcdef.js?vsn=d",
  ])("accepts a canonical server bridge URL: %s", async bridgeSource => {
    const handleRequest = vi.fn(async () => undefined)
    const startPrivyBridge = vi.fn(async () => ({request: handleRequest}))
    const runtimeImport = vi.fn(async () => ({startPrivyBridge}))
    const loader = createLazyAuthLoader(
      createBrowserPrivyBridgeImporter({
        bridgeSource,
        runtimeImport,
        currentOrigin: "http://127.0.0.1:4002",
      }),
    )

    await loader.request("sync")

    expect(runtimeImport).toHaveBeenCalledWith(
      bridgeSource.includes("?vsn=d")
        ? "http://127.0.0.1:4002/assets/js/privy_bridge-0123456789abcdef0123456789abcdef.js?vsn=d&regent_retry=0"
        : "http://127.0.0.1:4002/assets/js/privy_bridge.js?regent_retry=0",
    )
    expect(startPrivyBridge).toHaveBeenCalledWith()
    expect(handleRequest).toHaveBeenCalledWith("sync")
  })

  it("rejects a bridge module without the canonical start function", async () => {
    const loader = createLazyAuthLoader(
      createBrowserPrivyBridgeImporter({
        bridgeSource: "/assets/js/privy_bridge.js",
        runtimeImport: vi.fn(async () => ({startPrivyBridge: "not callable"}) as never),
        currentOrigin: "http://127.0.0.1:4002",
      }),
    )

    await expect(loader.request("sign-in")).rejects.toThrow(
      "Privy bridge module is invalid",
    )
  })

  it("rejects a bridge that mounts without a callable request handle", async () => {
    const loader = createLazyAuthLoader(
      vi.fn(async () => ({
        startPrivyBridge: vi.fn(async () => ({request: "not callable"}) as never),
      })),
    )

    await expect(loader.request("sign-in")).rejects.toThrow(
      "Privy bridge handle is invalid",
    )
  })

  it("does not load Privy before an account action and starts once for repeated first clicks", async () => {
    let resolveModule: ((module: PrivyBridgeModule) => void) | undefined
    const importer = vi.fn(
      () =>
        new Promise<PrivyBridgeModule>(resolve => {
          resolveModule = resolve
        }),
    )
    const loader = createLazyAuthLoader(importer)

    expect(importer).not.toHaveBeenCalled()

    const first = loader.request("sign-in")
    const repeat = loader.request("sign-in")
    expect(importer).toHaveBeenCalledOnce()

    const handleRequest = vi.fn(async (_request: AccountRequest) => undefined)
    const startPrivyBridge = vi.fn(async () => ({request: handleRequest}))
    resolveModule?.({startPrivyBridge})
    await Promise.all([first, repeat])

    expect(startPrivyBridge).toHaveBeenCalledOnce()
    expect(handleRequest).toHaveBeenCalledOnce()
    expect(handleRequest).toHaveBeenCalledWith("sign-in")
  })

  it("allows a clean retry after the Privy chunk cannot load", async () => {
    const handleRequest = vi.fn(async () => undefined)
    const startPrivyBridge = vi.fn(async () => ({request: handleRequest}))
    const importer = vi
      .fn<() => Promise<PrivyBridgeModule>>()
      .mockRejectedValueOnce(new Error("chunk unavailable"))
      .mockResolvedValueOnce({startPrivyBridge})
    const loader = createLazyAuthLoader(importer)

    await expect(loader.request("sign-in")).rejects.toThrow("chunk unavailable")
    await loader.request("sign-in")

    expect(importer).toHaveBeenCalledTimes(2)
    expect(startPrivyBridge).toHaveBeenCalledOnce()
    expect(handleRequest).toHaveBeenCalledWith("sign-in")
  })

  it("shows a sign-in load failure and clears it when the next click succeeds", async () => {
    vi.stubGlobal("Element", AccountElement)
    const handleRequest = vi.fn(async () => undefined)
    const startPrivyBridge = vi.fn(async () => ({request: handleRequest}))
    const importer = vi
      .fn<() => Promise<PrivyBridgeModule>>()
      .mockRejectedValueOnce(new Error("chunk unavailable"))
      .mockResolvedValueOnce({startPrivyBridge})
    const page = accountDocument()

    installAccountAuthLazyLoader(page.documentRoot, importer)
    page.click("sign-in")
    await vi.waitFor(() => expect(page.status.hidden).toBe(false))
    expect(page.status.textContent).toBe("Sign in couldn’t start. Try again.")

    const replacementStatus = page.replaceStatus()
    page.click("sign-in")
    await vi.waitFor(() => expect(handleRequest).toHaveBeenCalledWith("sign-in"))
    expect(replacementStatus.hidden).toBe(true)
    expect(replacementStatus.textContent).toBe("")
    expect(importer).toHaveBeenCalledTimes(2)
  })

  it("uses truthful failure copy for sign out and signed-in synchronization", async () => {
    vi.stubGlobal("Element", AccountElement)

    const signOutPage = accountDocument()
    installAccountAuthLazyLoader(
      signOutPage.documentRoot,
      vi.fn().mockRejectedValue(new Error("bridge unavailable")),
    )
    signOutPage.click("sign-out")
    await vi.waitFor(() => expect(signOutPage.status.hidden).toBe(false))
    expect(signOutPage.status.textContent).toBe("Sign out couldn’t finish. Try again.")

    const syncPage = accountDocument({signedIn: true})
    installAccountAuthLazyLoader(
      syncPage.documentRoot,
      vi.fn().mockRejectedValue(new Error("bridge unavailable")),
    )
    await vi.waitFor(() => expect(syncPage.status.hidden).toBe(false))
    expect(syncPage.status.textContent).toBe(
      "Account connection couldn’t refresh. Try again.",
    )
  })

  it("starts wallet synchronization on signed-in load but keeps anonymous load lazy", async () => {
    const anonymousImporter = vi.fn<() => Promise<PrivyBridgeModule>>()
    installAccountAuthLazyLoader(accountDocument().documentRoot, anonymousImporter)
    expect(anonymousImporter).not.toHaveBeenCalled()

    const handleRequest = vi.fn(async () => undefined)
    const startPrivyBridge = vi.fn(async () => ({request: handleRequest}))
    const signedInImporter = vi.fn(async () => ({startPrivyBridge}))
    installAccountAuthLazyLoader(accountDocument({signedIn: true}).documentRoot, signedInImporter)

    await vi.waitFor(() => expect(handleRequest).toHaveBeenCalledWith("sync"))
    expect(signedInImporter).toHaveBeenCalledOnce()
  })
})
