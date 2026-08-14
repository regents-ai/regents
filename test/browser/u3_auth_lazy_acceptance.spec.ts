import {expect, test} from "@playwright/test"

const bridgePattern =
  /\/assets\/js\/privy_bridge(?:-[a-f0-9]{32})?\.js\?(?:vsn=d&)?regent_retry=\d+$/

const retryViewports = [
  {name: "desktop", width: 1280, height: 720},
  {name: "narrow", width: 320, height: 720},
] as const

async function expectStatusAnchored(
  page: import("@playwright/test").Page,
  headerHeight: number,
) {
  const status = page.locator("#account-auth-status")
  await expect(status).toHaveCSS("position", "absolute")

  const statusBox = await status.boundingBox()
  const accountBox = await page.locator("#account-control").boundingBox()
  const currentHeaderBox = await page.locator("#shell-header").boundingBox()

  expect(statusBox).not.toBeNull()
  expect(accountBox).not.toBeNull()
  expect(currentHeaderBox).not.toBeNull()
  expect(currentHeaderBox?.height).toBe(headerHeight)
  expect(statusBox?.y).toBeGreaterThanOrEqual((accountBox?.y ?? 0) + (accountBox?.height ?? 0))
  expect(statusBox?.x).toBeGreaterThanOrEqual(0)
  expect((statusBox?.x ?? 0) + (statusBox?.width ?? 0)).toBeLessThanOrEqual(
    await page.evaluate(() => window.innerWidth),
  )
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
  ).toBe(true)
}

const bridgeStub = `
export async function startPrivyBridge() {
  return {
    async request(request) {
      window.__u3BridgeCalls = [...(window.__u3BridgeCalls || []), request]
    }
  }
}
`

const productionSignOutBridgeStub = `
import {startPrivyBridge as startProductionPrivyBridge} from "/assets/js/privy_bridge.js?u3_original=1"

export async function startPrivyBridge(options) {
  window.__u3StartModes = [...(window.__u3StartModes || []), options?.mode || "ordinary"]
  if (options?.mode !== "sign-out-only") {
    return {async request() { await new Promise(() => {}) }}
  }
  const handle = await startProductionPrivyBridge(options, {
    appId: "clp0000000000000000000000",
    authenticated: true,
    async getAccessToken() {
      window.__u3TokenReads = (window.__u3TokenReads || 0) + 1
      return "unexpected-token"
    },
    async logout() {
      window.__u3ProviderLogouts = (window.__u3ProviderLogouts || 0) + 1
      await window.__u3ProviderLogout()
    },
    ready: true,
    wallets: [{
      address: "0x1111111111111111111111111111111111111111",
      async getEthereumProvider() {
        window.__u3WalletReads = (window.__u3WalletReads || 0) + 1
        return {request: async () => null}
      }
    }]
  })
  window.__u3ProductionHandle = handle
  return handle
}
`

const neverReadyBridgeStub = `
export function startPrivyBridge() {
  return new Promise(() => {})
}
`

const realReconciliationBridgeStub = `
import {createProviderSessionReconciler} from "/assets/js/privy_bridge.js?u3_original=1"

export async function startPrivyBridge() {
  return {
    async request(request) {
      window.__u3BridgeCalls = [...(window.__u3BridgeCalls || []), request]
      if (request !== "sync") return
      const reconcile = createProviderSessionReconciler({
        clearSession: async () => { window.__u3UnexpectedDelete = true },
        getAccessToken: async () => "valid",
        hasLinkedWallet: () => true,
        providerAuthenticated: () => true,
        reload: () => { window.__u3ReloadAttempted = true }
      })
      window.__u3Reconciled = await reconcile()
    }
  }
}
`

// A bearer the server refuses only ever reaches it through an explicit
// establishment; startup reconciliation offers none.
const rejectedBearerBridgeStub = `
import {createLocalSession} from "/assets/js/privy_bridge.js?u3_original=1"

export async function startPrivyBridge() {
  return {
    async request(request) {
      if (request !== "sync") return
      await createLocalSession("invalid").catch(() => undefined)
      window.location.reload()
    }
  }
}
`

async function establishLocalSession(page: import("@playwright/test").Page) {
  const csrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: csrfToken} = await csrfResponse.json()
  const response = await page.request.post("/auth/privy/session", {
    headers: {authorization: "Bearer valid", "x-csrf-token": csrfToken},
    data: {},
  })
  expect(response.status()).toBe(200)
}

