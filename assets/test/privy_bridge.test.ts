import {afterEach, describe, expect, it, vi} from "vitest"
import React from "react"

const productionRootRender = vi.hoisted(() => vi.fn())
const productionPrivyHooks = vi.hoisted(() => ({
  login: vi.fn(),
  linkTwitter: vi.fn(),
  linkGithub: vi.fn(),
  linkFarcaster: vi.fn(),
  unlinkOAuth: vi.fn(async () => undefined),
  unlinkFarcaster: vi.fn(async () => undefined),
  connectActiveWallet: vi.fn(async () => ({})),
}))

vi.mock("react-dom/client", () => ({
  createRoot: () => ({render: productionRootRender}),
}))

vi.mock("@privy-io/react-auth", () => ({
  PrivyProvider: "privy-provider",
  usePrivy: () => ({authenticated: false, logout: vi.fn(), ready: true}),
  useWallets: () => ({wallets: []}),
  useActiveWallet: () => ({
    wallet: undefined,
    connect: productionPrivyHooks.connectActiveWallet,
  }),
  useToken: () => ({getAccessToken: vi.fn(async () => null)}),
  useLogin: () => ({login: productionPrivyHooks.login}),
  useLinkAccount: () => ({
    linkTwitter: productionPrivyHooks.linkTwitter,
    linkGithub: productionPrivyHooks.linkGithub,
    linkFarcaster: productionPrivyHooks.linkFarcaster,
  }),
  useUnlinkOAuth: () => ({unlink: productionPrivyHooks.unlinkOAuth}),
  useUnlinkFarcaster: () => ({unlink: productionPrivyHooks.unlinkFarcaster}),
}))

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

import * as bridge from "../js/privy_bridge"
import {clearLocalSession, createSessionMutationCoordinator} from "../js/auth_lazy"
import {
  activeEthereumWallet,
  replaceActiveEthereumWallet,
  selectConnectedEthereumWallet,
  type EthereumProvider,
} from "../js/wallet_actions/connected_wallet"

const {
  createLocalSession,
  createAccountRequestHandler,
  createIdentityRequestHandler,
  createProviderSessionReconciler,
  createSignOutOnlyBridgeState,
  createPrivyLoginCallbacks,
  createReadyLoginGate,
  createPrivySessionCompletion,
  createPrivyTokenCallbacks,
} = bridge

type HookSlot = {
  deps?: readonly unknown[]
  value?: unknown
}

function installAccountBridgeRenderer() {
  const slots: HookSlot[] = []
  let cursor = 0
  let pendingEffects: React.EffectCallback[] = []
  const unchanged = (left?: readonly unknown[], right?: readonly unknown[]) =>
    left !== undefined &&
    right !== undefined &&
    left.length === right.length &&
    left.every((value, index) => Object.is(value, right[index]))

  vi.spyOn(React, "useRef").mockImplementation(((initial: unknown) => {
    const index = cursor++
    if (!slots[index]) slots[index] = {value: {current: initial}}
    return slots[index].value
  }) as typeof React.useRef)
  vi.spyOn(React, "useMemo").mockImplementation(((factory: () => unknown, deps?: unknown[]) => {
    const index = cursor++
    if (!slots[index] || !unchanged(slots[index].deps, deps)) {
      slots[index] = {deps, value: factory()}
    }
    return slots[index].value
  }) as typeof React.useMemo)
  vi.spyOn(React, "useCallback").mockImplementation(((callback: unknown, deps?: unknown[]) => {
    const index = cursor++
    if (!slots[index] || !unchanged(slots[index].deps, deps)) {
      slots[index] = {deps, value: callback}
    }
    return slots[index].value
  }) as typeof React.useCallback)
  vi.spyOn(React, "useEffect").mockImplementation(((effect: React.EffectCallback, deps?: unknown[]) => {
    const index = cursor++
    if (!slots[index] || !unchanged(slots[index].deps, deps)) {
      slots[index] = {deps}
      pendingEffects.push(effect)
    }
  }) as typeof React.useEffect)

  return (element: React.ReactElement) => {
    cursor = 0
    pendingEffects = []
    ;(element.type as (props: unknown) => unknown)(element.props)
    const effects = pendingEffects
    pendingEffects = []
    effects.forEach(effect => effect())
  }
}

