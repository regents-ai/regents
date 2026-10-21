import {expect, test, type Page} from "./support/offline"
import {
  installAuthenticatedPrivy,
  matchesAuthenticatedPrivyBridgeUrl,
} from "./support/authenticated_privy"

const shellRoutes = [
  "/",
  "/redeem",
]

// The shell holds one live session across every application, so a link to another
// application patches the page it is already on. Content links do this in the product;
// the test raises one so the patch can be exercised from any route.
async function patchTo(page: Page, path: string) {
  await page.evaluate(destination => {
    document.querySelector("#patch-probe")?.remove()
    const link = document.createElement("a")
    link.id = "patch-probe"
    link.href = destination
    link.textContent = destination
    link.dataset.phxLink = "patch"
    link.dataset.phxLinkState = "push"
    document.querySelector("#route-content")?.append(link)
  }, path)

  await page.locator("#patch-probe").click()
}

// Actual ruled-frame surfaces replace all page-background masks.
function readFamily(page: Page) {
  return page.evaluate(() => {
    const shell = document.querySelector("#app-shell")
    return {
      ground: shell && getComputedStyle(shell).backgroundColor,
      text: shell && getComputedStyle(shell).color,
    }
  })
}

async function chooseTheme(page: Page, choice: "light" | "dark") {
  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  // A press chooses the opposite of the theme showing, which before any choice
  // is the device's, so reaching one theme can take a second press.
  for (let press = 0; press < 2; press++) {
    if ((await page.locator("html").getAttribute("data-theme")) === choice) break
    await page.locator("#theme-control [data-theme-toggle]").click()
  }
  await expect(page.locator("html")).toHaveAttribute("data-theme", choice)
}

test("[U2] the ruled shell keeps the Regents palette across pages", async ({page}) => {
  const palette: Record<string, {ground: string | null; text: string | null}> = {}
  for (const choice of ["light", "dark"] as const) {
    await chooseTheme(page, choice)
    for (const route of ["/", "/redeem"]) {
      await page.goto(route)
      await expect(page.locator("html")).toHaveAttribute("data-theme", choice)
      await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
      await expect(page.locator(".shell-background, .shell-background__asset")).toHaveCount(0)
      await expect(page.locator("#app-shell")).toHaveClass(/rg-frame/)
      const colors = await readFamily(page)
      palette[choice] ??= colors
      expect(colors).toEqual(palette[choice])
    }
    await page.goto("/redeem")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    for (const destination of ["/autolaunch", "/"]) {
      await patchTo(page, destination)
      await expect(page).toHaveURL(new RegExp(`${destination}$`))
      await expect.poll(() => readFamily(page)).toEqual(palette[choice])
    }
  }
  expect(palette.light).not.toEqual(palette.dark)
})

test("[U2] direct application loads seed the canonical RegentUI brand", async ({
  page,
  request,
}) => {
  for (const [route, brand] of [
    ["/redeem", "platform"],
    ["/", "platform"],
  ] as const) {
    const served = await (await request.get(route)).text()
    expect(served).toContain(`data-brand="${brand}"`)
    // Nothing chosen yet, so the page carries no theme and the device decides.
    expect(served).not.toMatch(/<html[^>]*data-theme=/)

    await page.goto(route)
    await expect(page.locator("html")).toHaveAttribute("data-brand", brand)
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  }
})

test("product headings use canonical Pixel Square", async ({page}) => {
  await page.goto("/")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  expect(
    await page
      .locator("#staking-page-heading")
      .evaluate(element => getComputedStyle(element).fontFamily),
  ).toContain("Geist Pixel Square")
})

test("all approved routes render within their page budget", async ({page, request}) => {
  const home = await request.get("/")
  expect(home.status()).toBe(200)
  expect((await home.body()).byteLength).toBeLessThanOrEqual(100 * 1024)

  for (const route of shellRoutes) {
    const response = await request.get(route)
    expect(response.status(), route).toBe(200)
    expect((await response.body()).byteLength, route).toBeLessThanOrEqual(100 * 1024)
  }

  // No Regent profile exists here, so a profile address is an honest not-found.
  expect((await request.get("/regents/not-here")).status()).toBe(404)

  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toBeVisible()
})