test("anonymous load does not request the deferred Privy bridge", async ({page}) => {
  const bridgeRequests: string[] = []
  page.on("request", request => {
    if (bridgePattern.test(request.url())) bridgeRequests.push(request.url())
  })

  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator("#account-auth-status")).toBeHidden()
  await page.waitForLoadState("networkidle")

  expect(bridgeRequests).toEqual([])
})

for (const invalidHandoff of [
  {name: "malformed", value: "not-json"},
  {name: "future", value: JSON.stringify({version: 1, issuedAtMs: Date.now() + 60_000})},
  {name: "expired", value: JSON.stringify({version: 1, issuedAtMs: 0})},
]) {
  test(`${invalidHandoff.name} sign-out handoff remains ordinary and lazy`, async ({page}) => {
    let bridgeRequests = 0
    await page.addInitScript(value => {
      sessionStorage.setItem("regent:privy-sign-out-handoff:v1", value)
    }, invalidHandoff.value)
    page.on("request", request => {
      if (bridgePattern.test(request.url())) bridgeRequests += 1
    })

    await page.goto("/app")
    await expect(page.getByRole("button", {name: "Sign In"})).toBeVisible()
    await page.waitForLoadState("networkidle")
    expect(bridgeRequests).toBe(0)
    expect(
      await page.evaluate(() =>
        sessionStorage.getItem("regent:privy-sign-out-handoff:v1"),
      ),
    ).toBeNull()
  })
}

test("the deferred Privy bridge is served as JavaScript", async ({request}) => {
  const response = await request.get("/assets/js/privy_bridge.js")

  expect(response.status()).toBe(200)
  expect(response.headers()["content-type"]).toContain("javascript")
})

test("a production-like digested bridge source remains same-origin and callable", async ({page}) => {
  const digest = "0123456789abcdef0123456789abcdef"
  await page.route("http://127.0.0.1:4002/app", async route => {
    const response = await route.fetch()
    const body = (await response.text()).replace(
      "/assets/js/privy_bridge.js",
      `/assets/js/privy_bridge-${digest}.js?vsn=d`,
    )
    await route.fulfill({response, body})
  })
  await page.route(bridgePattern, route =>
    route.fulfill({body: bridgeStub, contentType: "application/javascript"}),
  )

  await page.goto("/app")
  await page.getByRole("button", {name: "Sign In"}).click()
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls ?? [],
      ),
    )
    .toEqual(["sign-in"])
})

