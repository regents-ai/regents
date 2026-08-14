import {afterEach, describe, expect, it, vi} from "vitest"

import {
  SessionLifecycleError,
  announceCsrfRotation,
  browserCsrfToken,
  clearLocalSession,
  createSessionMutationCoordinator,
  csrfRotated,
  csrfToken,
  installCrossTabCsrf,
  recoverOnce,
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
