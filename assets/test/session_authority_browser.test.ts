import {afterEach, describe, expect, it, vi} from "vitest"

import {
  SessionLifecycleError,
  acrossCookieRotation,
  announceCsrfRotation,
  browserCsrfToken,
  browserSessionMutations,
  clearLocalSession,
  createSessionMutationCoordinator,
  csrfRotated,
  csrfToken,
  holdSocketDuringCookieRotation,
  installCrossTabCsrf,
  recoverOnce,
  type PinnedSocket,
} from "../js/auth_lazy"
import {createLocalSession} from "../js/privy_bridge"

afterEach(() => vi.unstubAllGlobals())

type Meta = {content: string}

function pageWithCsrfMeta(initial: string): Meta {
  const meta: Meta = {content: initial}
  vi.stubGlobal("document", {
    querySelector: (selector: string) =>
      selector === "meta[name='csrf-token']" ? meta : null,
  })
  return meta
}

function csrfResponse(token: string) {
  return new Response(JSON.stringify({csrf_token: token}), {status: 200})
}

function lifecycleResponse(error: string) {
  return new Response(JSON.stringify({error}), {status: 409})
}

function signedInResponse(sessionChanged: "true" | "false") {
  return new Response("{}", {
    status: 200,
    headers: {"x-ash-session-changed": sessionChanged},
  })
}

// A sign in that rotates: the read before the bind, the bind itself, then the
// adoption of the token the renewed cookie carries.
const signingIn = (adopted: string) =>
  vi.fn(async (input: RequestInfo | URL) =>
    input === "/auth/csrf" ? csrfResponse(adopted) : signedInResponse("true"),
  ) as unknown as typeof fetch

describe("DYNAMIC_BROWSER_CSRF", () => {
  it("reads the token the page holds on every call", async () => {
    const meta = pageWithCsrfMeta("first")
    expect(browserCsrfToken()).toBe("first")

    const fetcher = vi.fn(async () => csrfResponse("second")) as unknown as typeof fetch
    await csrfToken(fetcher)

    expect(meta.content).toBe("second")
    expect(browserCsrfToken()).toBe("second")
  })

  it("adopts the rotated token before a renewing sign in resolves", async () => {
    const meta = pageWithCsrfMeta("page-token")
    const tokens = ["before-post", "after-renewal"]
    const observed: string[] = []
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (input === "/auth/csrf") return csrfResponse(tokens.shift() ?? "exhausted")
      observed.push(String(new Headers(init?.headers).get("x-csrf-token")))
      // The socket may reconnect the instant the response lands, so the token it
      // would read must already be the renewed one when the promise resolves.
      expect(meta.content).toBe("before-post")
      return signedInResponse("true")
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", fetcher)).resolves.toEqual({
      sessionChanged: true,
    })

    expect(observed).toEqual(["before-post"])
    expect(browserCsrfToken()).toBe("after-renewal")
  })

  it("adopts the current token and retries exactly once when sign out is refused", async () => {
    const meta = pageWithCsrfMeta("stale-token")
    const sent: string[] = []
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (input === "/auth/csrf") return csrfResponse("current-token")
      sent.push(String(new Headers(init?.headers).get("x-csrf-token")))
      return sent.length === 1
        ? new Response("", {status: 403})
        : new Response("{}", {status: 200})
    }) as unknown as typeof fetch

    await clearLocalSession(fetcher)

    // The page token leads, so a stale lineage still reaches logout; only the
    // CSRF refusal earns the adoption and the single idempotent retry.
    expect(sent).toEqual(["stale-token", "current-token"])
    expect(meta.content).toBe("current-token")
  })

  it("gives up rather than looping when the retried sign out is refused again", async () => {
    pageWithCsrfMeta("stale-token")
    let deletes = 0
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input === "/auth/csrf") return csrfResponse("current-token")
      deletes += 1
      return new Response("", {status: 403})
    }) as unknown as typeof fetch

    await expect(clearLocalSession(fetcher)).rejects.toThrow("Sign out could not be completed.")
    expect(deletes).toBe(2)
  })

  it("treats any failure that is not a CSRF refusal as final", async () => {
    pageWithCsrfMeta("page-token")
    const requests: Array<RequestInfo | URL> = []
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      requests.push(input)
      return new Response("", {status: 500})
    }) as unknown as typeof fetch

    await expect(clearLocalSession(fetcher)).rejects.toThrow("Sign out could not be completed.")
    expect(requests).toEqual(["/auth/privy/session"])
  })

  it("signs out with the token the page already holds", async () => {
    pageWithCsrfMeta("held-token")
    const calls: Array<[RequestInfo | URL, RequestInit | undefined]> = []
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push([input, init])
      return new Response("{}", {status: 200})
    }) as unknown as typeof fetch

    await clearLocalSession(fetcher)

    expect(calls).toEqual([
      [
        "/auth/privy/session",
        {
          method: "DELETE",
          credentials: "same-origin",
          headers: {"x-csrf-token": "held-token"},
        },
      ],
    ])
  })
})