for (const viewport of retryViewports) {
  test(`sign-in retries failed deferred bridge loads at ${viewport.name} width`, async ({page}) => {
    const bridgeRequests: string[] = []
    await page.setViewportSize({width: viewport.width, height: viewport.height})
    await page.addInitScript(() => {
      ;(window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls = []
    })
    await page.route(bridgePattern, async route => {
      const url = route.request().url()
      bridgeRequests.push(url)
      const retry = new URL(url).searchParams.get("regent_retry")
      if (retry === "0" || retry === "1") {
        await route.fulfill({status: 503, body: "deferred bridge unavailable"})
        return
      }
      await route.fulfill({body: bridgeStub, contentType: "application/javascript"})
    })

    await page.goto("/app")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await page.evaluate(() => document.fonts.ready)
    const headerHeight = (await page.locator("#shell-header").boundingBox())?.height
    expect(headerHeight).toBeDefined()
    const status = page.locator("#account-auth-status")

    await page.getByRole("button", {name: "Sign In"}).click()
    await expect.poll(() => bridgeRequests.length).toBe(1)
    await expect(status).toBeVisible()
    await expect(status).toHaveText("Sign in couldn’t start. Try again.")
    await expectStatusAnchored(page, headerHeight ?? 0)

    await page.getByRole("button", {name: "Sign In"}).click()
    await expect.poll(() => bridgeRequests.length).toBe(2)
    await expect(status).toBeVisible()
    await expect(status).toHaveText("Sign in couldn’t start. Try again.")
    await expectStatusAnchored(page, headerHeight ?? 0)

    await page.getByRole("button", {name: "Sign In"}).click()
    await expect
      .poll(() =>
        page.evaluate(
          () => (window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls ?? [],
        ),
      )
      .toEqual(["sign-in"])
    await expect(status).toBeHidden()
    await expect(status).toHaveText("")

    expect(bridgeRequests).toHaveLength(3)
    expect(
      [...new Set(bridgeRequests.map(url => new URL(url).searchParams.get("regent_retry")))],
    ).toEqual(["0", "1", "2"])
    expect(
      await page.evaluate(
        () => (window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls ?? [],
      ),
    ).toEqual(["sign-in"])
  })
}

test("ORDINARY_SIGNED_IN_STARTUP_IS_STABLE: a same-account load writes no session", async ({
  page,
}) => {
  let bridgeRequests = 0
  let sessionDeletes = 0
  let sessionPosts = 0
  const documentRequests: string[] = []
  await page.addInitScript(() => {
    ;(window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls = []
  })
  page.on("request", request => {
    if (!request.url().endsWith("/auth/privy/session")) return
    if (request.method() === "DELETE") sessionDeletes += 1
    if (request.method() === "POST") sessionPosts += 1
  })
  page.on("request", request => {
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documentRequests.push(request.url())
    }
  })
  await page.route(bridgePattern, async route => {
    bridgeRequests += 1
    await route.fulfill({
      body: realReconciliationBridgeStub,
      contentType: "application/javascript",
    })
  })

  await establishLocalSession(page)
  const sessionCookieBefore = (await page.context().cookies()).find(
    cookie => cookie.name === "_ash_platform_key",
  )?.value

  let renderedCsrfToken = ""
  page.on("response", async response => {
    if (!response.request().isNavigationRequest()) return
    const html = await response.text()
    renderedCsrfToken =
      /name="csrf-token" content="([^"]+)"/.exec(html)?.[1] ?? renderedCsrfToken
  })

  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator("#account-auth-status")).toBeHidden()
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls ?? [],
      ),
    )
    .toEqual(["sync"])
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as Window & {__u3Reconciled?: boolean}).__u3Reconciled,
      ),
    )
    .toBe(true)

  expect(bridgeRequests).toBe(1)
  expect(sessionDeletes).toBe(0)
  expect(documentRequests).toEqual(["http://127.0.0.1:4002/app"])
  // Remaining signed in is not a session event: startup reaches the session
  // endpoint not at all, so the signed cookie and the token the page was
  // rendered with are the ones it still holds afterwards.
  expect(sessionPosts).toBe(0)
  const sessionCookieAfter = (await page.context().cookies()).find(
    cookie => cookie.name === "_ash_platform_key",
  )?.value
  expect(sessionCookieBefore).toBeTruthy()
  expect(sessionCookieAfter).toBe(sessionCookieBefore)
  expect(renderedCsrfToken).toBeTruthy()
  expect(await metaCsrfToken(page)).toBe(renderedCsrfToken)
  expect(
    await page.evaluate(() =>
      Boolean((window as Window & {__u3ReloadAttempted?: boolean}).__u3ReloadAttempted),
    ),
  ).toBe(false)
  expect(
    await page.evaluate(() =>
      Boolean((window as Window & {__u3UnexpectedDelete?: boolean}).__u3UnexpectedDelete),
    ),
  ).toBe(false)
  await expect(page.locator("[data-phx-session]").first()).toBeVisible()
  await page.locator("#account-menu summary").click()
  await expect(page.getByRole("button", {name: "Log Out"})).toBeVisible()
  await page.getByRole("link", {name: "Settings"}).click()
  await expect(page.locator("#settings-verified-connections")).toBeVisible()
  await page.evaluate(() => {
    window.dispatchEvent(new CustomEvent("ash:identity-state", {detail: {error: null}}))
  })
  await expect(page.getByText("Verified connections updated.")).toBeVisible()
  expect(documentRequests).toEqual(["http://127.0.0.1:4002/app"])
  expect((await page.request.get("/auth/session")).status()).toBe(200)
})

