import {afterEach, describe, expect, it, vi} from "vitest"

import {
  createBrowserPrivyBridgeImporter,
  createLazyAuthLoader,
  createSessionMutationCoordinator,
  consumeSignOutHandoff,
  installAccountAuthLazyLoader,
  proveAnonymousSession,
  writeSignOutHandoff,
  type AccountRequest,
  type PrivyBridgeModule,
} from "../js/auth_lazy"
import {createAccountRequestHandler} from "../js/privy_bridge"

afterEach(() => vi.unstubAllGlobals())

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

function memoryStorage(initial?: string) {
  const values = new Map<string, string>()
  if (initial !== undefined) {
    values.set("regent:privy-sign-out-handoff:v1", initial)
  }
  return {
    getItem: vi.fn((key: string) => values.get(key) ?? null),
    setItem: vi.fn((key: string, value: string) => void values.set(key, value)),
    removeItem: vi.fn((key: string) => void values.delete(key)),
  }
}

function accountDocument({
  signedIn = false,
  bridgeSource = "/assets/js/privy_bridge.js",
  appId = "public-app-id",
}: {signedIn?: boolean; bridgeSource?: string | null; appId?: string | null} = {}) {
  let status = new AccountElement()
  const listeners = new Map<string, (event: Event) => void>()
  const documentRoot = {
    querySelector(selector: string) {
      if (selector === "meta[name='privy-app-id']") {
        return appId === null ? null : {content: appId}
      }
      if (selector === "meta[name='privy-bridge-src']") {
        return bridgeSource === null ? null : {content: bridgeSource}
      }
      if (selector === "#account-auth-status") return status
      if (selector === "#account-control [data-account-target='sign-out']") {
        return signedIn ? new AccountElement("sign-out") : null
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
  it("aborts an in-flight session establishment before one local deletion and blocks later writes", async () => {
    vi.useFakeTimers()

    try {
      const sessionMutations = createSessionMutationCoordinator({cancellationWaitMs: 10})
      const order: string[] = []
      let finishLate: (() => void) | undefined
      const establishment = sessionMutations.establish(
        signal =>
          new Promise<void>(resolve => {
            order.push("establish")
            finishLate = resolve
            signal.addEventListener("abort", () => order.push("abort"), {once: true})
          }),
      )
      await vi.advanceTimersByTimeAsync(0)
      expect(order).toEqual(["establish"])
      const establishmentFailure = expect(establishment).rejects.toMatchObject({
        name: "AbortError",
      })

      const clearSession = vi.fn(async () => {
        order.push("delete")
      })
      const signOut = sessionMutations.signOut(clearSession)
      expect(clearSession).not.toHaveBeenCalled()
      await vi.advanceTimersByTimeAsync(10)
      await signOut
      expect(order).toEqual(["establish", "abort", "delete"])

      finishLate?.()
      await establishmentFailure

      const lateEstablishment = vi.fn(async () => undefined)
      await expect(sessionMutations.establish(lateEstablishment)).rejects.toThrow(
        "Local sign out has already started.",
      )
      await sessionMutations.signOut(clearSession)
      expect(lateEstablishment).not.toHaveBeenCalled()
      expect(clearSession).toHaveBeenCalledOnce()
    } finally {
      vi.useRealTimers()
    }
  })

  it("replaces pending sync with sign out until the bridge is ready", async () => {
    let resolveModule: ((module: PrivyBridgeModule) => void) | undefined
    let resolveHandle: ((handle: {request: (request: AccountRequest) => Promise<void>}) => void) |
      undefined
    const order: string[] = []
    const handleRequest = vi.fn(
      createAccountRequestHandler({
        requestLogin: vi.fn(),
        providerLogout: vi.fn(async () => {
          order.push("provider")
        }),
        synchronizeWallets: vi.fn(async () => undefined),
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
    expect(order).toEqual(["provider"])
  })

  it("processes queued sign out after an in-flight sync rejects", async () => {
    let rejectSync: ((error: Error) => void) | undefined
    const handleRequest = vi.fn(
      (request: AccountRequest) =>
        request === "sync"
          ? new Promise<void>((_resolve, reject) => {
              rejectSync = reject
            })
          : Promise.resolve(),
    )
    const loader = createLazyAuthLoader(
      vi.fn(async () => ({
        startPrivyBridge: vi.fn(async () => ({request: handleRequest})),
      })),
    )

    const sync = loader.request("sync")
    const syncFailure = expect(sync).rejects.toThrow("wallet sync failed")
    await vi.waitFor(() => expect(handleRequest).toHaveBeenCalledWith("sync"))

    const signOut = loader.request("sign-out")
    rejectSync?.(new Error("wallet sync failed"))

    await syncFailure
    await expect(signOut).resolves.toBeUndefined()
    expect(handleRequest.mock.calls.map(([request]) => request)).toEqual([
      "sync",
      "sign-out",
    ])
  })

  it("keeps a successful in-flight sync independent from a queued sign-out rejection", async () => {
    let resolveSync: (() => void) | undefined
    const signOutError = new Error("local session deletion failed")
    const handleRequest = vi.fn(
      (request: AccountRequest) =>
        request === "sync"
          ? new Promise<void>(resolve => {
              resolveSync = resolve
            })
          : Promise.reject(signOutError),
    )
    const loader = createLazyAuthLoader(
      vi.fn(async () => ({
        startPrivyBridge: vi.fn(async () => ({request: handleRequest})),
      })),
    )

    const sync = loader.request("sync")
    await vi.waitFor(() => expect(handleRequest).toHaveBeenCalledWith("sync"))

    const signOut = loader.request("sign-out")
    const syncOutcome = expect(sync).resolves.toBeUndefined()
    const signOutOutcome = expect(signOut).rejects.toBe(signOutError)
    resolveSync?.()

    await Promise.all([syncOutcome, signOutOutcome])
    expect(handleRequest.mock.calls.map(([request]) => request)).toEqual([
      "sync",
      "sign-out",
    ])
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

  it("does not silently disable account actions when the public app ID is absent", async () => {
    vi.stubGlobal("Element", AccountElement)
    const importer = vi.fn().mockRejectedValue(new Error("bridge unavailable"))
    const page = accountDocument({appId: null})

    installAccountAuthLazyLoader(page.documentRoot, importer)
    page.click("sign-in")

    await vi.waitFor(() => expect(page.status.hidden).toBe(false))
    expect(importer).toHaveBeenCalledOnce()
    expect(page.status.textContent).toBe("Sign in couldn’t start. Try again.")
  })

  it("writes the handoff before local deletion and leaves provider work to the new document", async () => {
    vi.stubGlobal("Element", AccountElement)
    const order: string[] = []
    const page = accountDocument()
    const storage = memoryStorage()
    const clearSession = vi.fn(async () => {
      order.push("local")
    })
    const setItem = storage.setItem.getMockImplementation()!
    storage.setItem.mockImplementation((key, value) => {
      order.push("handoff")
      setItem(key, value)
    })
    const importer = vi.fn<() => Promise<PrivyBridgeModule>>()

    installAccountAuthLazyLoader(page.documentRoot, importer, {
      clearSession,
      handoffStorage: storage,
      now: () => 1_000,
      sessionMutations: createSessionMutationCoordinator(),
    })
    page.click("sign-out")

    await vi.waitFor(() => expect(clearSession).toHaveBeenCalledOnce())
    expect(order.slice(0, 2)).toEqual(["handoff", "local"])
    expect(clearSession).toHaveBeenCalledOnce()
    expect(importer).not.toHaveBeenCalled()
  })

  it("gives a consumed handoff one bounded provider attempt without reloading", async () => {
    vi.useFakeTimers()

    try {
      vi.stubGlobal("Element", AccountElement)
      const page = accountDocument()
      const storage = memoryStorage(JSON.stringify({version: 1, issuedAtMs: 1_000}))
      const fetcher = vi.fn(async () =>
        new Response(JSON.stringify({authenticated: false}), {status: 200}),
      ) as typeof fetch
      vi.stubGlobal("fetch", fetcher)
      const importer = vi.fn(async () => ({
        startPrivyBridge: vi.fn(() => new Promise<never>(() => undefined)),
      }))
      installAccountAuthLazyLoader(page.documentRoot, importer, {
        handoffStorage: storage,
        now: () => 1_001,
        providerSignOutTimeoutMs: 10,
      })

      await vi.advanceTimersByTimeAsync(0)
      expect(fetcher).toHaveBeenCalledWith("/auth/session", {
        credentials: "same-origin",
        redirect: "error",
      })
      await vi.advanceTimersByTimeAsync(10)
      await vi.waitFor(() => expect(page.status.hidden).toBe(false))
      expect(page.status.textContent).toBe(
        "Signed out locally. Provider sign out couldn’t finish.",
      )
    } finally {
      vi.useRealTimers()
    }
  })

  it("does not attempt provider logout when local deletion fails", async () => {
    vi.stubGlobal("Element", AccountElement)
    const page = accountDocument()
    const importer = vi.fn<() => Promise<PrivyBridgeModule>>()
    const storage = memoryStorage()

    installAccountAuthLazyLoader(page.documentRoot, importer, {
      clearSession: vi.fn().mockRejectedValue(new Error("local deletion failed")),
      handoffStorage: storage,
      sessionMutations: createSessionMutationCoordinator(),
    })
    page.click("sign-out")

    await vi.waitFor(() => expect(page.status.hidden).toBe(false))
    expect(page.status.textContent).toBe("Sign out couldn’t finish. Try again.")
    expect(importer).not.toHaveBeenCalled()
    expect(storage.getItem("regent:privy-sign-out-handoff:v1")).toBeNull()
  })

  it("uses truthful failure copy for sign out and signed-in synchronization", async () => {
    vi.stubGlobal("Element", AccountElement)

    const signOutPage = accountDocument()
    installAccountAuthLazyLoader(
      signOutPage.documentRoot,
      vi.fn().mockRejectedValue(new Error("bridge unavailable")),
      {
        clearSession: vi.fn().mockRejectedValue(new Error("local deletion failed")),
        sessionMutations: createSessionMutationCoordinator(),
      },
    )
    signOutPage.click("sign-out")
    await vi.waitFor(() => expect(signOutPage.status.hidden).toBe(false))
    expect(signOutPage.status.textContent).toBe("Sign out couldn’t finish. Try again.")

    const syncPage = accountDocument({signedIn: true})
    installAccountAuthLazyLoader(
      syncPage.documentRoot,
      vi.fn().mockRejectedValue(new Error("bridge unavailable")),
      {
        clearSession: vi.fn(async () => undefined),
        sessionMutations: createSessionMutationCoordinator(),
      },
    )
    await vi.waitFor(() => expect(syncPage.status.hidden).toBe(false))
    expect(syncPage.status.textContent).toBe(
      "Account connection couldn’t refresh. Try again.",
    )
  })

  it.each([
    {
      name: "the bridge import fails",
      importer: () => Promise.reject(new Error("bridge unavailable")),
    },
    {
      name: "provider readiness never settles",
      importer: () =>
        Promise.resolve({
          startPrivyBridge: vi.fn(() => new Promise<never>(() => undefined)),
        }),
    },
  ])("fails closed on signed-in startup when $name", async ({importer}) => {
    const page = accountDocument({signedIn: true})
    const clearSession = vi.fn(async () => undefined)

    installAccountAuthLazyLoader(page.documentRoot, vi.fn(importer), {
      clearSession,
      sessionMutations: createSessionMutationCoordinator(),
      signedInStartupTimeoutMs: 10,
    })

    await vi.waitFor(() => expect(clearSession).toHaveBeenCalledOnce())
    expect(clearSession).toHaveBeenCalledOnce()
    expect(page.status.textContent).toBe(
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

  it.each([
    null,
    "",
    "not-json",
    JSON.stringify({version: 1, issuedAtMs: 1_000, extra: true}),
    JSON.stringify({version: 2, issuedAtMs: 1_000}),
    JSON.stringify({version: 1, issuedAtMs: 1_001}),
    JSON.stringify({version: 1, issuedAtMs: -29_001}),
  ])("rejects and removes an absent or invalid handoff: %s", value => {
    const storage = memoryStorage(value ?? undefined)
    const page = accountDocument()

    expect(consumeSignOutHandoff(page.documentRoot, storage, 1_000)).toBe(false)
    expect(storage.getItem("regent:privy-sign-out-handoff:v1")).toBeNull()
  })

  it("consumes a strict current handoff once per document", () => {
    const value = JSON.stringify({version: 1, issuedAtMs: 1_000})
    const storage = memoryStorage(value)
    const page = accountDocument()

    expect(consumeSignOutHandoff(page.documentRoot, storage, 31_000)).toBe(true)
    storage.setItem("regent:privy-sign-out-handoff:v1", value)
    expect(consumeSignOutHandoff(page.documentRoot, storage, 31_000)).toBe(false)
  })

  it("writes only the strict versioned handoff and confirms it synchronously", () => {
    const storage = memoryStorage()

    expect(writeSignOutHandoff(storage, 1_000)).toBe(true)
    expect(storage.getItem("regent:privy-sign-out-handoff:v1")).toBe(
      JSON.stringify({version: 1, issuedAtMs: 1_000}),
    )
  })

  it("fails closed when handoff read, removal, or removal confirmation fails", () => {
    const value = JSON.stringify({version: 1, issuedAtMs: 1_000})
    for (const operation of ["read", "remove", "confirm"] as const) {
      const storage = memoryStorage(value)
      if (operation === "read") {
        storage.getItem.mockImplementationOnce(() => {
          throw new Error()
        })
      }
      if (operation === "remove") {
        storage.removeItem.mockImplementationOnce(() => {
          throw new Error()
        })
      }
      if (operation === "confirm") {
        storage.getItem
          .mockImplementationOnce(() => value)
          .mockImplementationOnce(() => value)
      }

      expect(
        consumeSignOutHandoff(accountDocument().documentRoot, storage, 1_001),
      ).toBe(false)
    }
  })

  it.each([
    new Response(JSON.stringify({authenticated: true}), {status: 200}),
    new Response(JSON.stringify({authenticated: false}), {status: 500}),
    new Response("not-json", {status: 200}),
    {
      ok: true,
      redirected: true,
      json: async () => ({authenticated: false}),
    } as Response,
  ])("requires an ordinary successful anonymous session proof", async response => {
    const fetcher = vi.fn(async () => response) as typeof fetch
    await expect(proveAnonymousSession(fetcher)).resolves.toBe(false)
  })

  it("does not import Privy when a consumed handoff cannot prove an anonymous session", async () => {
    const page = accountDocument()
    const storage = memoryStorage(JSON.stringify({version: 1, issuedAtMs: 1_000}))
    const importer = vi.fn<() => Promise<PrivyBridgeModule>>()
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(JSON.stringify({authenticated: true}), {status: 200}),
      ),
    )

    installAccountAuthLazyLoader(page.documentRoot, importer, {
      handoffStorage: storage,
      now: () => 1_001,
    })

    await vi.waitFor(() => expect(storage.removeItem).toHaveBeenCalledOnce())
    expect(importer).not.toHaveBeenCalled()
  })

  it("a retained marker after failed deletion still requires current anonymous truth", async () => {
    vi.stubGlobal("Element", AccountElement)
    const originalPage = accountDocument()
    const storage = memoryStorage()
    const setItem = storage.setItem.getMockImplementation()!
    const removeItem = storage.removeItem.getMockImplementation()!
    let writeCount = 0
    storage.setItem.mockImplementation((key, value) => {
      writeCount += 1
      if (writeCount > 1) throw new Error("tombstone failed")
      setItem(key, value)
    })
    storage.removeItem.mockImplementation(() => {
      throw new Error("removal failed")
    })

    installAccountAuthLazyLoader(originalPage.documentRoot, vi.fn(), {
      clearSession: vi.fn().mockRejectedValue(new Error("deletion failed")),
      handoffStorage: storage,
      now: () => 1_000,
      sessionMutations: createSessionMutationCoordinator(),
    })
    originalPage.click("sign-out")
    await vi.waitFor(() => expect(originalPage.status.hidden).toBe(false))

    storage.setItem.mockImplementation(setItem)
    storage.removeItem.mockImplementation(removeItem)
    const importer = vi.fn<() => Promise<PrivyBridgeModule>>()
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(JSON.stringify({authenticated: true}), {status: 200}),
      ),
    )
    installAccountAuthLazyLoader(accountDocument().documentRoot, importer, {
      handoffStorage: storage,
      now: () => 1_001,
    })

    await vi.waitFor(() => expect(storage.removeItem).toHaveBeenCalled())
    expect(importer).not.toHaveBeenCalled()
  })

  it("enforces preterminal and terminal handoff request states", async () => {
    const request = vi.fn(async (_request: AccountRequest) => undefined)
    const identity = vi.fn(async () => undefined)
    const finishSignOutOnly = vi.fn()
    const startPrivyBridge = vi.fn(async () => ({request, identity, finishSignOutOnly}))
    const loader = createLazyAuthLoader(
      vi.fn(async () => ({startPrivyBridge})),
      {mode: "sign-out-only"},
    )

    await expect(loader.request("sign-in")).rejects.toThrow("still in progress")
    await expect(loader.request("sync")).rejects.toThrow("still in progress")
    await expect(loader.identity({action: "link", provider: "x"})).rejects.toThrow(
      "still in progress",
    )
    await Promise.all([loader.request("sign-out"), loader.request("sign-out")])
    expect(startPrivyBridge).toHaveBeenCalledWith({mode: "sign-out-only"})
    expect(request).toHaveBeenCalledOnce()
    expect(request).toHaveBeenCalledWith("sign-out")

    loader.finishHandoff()
    await loader.request("sign-out")
    await expect(loader.request("sync")).rejects.toThrow("disabled")
    await loader.request("sign-in")
    await loader.identity({action: "link", provider: "x"})
    expect(request.mock.calls.map(([value]) => value)).toEqual(["sign-out", "sign-in"])
    expect(identity).toHaveBeenCalledOnce()
    expect(finishSignOutOnly).toHaveBeenCalledOnce()
  })

  it("invalidates a timed-out handoff before late bridge readiness", async () => {
    let resolveModule: ((module: PrivyBridgeModule) => void) | undefined
    const request = vi.fn(async () => undefined)
    const finishSignOutOnly = vi.fn()
    const loader = createLazyAuthLoader(
      vi.fn(
        () =>
          new Promise<PrivyBridgeModule>(resolve => {
            resolveModule = resolve
          }),
      ),
      {mode: "sign-out-only"},
    )

    const signOut = loader.request("sign-out")
    loader.finishHandoff()
    resolveModule?.({
      startPrivyBridge: vi.fn(async () => ({request, finishSignOutOnly})),
    })

    await signOut
    expect(request).not.toHaveBeenCalled()
    expect(finishSignOutOnly).toHaveBeenCalledOnce()
  })
})