// The exact establishment surface of the pinned phoenix 1.8.9 socket: the first
// attempt arrives from `LiveSocket.connect`, every automatic retry from the
// socket's own reconnect timer, both through `Socket.connect`, which returns
// without work while a transport is live and otherwise reaches
// `Socket.transportConnect`, where the endpoint URL and its CSRF param are read.
function pinnedSocket() {
  const attempts: string[] = []
  let live = false
  const socket = {
    attempts,
    connect: () => {
      if (live) return
      socket.transportConnect()
    },
    // `connect` arms `connectWithFallback`, whose long-poll timer and transport
    // error path replace the transport and reach `transportConnect` a second
    // time directly, without returning through `connect`.
    connectWithFallback: () => {
      socket.connect()
      if (!live) socket.transportConnect()
    },
    transportConnect: () => {
      live = true
      attempts.push(browserCsrfToken())
    },
    isConnected: () => live,
  }

  return socket
}

describe("COOKIE_TO_CSRF_HAS_A_REAL_LIVESOCKET_BARRIER", () => {
  it("admits no connection between the renewed cookie and the token it carries", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const tokens = ["before-post", "after-renewal"]
    const insideInterval: number[] = []
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input === "/auth/csrf") return csrfResponse(tokens.shift() ?? "exhausted")
      // The reconnect timer fires on its own, with no knowledge of the auth
      // promise, at the instant the renewed cookie lands.
      socket.connect()
      insideInterval.push(socket.attempts.length)
      return signedInResponse("true")
    }) as unknown as typeof fetch

    await createLocalSession("verified", fetcher)

    expect(insideInterval).toEqual([0])
    expect(socket.attempts).toEqual(["after-renewal"])
    expect(socket.isConnected()).toBe(true)
  })

  it("leaves an already-mounted socket connected across the rotation", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    socket.connect()
    const tokens = ["before-post", "after-renewal"]
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input === "/auth/csrf") return csrfResponse(tokens.shift() ?? "exhausted")
      socket.connect()
      return signedInResponse("false")
    }) as unknown as typeof fetch

    await createLocalSession("verified", fetcher)

    // Policy C: the mounted same-account socket is never torn down, so the
    // rotation costs it no re-establishment.
    expect(socket.isConnected()).toBe(true)
    expect(socket.attempts).toEqual(["page-token"])
  })

  it("stays closed when the adoption after a renewal fails, until one succeeds", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    let reads = 0
    const unreadable = vi.fn(async (input: RequestInfo | URL) => {
      if (input !== "/auth/csrf") return signedInResponse("true")
      reads += 1
      // The sign-in response has already renewed the cookie; what fails is the
      // read of the CSRF state that cookie now carries.
      return reads === 1 ? csrfResponse("before-post") : new Response("", {status: 503})
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", unreadable)).rejects.toThrow(
      "Unable to start a secure session change.",
    )

    // Admitting anything now would pair the renewed cookie with the retired
    // token, so the reconnect arriving after the failure is refused as well.
    socket.connect()
    expect(socket.attempts).toEqual([])
    expect(socket.isConnected()).toBe(false)

    const readable = vi.fn(async (input: RequestInfo | URL) =>
      input === "/auth/csrf" ? csrfResponse("after-renewal") : signedInResponse("true"),
    ) as unknown as typeof fetch

    await createLocalSession("verified", readable)

    expect(socket.attempts).toEqual(["after-renewal"])
    expect(socket.isConnected()).toBe(true)
  })

  it("stays closed when an adopting tab cannot read the cookie it now shares", async () => {
    const meta = pageWithCsrfMeta("stale-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const unreadable = vi.fn(async () => new Response("", {status: 503})) as unknown as typeof fetch

    // Exactly the rotation an adoption notice runs: the other tab renewed the
    // cookie both share and this one could not read what it carries.
    await expect(
      acrossCookieRotation(renewed => {
        renewed()
        return csrfToken(unreadable)
      }),
    ).rejects.toThrow("Unable to start a secure session change.")

    socket.connect()
    expect(socket.attempts).toEqual([])
    expect(meta.content).toBe("stale-token")

    const readable = vi.fn(async () => csrfResponse("renewed-token")) as unknown as typeof fetch
    await acrossCookieRotation(renewed => {
      renewed()
      return csrfToken(readable)
    })

    expect(socket.attempts).toEqual(["renewed-token"])
  })

  it("holds an adopting tab's reconnect and converges without a loop", async () => {
    pageWithCsrfMeta("stale-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const insideInterval: number[] = []
    const fetcher = vi.fn(async () => {
      // A deploy-style reconnect in the tab that only adopted the notice.
      socket.connect()
      insideInterval.push(socket.attempts.length)
      return csrfResponse("renewed-token")
    }) as unknown as typeof fetch
    const peer = new BroadcastChannel(csrfRotated)
    const stopAdopting = installCrossTabCsrf(fetcher)

    try {
      peer.postMessage(csrfRotated)
      await until(() => socket.attempts.length > 0)

      expect(insideInterval).toEqual([0])
      expect(socket.attempts).toEqual(["renewed-token"])
      expect(fetcher).toHaveBeenCalledOnce()
    } finally {
      stopAdopting()
      peer.close()
    }
  })
})

