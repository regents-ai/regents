import {describe, expect, it, vi} from "vitest"

import * as bridge from "../js/privy_bridge"
import {clearLocalSession, createSessionMutationCoordinator} from "../js/auth_lazy"
import {
  selectConnectedEthereumWallet,
  type EthereumProvider,
} from "../js/wallet_actions/connected_wallet"

const {
  createLocalSession,
  createAccountRequestHandler,
  createProviderSessionReconciler,
  createPrivyLoginCallbacks,
  createReadyLoginGate,
  createPrivySessionCompletion,
  createPrivyTokenCallbacks,
  LocalSessionEstablishmentError,
} = bridge

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