test("a held pre-logout session response cannot restore browser or LiveView access", async ({
  page,
}) => {
  let releaseHeldResponse: (() => void) | undefined
  const releaseGate = new Promise<void>(resolve => (releaseHeldResponse = resolve))
  let markPostProcessed: (() => void) | undefined
  const postProcessed = new Promise<void>(resolve => (markPostProcessed = resolve))
  let heldSetCookie = ""
  const documentRequests: string[] = []

  page.on("request", request => {
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documentRequests.push(request.url())
    }
  })
  await page.route("**/auth/privy/session", async route => {
    if (route.request().method() !== "POST") {
      await route.continue()
      return
    }

    const response = await route.fetch()
    heldSetCookie = response.headers()["set-cookie"] ?? ""
    markPostProcessed?.()
    await releaseGate
    await route.fulfill({response})
  })

  await page.goto("/autolaunch/create")
  await expect(page.locator("#autolaunch-verified-connections")).toBeVisible()
  await expect(page.getByRole("button", {name: "Sign in to connect"}).first()).toBeVisible()
  const csrfToken = await page.evaluate(async () => {
    const response = await fetch("/auth/csrf", {credentials: "same-origin"})
    return ((await response.json()) as {csrf_token: string}).csrf_token
  })
  const sessionCookieBefore = (await page.context().cookies()).find(
    cookie => cookie.name === "_ash_platform_key",
  )?.value

  const heldPost = page.evaluate(async token => {
    const response = await fetch("/auth/privy/session", {
      method: "POST",
      credentials: "same-origin",
      headers: {authorization: "Bearer valid", "x-csrf-token": token},
    })
    return {
      status: response.status,
      sessionChanged: response.headers.get("x-ash-session-changed"),
    }
  }, csrfToken)
  await postProcessed
  expect(heldSetCookie).toContain("_ash_platform_key=")

  // The held response has already renewed this browser's session, so sign out
  // adopts the rotated token before it revokes the lineage the response is
  // still carrying.
  const deleteCsrfToken = await page.evaluate(async () => {
    const response = await fetch("/auth/csrf", {credentials: "same-origin"})
    return ((await response.json()) as {csrf_token: string}).csrf_token
  })
  const deleted = await page.evaluate(async token => {
    const response = await fetch("/auth/privy/session", {
      method: "DELETE",
      credentials: "same-origin",
      headers: {"x-csrf-token": token},
    })
    return response.status
  }, deleteCsrfToken)
  expect(deleted).toBe(200)

  releaseHeldResponse?.()
  await expect(heldPost).resolves.toEqual({status: 200, sessionChanged: "true"})
  const staleSessionCookie = (await page.context().cookies()).find(
    cookie => cookie.name === "_ash_platform_key",
  )?.value
  expect(staleSessionCookie).toBeTruthy()
  expect(staleSessionCookie).not.toBe(sessionCookieBefore)

  const session = await page.request.get("/auth/session")
  expect((await session.json()).authenticated).toBe(false)
  await expect(page.locator("[data-phx-session]").first()).toBeVisible()
  await page.evaluate(() => {
    const liveView = document.querySelector<HTMLElement>("[data-phx-session]")
    if (!liveView) throw new Error("The protected LiveView is not mounted.")
    const button = document.createElement("button")
    button.id = "u3-protected-identity-probe"
    button.type = "button"
    button.setAttribute("phx-click", "request_verified_connection")
    button.setAttribute("phx-value-action", "link")
    button.setAttribute("phx-value-provider", "github")
    button.textContent = "Probe protected identity action"
    liveView.append(button)
  })
  await page.locator("#u3-protected-identity-probe").click()
  await expect(
    page.getByText("That connection couldn’t be updated. Refresh the page and try again."),
  ).toBeVisible()
  const sessionAfterProtectedAction = await page.request.get("/auth/session")
  expect((await sessionAfterProtectedAction.json()).authenticated).toBe(false)
  await expect(page.getByRole("button", {name: "Sign in to connect"}).first()).toBeVisible()
  expect(documentRequests).toEqual(["http://127.0.0.1:4002/autolaunch/create"])
})