// The pinned phoenix 1.8.9 client itself, loaded from `deps` exactly as the
// asset build resolves it. Its `connect` arms `connectWithFallback`, whose
// long-poll timer and transport-error path each replace the transport and call
// `transportConnect` directly, never returning through `connect`.
const {Socket: PinnedPhoenixSocket} = (await import(
  new URL("../../deps/phoenix/priv/static/phoenix.mjs", import.meta.url).href
)) as {
  Socket: new (
    endPoint: string,
    options: Record<string, unknown>,
  ) => PinnedSocket & {conn: {onerror: (reason: unknown) => void; pollEndpoint?: string} | null}
}

// Records every transport the socket builds, so an establishment refused inside
// the interval is the absence of a constructed transport rather than a claim
// about one.
function pinnedPhoenixSocketBuilding(built: string[]) {
  vi.stubGlobal("location", {protocol: "https:", host: "socket.test"})

  return new PinnedPhoenixSocket("/live", {
    transport: class {
      binaryType = ""
      timeout = 0
      onopen: () => void = () => {}
      onerror: (reason: unknown) => void = () => {}
      onmessage: (event: unknown) => void = () => {}
      onclose: (event: unknown) => void = () => {}

      constructor(url: string) {
        built.push(url)
      }

      close() {}
    },
    // The exact options app.ts gives LiveSocket.
    longPollFallbackMs: 2500,
    params: () => ({_csrf_token: browserCsrfToken()}),
  })
}

const longPollEndpoint = (token: string) =>
  `https://socket.test/live/longpoll?_csrf_token=${token}&vsn=2.0.0`