function stubBrowserGlobals(): string[] {
  const dispatched: string[] = []

  vi.stubGlobal("document", {
    body: {append: vi.fn()},
    createElement: () => ({hidden: false}),
    querySelector: () => null,
  })
  vi.stubGlobal("window", {
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
    dispatchEvent: (event: {type: string}) => dispatched.push(event.type),
    location: {origin: "https://regents.sh"},
  })
  vi.stubGlobal(
    "CustomEvent",
    class {
      constructor(readonly type: string) {}
    },
  )

  return dispatched
}

function ethereumWallet(address: string) {
  const provider: EthereumProvider = {request: vi.fn()}
  return {address, type: "ethereum", provider, getEthereumProvider: async () => provider}
}

// Yields to the event loop until `reached` holds, so an ordering assertion waits
// on the work itself rather than on a duration.
async function until(reached: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 200 && !reached(); attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 0))
  }

  if (!reached()) throw new Error("The awaited step never happened.")
}

describe("Privy session bridge", () => {
  it("synchronizes wallets without changing the local or provider session", async () => {
    const requestLogin = vi.fn()
    const providerLogout = vi.fn(async () => undefined)
    const synchronizeWallets = vi.fn(async () => undefined)
    const request = createAccountRequestHandler({
      requestLogin,
      providerLogout,
      synchronizeWallets,
    })

    await request("sync")

    expect(synchronizeWallets).toHaveBeenCalledOnce()
    expect(requestLogin).not.toHaveBeenCalled()
    expect(providerLogout).not.toHaveBeenCalled()
  })

  it("retains the first sign-in click until Privy is ready", () => {
    const login = vi.fn()
    const gate = createReadyLoginGate(login)

    gate.requestLogin()
    gate.requestLogin()
    expect(login).not.toHaveBeenCalled()

    gate.setReady(true)
    gate.setReady(true)
    expect(login).toHaveBeenCalledOnce()
  })

  it("creates a local session with only the verified bearer and CSRF headers", async () => {
    const calls: Array<[RequestInfo | URL, RequestInit | undefined]> = []
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push([input, init])
      return input === "/auth/csrf"
        ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
        : new Response("{}", {
            status: 200,
            headers: {"x-ash-session-changed": "false"},
          })
    }) as typeof fetch

    await expect(createLocalSession("verified", fetcher)).resolves.toEqual({
      sessionChanged: false,
    })

    expect(calls[1]).toEqual([
      "/auth/privy/session",
      {
        method: "POST",
        credentials: "same-origin",
        headers: {authorization: "Bearer verified", "x-csrf-token": "csrf"},
      },
    ])
  })

  it("returns a verified identity conflict from the refreshed local session", async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL) =>
      input === "/auth/csrf"
        ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
        : new Response("{}", {
            status: 200,
            headers: {
              "x-ash-session-changed": "false",
              "x-ash-identity-error": "already-connected",
            },
          }),
    ) as typeof fetch

    await expect(createLocalSession("verified", fetcher)).resolves.toEqual({
      sessionChanged: false,
      identityError: "already-connected",
    })
  })

  it("routes link and unlink commands through Privy before refreshing the session", async () => {
    const linkX = vi.fn()
    const linkGithub = vi.fn()
    const linkFarcaster = vi.fn()
    const unlinkOAuth = vi.fn(async () => undefined)
    const unlinkFarcaster = vi.fn(async () => undefined)
    const refreshSession = vi.fn(async () => undefined)
    const request = createIdentityRequestHandler({
      linkX,
      linkGithub,
      linkFarcaster,
      unlinkOAuth,
      unlinkFarcaster,
      refreshSession,
    })

    await request({action: "link", provider: "x"})
    await request({action: "link", provider: "github"})
    await request({action: "link", provider: "farcaster"})

    expect(linkX).toHaveBeenCalledOnce()
    expect(linkGithub).toHaveBeenCalledOnce()
    expect(linkFarcaster).toHaveBeenCalledOnce()
    expect(refreshSession).not.toHaveBeenCalled()

    await request({action: "unlink", provider: "x", subject: "twitter-42"})
    await request({action: "unlink", provider: "github", subject: "github-7"})
    await request({action: "unlink", provider: "farcaster", subject: "12345"})

    expect(unlinkOAuth).toHaveBeenNthCalledWith(1, "twitter", "twitter-42")
    expect(unlinkOAuth).toHaveBeenNthCalledWith(2, "github", "github-7")
    expect(unlinkFarcaster).toHaveBeenCalledWith(12345)
    expect(refreshSession).toHaveBeenCalledTimes(3)
  })

  it("rejects unlink commands without a verified provider subject", async () => {
    const request = createIdentityRequestHandler({
      linkX: vi.fn(),
      linkGithub: vi.fn(),
      linkFarcaster: vi.fn(),
      unlinkOAuth: vi.fn(),
      unlinkFarcaster: vi.fn(),
      refreshSession: vi.fn(),
    })

    await expect(
      request({action: "unlink", provider: "farcaster", subject: "not-a-fid"}),
    ).rejects.toThrow("unavailable")
    await expect(request({action: "unlink", provider: "x"})).rejects.toThrow(
      "unavailable",
    )
  })

  it("aborts a never-settling bootstrap before one local deletion", async () => {
    const sessionMutations = createSessionMutationCoordinator()
    let bootstrapStarted = false
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      if (input !== "/auth/csrf") throw new Error("The session POST was never reachable.")
      bootstrapStarted = true
      return new Promise<Response>((_resolve, reject) =>
        init?.signal?.addEventListener("abort", () => reject(init.signal?.reason), {once: true}),
      )
    })
    const fetcher = fetchMock as unknown as typeof fetch

    const establishment = createLocalSession("verified", fetcher, sessionMutations)
    await until(() => bootstrapStarted)
    const establishmentFailure = expect(establishment).rejects.toMatchObject({name: "AbortError"})

    const clearSession = vi.fn(async () => undefined)
    await sessionMutations.signOut(clearSession)
    expect(clearSession).toHaveBeenCalledOnce()

    await establishmentFailure
    expect(fetchMock).not.toHaveBeenCalledWith("/auth/privy/session", expect.anything())

    const fetchCallCount = fetchMock.mock.calls.length
    await expect(createLocalSession("verified", fetcher, sessionMutations)).rejects.toThrow(
      "Local sign out has already started.",
    )
    expect(fetchMock).toHaveBeenCalledTimes(fetchCallCount)
  })

  it("holds a queued sign out until a dispatched session POST has adopted its token", async () => {
    const sessionMutations = createSessionMutationCoordinator()
    const order: string[] = []
    let releasePost: (() => void) | undefined
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      if (input === "/auth/csrf") {
        order.push("csrf")
        return Promise.resolve(new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200}))
      }
      order.push("post")
      return new Promise<Response>(resolve => {
        releasePost = () =>
          resolve(new Response("{}", {status: 200, headers: {"x-ash-session-changed": "false"}}))
      })
    })
    const fetcher = fetchMock as unknown as typeof fetch

    const establishment = createLocalSession("verified", fetcher, sessionMutations)
    await until(() => order.includes("post"))

    const clearSession = vi.fn(async () => void order.push("delete"))
    const signOut = sessionMutations.signOut(clearSession)
    expect(clearSession).not.toHaveBeenCalled()

    releasePost?.()
    await expect(establishment).resolves.toEqual({sessionChanged: false})
    await signOut

    // The dispatched POST may already have renewed the cookie, so sign out runs
    // only after the adoption fetch that follows it.
    expect(order).toEqual(["csrf", "post", "csrf", "delete"])
  })

  it("completes the local session from Privy's access-token grant", async () => {
    const reload = vi.fn()
    const fetcher = vi.fn(async (input: RequestInfo | URL) =>
      input === "/auth/csrf"
        ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
        : new Response("{}", {
            status: 200,
            headers: {"x-ash-session-changed": "true"},
          }),
    ) as typeof fetch

    const completeLogin = createPrivySessionCompletion({
      fetcher,
      localSessionNeeded: () => true,
      reload,
    })

    await Promise.all([completeLogin("verified"), completeLogin("verified")])

    expect(fetcher).toHaveBeenCalledWith(
      "/auth/privy/session",
      expect.objectContaining({method: "POST"}),
    )
    expect(reload).toHaveBeenCalledOnce()
  })

  it("finishes sign in when Privy grants the token after wallet authentication settles", async () => {
    vi.useFakeTimers()

    try {
      const reload = vi.fn()
      const fetcher = vi.fn(async (input: RequestInfo | URL) =>
        input === "/auth/csrf"
          ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
          : new Response("{}", {
              status: 200,
              headers: {"x-ash-session-changed": "true"},
            }),
      ) as typeof fetch

      const completeLogin = createPrivySessionCompletion({
        fetcher,
        localSessionNeeded: () => true,
        reload,
      })
      const tokenCallbacks = createPrivyTokenCallbacks(completeLogin)

      const completion = new Promise<void>(resolve => {
        setTimeout(
          () => void tokenCallbacks.onAccessTokenGranted({accessToken: "verified"}).then(resolve),
          10_000,
        )
      })
      await vi.advanceTimersByTimeAsync(10_000)
      await completion

      expect(fetcher).toHaveBeenCalledWith(
        "/auth/privy/session",
        expect.objectContaining({method: "POST"}),
      )
      expect(reload).toHaveBeenCalledOnce()
    } finally {
      vi.useRealTimers()
    }
  })

  it("finishes the local session from the first successful wallet login", async () => {
    const completeLogin = vi.fn(async () => undefined)
    const getAccessToken = vi.fn(async () => "first-login-token")
    const loginCallbacks = createPrivyLoginCallbacks(getAccessToken, completeLogin)

    await loginCallbacks.onComplete?.(
      {} as Parameters<NonNullable<typeof loginCallbacks.onComplete>>[0],
    )

    expect(getAccessToken).toHaveBeenCalledOnce()
    expect(completeLogin).toHaveBeenCalledWith("first-login-token")
  })

  it("clears Regent before provider logout is attempted", async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL) =>
      input === "/auth/csrf"
        ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
        : new Response("{}", {status: 200}),
    ) as typeof fetch

    await clearLocalSession(fetcher)
    expect(fetcher).toHaveBeenLastCalledWith(
      "/auth/privy/session",
      expect.objectContaining({method: "DELETE"}),
    )
  })

  it("leaves local deletion and reload to the always-loaded sign-out path", async () => {
    const order: string[] = []
    const request = createAccountRequestHandler({
      requestLogin: vi.fn(),
      providerLogout: vi.fn(async () => {
        order.push("provider")
        throw new Error("provider unavailable")
      }),
      synchronizeWallets: vi.fn(async () => undefined),
    })

    await expect(request("sign-out")).rejects.toThrow("provider unavailable")

    expect(order).toEqual(["provider"])
  })

  it("keeps sign-out-only startup preterminal until one provider attempt settles", async () => {
    let finishProviderLogout: (() => void) | undefined
    const ordinaryRequest = vi.fn(
      (request: "sign-in" | "sign-out" | "sync") =>
        request === "sign-out"
          ? new Promise<void>(resolve => {
              finishProviderLogout = resolve
            })
          : Promise.resolve(),
    )
    const ordinaryIdentity = vi.fn(async () => undefined)
    const onTerminal = vi.fn()
    const state = createSignOutOnlyBridgeState({
      ordinaryRequest,
      ordinaryIdentity,
      onTerminal,
    })

    await expect(state.request("sign-in")).rejects.toThrow("still in progress")
    await expect(state.request("sync")).rejects.toThrow("still in progress")
    await expect(state.identity({action: "link", provider: "x"})).rejects.toThrow(
      "still in progress",
    )
    const firstSignOut = state.request("sign-out")
    const joinedSignOut = state.request("sign-out")
    expect(ordinaryRequest).toHaveBeenCalledOnce()
    finishProviderLogout?.()
    await Promise.all([firstSignOut, joinedSignOut])
    expect(onTerminal).toHaveBeenCalledOnce()

    await state.request("sign-out")
    await expect(state.request("sync")).rejects.toThrow("disabled")
    await state.request("sign-in")
    await state.identity({action: "link", provider: "github"})
    expect(ordinaryRequest.mock.calls.map(([request]) => request)).toEqual([
      "sign-out",
      "sign-in",
    ])
    expect(ordinaryIdentity).toHaveBeenCalledOnce()
  })

  it.each(["resolve", "reject"] as const)(
    "holds explicit work after timeout until late provider %s",
    async outcome => {
      let resolveProvider: (() => void) | undefined
      let rejectProvider: ((error: Error) => void) | undefined
      const order: string[] = []
      const ordinaryRequest = vi.fn((request: "sign-in" | "sign-out" | "sync") => {
        order.push(request)
        return request === "sign-out"
          ? new Promise<void>((resolve, reject) => {
              resolveProvider = resolve
              rejectProvider = reject
            })
          : Promise.resolve()
      })
      const ordinaryIdentity = vi.fn(async () => {
        order.push("identity")
      })
      const onTerminal = vi.fn()
      const state = createSignOutOnlyBridgeState({
        ordinaryRequest,
        ordinaryIdentity,
        onTerminal,
      })

      const providerAttempt = state.request("sign-out")
      const providerSettled = providerAttempt.catch(() => undefined)
      state.finish()
      state.finish()
      expect(onTerminal).toHaveBeenCalledOnce()

      const signIn = state.request("sign-in")
      const identity = state.identity({action: "link", provider: "github"})
      await Promise.resolve()
      expect(order).toEqual(["sign-out"])
      expect(ordinaryIdentity).not.toHaveBeenCalled()

      await state.request("sign-out")
      await expect(state.request("sync")).rejects.toThrow("disabled")
      order.push("provider-settled")
      if (outcome === "resolve") resolveProvider?.()
      else rejectProvider?.(new Error("provider logout failed"))

      await providerSettled
      await Promise.all([signIn, identity])
      expect(onTerminal).toHaveBeenCalledOnce()
      expect(order).toEqual(["sign-out", "provider-settled", "sign-in", "identity"])
      expect(ordinaryRequest.mock.calls.map(([request]) => request)).toEqual([
        "sign-out",
        "sign-in",
      ])
      expect(ordinaryIdentity).toHaveBeenCalledOnce()
    },
  )

  it.each(["resolve", "reject"] as const)(
    "keeps the production component queue through a rerender until provider %s",
    async outcome => {
      productionRootRender.mockReset()
      const renderAccountBridge = installAccountBridgeRenderer()
      const firstLogin = vi.fn()
      const firstLinkGithub = vi.fn()
      const order: string[] = []
      productionPrivyHooks.login = firstLogin
      productionPrivyHooks.linkGithub = firstLinkGithub
      stubBrowserGlobals()

      let resolveProvider: (() => void) | undefined
      let rejectProvider: ((error: Error) => void) | undefined
      const providerLogout = vi.fn(
        () =>
          new Promise<void>((resolve, reject) => {
            resolveProvider = resolve
            rejectProvider = reject
          }),
      )
      const getAccessToken = vi.fn(async () => "unexpected-token")
      const startup = bridge.startPrivyBridge(
        {mode: "sign-out-only"},
        {
          appId: "test-app",
          authenticated: true,
          getAccessToken,
          logout: providerLogout,
          ready: true,
          wallets: [],
        },
      )
      const providerElement = productionRootRender.mock.calls[0]?.[0] as React.ReactElement<{
        children: React.ReactElement
      }>
      const accountElement = providerElement.props.children
      renderAccountBridge(accountElement)
      const handle = await startup

      const providerAttempt = handle.request("sign-out")
      const providerSettled = providerAttempt.catch(() => undefined)
      handle.finishSignOutOnly?.()

      const latestLogin = vi.fn(() => order.push("sign-in"))
      const latestLinkGithub = vi.fn(() => order.push("identity"))
      productionPrivyHooks.login = latestLogin
      productionPrivyHooks.linkGithub = latestLinkGithub
      renderAccountBridge(accountElement)

      const signIn = handle.request("sign-in")
      const identity = handle.identity?.({action: "link", provider: "github"})
      await Promise.resolve()
      expect(order).toEqual([])
      expect(firstLogin).not.toHaveBeenCalled()
      expect(firstLinkGithub).not.toHaveBeenCalled()
      expect(latestLogin).not.toHaveBeenCalled()
      expect(latestLinkGithub).not.toHaveBeenCalled()

      await handle.request("sign-out")
      await expect(handle.request("sync")).rejects.toThrow("disabled")
      order.push("provider-settled")
      if (outcome === "resolve") resolveProvider?.()
      else rejectProvider?.(new Error("provider logout failed"))

      await providerSettled
      await Promise.all([signIn, identity])
      expect(order).toEqual(["provider-settled", "sign-in", "identity"])
      expect(providerLogout).toHaveBeenCalledOnce()
      expect(latestLogin).toHaveBeenCalledOnce()
      expect(latestLinkGithub).toHaveBeenCalledOnce()
      expect(getAccessToken).not.toHaveBeenCalled()
    },
  )

  it("clears a stale server session when Privy is unauthenticated", async () => {
    const clearSession = vi.fn(async () => undefined)
    const reload = vi.fn()
    const reconcile = createProviderSessionReconciler({
      clearSession,
      getAccessToken: vi.fn(),
      hasLinkedWallet: () => false,
      providerAuthenticated: () => false,
      reload,
    })

    await expect(reconcile()).resolves.toBe(false)
    expect(clearSession).toHaveBeenCalledOnce()
    expect(reload).toHaveBeenCalledOnce()
  })

  it("ORDINARY_SIGNED_IN_STARTUP_IS_STABLE: a still-signed-in account writes no session", async () => {
    const clearSession = vi.fn(async () => undefined)
    const reload = vi.fn()
    const fetcher = vi.fn()
    vi.stubGlobal("fetch", fetcher)
    const reconcile = createProviderSessionReconciler({
      clearSession,
      getAccessToken: vi.fn(async () => "current-token"),
      hasLinkedWallet: () => true,
      providerAuthenticated: () => true,
      reload,
    })

    await expect(reconcile()).resolves.toBe(true)

    // Startup reconciliation only reads the provider, so nothing reaches the
    // server: no generation advances, no cookie renews and nothing reloads.
    expect(fetcher).not.toHaveBeenCalled()
    expect(clearSession).not.toHaveBeenCalled()
    expect(reload).not.toHaveBeenCalled()
  })

  it("drops the local session when the provider has no current linked wallet", async () => {
    const clearSession = vi.fn(async () => undefined)
    const reload = vi.fn()
    const reconcile = createProviderSessionReconciler({
      clearSession,
      getAccessToken: vi.fn(async () => "current-token"),
      hasLinkedWallet: () => false,
      providerAuthenticated: () => true,
      reload,
    })

    await expect(reconcile()).resolves.toBe(false)
    expect(clearSession).toHaveBeenCalledOnce()
    expect(reload).toHaveBeenCalledOnce()
  })

  it("drops the local session when the provider has no usable access token", async () => {
    const clearSession = vi.fn(async () => undefined)
    const reload = vi.fn()
    const reconcile = createProviderSessionReconciler({
      clearSession,
      getAccessToken: vi.fn(async () => null),
      hasLinkedWallet: () => true,
      providerAuthenticated: () => true,
      reload,
    })

    await expect(reconcile()).resolves.toBe(false)
    expect(clearSession).toHaveBeenCalledOnce()
    expect(reload).toHaveBeenCalledOnce()
  })

  it("does not own or inject server-rendered account markup", () => {
    expect(bridge).not.toHaveProperty("loadLocalSession")
  })

  // Privy can move the selection without changing the connected set. Stake reads
  // the selection, so that change has to reach the page as a wallet-state event.
  it("P1_ACTIVE_WALLET_ONLY: publishes the selection and announces a selection-only change", async () => {
    productionRootRender.mockReset()
    replaceActiveEthereumWallet(null)
    const renderAccountBridge = installAccountBridgeRenderer()
    const dispatched = stubBrowserGlobals()
    const first = ethereumWallet("0x1111111111111111111111111111111111111111")
    const second = ethereumWallet("0x2222222222222222222222222222222222222222")
    const solana = {address: "SoLaNa1111111111111111111111111111111111111", type: "solana"}
    const providerState = {
      appId: "test-app",
      authenticated: true,
      getAccessToken: async () => "current-token",
      logout: async () => undefined,
      ready: true,
      wallets: [first, second],
      activeWallet: first,
    }

    const startup = bridge.startPrivyBridge(
      {},
      providerState as unknown as bridge.PrivyBridgeProviderState,
    )
    const providerElement = productionRootRender.mock.calls[0]?.[0] as React.ReactElement<{
      children: React.ReactElement
    }>
    const accountElement = providerElement.props.children
    renderAccountBridge(accountElement)
    await startup
    await until(() => activeEthereumWallet()?.provider === first.provider)
    expect(dispatched).toEqual(["ash:wallet-state"])

    // The connected set is identical; only the selection moved.
    providerState.activeWallet = second
    renderAccountBridge(accountElement)
    await until(() => activeEthereumWallet()?.provider === second.provider)

    // A Solana selection is no Stake wallet, and no other wallet stands in.
    providerState.activeWallet = solana as unknown as typeof first
    renderAccountBridge(accountElement)
    await until(() => dispatched.length === 5)
    expect(activeEthereumWallet()).toBeNull()
    expect(new Set(dispatched)).toEqual(new Set(["ash:wallet-state"]))
  })

  // The customer's new choice is known before any of the reconciliation it
  // starts can finish. The wallet they left has to stop being Stake's wallet at
  // once, or the page could prepare and send for it during that gap.
  it("P1_ACTIVE_WALLET_ONLY: the wallet left behind is unavailable before the new one resolves", async () => {
    productionRootRender.mockReset()
    replaceActiveEthereumWallet(null)
    const renderAccountBridge = installAccountBridgeRenderer()
    stubBrowserGlobals()
    const first = ethereumWallet("0x1111111111111111111111111111111111111111")
    const chosenProvider: EthereumProvider = {request: vi.fn()}
    let release: (() => void) | undefined
    let resolutions = 0
    const chosen = {
      address: "0x2222222222222222222222222222222222222222",
      type: "ethereum",
      getEthereumProvider: () =>
        ++resolutions === 1
          ? Promise.resolve(chosenProvider)
          : new Promise<EthereumProvider>(resolve => {
              release = () => resolve(chosenProvider)
            }),
    }
    const providerState = {
      appId: "test-app",
      authenticated: true,
      getAccessToken: async () => "current-token",
      logout: async () => undefined,
      ready: true,
      wallets: [first, chosen],
      activeWallet: first,
    }

    const startup = bridge.startPrivyBridge(
      {},
      providerState as unknown as bridge.PrivyBridgeProviderState,
    )
    const providerElement = productionRootRender.mock.calls[0]?.[0] as React.ReactElement<{
      children: React.ReactElement
    }>
    const accountElement = providerElement.props.children
    renderAccountBridge(accountElement)
    await startup
    await until(() => activeEthereumWallet()?.provider === first.provider)

    providerState.activeWallet = chosen as unknown as typeof first
    renderAccountBridge(accountElement)

    // The choice has only been made; nothing has resolved yet.
    expect(activeEthereumWallet()).toBeNull()
    await until(() => release !== undefined)
    expect(activeEthereumWallet()).toBeNull()

    release?.()
    await until(() => activeEthereumWallet()?.provider === chosenProvider)
    expect(activeEthereumWallet()?.address).toBe(chosen.address)
  })

  // A selection whose provider cannot be resolved is no Stake wallet. Keeping
  // the previous one would let a page act for a wallet the customer has left.
  it("P1_ACTIVE_WALLET_ONLY: a selection whose provider fails leaves no active wallet", async () => {
    productionRootRender.mockReset()
    replaceActiveEthereumWallet(null)
    const renderAccountBridge = installAccountBridgeRenderer()
    const dispatched = stubBrowserGlobals()
    const first = ethereumWallet("0x1111111111111111111111111111111111111111")
    const unavailable = {
      address: "0x2222222222222222222222222222222222222222",
      type: "ethereum",
      getEthereumProvider: async () => {
        throw new Error("provider unavailable")
      },
    }
    const providerState = {
      appId: "test-app",
      authenticated: true,
      getAccessToken: async () => "current-token",
      logout: async () => undefined,
      ready: true,
      wallets: [first, unavailable],
      activeWallet: first,
    }

    const startup = bridge.startPrivyBridge(
      {},
      providerState as unknown as bridge.PrivyBridgeProviderState,
    )
    const providerElement = productionRootRender.mock.calls[0]?.[0] as React.ReactElement<{
      children: React.ReactElement
    }>
    const accountElement = providerElement.props.children
    renderAccountBridge(accountElement)
    await startup
    await until(() => activeEthereumWallet()?.provider === first.provider)

    // The connected set is identical; only the selection moved, and this
    // wallet's provider does not resolve.
    providerState.activeWallet = unavailable as unknown as typeof first
    renderAccountBridge(accountElement)
    const announced = dispatched.length
    await until(() => dispatched.length > announced)
    expect(activeEthereumWallet()).toBeNull()
  })

  it("selects the signer-bound wallet regardless of provider order", () => {
    const first = {request: vi.fn()}
    const expected = {request: vi.fn()}
    const wallets: Array<[string, EthereumProvider]> = [
      ["0x2222222222222222222222222222222222222222", first],
      ["0x1111111111111111111111111111111111111111", expected],
    ]

    expect(
      selectConnectedEthereumWallet(
        wallets,
        "0x1111111111111111111111111111111111111111",
      )?.provider,
    ).toBe(expected)
  })
})