test("sign out replaces pending sync and runs once after the bridge is ready", async ({page}) => {
  let sessionDeletes = 0
  let finishProviderLogout: (() => void) | undefined
  const documentRequests: string[] = []
  const eventOrder: string[] = []
  await page.exposeFunction(
    "__u3ProviderLogout",
    () => new Promise<void>(resolve => (finishProviderLogout = resolve)),
  )
  let localSessionPostsAfterDelete = 0
  page.on("request", request => {
    if (request.method() === "DELETE" && request.url().endsWith("/auth/privy/session")) {
      sessionDeletes += 1
    }
    if (
      sessionDeletes > 0 &&
      request.method() === "POST" &&
      request.url().endsWith("/auth/privy/session")
    ) {
      localSessionPostsAfterDelete += 1
    }
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documentRequests.push(request.url())
      eventOrder.push(`document-${documentRequests.length}`)
    }
  })
  page.on("response", response => {
    if (
      response.request().method() === "DELETE" &&
      response.url().endsWith("/auth/privy/session")
    ) {
      eventOrder.push("delete-response")
    }
  })
  await page.route(bridgePattern, route =>
    route.fulfill({body: productionSignOutBridgeStub, contentType: "application/javascript"}),
  )

  await establishLocalSession(page)

  await page.goto("/app")
  await expect(page.locator("#account-menu [data-account-target='profile']")).toBeVisible()
  await page.locator("#account-menu summary").click()
  await page.getByRole("button", {name: "Log Out"}).click()
  await expect.poll(() => sessionDeletes).toBe(1)

  await expect.poll(() => documentRequests.length).toBe(2)
  // The retired logout-epoch cookie is gone; revocation is the only authority.
  expect(
    (await page.context().cookies()).map(cookie => cookie.name),
  ).not.toContain("_ash_platform_logout_epoch")
  expect(eventOrder.indexOf("delete-response")).toBeLessThan(
    eventOrder.indexOf("document-2"),
  )
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as Window & {__u3StartModes?: string[]}).__u3StartModes ?? [],
      ),
    )
    .toContain("sign-out-only")
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as Window & {__u3ProviderLogouts?: number}).__u3ProviderLogouts ?? 0,
      ),
    )
    .toBe(1)
  const blockedProductionRequests = await page.evaluate(async () => {
    const handle = (
      window as Window & {
        __u3ProductionHandle?: {
          request: (request: "sign-in" | "sign-out" | "sync") => Promise<void>
          identity?: (request: {action: "link"; provider: "x"}) => Promise<void>
        }
      }
    ).__u3ProductionHandle
    if (!handle?.identity) return []
    return Promise.all([
      handle.request("sync").then(
        () => "resolved",
        () => "rejected",
      ),
      handle.request("sign-in").then(
        () => "resolved",
        () => "rejected",
      ),
      handle.identity({action: "link", provider: "x"}).then(
        () => "resolved",
        () => "rejected",
      ),
    ])
  })
  expect(blockedProductionRequests).toEqual(["rejected", "rejected", "rejected"])
  expect(
    await page.evaluate(
      () => (window as Window & {__u3TokenReads?: number}).__u3TokenReads ?? 0,
    ),
  ).toBe(0)
  expect(
    await page.evaluate(
      () => (window as Window & {__u3WalletReads?: number}).__u3WalletReads ?? 0,
    ),
  ).toBe(0)
  expect(localSessionPostsAfterDelete).toBe(0)
  finishProviderLogout?.()
  await page.waitForTimeout(100)
  expect(
    await page.evaluate(
      () => (window as Window & {__u3ProviderLogouts?: number}).__u3ProviderLogouts ?? 0,
    ),
  ).toBe(1)
  expect(documentRequests).toHaveLength(2)
  expect(sessionDeletes).toBe(1)
})

test("a valid handoff uses the real session resource and refuses authenticated truth", async ({
  page,
}) => {
  const sessionReads: string[] = []
  let bridgeLoads = 0
  await establishLocalSession(page)
  await page.addInitScript(() => {
    sessionStorage.setItem(
      "regent:privy-sign-out-handoff:v1",
      JSON.stringify({version: 1, issuedAtMs: Date.now()}),
    )
  })
  page.on("request", request => {
    if (request.method() === "GET" && new URL(request.url()).pathname.startsWith("/auth/")) {
      sessionReads.push(new URL(request.url()).pathname)
    }
  })
  await page.route(bridgePattern, route => {
    bridgeLoads += 1
    return route.fulfill({body: bridgeStub, contentType: "application/javascript"})
  })

  await page.goto("/app")
  await expect.poll(() => sessionReads).toContain("/auth/session")
  await page.waitForLoadState("networkidle")
  expect(sessionReads.filter(path => path === "/auth/session")).toHaveLength(1)
  expect(sessionReads.filter(path => path !== "/auth/session")).toEqual([])
  expect(bridgeLoads).toBe(0)
  expect((await (await page.request.get("/auth/session")).json()).authenticated).toBe(true)
})