describe("PINNED_LONG_POLL_FALLBACK_OBEYS_THE_BARRIER", () => {
  afterEach(() => vi.useRealTimers())

  it("builds no transport when the fallback timer fires inside the interval", async () => {
    vi.useFakeTimers()
    pageWithCsrfMeta("page-token")
    const built: string[] = []
    const socket = pinnedPhoenixSocketBuilding(built)
    holdSocketDuringCookieRotation(socket)
    // The page's opening attempt, whose websocket handshake is still pending
    // when the rotation begins. It armed the fallback timer, which owes nothing
    // to `connect` when it expires.
    socket.connect()

    expect(built).toEqual(["wss://socket.test/live/websocket?_csrf_token=page-token&vsn=2.0.0"])

    const tokens = ["before-post", "after-renewal"]
    const insideInterval: {built: number; connected: boolean}[] = []
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input === "/auth/csrf") return csrfResponse(tokens.shift() ?? "exhausted")
      vi.advanceTimersByTime(2500)
      insideInterval.push({built: built.length, connected: Boolean(socket.conn)})
      return signedInResponse("true")
    }) as unknown as typeof fetch

    await createLocalSession("verified", fetcher)

    expect(insideInterval).toEqual([{built: 1, connected: false}])
    // The fallback had already swapped the transport before it was refused, so
    // the single attempt admitted after adoption is the long poll, carrying the
    // token this tab has just read.
    expect(socket.conn?.pollEndpoint).toBe(longPollEndpoint("after-renewal"))
  })

  it("builds no transport when the fallback error path fires inside the interval", async () => {
    vi.useFakeTimers()
    pageWithCsrfMeta("page-token")
    const built: string[] = []
    const socket = pinnedPhoenixSocketBuilding(built)
    holdSocketDuringCookieRotation(socket)
    socket.connect()

    expect(built).toEqual(["wss://socket.test/live/websocket?_csrf_token=page-token&vsn=2.0.0"])

    const tokens = ["before-post", "after-renewal"]
    const insideInterval: {built: number; connected: boolean}[] = []
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input === "/auth/csrf") return csrfResponse(tokens.shift() ?? "exhausted")
      // The primary transport fails as the renewed cookie lands: the fallback
      // takes its error path rather than its timer.
      socket.conn?.onerror("primary refused")
      insideInterval.push({built: built.length, connected: Boolean(socket.conn)})
      return signedInResponse("true")
    }) as unknown as typeof fetch

    await createLocalSession("verified", fetcher)

    expect(insideInterval).toEqual([{built: 1, connected: false}])
    expect(socket.conn?.pollEndpoint).toBe(longPollEndpoint("after-renewal"))
  })
})

// The exact state a renewal leaves behind when its own adoption fails: the
// cookie in this browser is the renewed one and this tab has never read the
// CSRF state that cookie carries.
async function withUnreadRenewal(): Promise<void> {
  const unreadable = vi.fn(async () => new Response("", {status: 503})) as unknown as typeof fetch

  await expect(
    acrossCookieRotation(renewed => {
      renewed()
      return csrfToken(unreadable)
    }),
  ).rejects.toThrow("Unable to start a secure session change.")
}

