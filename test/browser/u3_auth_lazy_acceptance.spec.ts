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

const delayedSignOutBridgeStub = `
export function startPrivyBridge() {
  return new Promise(resolve => {
    window.__u3ReadyBridge = () => resolve({
      async request(request) {
        window.__u3BridgeCalls = [...(window.__u3BridgeCalls || []), request]
        if (request !== "sign-out") return
        await window.__u3ProviderLogout()
      }
    })
  })
}
`

const neverReadyBridgeStub = `
export function startPrivyBridge() {
  return new Promise(() => {})
}
`

const delayedReconciliationBridgeStub = `
import {createLocalSession} from "/assets/js/privy_bridge.js?u3_original=1"

function fetchIgnoringAbort(input, init = {}) {
  const {signal: _ignoredSignal, ...request} = init
  return fetch(input, request)
}

export async function startPrivyBridge() {
  return {
    async request(request) {
      window.__u3BridgeCalls = [...(window.__u3BridgeCalls || []), request]
      if (request === "sync") await createLocalSession("valid", fetchIgnoringAbort)
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

test("signed-in direct load requests sync without clearing or reloading", async ({page}) => {
  let bridgeRequests = 0
  let sessionDeletes = 0
  const documentRequests: string[] = []
  await page.addInitScript(() => {
    ;(window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls = []
  })
  page.on("request", request => {
    if (request.method() === "DELETE" && request.url().endsWith("/auth/privy/session")) {
      sessionDeletes += 1
    }
  })
  page.on("request", request => {
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documentRequests.push(request.url())
    }
  })
  await page.route(bridgePattern, async route => {
    bridgeRequests += 1
    await route.fulfill({body: bridgeStub, contentType: "application/javascript"})
  })

  await establishLocalSession(page)

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

  expect(bridgeRequests).toBe(1)
  expect(sessionDeletes).toBe(0)
  expect(documentRequests).toEqual(["http://127.0.0.1:4002/app"])
  expect((await page.request.get("/auth/session")).status()).toBe(200)
})

test("sign out replaces pending sync and runs once after the bridge is ready", async ({page}) => {
  let sessionDeletes = 0
  let providerLogouts = 0
  const documentRequests: string[] = []
  await page.exposeFunction("__u3ProviderLogout", () => {
    providerLogouts += 1
  })
  page.on("request", request => {
    if (request.method() === "DELETE" && request.url().endsWith("/auth/privy/session")) {
      sessionDeletes += 1
    }
    if (request.isNavigationRequest() && request.resourceType() === "document") {
      documentRequests.push(request.url())
    }
  })
  await page.route(bridgePattern, route =>
    route.fulfill({body: delayedSignOutBridgeStub, contentType: "application/javascript"}),
  )

  await establishLocalSession(page)

  await page.goto("/app")
  await expect(page.locator("#account-menu [data-account-target='profile']")).toBeVisible()
  await page.locator("#account-menu summary").click()
  await page.getByRole("button", {name: "Log Out"}).click()
  await expect.poll(() => sessionDeletes).toBe(1)
  expect(providerLogouts).toBe(0)

  await page.evaluate(() =>
    (window as Window & {__u3ReadyBridge?: () => void}).__u3ReadyBridge?.(),
  )
  await expect.poll(() => providerLogouts).toBe(1)
  await expect.poll(() => documentRequests.length).toBe(2)
  expect(sessionDeletes).toBe(1)
})

test("logout rejects a stale session response released after local deletion", async ({
  page,
}) => {
  let sessionDeletes = 0
  let releasePost: (() => void) | undefined
  let markPostProcessed: (() => void) | undefined
  const postProcessed = new Promise<void>(resolve => {
    markPostProcessed = resolve
  })
  await page.route(bridgePattern, route =>
    route.fulfill({body: delayedReconciliationBridgeStub, contentType: "application/javascript"}),
  )

  await establishLocalSession(page)
  const setupCsrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: setupCsrfToken} = await setupCsrfResponse.json()
  const setupLogout = await page.request.delete("/auth/privy/session", {
    headers: {"x-csrf-token": setupCsrfToken},
  })
  expect(setupLogout.status()).toBe(200)
  await establishLocalSession(page)

  const oldMarker = (
    await page.context().cookies()
  ).find(cookie => cookie.name === "_ash_platform_logout_epoch")?.value
  expect(oldMarker).toBeTruthy()

  page.on("request", request => {
    if (request.method() === "DELETE" && request.url().endsWith("/auth/privy/session")) {
      sessionDeletes += 1
    }
  })
  await page.route("**/auth/privy/session", async route => {
    if (route.request().method() !== "POST") {
      await route.continue()
      return
    }

    expect(route.request().headers().cookie).toContain(
      `_ash_platform_logout_epoch=${oldMarker}`,
    )
    const response = await route.fetch()
    markPostProcessed?.()
    await new Promise<void>(resolve => {
      releasePost = resolve
    })
    await route.fulfill({response})
  })
  await page.goto("/app")
  await postProcessed
  await page.locator("#account-menu summary").click()
  await page.getByRole("button", {name: "Log Out"}).click()

  await expect.poll(() => sessionDeletes).toBe(1)
  const newMarker = (
    await page.context().cookies()
  ).find(cookie => cookie.name === "_ash_platform_logout_epoch")?.value
  expect(newMarker).toBeTruthy()
  expect(newMarker).not.toBe(oldMarker)
  const finalSession = await page.request.get("/auth/session")
  expect((await finalSession.json()).authenticated).toBe(false)

  releasePost?.()
  await expect(page.getByRole("button", {name: "Sign In"})).toBeVisible()
  const sessionAfterLateCompletion = await page.request.get("/auth/session")
  expect((await sessionAfterLateCompletion.json()).authenticated).toBe(false)
  expect(sessionDeletes).toBe(1)
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
