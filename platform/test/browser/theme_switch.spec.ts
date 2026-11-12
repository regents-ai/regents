import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The light and dark switch (Shell.theme_toggle/1), from ash-template's theme switch
// rollout (12 Nov 2026). It is a real switch, on for the light theme: a press, Space
// or Enter turns the page's theme once, the choice holds over a reload and a live
// page change, and the account menu keeps its size whichever way it is turned.
// Signed in it is a row of the account menu; signed out it sits in the app's header,
// and on a plain page in the footer. A page has one switch, never two.

// The theme on screen: the page's own once chosen, otherwise the device's.
const showing = (page: Page) =>
  page.evaluate(() => {
    const theme = document.documentElement.dataset.theme
    if (theme === "light" || theme === "dark") return theme
    return matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"
  })

// Errors the page throws while the walk runs.
function watch(page: Page) {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  return {expect: async () => expect(errors).toEqual([])}
}

const ready = (page: Page) =>
  expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

const sideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

for (const width of [1280, 390, 320]) {
  test(`signed in, the account menu's switch turns the theme by press and by key, and the choice holds (${width})`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 800})
    const auth = await installAuthenticatedPrivy(page, "valid")
    await auth.establishLocalSession()
    await page.goto("/app")
    await ready(page)
    await expect(page.locator("[data-theme-switch]")).toHaveCount(1)

    const menu = page.locator("#account-menu")
    const toggle = menu.getByRole("switch", {name: "Light theme"})
    const openMenu = async () => {
      await page.locator("#account-chip").click()
      await expect(menu).toBeVisible()
      await expect.poll(() => menu.evaluate(element => element.getAnimations().length)).toBe(0)
    }
    const expectTheme = async (theme: "light" | "dark") => {
      await expect.poll(() => showing(page)).toBe(theme)
      await expect(toggle).toHaveAttribute("aria-checked", String(theme === "light"))
    }
    const size = async () => {
      const box = (await menu.boundingBox())!
      return {width: box.width, height: box.height}
    }

    const content = page.locator("#route-content")
    const before = await content.boundingBox()
    await openMenu()
    expect(await content.boundingBox()).toEqual(before)

    const first = await showing(page)
    const other = first === "light" ? "dark" : "light"
    await expectTheme(first)
    const opened = await size()

    await toggle.click()
    await expectTheme(other)
    await expect(menu).toBeVisible()
    expect(await size()).toEqual(opened)

    await toggle.focus()
    await page.keyboard.press("Space")
    await expectTheme(first)
    await page.keyboard.press("Enter")
    await expectTheme(other)
    expect(await size()).toEqual(opened)
    expect(await sideways(page)).toBeLessThanOrEqual(0)

    await page.reload()
    await ready(page)
    await expect.poll(() => page.evaluate(() => document.documentElement.dataset.theme)).toBe(other)
    await openMenu()
    await expectTheme(other)

    // Manage Account is a live page change: the document stays and restates its theme.
    await menu.getByRole("link", {name: "Manage Account"}).click()
    await expect(page).toHaveURL(/\/account$/)
    await expect.poll(() => page.evaluate(() => document.documentElement.dataset.theme)).toBe(other)
    await openMenu()
    await expectTheme(other)
    await problems.expect()
  })
}

// Signed out there is no account menu: the switch sits in the app's header, and in
// the footer of a plain page, which no live view draws. Each press turns it once.
for (const path of ["/app", "/privacy"]) {
  for (const width of [1280, 320]) {
    test(`signed out, the theme switch on ${path} turns the theme once a press (${width})`, async ({page}) => {
      const problems = watch(page)
      await page.setViewportSize({width, height: 800})
      await page.goto(path)
      const bar = page.getByRole("switch", {name: "Light theme"})
      await expect(bar).toHaveCount(1)
      const first = await showing(page)
      const other = first === "light" ? "dark" : "light"
      await expect(bar).toHaveAttribute("aria-checked", String(first === "light"))

      await bar.click()
      await expect.poll(() => showing(page)).toBe(other)
      await expect(bar).toHaveAttribute("aria-checked", String(other === "light"))

      await bar.focus()
      await page.keyboard.press("Space")
      await expect.poll(() => showing(page)).toBe(first)
      await expect(bar).toHaveAttribute("aria-checked", String(first === "light"))
      await page.keyboard.press("Enter")
      await expect.poll(() => showing(page)).toBe(other)

      await page.reload()
      await expect.poll(() => showing(page)).toBe(other)
      await expect(bar).toHaveAttribute("aria-checked", String(other === "light"))
      expect(await sideways(page)).toBeLessThanOrEqual(0)
      await problems.expect()
    })
  }
}