describe("A_LATER_CONNECT_READS_WHAT_A_FAILED_ADOPTION_NEVER_DID", () => {
  it("adopts on the next connection opportunity and admits one transport", async () => {
    const meta = pageWithCsrfMeta("stale-token")
    const socket = pinnedSocket()
    const requests: Array<RequestInfo | URL> = []
    const readable = vi.fn(async (input: RequestInfo | URL) => {
      requests.push(input)
      return csrfResponse("renewed-token")
    }) as unknown as typeof fetch
    holdSocketDuringCookieRotation(socket, readable)
    await withUnreadRenewal()

    socket.connect()

    // The read is what the opportunity starts; nothing may go out under the
    // token the retired session issued while it is in flight.
    expect(socket.attempts).toEqual([])
    expect(meta.content).toBe("stale-token")

    await until(() => socket.isConnected())

    expect(requests).toEqual(["/auth/csrf"])
    expect(meta.content).toBe("renewed-token")
    expect(socket.attempts).toEqual(["renewed-token"])
  })

  it("shares one read between the websocket and the long poll behind it", async () => {
    pageWithCsrfMeta("stale-token")
    const socket = pinnedSocket()
    let reads = 0
    const fetcher = vi.fn(async () => {
      reads += 1
      // A failed read leaves the renewal unread, so a second read from the same
      // opportunity would be a queued follow-on rather than a shared one.
      return reads === 1 ? new Response("", {status: 503}) : csrfResponse("renewed-token")
    }) as unknown as typeof fetch
    holdSocketDuringCookieRotation(socket, fetcher)
    await withUnreadRenewal()

    socket.connectWithFallback()
    await until(() => reads === 1)
    await settle()

    // Both refused attempts joined the read the first of them started.
    expect(reads).toBe(1)
    expect(socket.attempts).toEqual([])

    socket.connect()
    await until(() => socket.isConnected())

    expect(reads).toBe(2)
    expect(socket.attempts).toEqual(["renewed-token"])
  })

  it("stays closed on a failed retry and reads again on a later opportunity", async () => {
    const meta = pageWithCsrfMeta("stale-token")
    const socket = pinnedSocket()
    let reads = 0
    const unavailable = vi.fn(async () => {
      reads += 1
      return reads === 1 ? new Response("", {status: 503}) : csrfResponse("renewed-token")
    }) as unknown as typeof fetch
    holdSocketDuringCookieRotation(socket, unavailable)
    await withUnreadRenewal()

    socket.connect()
    await until(() => reads === 1)
    await settle()

    expect(socket.attempts).toEqual([])
    expect(socket.isConnected()).toBe(false)
    expect(meta.content).toBe("stale-token")

    socket.connect()
    await until(() => socket.isConnected())

    expect(reads).toBe(2)
    expect(meta.content).toBe("renewed-token")
    expect(socket.attempts).toEqual(["renewed-token"])
  })

  it("releases nothing when a retry reads a body carrying no token", async () => {
    const meta = pageWithCsrfMeta("stale-token")
    const socket = pinnedSocket()
    let reads = 0
    const unadoptable = vi.fn(async () => {
      reads += 1
      // A 200 that rotated the cookie and a 200 that wrote nothing are the same
      // response without a token in it, so neither one may release.
      return reads === 1
        ? new Response('{"ok":true}', {status: 200})
        : csrfResponse("renewed-token")
    }) as unknown as typeof fetch
    holdSocketDuringCookieRotation(socket, unadoptable)
    await withUnreadRenewal()

    socket.connect()
    await until(() => reads === 1)
    await settle()

    expect(socket.attempts).toEqual([])
    expect(meta.content).toBe("stale-token")

    socket.connect()
    await until(() => socket.isConnected())

    expect(socket.attempts).toEqual(["renewed-token"])
  })

  it("starts no retry for a connect that arrives while a rotation is open", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    const reads: string[] = []
    const tokens = ["before-post", "after-renewal"]
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input !== "/auth/csrf") {
        socket.connect()
        return signedInResponse("true")
      }
      reads.push(browserCsrfToken())
      return csrfResponse(tokens.shift() ?? "exhausted")
    }) as unknown as typeof fetch
    holdSocketDuringCookieRotation(socket, fetcher)

    await createLocalSession("verified", fetcher)

    // The rotation still owns the adoption, so the refused reconnect inside it
    // waits for that read rather than starting one of its own.
    expect(reads).toEqual(["page-token", "before-post"])
    expect(socket.attempts).toEqual(["after-renewal"])
  })

  it("leaves a mounted transport alone and starts no read for it", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    const readable = vi.fn(async () => csrfResponse("renewed-token")) as unknown as typeof fetch
    holdSocketDuringCookieRotation(socket, readable)
    socket.connect()
    await withUnreadRenewal()

    socket.connect()

    expect(readable).not.toHaveBeenCalled()
    expect(socket.isConnected()).toBe(true)
    expect(socket.attempts).toEqual(["page-token"])

    await acrossCookieRotation(renewed => {
      renewed()
      return csrfToken(readable)
    })

    expect(browserCsrfToken()).toBe("renewed-token")
  })

  it("reads nothing when a sign in ordered ahead of the retry already recovered the tab", async () => {
    const meta = pageWithCsrfMeta("stale-token")
    const socket = pinnedSocket()
    const reads: string[] = []
    const tokens = ["before-post", "after-renewal"]
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input !== "/auth/csrf") return signedInResponse("true")
      reads.push(browserCsrfToken())
      return csrfResponse(tokens.shift() ?? "exhausted")
    }) as unknown as typeof fetch
    holdSocketDuringCookieRotation(socket, fetcher)
    await withUnreadRenewal()

    // The sign in takes the queue first and its body has not run yet, so the
    // connect in the same turn still sees an unread renewal and queues its
    // retry behind a mutation that is about to recover the tab itself.
    const signIn = createLocalSession("verified", fetcher)
    socket.connect()
    expect(reads).toEqual([])
    expect(socket.attempts).toEqual([])

    await signIn
    // Queued behind the retry, so awaiting it proves the retry body has run.
    await browserSessionMutations.establish(async () => undefined)

    expect(reads).toEqual(["stale-token", "before-post"])
    expect(meta.content).toBe("after-renewal")
    expect(socket.attempts).toEqual(["after-renewal"])
    expect(socket.isConnected()).toBe(true)
  })
})

