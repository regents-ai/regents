import {expect, test} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The site header runs the full width over the side panel, and the panel opens under
// its bottom line at every width: beside the page on a wide screen, over it below that,
// and over the whole page on a phone.
test("the side panel opens under the header", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()

  for (const width of [2000, 1280, 800, 390]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/account")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    const aside = page.locator("#shell-aside")
    if (!(await aside.isVisible())) await page.locator("#shell-aside-button").click()
    await expect(aside).toBeVisible()
    // Measured once the panel has finished sliding in.
    const sliding = () =>
      page.evaluate(() => document.getAnimations().filter(a => a instanceof CSSTransition).length)
    await expect.poll(sliding).toBe(0)

    const header = (await page.locator("#shell-header").boundingBox())!
    const panel = (await aside.boundingBox())!
    expect(panel.y, `at ${width} wide`).toBeCloseTo(header.y + header.height, 0)
    expect(panel.x).toBeLessThan(header.x + header.width)
    expect(panel.x + panel.width).toBeGreaterThan(header.x)
  }
})

// On a phone the menu and its backdrop also open under the header's line.
test("the phone menu opens under the header", async ({page}) => {
  await page.setViewportSize({width: 390, height: 844})
  await page.goto("/stake")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await page.locator(".mobile-menu-button").click()
  const menu = page.locator("#shell-sidebar")
  await expect(menu).toBeVisible()

  const header = (await page.locator("#shell-header").boundingBox())!
  const line = header.y + header.height
  expect((await menu.boundingBox())!.y).toBeCloseTo(line, 0)
  expect((await page.locator(".shell-menu-scrim").boundingBox())!.y).toBeCloseTo(line, 0)
})
