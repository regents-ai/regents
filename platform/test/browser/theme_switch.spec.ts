import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The light and dark switch (Shell.theme_toggle/1), from ash-template's theme switch
// rollouts (12 and 13 Nov 2026). It is a real switch, on for the light theme: a press,
// Space or Enter turns the page's theme once, the choice holds over a reload and a live
// page change, and the account menu keeps its size whichever way it is turned.
// Signed in it is a row of the account menu; signed out it sits in the app's header,
// and on a plain page in the footer. A page has one switch, never two. The GPU is on,
// as on a visitor's browser, so the grains over the switch draw.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

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

// The grains over the header's switch on /about, signed out, drawn on the GPU: they
// take over from the server's drawing without moving anything, a second press while
// they fly turns them round, and once they rest nothing is drawn. With less motion
// they never draw and the server's switch is the whole of it. /about draws no other
// GPU picture, so every frame counted is the switch's.
test.describe("the grains", () => {
  const control = "#theme-control"
  const field = (page: Page) => page.locator(`${control} .particle-field`)
  const bar = (page: Page) => page.locator(`${control} [role='switch']`)

  /** Where the switch's parts stand: the press, the knob, the grains' box and the drawing showing. */
  const places = (page: Page) =>
    page.evaluate(selector => {
      const root = document.querySelector(selector)!
      const box = (part: string) => {
        const shown = [...root.querySelectorAll(part)].find(element => element.getClientRects().length > 0)!
        const {x, y, width, height} = shown.getBoundingClientRect()
        return {x, y, width, height}
      }
      return {
        press: box("[role='switch']"),
        knob: box(".theme-switch__knob"),
        field: box(".particle-field"),
        drawing: box("svg[data-particle-source]"),
      }
    }, control)

  async function drawn(page: Page) {
    await expect(field(page)).toHaveAttribute("data-particle-ready", "true")
  }

  test("take over from the drawing without moving the switch", async ({page}) => {
    const problems = watch(page)
    // The places as the page first lays the switch out, before any script has run.
    await page.addInitScript(selector => {
      document.addEventListener("DOMContentLoaded", () => {
        const root = document.querySelector(selector)!
        const box = (part: string) => {
          const shown = [...root.querySelectorAll(part)].find(element => element.getClientRects().length > 0)!
          const {x, y, width, height} = shown.getBoundingClientRect()
          return {x, y, width, height}
        }
        ;(window as unknown as {firstPlaces: unknown}).firstPlaces = {
          press: box("[role='switch']"),
          knob: box(".theme-switch__knob"),
          field: box(".particle-field"),
          drawing: box("svg[data-particle-source]"),
        }
      })
    }, control)
    await page.goto("/about")
    await drawn(page)
    const first = await page.evaluate(() => (window as unknown as {firstPlaces: unknown}).firstPlaces)
    expect(await places(page)).toEqual(first)
    await problems.expect()
  })

  test("a second press while the grains fly turns them round", async ({page}) => {
    const problems = watch(page)
    await page.goto("/about")
    await drawn(page)
    const first = await showing(page)
    const other = first === "light" ? "dark" : "light"
    const shapeOf = (theme: string) => (theme === "light" ? "sun" : "moon")

    await bar(page).click()
    await expect.poll(() => showing(page)).toBe(other)
    await expect(field(page)).toHaveAttribute("data-particle-shape", shapeOf(other))
    // Well inside the half second the grains fly for.
    await page.waitForTimeout(120)
    await bar(page).click()
    await expect.poll(() => showing(page)).toBe(first)
    await expect(bar(page)).toHaveAttribute("aria-checked", String(first === "light"))
    await expect(field(page)).toHaveAttribute("data-particle-shape", shapeOf(first))
    await problems.expect()
  })

  test("draw nothing while they rest", async ({page}) => {
    await page.addInitScript(() => {
      const counted = window as unknown as {frames: number}
      counted.frames = 0
      const submit = GPUQueue.prototype.submit
      GPUQueue.prototype.submit = function (buffers) {
        counted.frames += 1
        return submit.call(this, buffers)
      }
    })
    await page.goto("/about")
    await drawn(page)
    await bar(page).click()
    // The flight is over in about half a second.
    await page.waitForTimeout(1500)
    await page.evaluate(() => ((window as unknown as {frames: number}).frames = 0))
    await page.waitForTimeout(10_000)
    expect(await page.evaluate(() => (window as unknown as {frames: number}).frames)).toBe(0)
  })

  test.describe("with less motion", () => {
    test.use({reducedMotion: "reduce"})

    test("never draw, and the server's switch still turns the theme", async ({page}) => {
      await page.goto("/about")
      await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
      await page.waitForTimeout(1500)
      await expect(field(page)).not.toHaveAttribute("data-particle-ready", "true")
      await expect(page.locator(`${control} .particle-field__stage`)).toHaveCSS("visibility", "hidden")
      const drawing = page.locator(`${control} svg[data-particle-source]:visible`)
      await expect(drawing).toHaveCount(1)

      const first = await showing(page)
      await bar(page).click()
      await expect.poll(() => showing(page)).not.toBe(first)
      await expect(drawing).toHaveCount(1)
      await expect(field(page)).not.toHaveAttribute("data-particle-ready", "true")
    })
  })
})
