import {expect, test} from "@playwright/test"

const bridgePattern =
  /\/assets\/js\/privy_bridge(?:-[a-f0-9]{32})?\.js\?(?:vsn=d&)?regent_retry=\d+$/

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
        const csrf = await fetch("/auth/csrf", {credentials: "same-origin"}).then(response => response.json())
        await fetch("/auth/privy/session", {
          method: "DELETE",
          credentials: "same-origin",
          headers: {"x-csrf-token": csrf.csrf_token}
        })
        await window.__u3ProviderLogout()
        window.location.reload()
      }
    })
  })
}
`

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

test("sign-in retries failed deferred bridge loads with fresh module URLs", async ({page}) => {
  const bridgeRequests: string[] = []
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
  const status = page.locator("#account-auth-status")
  await expect(status).toBeHidden()

  await page.getByRole("button", {name: "Sign In"}).click()
  await expect(status).toBeVisible()
  await expect(status).toHaveText("Sign in couldn’t start. Try again.")

  await page.getByRole("button", {name: "Sign In"}).click()
  await expect(status).toBeVisible()
  await expect(status).toHaveText("Sign in couldn’t start. Try again.")

  await page.getByRole("button", {name: "Sign In"}).click()
  await expect(status).toBeHidden()
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as Window & {__u3BridgeCalls?: string[]}).__u3BridgeCalls ?? [],
      ),
    )
    .toEqual(["sign-in"])

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

  const csrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: csrfToken} = await csrfResponse.json()
  const sessionResponse = await page.request.post("/auth/privy/session", {
    headers: {authorization: "Bearer valid", "x-csrf-token": csrfToken},
    data: {},
  })
  expect(sessionResponse.status()).toBe(200)

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

  const csrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: csrfToken} = await csrfResponse.json()
  expect(
    (
      await page.request.post("/auth/privy/session", {
        headers: {authorization: "Bearer valid", "x-csrf-token": csrfToken},
        data: {},
      })
    ).status(),
  ).toBe(200)

  await page.goto("/app")
  await expect(page.locator("#account-menu [data-account-target='identity']")).toBeVisible()
  await page.locator("#account-menu summary").click()
  await page.getByRole("button", {name: "Log Out"}).click()
  expect(sessionDeletes).toBe(0)

  await page.evaluate(() =>
    (window as Window & {__u3ReadyBridge?: () => void}).__u3ReadyBridge?.(),
  )
  await expect.poll(() => sessionDeletes).toBe(1)
  await expect.poll(() => providerLogouts).toBe(1)
  await expect.poll(() => documentRequests.length).toBe(2)
})
