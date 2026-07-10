import {expect, test} from "@playwright/test"

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

  const appSelector = page.getByRole("navigation", {name: "Applications"})
  const accountControl = page.locator("#account-control")

  await expect(accountControl.getByRole("button", {name: "Sign In"})).toBeVisible()
  await expect(appSelector.getByRole("button", {name: "Sign In"})).toHaveCount(0)
  await expect(accountControl.getByRole("link", {name: "Formation"})).toHaveCount(0)
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

  await page.locator("#shell-header").getByRole("link", {name: "Techtree"}).click()
  await expect(page).toHaveURL(/\/techtree$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")

  expect(
    await page.evaluate(() => Boolean((window as Window & {founderShellDocument?: object}).founderShellDocument)),
  ).toBe(true)
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await page.locator("#shell-header").getByRole("link", {name: "Autolaunch"}).click()
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

test("theme and reduced-motion preferences apply immediately", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  await expect(page.locator("html")).toHaveAttribute("data-reduced-motion", "true")
  await page.getByRole("button", {name: "Dark"}).click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await context.close()
})

test("the 320px menu is keyboard closable and landmarks remain available", async ({page}) => {
  await page.setViewportSize({width: 320, height: 640})
  await page.goto("/techtree")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const menu = page.getByRole("button", {name: "Menu"})
  await menu.click()
  await expect(menu).toHaveAttribute("aria-expanded", "true")
  await expect(page.getByRole("navigation", {name: "Context navigation"})).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(menu).toHaveAttribute("aria-expanded", "false")
  await expect(menu).toBeFocused()
  await expect(page.locator("#shell-sidebar")).toHaveCount(1)
  await expect(page.locator("#shell-sidebar")).toBeHidden()
  await expect(page.getByRole("banner")).toHaveCount(1)
  await expect(page.getByRole("main")).toHaveCount(1)
})

test("content errors and crashes do not remove shell controls", async ({page}) => {
  for (const route of ["/regents/fixture-error", "/regents/fixture-crash"]) {
    await page.goto(route)
    await expect(page.getByRole("alert")).toContainText("could not be loaded")
    await expect(page.locator("#shell-header").getByRole("link", {name: "Techtree"})).toBeVisible()
    await expect(page.getByRole("button", {name: "System"})).toBeVisible()
  }
})
