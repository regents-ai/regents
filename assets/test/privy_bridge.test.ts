import {afterEach, describe, expect, it, vi} from "vitest"

import * as bridge from "../js/privy_bridge"
import {
  connectedEthereumWallet,
  replaceConnectedEthereumWallets,
  selectConnectedEthereumWallet,
  type EthereumProvider,
} from "../js/wallet_actions/connected_wallet"

const {
  clearLocalSession,
  createLocalSession,
  createPrivyLoginCallbacks,
  createReadyLoginGate,
  createPrivySessionCompletion,
  createPrivyTokenCallbacks,
} = bridge

describe("Privy session bridge", () => {
  afterEach(() => {
    replaceConnectedEthereumWallets([])
    vi.unstubAllGlobals()
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
        : new Response("{}", {status: 200})
    }) as typeof fetch

    await createLocalSession("verified", fetcher)

    expect(calls[1]).toEqual([
      "/auth/privy/session",
      {
        method: "POST",
        credentials: "same-origin",
        headers: {authorization: "Bearer verified", "x-csrf-token": "csrf"},
      },
    ])
  })

  it("completes the local session from Privy's access-token grant", async () => {
    const reload = vi.fn()
    const fetcher = vi.fn(async (input: RequestInfo | URL) =>
      input === "/auth/csrf"
        ? new Response(JSON.stringify({csrf_token: "csrf"}), {status: 200})
        : new Response("{}", {status: 200}),
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
          : new Response("{}", {status: 200}),
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

  it("rejects a connected wallet when its signer does not match", () => {
    const provider = {request: vi.fn()}

    expect(
      selectConnectedEthereumWallet(
        [["0x2222222222222222222222222222222222222222", provider]],
        "0x1111111111111111111111111111111111111111",
      ),
    ).toBeNull()
  })

  it("admits the injected test wallet only on the exact controlled test origin", () => {
    const provider = {request: vi.fn()}
    const testWallet = {address: "0x1111111111111111111111111111111111111111", provider}

    vi.stubGlobal("window", {
      location: {origin: "http://127.0.0.1:4002"},
      __ashPlatformTestWallet: testWallet,
    })
    expect(connectedEthereumWallet(testWallet.address)).toEqual(testWallet)

    for (const origin of ["http://localhost:4002", "http://127.0.0.1:4000", "https://127.0.0.1:4002"]) {
      vi.stubGlobal("window", {location: {origin}, __ashPlatformTestWallet: testWallet})
      expect(connectedEthereumWallet(testWallet.address)).toBeNull()
    }
  })
})