test("anonymous Sign in stays separate from the brand link", async ({page}) => {
  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const brand = page.locator("#shell-brand")
  const accountControl = page.locator("#account-control")

  await expect(brand).toContainText("Regents Labs")
  await expect(brand).toHaveAttribute("href", "/")
  await expect(brand.getByRole("button")).toHaveCount(0)
  await expect(accountControl.getByRole("button", {name: "Sign in"})).toBeVisible()
  await expect(accountControl.getByRole("link", {name: "Nous Portal"})).toHaveCount(0)
  await expect(accountControl.getByRole("link", {name: "Settings"})).toHaveCount(0)
})

test("a signed-in account without a Regent shows its available account menu", async ({page}) => {
  const ashOrigin = "http://127.0.0.1:4002"
  const hashedBridge = "privy_bridge-0123456789abcdef0123456789abcdef.js"
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `${ashOrigin}/assets/js/privy_bridge.js?regent_retry=1`,
      ashOrigin,
    ),
  ).toBe(true)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `${ashOrigin}/assets/js/${hashedBridge}?vsn=d&regent_retry=2`,
      ashOrigin,
    ),
  ).toBe(true)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      "https://attacker.example/assets/js/privy_bridge.js?regent_retry=1",
      ashOrigin,
    ),
  ).toBe(false)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `https://attacker.example/assets/js/${hashedBridge}?vsn=d&regent_retry=2`,
      ashOrigin,
    ),
  ).toBe(false)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `${ashOrigin}/assets/js/privy_bridge.js?authenticated_privy_original=1`,
      ashOrigin,
    ),
  ).toBe(false)

  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()

  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator("#theme-control [data-theme-toggle]")).toBeVisible()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})

  const account = page.locator("#account-chip")
  await expect(account.locator("img.account-avatar")).toHaveAttribute(
    "src",
    /^data:image\/svg\+xml;base64,/,
  )
  await expect
    .poll(() => account.locator("img.account-avatar").evaluate(image => image.naturalWidth))
    .toBeGreaterThan(0)
  await account.click()
  const panel = page.locator("#shell-account")
  await expect(panel.locator("> *")).toHaveText(["Sign out", "Manage Account"])
  await expect(panel.getByRole("link", {name: "Manage Account", exact: true})).toHaveAttribute(
    "href",
    "/account",
  )
  await expect(panel.getByRole("button", {name: "Sign out"})).toBeVisible()

  await page.emulateMedia({colorScheme: "dark"})
  await expect(page.locator("html")).not.toHaveAttribute("data-theme")
  await page.locator("#theme-control [data-theme-toggle]").click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  expect(await page.evaluate(() => document.cookie)).toContain("regent_theme=light")

  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
})

