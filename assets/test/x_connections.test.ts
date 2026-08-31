import {beforeEach, describe, expect, it, vi} from "vitest"

vi.mock("../js/auth_lazy", () => ({browserCsrfToken: () => "csrf-token"}))

import {XConnections} from "../js/hooks/x_connections"

class FakeElement {
  dataset: Record<string, string> = {}
  textContent = ""
  listeners = new Map<string, (event: Event) => void>()

  addEventListener(type: string, listener: EventListener) {
    this.listeners.set(type, listener as (event: Event) => void)
  }

  removeEventListener(type: string) {
    this.listeners.delete(type)
  }

  closest(_selector: string): FakeElement | null {
    return null
  }
}

class Root extends FakeElement {
  status = new FakeElement()

  querySelector(selector: string) {
    return selector === "[data-x-connection-status]" ? this.status : null
  }
}

class RoleTarget extends FakeElement {
  constructor(kind: "connect" | "disconnect", role: "profile" | "company") {
    super()
    if (kind === "connect") this.dataset.xConnectRole = role
    if (kind === "disconnect") this.dataset.xDisconnectRole = role
  }

  closest(selector: string) {
    if (selector === "[data-x-connect-role]" && this.dataset.xConnectRole) return this
    if (selector === "[data-x-disconnect-role]" && this.dataset.xDisconnectRole) return this
    return null
  }
}

function popup() {
  const value = {
    closed: false,
    document: {title: ""},
    location: {replace: vi.fn()},
    close: vi.fn(() => {
      value.closed = true
    }),
  }
  return value
}

function response(body: Record<string, unknown>, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response
}

async function settled() {
  for (let turn = 0; turn < 10; turn += 1) await Promise.resolve()
}