describe("A_ROTATION_LATCHES_ONLY_ONCE_A_RENEWAL_LANDS", () => {
  it("leaves reconnects available when nothing landed before the failure", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const offline = vi.fn(async () => {
      throw new Error("offline")
    }) as unknown as typeof fetch

    // The opening CSRF read never returns a response, so no cookie changed and
    // the token this tab holds still matches the one it would connect under.
    await expect(createLocalSession("verified", offline)).rejects.toThrow("offline")

    socket.connect()
    expect(socket.attempts).toEqual(["page-token"])
    expect(socket.isConnected()).toBe(true)
  })

  it("leaves reconnects available when an exact CSRF read is followed by a sign in that never lands", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      // Exact and current: the server writes no session and emits no cookie,
      // and this tab has adopted the token that observation returned.
      if (input === "/auth/csrf") return csrfResponse("current-token")
      throw new Error("offline")
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", fetcher)).rejects.toThrow("offline")

    socket.connect()
    expect(socket.attempts).toEqual(["current-token"])
  })

  it("leaves reconnects available when the CSRF read fails without writing a session", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const unavailable = vi.fn(async () => new Response("", {status: 503})) as unknown as typeof fetch

    await expect(createLocalSession("verified", unavailable)).rejects.toThrow(
      "Unable to start a secure session change.",
    )

    socket.connect()
    expect(socket.attempts).toEqual(["page-token"])
  })

  it("leaves reconnects available when a superseded sign in is retried and the retry never lands", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    let posts = 0
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input !== "/auth/csrf") {
        posts += 1
        // A superseded claim emits no cookie, so the recovery attempt starts
        // with the cookie exactly as this tab already read it.
        return lifecycleResponse("session_superseded")
      }
      if (posts === 0) return csrfResponse("current-token")
      throw new Error("offline")
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", fetcher)).rejects.toThrow("offline")

    socket.connect()
    expect(socket.attempts).toEqual(["current-token"])
  })

  it("stays closed when a refused bearer drops the cookie and no adoption follows", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const refused = vi.fn(async (input: RequestInfo | URL) =>
      input === "/auth/csrf"
        ? csrfResponse("current-token")
        : new Response(JSON.stringify({error: "unauthorized"}), {status: 401}),
    ) as unknown as typeof fetch

    // The refusal revoked the lineage and dropped its cookie, so the token this
    // tab holds names a session the browser no longer carries.
    await expect(createLocalSession("verified", refused)).rejects.toThrow(
      "Sign in could not be completed.",
    )

    socket.connect()
    expect(socket.attempts).toEqual([])

    await createLocalSession("verified", signingIn("after-reset"))

    expect(socket.attempts).toEqual(["after-reset"])
  })

  // A cookie takes effect when the response headers land, so a body that cannot
  // be read afterwards leaves this tab holding an unread session, not a proof
  // that nothing was written.
  it.each([
    ["truncated", '{"csrf_token":"after-boot'],
    ["carrying no token", '{"ok":true}'],
  ])("stays closed when a rotating CSRF read returns a body %s", async (_shape, body) => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    // A bootstrap rotates the cookie; only the token in this body would say so
    // and adopt it, and an exact observation is indistinguishable without it.
    const unadoptable = vi.fn(
      async () => new Response(body, {status: 200}),
    ) as unknown as typeof fetch

    await expect(createLocalSession("verified", unadoptable)).rejects.toThrow()

    socket.connect()
    expect(socket.attempts).toEqual([])

    await createLocalSession("verified", signingIn("after-bootstrap"))

    expect(socket.attempts).toEqual(["after-bootstrap"])
  })

  it("stays closed when a sign-in conflict cannot be read to rule out a drop", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    const unreadableConflict = vi.fn(async (input: RequestInfo | URL) =>
      input === "/auth/csrf"
        ? csrfResponse("current-token")
        : // An account switch and a revoked lineage both drop the cookie at
          // header time and both answer 409. This body cannot say it was neither.
          new Response('{"error":"account_switch_requ', {status: 409}),
    ) as unknown as typeof fetch

    await expect(createLocalSession("verified", unreadableConflict)).rejects.toThrow()

    socket.connect()
    expect(socket.attempts).toEqual([])

    await createLocalSession("verified", signingIn("after-switch"))

    expect(socket.attempts).toEqual(["after-switch"])
  })

  it("stays closed when the CSRF read drops a revoked lineage and the retry never lands", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    let reads = 0
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input !== "/auth/csrf") return signedInResponse("true")
      reads += 1
      // The revoked lineage is dropped here; the recovery attempt that would
      // have bootstrapped a fresh one never reaches the server.
      if (reads === 1) return lifecycleResponse("session_reset_required")
      throw new Error("offline")
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", fetcher)).rejects.toThrow("offline")

    socket.connect()
    expect(socket.attempts).toEqual([])

    await createLocalSession("verified", signingIn("after-reset"))

    expect(socket.attempts).toEqual(["after-reset"])
  })

  it("stays closed when the sign-in response landed and its adoption never did", async () => {
    pageWithCsrfMeta("page-token")
    const socket = pinnedSocket()
    holdSocketDuringCookieRotation(socket)
    let reads = 0
    const unreadable = vi.fn(async (input: RequestInfo | URL) => {
      if (input !== "/auth/csrf") return signedInResponse("true")
      reads += 1
      if (reads === 1) return csrfResponse("before-post")
      throw new Error("offline")
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", unreadable)).rejects.toThrow("offline")

    socket.connect()
    expect(socket.attempts).toEqual([])

    await createLocalSession("verified", signingIn("after-renewal"))

    expect(socket.attempts).toEqual(["after-renewal"])
  })
})