test("the second document proves anonymous server truth before importing Privy", async ({
  page,
}) => {
  const order: string[] = []
  let bridgeLoads = 0
  let sessionDeletes = 0
  const documentRequests: string[] = []

  page.on("request", request => {
    if (request.method() === "DELETE" && request.url().endsWith("/auth/privy/session")) {
      sessionDeletes += 1
    }
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documentRequests.push(request.url())
    }
  })
  page.on("response", response => {
    if (response.request().method() === "GET" && response.url().endsWith("/auth/session")) {
      order.push("anonymous-proof")
    }
  })
  await page.route(bridgePattern, route => {
    bridgeLoads += 1
    order.push(`bridge-${bridgeLoads}`)
    return route.fulfill({body: bridgeStub, contentType: "application/javascript"})
  })

  await establishLocalSession(page)
  await page.goto("/app")
  await expect.poll(() => bridgeLoads).toBe(1)
  await page.locator("#account-menu summary").click()
  await page.getByRole("button", {name: "Log Out"}).click()

  await expect.poll(() => sessionDeletes).toBe(1)
  await expect.poll(() => documentRequests.length).toBe(2)
  await expect.poll(() => bridgeLoads).toBe(2)
  expect(order.indexOf("anonymous-proof")).toBeGreaterThan(order.indexOf("bridge-1"))
  expect(order.indexOf("anonymous-proof")).toBeLessThan(order.indexOf("bridge-2"))
  expect((await (await page.request.get("/auth/session")).json()).authenticated).toBe(false)
})

for (const failure of [
  {name: "the public app ID is absent", bridgeBody: null},
  {name: "the bridge import fails", bridgeBody: "failure"},
  {name: "provider readiness never settles", bridgeBody: neverReadyBridgeStub},
] as const) {
  test(`signed-in startup fails closed when ${failure.name}`, async ({page}) => {
    let sessionDeletes = 0
    const documentRequests: string[] = []
    page.on("request", request => {
      if (request.method() === "DELETE" && request.url().endsWith("/auth/privy/session")) {
        sessionDeletes += 1
      }
      if (request.isNavigationRequest() && request.resourceType() === "document") {
        documentRequests.push(request.url())
      }
    })
    if (failure.bridgeBody === "failure") {
      await page.route(bridgePattern, route =>
        route.fulfill({status: 503, body: "deferred bridge unavailable"}),
      )
    } else if (failure.bridgeBody) {
      await page.route(bridgePattern, route =>
        route.fulfill({body: failure.bridgeBody, contentType: "application/javascript"}),
      )
    }

    await establishLocalSession(page)
    await page.goto("/app")

    await expect.poll(() => sessionDeletes, {timeout: 10_000}).toBe(1)
    await expect.poll(() => documentRequests.length, {timeout: 10_000}).toBe(2)
    await expect(page.getByRole("button", {name: "Sign In"})).toBeVisible()
    const finalSession = await page.request.get("/auth/session")
    expect((await finalSession.json()).authenticated).toBe(false)
    expect(sessionDeletes).toBe(1)
  })
}

function metaCsrfToken(page: import("@playwright/test").Page): Promise<string> {
  return page.evaluate(
    () => document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content ?? "",
  )
}

function trackDocuments(page: import("@playwright/test").Page): string[] {
  const documents: string[] = []
  page.on("request", request => {
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documents.push(request.url())
    }
  })
  return documents
}

// The deferred bridge is inert here: these tests drive the renewal themselves.
function stubBridge(page: import("@playwright/test").Page) {
  return page.route(bridgePattern, route =>
    route.fulfill({body: bridgeStub, contentType: "application/javascript"}),
  )
}

// Runs the real in-page establishment, so the renewal rotates this browser's
// CSRF state and announces it the way the product does.
async function refreshInPage(page: import("@playwright/test").Page) {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await page.evaluate(async () => {
    const source = "/assets/js/privy_bridge.js"
    const bridge = (await import(source)) as {
      createLocalSession: (accessToken: string) => Promise<{sessionChanged: boolean}>
    }
    await bridge.createLocalSession("valid")
  })
}

