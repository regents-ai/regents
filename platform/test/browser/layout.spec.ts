import {expect, test} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

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
// so on a phone the open menu is checked against the page's foot, and the account's
// note against the account menu. Before the layers cutover the account's panel took
// a higher place than the header, so a "Sign out couldn't finish" note opened behind
// it, unseen.
test("on a phone, the open menu covers the page and stills it, and the account's note shows once the account menu closes", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await page.setViewportSize({width: 390, height: 844})
  await page.goto("/stake")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const onTop = (x: number, y: number, selector: string) =>
    page.evaluate(([x, y, selector]) => document.elementFromPoint(x, y)?.closest(selector) !== null, [x, y, selector] as const)
  const foot = 844 - 8

  // The menu covers the page down to the foot of the screen, and past its edge the
  // shade lies over the page. The page behind takes no press, key or scroll.
  await page.locator(".mobile-menu-button").click()
  const menu = page.locator("#shell-sidebar")
  await expect(menu).toBeVisible()
  // It slides in from the left edge; it is measured once it is there.
  await expect.poll(async () => (await menu.boundingBox())!.x).toBeCloseTo(0, 0)
  const drawer = (await menu.boundingBox())!
  expect(await onTop(drawer.x + 8, foot, "#shell-sidebar")).toBe(true)
  expect(await onTop(drawer.x + drawer.width + 8, foot, ".shell-menu-scrim")).toBe(true)
  await expect(page.locator("#app-shell-scroller")).toHaveAttribute("inert", "")
  await page.locator("[data-shell-menu-close]").click()
  await expect(menu).toBeHidden()
  await expect(page.locator("#app-shell-scroller")).not.toHaveAttribute("inert")

  // Sign out pressed in the account menu while the site cannot be reached: the menu
  // closes, so its note shows under the account button with nothing over it.
  await page.route("**/auth/privy/session", route =>
    route.request().method() === "DELETE" ? route.abort() : route.fallback(),
  )
  await page.locator("#account-chip").click()
  const account = page.locator("#account-menu")
  await expect(account).toBeVisible()
  await account.locator("[data-account-target='sign-out']").click()
  await expect(account).toBeHidden()
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
