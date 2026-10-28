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

// Ported from the template's layers check of 27 Oct. regents.sh has no bottom bar,
// so on a phone the open menu and side panel are checked against the page's foot
// and the account's note. Before the layers cutover the side panel took a higher
// place than the header, so a "Sign out couldn't finish" note pressed from the
// panel opened behind it, unseen.
test("on a phone, the open menu and side panel cover the page, and the account's note sits over them", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await page.setViewportSize({width: 390, height: 844})
  await page.goto("/stake")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const onTop = (x: number, y: number, selector: string) =>
    page.evaluate(([x, y, selector]) => document.elementFromPoint(x, y)?.closest(selector) !== null, [x, y, selector] as const)
  const sliding = () =>
    page.evaluate(() => document.getAnimations().filter(a => a instanceof CSSTransition).length)
  const foot = 844 - 8

  // The menu covers the page down to the foot of the screen, and past its edge the
  // shade lies over the page.
  await page.locator(".mobile-menu-button").click()
  const menu = page.locator("#shell-sidebar")
  await expect(menu).toBeVisible()
  // It slides in from the left edge; it is measured once it is there.
  await expect.poll(async () => (await menu.boundingBox())!.x).toBeCloseTo(0, 0)
  const drawer = (await menu.boundingBox())!
  expect(await onTop(drawer.x + 8, foot, "#shell-sidebar")).toBe(true)
  expect(await onTop(drawer.x + drawer.width + 8, foot, ".shell-menu-scrim")).toBe(true)
  await page.locator("[data-shell-menu-close]").click()
  await expect(menu).toBeHidden()

  // The side panel covers the page down to the foot of the screen.
  await page.locator("#shell-aside-button").click()
  const aside = page.locator("#shell-aside")
  await expect(aside).toBeVisible()
  await expect.poll(sliding).toBe(0)
  expect(await onTop(195, foot, "#shell-aside")).toBe(true)

  // Sign out pressed in the panel while the site cannot be reached: its note shows
  // over the panel.
  await page.route("**/auth/privy/session", route =>
    route.request().method() === "DELETE" ? route.abort() : route.fallback(),
  )
  await aside.locator("[data-account-target='sign-out']").click()
  const note = page.locator("#account-auth-status")
  await expect(note).toHaveText("Sign out couldn’t finish. Try again.")
  // The note lets presses through to what is under it, so it takes them for this
  // one reading.
  const box = (await note.boundingBox())!
  await note.evaluate(element => (element.style.pointerEvents = "auto"))
  expect(await onTop(box.x + box.width / 2, box.y + box.height / 2, "#account-auth-status")).toBe(true)
})

// From the keyboard, the first Tab on a page shows "Skip to content" over the
// header, and Enter moves on to the page itself.
test("the first Tab shows Skip to content over the header", async ({page}) => {
  for (const width of [1280, 390]) {
    await page.setViewportSize({width, height: 844})
    await page.goto("/stake")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await page.keyboard.press("Tab")
    const skip = page.getByRole("link", {name: "Skip to content"})
    await expect(skip).toBeFocused()
    const box = (await skip.boundingBox())!
    expect(
      await page.evaluate(([x, y]) => document.elementFromPoint(x, y)?.closest(".shell-skip") !== null, [
        box.x + box.width / 2,
        box.y + box.height / 2,
      ] as const),
      `at ${width} wide`,
    ).toBe(true)
    await page.keyboard.press("Enter")
    await expect(page).toHaveURL(/#route-content$/)
    await page.keyboard.press("Tab")
    await expect(page.locator("#route-content :focus")).toHaveCount(1)
  }
})