test("COOKIE_TO_CSRF_HAS_A_REAL_LIVESOCKET_BARRIER: nothing connects before the token is read", async ({
  page,
}) => {
  await stubBridge(page)
  await establishLocalSession(page)
  const documents = trackDocuments(page)

  // The adoption that follows the renewing response is held, so the browser
  // sits inside the interval for as long as this test needs it to.
  let csrfRequests = 0
  let releaseAdoption: (() => void) | undefined
  const heldAdoption = new Promise<void>(resolve => (releaseAdoption = resolve))
  let markHeld: (() => void) | undefined
  const adoptionHeld = new Promise<void>(resolve => (markHeld = resolve))
  await page.route("**/auth/csrf", async route => {
    csrfRequests += 1
    if (csrfRequests === 2) {
      markHeld?.()
      await heldAdoption
    }
    await route.continue()
  })

  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const connected = () =>
    page.evaluate(() =>
      Boolean((window.liveSocket as unknown as {isConnected(): boolean}).isConnected()),
    )
  await expect.poll(connected).toBe(true)

  const establishment = page.evaluate(async () => {
    const source = "/assets/js/privy_bridge.js"
    const bridge = (await import(source)) as {
      createLocalSession: (accessToken: string) => Promise<{sessionChanged: boolean}>
    }
    await bridge.createLocalSession("valid")
  })
  await adoptionHeld
  const heldToken = await metaCsrfToken(page)

  await page.evaluate(
    () =>
      new Promise<void>(resolve =>
        (window.liveSocket as unknown as {disconnect(callback: () => void): void}).disconnect(
          resolve,
        ),
      ),
  )
  await expect.poll(connected).toBe(false)

  // The cookie is already the renewed one and this tab has not read the state
  // it carries. `Socket.connect` reaches `transportConnect`, which builds its
  // transport synchronously, so a still-closed state right after the call means
  // no connection was started at all, rather than one that was started and
  // refused by the server.
  expect(
    await page.evaluate(() => {
      const socket = (
        window.liveSocket as unknown as {getSocket(): {connectionState(): string}}
      ).getSocket()
      window.liveSocket.connect()
      return socket.connectionState()
    }),
  ).toBe("closed")
  expect(await metaCsrfToken(page)).toBe(heldToken)

  releaseAdoption?.()
  await establishment

  // Released, the held reconnect goes out once and lands, with no reload.
  await expect.poll(connected).toBe(true)
  expect(documents.map(url => new URL(url).pathname)).toEqual(["/app"])
  await expect(page.locator("#account-menu [data-account-target='profile']")).toBeVisible()
})

test("a refresh between another tab's dead render and its connect recovers in one reload", async ({
  context,
}) => {
  const refreshingTab = await context.newPage()
  const waitingTab = await context.newPage()
  await stubBridge(refreshingTab)
  await stubBridge(waitingTab)
  await establishLocalSession(refreshingTab)
  const documents = trackDocuments(waitingTab)

  // Barrier: the waiting tab's entrypoint is held, so its dead render lands
  // while its socket cannot start yet.
  let releaseEntrypoint: (() => void) | undefined
  const heldEntrypoint = new Promise<void>(resolve => (releaseEntrypoint = resolve))
  let held = false
  await waitingTab.route("**/assets/js/app.js", async route => {
    if (!held) {
      held = true
      await heldEntrypoint
    }
    await route.continue()
  })

  await waitingTab.goto("/app", {waitUntil: "commit"})
  await expect(waitingTab.locator("#app-shell")).toBeVisible()
  const renderedToken = await metaCsrfToken(waitingTab)

  await refreshInPage(refreshingTab)
  releaseEntrypoint?.()

  // The held tab missed the notice, so its first connect carries the retired
  // token. Phoenix refuses that handshake at the transport, before any mount
  // hook runs, and LiveView falls back to exactly one further request for the
  // same route, which then carries the current token.
  await expect(waitingTab.locator("#account-menu [data-account-target='profile']")).toBeVisible()
  await waitingTab.waitForLoadState("networkidle")

  expect(documents.map(url => new URL(url).pathname)).toEqual(["/app", "/app"])
  expect(await metaCsrfToken(waitingTab)).not.toBe(renderedToken)
  expect(
    await waitingTab.evaluate(() =>
      Boolean((window.liveSocket as unknown as {isConnected(): boolean}).isConnected()),
    ),
  ).toBe(true)
})