describe("browser session lifecycle recovery", () => {
  it.each(["session_superseded", "session_reset_required", "account_switch_required"])(
    "recovers from %s in exactly one further attempt",
    async lifecycle => {
      pageWithCsrfMeta("page-token")
      let posts = 0
      const fetcher = vi.fn(async (input: RequestInfo | URL) => {
        if (input === "/auth/csrf") return csrfResponse(`token-${posts}`)
        posts += 1
        return posts === 1 ? lifecycleResponse(lifecycle) : signedInResponse("true")
      }) as unknown as typeof fetch

      await expect(createLocalSession("verified", fetcher)).resolves.toEqual({
        sessionChanged: true,
      })

      expect(posts).toBe(2)
    },
  )

  it("gives up rather than looping when the lineage stays unusable", async () => {
    pageWithCsrfMeta("page-token")
    let posts = 0
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input === "/auth/csrf") return csrfResponse("token")
      posts += 1
      return lifecycleResponse("session_superseded")
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", fetcher)).rejects.toBeInstanceOf(
      SessionLifecycleError,
    )

    expect(posts).toBe(2)
  })

  it("recovers a refused bootstrap without reaching the session endpoint twice", async () => {
    pageWithCsrfMeta("page-token")
    const bootstraps: number[] = []
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      if (input === "/auth/csrf") {
        bootstraps.push(bootstraps.length)
        return bootstraps.length === 1
          ? lifecycleResponse("session_reset_required")
          : csrfResponse("bootstrapped")
      }
      return signedInResponse("true")
    }) as unknown as typeof fetch

    await expect(createLocalSession("verified", fetcher)).resolves.toEqual({
      sessionChanged: true,
    })

    // The refused bootstrap, the replacement bootstrap and the adoption that
    // follows the renewing response.
    expect(bootstraps).toHaveLength(3)
  })

  it("serialises this tab's queued establishments onto the newest token", async () => {
    const meta = pageWithCsrfMeta("page-token")
    const mutations = createSessionMutationCoordinator()
    const issued: string[] = []
    const sent: string[] = []
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (input === "/auth/csrf") {
        const token = `token-${issued.length}`
        issued.push(token)
        return csrfResponse(token)
      }
      sent.push(String(new Headers(init?.headers).get("x-csrf-token")))
      return signedInResponse("false")
    }) as unknown as typeof fetch

    await Promise.all([
      createLocalSession("verified", fetcher, mutations),
      createLocalSession("verified", fetcher, mutations),
    ])

    // The second establishment waits for the first to adopt, so it never signs
    // its request with a token the first one already retired.
    expect(sent).toEqual(["token-0", "token-2"])
    expect(meta.content).toBe(issued.at(-1))
  })

  it("passes anything that is not a lifecycle refusal straight through", async () => {
    const attempt = vi.fn(async () => {
      throw new Error("network down")
    })

    await expect(recoverOnce(attempt)).rejects.toThrow("network down")
    expect(attempt).toHaveBeenCalledOnce()
  })
})

