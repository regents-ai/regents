import {expect, test, type Page} from "@playwright/test"

const shellRoutes = [
  "/app",
  "/formation",
  "/regents/regent",
  "/techtree",
  "/techtree/nodes/node-1",
  "/techtree/genebench-pro-reference-lab",
  "/autolaunch",
  "/autolaunch/auctions",
  "/autolaunch/auctions/auction-1",
  "/autolaunch/tokens",
  "/autolaunch/tokens/token-1",
  "/autolaunch/create",
  "/stake",
  "/redeem",
]

async function switchApplication(page: Page, label: string) {
  await page.locator("#app-selector summary").click()
  await page.locator("#app-selector-menu").getByRole("link", {name: label}).click()
}

test("all approved routes render within their page budget", async ({page, request}) => {
  const home = await request.get("/")
  expect(home.status()).toBe(200)
  expect((await home.body()).byteLength).toBeLessThanOrEqual(100 * 1024)

  for (const route of shellRoutes) {
    const response = await request.get(route)
    expect(response.status(), route).toBe(200)
    expect((await response.body()).byteLength, route).toBeLessThanOrEqual(100 * 1024)
  }

  await page.goto("/app")
  await expect(page.locator("#app-shell")).toBeVisible()
})

test("anonymous Sign In stays separate from the app selector", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const appSelector = page.getByRole("navigation", {name: "Applications"})
  const accountControl = page.locator("#account-control")

  await expect(accountControl.getByRole("button", {name: "Sign In"})).toBeVisible()
  await expect(appSelector.getByRole("button", {name: "Sign In"})).toHaveCount(0)
  await expect(accountControl.getByRole("link", {name: "Formation"})).toHaveCount(0)

  await page.locator("#app-selector summary").click()
  await expect(appSelector.getByRole("link")).toHaveCount(4)
  await expect(appSelector.getByRole("link", {name: "Formation"})).toHaveAttribute(
    "href",
    "/formation",
  )
  await expect(appSelector.getByRole("link", {name: "Autolaunch"})).toHaveAttribute(
    "href",
    "/autolaunch",
  )
  await expect(appSelector.getByRole("link", {name: "Techtree"})).toHaveAttribute(
    "href",
    "/techtree",
  )
  await expect(appSelector.getByRole("link", {name: "Regents Labs"})).toHaveAttribute(
    "href",
    "/app",
  )
  await page.locator("#app-selector summary").click()

  await page.evaluate(() => {
    const link = document.createElement("a")
    link.href = "/settings"
    link.textContent = "Anonymous Settings patch"
    link.dataset.phxLink = "patch"
    link.dataset.phxLinkState = "push"
    document.querySelector("#shell-header")?.append(link)
  })
  await page.getByRole("link", {name: "Anonymous Settings patch"}).click()
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole("heading", {name: "Settings"})).toHaveCount(0)
  await expect(page.getByRole("heading", {name: "Appearance"})).toHaveCount(0)

  await page.goto("/settings")
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole("heading", {name: "Settings"})).toHaveCount(0)
  await expect(page.getByRole("heading", {name: "Appearance"})).toHaveCount(0)
})

test("signed-in Settings is a real account route with browser-local Appearance", async ({page}) => {
  const csrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: csrfToken} = await csrfResponse.json()

  const sessionResponse = await page.request.post("/auth/privy/session", {
    headers: {
      authorization: "Bearer valid",
      "x-csrf-token": csrfToken,
    },
    data: {},
  })
  expect(sessionResponse.status()).toBe(200)

  await page.goto("/app")
  await expect(page.locator("#shell-header [data-theme-choice]")).toHaveCount(0)
  await page.locator("#account-menu summary").click()

  const menuItems = page.locator("#account-menu [data-account-menu-item]")
  await expect(menuItems).toHaveText(["Settings", "Log Out"])

  await page.getByRole("link", {name: "Settings"}).click()
  await expect(page).toHaveURL(/\/settings$/)
  await expect(page.getByRole("heading", {name: "Settings", level: 1})).toBeVisible()
  await expect(page.getByRole("heading", {name: "Appearance", level: 2})).toBeVisible()

  const appearance = page.getByRole("group", {name: "Appearance"})
  await appearance.getByRole("button", {name: "Dark"}).click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  expect(await page.evaluate(() => localStorage.getItem("regent:theme"))).toBe("dark")

  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
})

test("navigation keeps the document and shell identity and starts at the top", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const shellInstance = await page.locator("#app-shell").getAttribute("data-shell-instance")
  await page.evaluate(() => {
    ;(window as Window & {founderShellDocument?: object}).founderShellDocument = {}
    const content = document.querySelector("#route-content")
    content?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })

  await switchApplication(page, "Techtree")
  await expect(page).toHaveURL(/\/techtree$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")

  expect(
    await page.evaluate(() => Boolean((window as Window & {founderShellDocument?: object}).founderShellDocument)),
  ).toBe(true)
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await switchApplication(page, "Autolaunch")
  await expect(page).toHaveURL(/\/autolaunch$/)
  await page.evaluate(() => {
    document
      .querySelector("#route-content")
      ?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })

  await page.goBack()
  await expect(page).toHaveURL(/\/techtree$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await page.evaluate(() => {
    document
      .querySelector("#route-content")
      ?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })
  await page.goForward()
  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)
})