test("a refresh in one tab leaves another tab mounted and its next reconnect uses the current token", async ({
  context,
}) => {
  const refreshingTab = await context.newPage()
  const mountedTab = await context.newPage()
  await stubBridge(refreshingTab)
  await stubBridge(mountedTab)
  await establishLocalSession(refreshingTab)
  const documents = trackDocuments(mountedTab)

  await mountedTab.goto("/app")
  await expect(mountedTab.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const mountedToken = await metaCsrfToken(mountedTab)
  const mountedView = await mountedTab.locator("[data-phx-session]").first().getAttribute("id")

  await refreshInPage(refreshingTab)

  // The notice reaches the mounted tab, which adopts the token without losing
  // the socket it already had.
  await expect.poll(() => metaCsrfToken(mountedTab)).not.toBe(mountedToken)
  expect(await mountedTab.locator("[data-phx-session]").first().getAttribute("id")).toBe(
    mountedView,
  )
  expect(documents).toHaveLength(1)

  const connected = () =>
    mountedTab.evaluate(() =>
      Boolean((window.liveSocket as unknown as {isConnected(): boolean}).isConnected()),
    )

  await mountedTab.evaluate(
    () =>
      new Promise<void>(resolve =>
        (window.liveSocket as unknown as {disconnect(callback: () => void): void}).disconnect(
          resolve,
        ),
      ),
  )
  await expect.poll(connected).toBe(false)

  await mountedTab.evaluate(() => window.liveSocket.connect())
  await expect.poll(connected).toBe(true)

  // A deploy-style reconnect carries the adopted token, so nothing reloads.
  expect(documents).toHaveLength(1)
  await expect(mountedTab.locator("#account-menu [data-account-target='profile']")).toBeVisible()
})

test("a tab holding a stale token still signs out, and the revoked lineage cannot reconnect", async ({
  context,
}) => {
  const refreshingTab = await context.newPage()
  const signingOutTab = await context.newPage()
  await stubBridge(refreshingTab)
  await stubBridge(signingOutTab)
  await establishLocalSession(refreshingTab)

  // Barrier: the signing-out tab never adopts the notice, so it reaches logout
  // holding the token its own render carried.
  await signingOutTab.addInitScript(() => {
    Object.defineProperty(window, "BroadcastChannel", {value: undefined})
  })
  await signingOutTab.goto("/app")
  await expect(signingOutTab.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const staleToken = await metaCsrfToken(signingOutTab)

  await refreshInPage(refreshingTab)
  expect(await metaCsrfToken(signingOutTab)).toBe(staleToken)

  const deletes: number[] = []
  signingOutTab.on("response", response => {
    if (response.request().method() === "DELETE") deletes.push(response.status())
  })

  await signingOutTab.evaluate(async () => {
    const source = "/assets/js/privy_bridge.js"
    const bridge = (await import(source)) as {clearLocalSession: () => Promise<void>}
    await bridge.clearLocalSession()
  })

  // The page token is refused, the current one is adopted, and the retry revokes.
  expect(deletes).toEqual([403, 200])

  const session = await signingOutTab.request.get("/auth/session")
  expect((await session.json()).authenticated).toBe(false)

  // The refreshing tab still holds the revoked lineage and cannot reconnect it.
  await refreshingTab.reload()
  await expect(
    refreshingTab.locator("#account-control [data-account-target='sign-in']"),
  ).toBeVisible()
})

test("a rejected bearer leaves the browser anonymous without a duplicate delete or a reload loop", async ({
  page,
}) => {
  const deletes: string[] = []
  const documents: string[] = []
  page.on("request", request => {
    if (request.method() === "DELETE") deletes.push(request.url())
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documents.push(new URL(request.url()).pathname)
    }
  })
  await page.route(bridgePattern, route =>
    route.fulfill({body: rejectedBearerBridgeStub, contentType: "application/javascript"}),
  )

  await establishLocalSession(page)
  await page.goto("/app")

  // The server already revoked and dropped the authority with its 401, so the
  // bridge adds no delete of its own and the single reload lands anonymous.
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible()
  await page.waitForLoadState("networkidle")

  expect(deletes).toEqual([])
  expect(documents).toEqual(["/app", "/app"])

  const session = await page.request.get("/auth/session")
  expect((await session.json()).authenticated).toBe(false)
})