describe("cross-tab CSRF adoption", () => {
  it("tells other tabs to adopt without carrying a claim or a token", async () => {
    pageWithCsrfMeta("page-token")
    const peer = new BroadcastChannel(csrfRotated)
    const notices: unknown[] = []
    peer.addEventListener("message", event => notices.push(event.data))

    try {
      announceCsrfRotation()
      await until(() => notices.length > 0)

      expect(notices).toEqual([csrfRotated])
    } finally {
      peer.close()
    }
  })

  it("adopts the shared cookie's token when another tab renews it", async () => {
    const meta = pageWithCsrfMeta("stale-token")
    const requests: Array<RequestInfo | URL> = []
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      requests.push(input)
      return csrfResponse("renewed-token")
    }) as unknown as typeof fetch
    const peer = new BroadcastChannel(csrfRotated)
    const stopAdopting = installCrossTabCsrf(fetcher)

    try {
      peer.postMessage(csrfRotated)
      await until(() => meta.content === "renewed-token")

      // The notice carries nothing, so the receiving tab asks the server under
      // the cookie both tabs already share.
      expect(requests).toEqual(["/auth/csrf"])
      expect(browserCsrfToken()).toBe("renewed-token")
    } finally {
      stopAdopting()
      peer.close()
    }
  })

  it("ignores traffic on the channel that is not a rotation notice", async () => {
    pageWithCsrfMeta("page-token")
    const fetcher = vi.fn(async () => csrfResponse("never")) as unknown as typeof fetch
    const peer = new BroadcastChannel(csrfRotated)
    const stopAdopting = installCrossTabCsrf(fetcher)

    try {
      peer.postMessage("something-else")
      await settle()

      expect(fetcher).not.toHaveBeenCalled()
      expect(browserCsrfToken()).toBe("page-token")
    } finally {
      stopAdopting()
      peer.close()
    }
  })
})

// Yields to the event loop until `reached` holds, so a cross-tab assertion waits
// on delivery rather than on a duration.
async function until(reached: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 200 && !reached(); attempt += 1) await settle()

  if (!reached()) throw new Error("The awaited notice never arrived.")
}

function settle(): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, 0))
}