describe("direct X role connections", () => {
  let root: Root
  let activePopup: ReturnType<typeof popup>
  let messageListener: (event: MessageEvent) => void
  let pushEvent: ReturnType<typeof vi.fn>
  let hook: never

  beforeEach(() => {
    vi.useFakeTimers()
    root = new Root()
    root.dataset.xOauthOrigin = "http://localhost:4000"
    activePopup = popup()
    pushEvent = vi.fn()

    vi.stubGlobal("Element", FakeElement)
    vi.stubGlobal("HTMLElement", FakeElement)
    vi.stubGlobal("fetch", vi.fn())
    vi.stubGlobal("window", {
      open: vi.fn(() => {
        if (activePopup.closed) activePopup = popup()
        return activePopup
      }),
      addEventListener: vi.fn((type: string, listener: (event: MessageEvent) => void) => {
        if (type === "message") messageListener = listener
      }),
      removeEventListener: vi.fn(),
      setInterval,
      clearInterval,
      setTimeout,
      clearTimeout,
    })

    hook = {el: root, pushEvent} as never
    XConnections.mounted?.call(hook)
  })

  it("binds the popup to the exact origin, window, role, and attempt generation", async () => {
    vi.mocked(fetch).mockResolvedValue(
      response({
        url: "https://x.example.test/authorize",
        role: "profile",
        generation: "generation-1",
      }),
    )

    root.listeners.get("click")?.({target: new RoleTarget("connect", "profile")} as unknown as Event)
    await settled()

    expect(fetch).toHaveBeenCalledWith("/auth/x/connections/profile", {
      method: "POST",
      credentials: "same-origin",
      headers: {"x-csrf-token": "csrf-token", accept: "application/json"},
      signal: expect.any(AbortSignal),
    })
    expect(activePopup.location.replace).toHaveBeenCalledWith("https://x.example.test/authorize")

    for (const event of [
      {
        origin: "https://attacker.example",
        source: activePopup,
        data: {source: "ash-x-oauth", status: "connected", role: "profile", generation: "generation-1"},
      },
      {
        origin: "http://localhost:4000",
        source: {},
        data: {source: "ash-x-oauth", status: "connected", role: "profile", generation: "generation-1"},
      },
      {
        origin: "http://localhost:4000",
        source: activePopup,
        data: {source: "ash-x-oauth", status: "connected", role: "company", generation: "generation-1"},
      },
      {
        origin: "http://localhost:4000",
        source: activePopup,
        data: {source: "ash-x-oauth", status: "connected", role: "profile", generation: "stale"},
      },
    ]) {
      messageListener(event as unknown as MessageEvent)
    }

    expect(pushEvent).not.toHaveBeenCalled()

    messageListener({
      origin: "http://localhost:4000",
      source: activePopup,
      data: {
        source: "ash-x-oauth",
        status: "connected",
        role: "profile",
        generation: "generation-1",
      },
    } as unknown as MessageEvent)

    expect(pushEvent).toHaveBeenCalledWith("refresh_x_connections", {
      role: "profile",
      status: "connected",
    })
    expect(activePopup.close).toHaveBeenCalledOnce()
    expect(root.status.textContent).toBe("X account connected.")
  })

  it("reports popup cancellation and failed start without claiming a connection", async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      response({
        url: "https://x.example.test/authorize",
        role: "company",
        generation: "generation-2",
      }),
    )

    root.listeners.get("click")?.({target: new RoleTarget("connect", "company")} as unknown as Event)
    await settled()
    activePopup.closed = true
    await vi.advanceTimersByTimeAsync(250)

    expect(root.status.textContent).toBe("X connection was not completed.")
    expect(pushEvent).not.toHaveBeenCalled()

    activePopup = popup()
    vi.mocked(fetch).mockResolvedValueOnce(response({error: "x_oauth_disabled"}, 503))
    root.listeners.get("click")?.({target: new RoleTarget("connect", "profile")} as unknown as Event)
    await settled()

    expect(activePopup.close).toHaveBeenCalled()
    expect(root.status.textContent).toBe("X connection could not start. Try again.")
  })

  it("closes an older popup before opening a replacement attempt", async () => {
    vi.mocked(fetch)
      .mockResolvedValueOnce(
        response({
          url: "https://x.example.test/first",
          role: "profile",
          generation: "generation-first",
        }),
      )
      .mockResolvedValueOnce(
        response({
          url: "https://x.example.test/second",
          role: "company",
          generation: "generation-second",
        }),
      )

    root.listeners.get("click")?.({target: new RoleTarget("connect", "profile")} as unknown as Event)
    await settled()
    const firstPopup = activePopup

    root.listeners.get("click")?.({target: new RoleTarget("connect", "company")} as unknown as Event)
    await settled()

    expect(firstPopup.close).toHaveBeenCalledOnce()
    expect(activePopup).not.toBe(firstPopup)
    expect(activePopup.location.replace).toHaveBeenCalledWith("https://x.example.test/second")
  })

  it("disconnects only the selected role with the current CSRF token", async () => {
    vi.mocked(fetch).mockResolvedValue(response({ok: true, role: "company"}))

    root.listeners.get("click")?.({target: new RoleTarget("disconnect", "company")} as unknown as Event)
    await settled()

    expect(fetch).toHaveBeenCalledWith("/auth/x/connections/company", {
      method: "DELETE",
      credentials: "same-origin",
      headers: {"x-csrf-token": "csrf-token", accept: "application/json"},
    })
    expect(pushEvent).toHaveBeenCalledWith("refresh_x_connections", {
      role: "company",
      status: "disconnected",
    })
    expect(root.status.textContent).toBe("X account disconnected.")
  })

  it("disconnects immediately while a same-role start is unresolved and ignores its late result", async () => {
    let resolveStart!: (value: Response) => void
    const delayedStart = new Promise<Response>(resolve => {
      resolveStart = resolve
    })

    vi.mocked(fetch)
      .mockImplementationOnce(() => delayedStart)
      .mockResolvedValueOnce(response({ok: true, role: "profile"}))

    root.listeners.get("click")?.({target: new RoleTarget("connect", "profile")} as unknown as Event)
    await settled()
    const startPopup = activePopup
    const startSignal = (vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit).signal

    expect(fetch).toHaveBeenCalledTimes(1)
    expect(startSignal?.aborted).toBe(false)

    root.listeners
      .get("click")
      ?.({target: new RoleTarget("disconnect", "profile")} as unknown as Event)

    expect(startPopup.close).toHaveBeenCalledOnce()
    expect(startSignal?.aborted).toBe(true)
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch).toHaveBeenNthCalledWith(2, "/auth/x/connections/profile", {
      method: "DELETE",
      credentials: "same-origin",
      headers: {"x-csrf-token": "csrf-token", accept: "application/json"},
    })

    await settled()

    expect(pushEvent).toHaveBeenCalledWith("refresh_x_connections", {
      role: "profile",
      status: "disconnected",
    })
    expect(root.status.textContent).toBe("X account disconnected.")

    resolveStart(
      response({
        url: "https://x.example.test/authorize",
        role: "profile",
        generation: "generation-delayed",
      }),
    )
    await settled()

    expect(startPopup.location.replace).not.toHaveBeenCalled()
    expect(root.status.textContent).toBe("X account disconnected.")
  })

  it("bounds a start that never returns", async () => {
    vi.mocked(fetch).mockImplementation((_path, options) => {
      const signal = options?.signal

      return new Promise<Response>((_resolve, reject) => {
        signal?.addEventListener("abort", () => reject(new Error("aborted")))
      })
    })

    root.listeners.get("click")?.({target: new RoleTarget("connect", "profile")} as unknown as Event)
    await settled()

    const startSignal = (vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit).signal
    expect(startSignal?.aborted).toBe(false)

    await vi.advanceTimersByTimeAsync(10_000)
    await settled()

    expect(startSignal?.aborted).toBe(true)
    expect(activePopup.close).toHaveBeenCalledOnce()
    expect(activePopup.location.replace).not.toHaveBeenCalled()
    expect(root.status.textContent).toBe("X connection could not start. Try again.")
    expect(pushEvent).not.toHaveBeenCalled()
  })
})