test("[U2][U6] navigation keeps brand, document, shell identity, and starts at the top", async ({page}) => {
  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  const shellInstance = await page.locator("#app-shell").getAttribute("data-shell-instance")
  await page.evaluate(() => {
    ;(window as Window & {founderShellDocument?: object}).founderShellDocument = {}
    const content = document.querySelector("#route-content")
    content?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })

  await patchTo(page, "/autolaunch")
  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")

  expect(
    await page.evaluate(() => Boolean((window as Window & {founderShellDocument?: object}).founderShellDocument)),
  ).toBe(true)
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await patchTo(page, "/")
  await expect(page).toHaveURL(/:\d+\/$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  await page.evaluate(() => {
    document
      .querySelector("#route-content")
      ?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })

  await page.goBack()
  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await page.evaluate(() => {
    document
      .querySelector("#route-content")
      ?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })
  await page.goForward()
  await expect(page).toHaveURL(/:\d+\/$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)
})

test("rapid app switches settle on the latest view with no motion left behind", async ({page}) => {
  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  await patchTo(page, "/autolaunch")
  await expect(page).toHaveURL(/\/autolaunch$/)
  await patchTo(page, "/")

  await expect(page).toHaveURL(/:\d+\/$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-app", "regent_ops")
  await expect(page.getByRole("heading", {name: "Agents build together. Useful work creates value."})).toBeVisible()
  await expect(page.locator("#route-content"), "the glide tidies up after itself").not.toHaveAttribute("style")
  await expect(page.locator("#route-content")).toHaveCSS("opacity", "1")
})

test("the theme preference applies immediately under reduced motion", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce", colorScheme: "dark"})
  const page = await context.newPage()
  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  // With nothing saved the page carries no theme, the device's dark shows, and
  // the switch says so before it is touched.
  const toggle = page.locator("#theme-control [data-theme-toggle]")
  const darkState = toggle.locator(".rg-theme-toggle__state--dark")
  const lightState = toggle.locator(".rg-theme-toggle__state--light")
  await expect(page.locator("html")).not.toHaveAttribute("data-theme")
  await expect(darkState).toHaveCSS("display", "block")
  await expect(lightState).toHaveCSS("display", "none")

  await toggle.click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await expect(lightState).toHaveCSS("display", "block")
  await expect(darkState).toHaveCSS("display", "none")

  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await expect(lightState).toHaveCSS("display", "block")

  await toggle.click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await context.close()
})

test("before any choice a device that asks for light gets light", async ({browser}) => {
  const context = await browser.newContext({colorScheme: "light"})
  const page = await context.newPage()
  await page.goto("/redeem")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const toggle = page.locator("#theme-control [data-theme-toggle]")
  await expect(page.locator("html")).not.toHaveAttribute("data-theme")
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).colorScheme)).toBe("light")
  await expect(toggle.locator(".rg-theme-toggle__state--light")).toHaveCSS("display", "block")

  // The first press chooses the opposite of what shows.
  await toggle.click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await context.close()
})

for (const width of [320, 390]) {
  test(`${width}px drawer contains focus and cleans up every close path`, async ({page}) => {
    await page.setViewportSize({width, height: 720})
    await page.goto("/redeem")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

    const menu = page.getByRole("button", {name: "Menu"})
    const sidebar = page.getByRole("navigation", {name: "Context navigation"})
    const scrim = page.locator("[data-shell-menu-scrim]")
    const scroller = page.locator("#app-shell-scroller")

    await menu.click()
    await expect(menu).toHaveAttribute("aria-expanded", "true")
    await expect(sidebar).toBeVisible()
    await expect(scrim).toBeVisible()
    await expect(scroller).toHaveAttribute("inert", "")
    expect(await sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)

    await page.keyboard.press("Shift+Tab")
    expect(await sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)
    await page.keyboard.press("Tab")
    expect(await sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)

    await page.keyboard.press("Escape")
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(menu).toBeFocused()
    await expect(scrim).toBeHidden()
    await expect(scroller).not.toHaveAttribute("inert", "")

    await menu.click()
    await scrim.click({position: {x: width - 2, y: 10}})
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(menu).toBeFocused()

    await menu.click()
    await sidebar.getByRole("button", {name: "Close navigation"}).click()
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(menu).toBeFocused()

    await menu.click()
    const destination = sidebar.locator('a[href]:not([href="/redeem"])').first()
    await destination.click()
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(scrim).toBeHidden()
    await expect(scroller).not.toHaveAttribute("inert", "")

    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
    await expect(page.getByRole("banner")).toHaveCount(1)
    await expect(page.getByRole("main")).toHaveCount(1)
  })
}

test("tablet, desktop, and effective 200 percent zoom have no horizontal overflow", async ({page}) => {
  for (const viewport of [
    {width: 768, height: 1024},
    {width: 1280, height: 800},
    {width: 640, height: 900},
  ]) {
    await page.setViewportSize(viewport)
    await page.goto("/redeem")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
      viewport.width,
    )
  }
})