test("Map and List stay local without adding browser history", async ({page}) => {
  await page.goto("/techtree/genebench-pro-reference-lab")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const historyLength = await page.evaluate(() => history.length)
  await page.getByRole("link", {name: "GeneBench-Pro Reference Lab list"}).click()

  await expect(page.locator("#app-shell")).toHaveAttribute("data-presentation", "list")
  expect(await page.evaluate(() => history.length)).toBe(historyLength)
})

test("tree names preserve presentation while explicit selectors force it", async ({page}) => {
  await page.goto("/techtree/genebench-pro-reference-lab")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await page.getByRole("link", {name: "GeneBench-Pro Reference Lab list"}).click()
  await page.getByRole("link", {name: "Question Forge Metaskills", exact: true}).click()

  await expect(page).toHaveURL(/\/techtree\/question-forge-metaskills$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-presentation", "list")

  await page.getByRole("link", {name: "BixBench Capsule Lab map"}).click()
  await expect(page).toHaveURL(/\/techtree\/bixbench-capsule-lab$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-presentation", "map")
})

test("Formation panels remain local and survive LiveView content patches", async ({page}) => {
  await page.goto("/formation")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const historyLength = await page.evaluate(() => history.length)
  await page.getByRole("button", {name: "Billing"}).click()

  await expect(page.locator("#app-shell")).toHaveAttribute("data-formation-panel", "billing")
  expect(await page.evaluate(() => history.length)).toBe(historyLength)
  await expect(page).toHaveURL(/\/formation$/)
  await expect(page.getByRole("heading", {name: "Formation"})).toBeVisible()
  await expect(page.locator("#app-shell")).toHaveAttribute("data-formation-panel", "billing")
})

test("reduced motion applies immediately and Appearance stays out of the shell", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  await expect(page.locator("html")).toHaveAttribute("data-reduced-motion", "true")
  await expect(page.locator("#shell-header [data-theme-choice]")).toHaveCount(0)
  await context.close()
})

test("the 320px menu contains focus, isolates content, and closes without overflow", async ({
  page,
}) => {
  await page.setViewportSize({width: 320, height: 640})
  await page.goto("/techtree")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const menu = page.getByRole("button", {name: "Menu"})
  const sidebar = page.getByRole("navigation", {name: "Context navigation"})
  const scrim = page.getByRole("button", {name: "Close navigation"})
  const scroller = page.locator("#app-shell-scroller")
  const firstTarget = sidebar.getByRole("link", {
    name: "GeneBench-Pro Reference Lab",
    exact: true,
  })
  const lastTarget = sidebar.getByRole("link", {name: "Skill Training Lab list"})

  await menu.click()
  await expect(menu).toHaveAttribute("aria-expanded", "true")
  await expect(sidebar).toBeVisible()
  await expect(scrim).toBeVisible()
  await expect(firstTarget).toBeFocused()
  expect(await scroller.evaluate(element => element.inert)).toBe(true)

  await page.keyboard.press("Shift+Tab")
  await expect(lastTarget).toBeFocused()
  await page.keyboard.press("Tab")
  await expect(firstTarget).toBeFocused()

  await page.keyboard.press("Escape")
  await expect(menu).toHaveAttribute("aria-expanded", "false")
  await expect(menu).toBeFocused()
  await expect(sidebar).toBeHidden()
  await expect(scrim).toBeHidden()
  expect(await scroller.evaluate(element => element.inert)).toBe(false)

  await menu.click()
  await expect(firstTarget).toBeFocused()
  await firstTarget.click()
  await expect(page).toHaveURL(/\/techtree\/genebench-pro-reference-lab$/)
  await expect(menu).toHaveAttribute("aria-expanded", "false")
  await expect(sidebar).toBeHidden()
  await expect(menu).toBeFocused()

  await menu.click()
  await expect(scrim).toBeVisible()
  await scrim.click({position: {x: 310, y: 20}})
  await expect(menu).toHaveAttribute("aria-expanded", "false")
  await expect(menu).toBeFocused()
  await expect(scrim).toBeHidden()

  expect(
    await page.evaluate(() => ({
      documentWidth: document.documentElement.scrollWidth,
      viewportWidth: window.innerWidth,
    })),
  ).toEqual({documentWidth: 320, viewportWidth: 320})
  await expect(page.getByRole("banner")).toHaveCount(1)
  await expect(page.getByRole("main")).toHaveCount(1)
})

test("content errors and crashes do not remove shell controls", async ({page}) => {
  for (const route of ["/regents/fixture-error", "/regents/fixture-crash"]) {
    await page.goto(route)
    await expect(page.getByRole("alert")).toContainText("could not be loaded")
    await expect(page.locator("#app-selector summary")).toBeVisible()
    await expect(page.getByRole("button", {name: "Sign In"})).toBeVisible()
    await page.locator("#app-selector summary").click()
    await expect(
      page.locator("#app-selector-menu").getByRole("link", {name: "Techtree"}),
    ).toBeVisible()
  }
})
