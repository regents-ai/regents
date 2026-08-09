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
}))

vi.mock("react-dom/client", () => ({
  createRoot: () => ({render: productionRootRender}),
}))

vi.mock("@privy-io/react-auth", () => ({
  PrivyProvider: "privy-provider",
  usePrivy: () => ({authenticated: false, logout: vi.fn(), ready: true}),
  useWallets: () => ({wallets: []}),
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
  LocalSessionEstablishmentError,
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
        signal: expect.any(AbortSignal),
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

  it.each(["csrf", "session POST"])(
    "aborts a never-settling %s before one local deletion",
    async phase => {
      vi.useFakeTimers()

      try {
        const sessionMutations = createSessionMutationCoordinator({
          cancellationWaitMs: 10,
        })
        let finishLate: (() => void) | undefined
        let hangingRequestStarted = false
        const fetchMock = vi.fn((input: RequestInfo | URL) => {
          const hangs =
            (phase === "csrf" && input === "/auth/csrf") ||
            (phase === "session POST" && input === "/auth/privy/session")

          if (hangs) {
            hangingRequestStarted = true
            return new Promise<Response>(resolve => {
              finishLate = () =>
                resolve(
                  input === "/auth/csrf"
                    ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
                    : new Response("{}", {
                        status: 200,
                        headers: {"x-ash-session-changed": "false"},
                      }),
                )
            })
          }

          return Promise.resolve(
            input === "/auth/csrf"
              ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
              : new Response("{}", {
                  status: 200,
                  headers: {"x-ash-session-changed": "false"},
                }),
          )
        })
        const fetcher = fetchMock as typeof fetch
        let localAuthenticated = true
        const establishment = createLocalSession("verified", fetcher, sessionMutations).then(
          result => {
            localAuthenticated = true
            return result
          },
        )
        await vi.advanceTimersByTimeAsync(0)
        expect(hangingRequestStarted).toBe(true)
        const establishmentFailure = expect(establishment).rejects.toMatchObject({
          name: "AbortError",
        })

        const clearSession = vi.fn(async () => {
          localAuthenticated = false
        })
        const signOut = sessionMutations.signOut(clearSession)
        expect(clearSession).not.toHaveBeenCalled()
        await vi.advanceTimersByTimeAsync(10)
        await signOut
        expect(clearSession).toHaveBeenCalledOnce()
        expect(localAuthenticated).toBe(false)

        finishLate?.()
        await establishmentFailure
        expect(localAuthenticated).toBe(false)
        await sessionMutations.signOut(clearSession)
        const fetchCallCount = fetchMock.mock.calls.length
        await expect(
          createLocalSession("verified", fetcher, sessionMutations),
        ).rejects.toThrow("Local sign out has already started.")
        expect(fetchMock).toHaveBeenCalledTimes(fetchCallCount)
        expect(clearSession).toHaveBeenCalledOnce()
        if (phase === "csrf") {
          expect(fetchMock).not.toHaveBeenCalledWith(
            "/auth/privy/session",
            expect.anything(),
          )
        }
      } finally {
        vi.useRealTimers()
      }
    },
  )

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
      vi.stubGlobal("document", {
        body: {append: vi.fn()},
        createElement: () => ({hidden: false}),
        querySelector: () => null,
      })

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
    const establishSession = vi.fn()
    const reload = vi.fn()
    const reconcile = createProviderSessionReconciler({
      clearSession,
      establishSession,
      getAccessToken: vi.fn(),
      hasLinkedWallet: () => false,
      providerAuthenticated: () => false,
      reload,
    })

    await expect(reconcile()).resolves.toBe(false)
    expect(clearSession).toHaveBeenCalledOnce()
    expect(establishSession).not.toHaveBeenCalled()
    expect(reload).toHaveBeenCalledOnce()
  })

  it("reloads when current provider evidence replaces a different server account", async () => {
    const clearSession = vi.fn(async () => undefined)
    const establishSession = vi.fn(async () => ({sessionChanged: true}))
    const reload = vi.fn()
    const reconcile = createProviderSessionReconciler({
      clearSession,
      establishSession,
      getAccessToken: vi.fn(async () => "current-token"),
      hasLinkedWallet: () => true,
      providerAuthenticated: () => true,
      reload,
    })

    await expect(reconcile()).resolves.toBe(true)
    expect(establishSession).toHaveBeenCalledWith("current-token")
    expect(clearSession).not.toHaveBeenCalled()
    expect(reload).toHaveBeenCalledOnce()
  })

  it("drops the local session when the provider has no current linked wallet", async () => {
    const clearSession = vi.fn(async () => undefined)
    const reload = vi.fn()
    const reconcile = createProviderSessionReconciler({
      clearSession,
      establishSession: vi.fn(async () => ({sessionChanged: false})),
      getAccessToken: vi.fn(async () => "current-token"),
      hasLinkedWallet: () => false,
      providerAuthenticated: () => true,
      reload,
    })

    await expect(reconcile()).resolves.toBe(false)
    expect(clearSession).toHaveBeenCalledOnce()
    expect(reload).toHaveBeenCalledOnce()
  })

  it("does not duplicate deletion after the server rejects stale wallet evidence", async () => {
    const clearSession = vi.fn(async () => undefined)
    const reload = vi.fn()
    const rejected = new LocalSessionEstablishmentError(true)
    const reconcile = createProviderSessionReconciler({
      clearSession,
      establishSession: vi.fn().mockRejectedValue(rejected),
      getAccessToken: vi.fn(async () => "stale-token"),
      hasLinkedWallet: () => false,
      providerAuthenticated: () => true,
      reload,
    })

    await expect(reconcile()).rejects.toBe(rejected)
    expect(clearSession).not.toHaveBeenCalled()
    expect(reload).toHaveBeenCalledOnce()
  })

  it("does not own or inject server-rendered account markup", () => {
    expect(bridge).not.toHaveProperty("loadLocalSession")
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
