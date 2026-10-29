import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The account menu, opened by the account's button at the top right of every page.
// The walk's person has four agents (Regents.BrowserAgents) and none has been
// active, so the menu shows the three paired last and leaves out Spare Agent, paired
// first. Manage beside the heading opens the agents on the Account page; with a
// mouse it shows while the pointer is over the list or a key has moved into it, and
// the rows never move when it does. Ported from ash-template's account_menu.spec.ts.
async function signIn(page: Page, path = "/stake") {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await page.goto(path)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
}

// Errors the page throws while the walk runs.
function watch(page: Page) {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  return {expect: async () => expect(errors).toEqual([])}
}

const menu = (page: Page) => page.locator("#account-menu")

// Opened, and done dropping in, so what is measured is where it rests.
async function openMenu(page: Page) {
  await page.locator("#account-chip").click()
  await expect(menu(page)).toBeVisible()
  await expect.poll(() => menu(page).evaluate(element => element.getAnimations().length)).toBe(0)
}

test("the account menu shows three agents and Manage", async ({page}) => {
  const problems = watch(page)
  await signIn(page)
  await openMenu(page)
  const agents = page.locator("#shell-agents")

  await expect(agents.getByRole("listitem")).toHaveCount(3)
  await expect(agents).not.toContainText("Spare Agent")

  const manage = agents.getByRole("link", {name: "Manage your agents"})
  await expect(manage).toHaveText("Manage")
  await expect(manage).toHaveAttribute("href", "/account#account-agents")
  const opacity = () => manage.evaluate(link => getComputedStyle(link).opacity)

  // Where the rows sit inside the menu.
  const rows = () =>
    agents.getByRole("list").evaluate(list => {
      const box = list.getBoundingClientRect()
      return {top: box.top - list.closest("section")!.getBoundingClientRect().top, height: box.height}
    })
  const before = await rows()
  await agents.getByRole("heading", {name: "Your agents"}).hover()
  await expect.poll(opacity).toBe("1")
  expect(await rows()).toEqual(before)

  // Off the list, still inside the menu, so it stays open.
  await menu(page).locator(".rg-account-menu__name").hover()
  await expect.poll(opacity).toBe("0")
  await manage.focus()
  await expect.poll(opacity).toBe("1")

  await manage.click()
  await expect(page).toHaveURL(/\/account#account-agents$/)
  await problems.expect()
})

test("the account menu hangs under its button and closes on Escape, focus back on the button", async ({page}) => {
  const problems = watch(page)
  await signIn(page)
  for (const width of [2000, 1280, 390, 320]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/stake")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await openMenu(page)

    const chip = (await page.locator("#account-chip").boundingBox())!
    const box = (await menu(page).boundingBox())!
    // Below the button, inside the screen, its right edge near the button's on a
    // wide screen.
    expect(box.y, `at ${width}`).toBeGreaterThanOrEqual(chip.y + chip.height)
    expect(box.x, `at ${width}`).toBeGreaterThanOrEqual(0)
    expect(box.x + box.width, `at ${width}`).toBeLessThanOrEqual(width)
    if (width >= 1280) expect(Math.abs(box.x + box.width - (chip.x + chip.width))).toBeLessThan(2)
    expect(await page.evaluate(() => document.documentElement.scrollWidth), `at ${width}`).toBeLessThanOrEqual(width)

    await menu(page).getByRole("link", {name: "Manage Account"}).focus()
    await page.keyboard.press("Escape")
    await expect(menu(page)).toBeHidden()
    await expect(page.locator("#account-chip")).toBeFocused()
  }
  await problems.expect()
})

test("the account menu opens from the keyboard, is named for the person, and a press outside closes it", async ({page}) => {
  const problems = watch(page)
  await signIn(page)
  await page.locator("#account-chip").focus()
  await page.keyboard.press("Enter")
  await expect(menu(page)).toBeVisible()
  await expect(menu(page)).toHaveRole("region")
  await expect(menu(page)).toHaveAccessibleName(/\S/)
  // A press in the header's empty middle, beside the menu; the stake page below it
  // is full of links that would leave the page.
  const header = (await page.locator("#shell-header").boundingBox())!
  await page.mouse.click(header.x + header.width / 2, header.y + header.height / 2)
  await expect(menu(page)).toBeHidden()
  await problems.expect()
})

// An open section on the page behind keeps its place: Escape is the menu's first.
test("Escape closes the account menu before an open section behind it", async ({page}) => {
  const problems = watch(page)
  await signIn(page)
  await page.locator("#route-content").evaluate(content => {
    const details = document.createElement("details")
    details.open = true
    details.id = "walk-open-section"
    details.innerHTML = "<summary>Section</summary><p>Inside</p>"
    content.prepend(details)
  })
  await openMenu(page)
  await page.keyboard.press("Escape")
  await expect(menu(page)).toBeHidden()
  await expect(page.locator("#walk-open-section")).toHaveAttribute("open", "")
  await problems.expect()
})

test("asked for less motion, the account menu appears at once", async ({page}) => {
  const problems = watch(page)
  await page.emulateMedia({reducedMotion: "reduce"})
  await signIn(page)
  await page.locator("#account-chip").click()
  await expect(menu(page)).toBeVisible()
  expect(await menu(page).evaluate(element => element.getAnimations().length)).toBe(0)
  await problems.expect()
})

for (const width of [1280, 390]) {
  test(`Manage Account opens the Account page and the menu closes at ${width}`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 900})
    await signIn(page)
    await openMenu(page)
    await expect(menu(page).getByRole("button", {name: "Sign out"})).toBeVisible()
    await menu(page).getByRole("link", {name: "Manage Account"}).click()
    await expect(page).toHaveURL(/\/account$/)
    await expect(page.locator("#account-agents")).toBeVisible()
    await expect(menu(page)).toBeHidden()
    await problems.expect()
  })

  test(`Pair New Agent in the menu lands on the Account page's pairing box at ${width}`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 900})
    await signIn(page)
    await openMenu(page)
    await menu(page).getByRole("link", {name: "Pair New Agent"}).click()
    await expect(page).toHaveURL(/\/account#account-pairing$/)
    await expect(menu(page)).toBeHidden()
    await expect(page.locator("#account-pairing")).toBeInViewport()
    // The keyboard starts on the agent choice.
    await expect(page.locator("#account-pairing").getByRole("radio").first()).toBeFocused()

    // Pressed again from the same address after scrolling away, it moves there again.
    await page.locator("#app-shell-scroller").evaluate(scroller => scroller.scrollTo({top: 0}))
    await expect(page.locator("#account-pairing").getByRole("heading", {name: "Pair New Agent"})).not.toBeInViewport()
    await openMenu(page)
    await menu(page).getByRole("link", {name: "Pair New Agent"}).click()
    await expect(menu(page)).toBeHidden()
    await expect(page.locator("#account-pairing")).toBeInViewport()
    await expect(page.locator("#account-pairing").getByRole("radio").first()).toBeFocused()
    await problems.expect()
  })
}

// On a short phone screen the open menu ends inside the screen and scrolls to
// Sign out.
test("on a short phone screen, the account menu reaches Sign out", async ({page}) => {
  await signIn(page)
  for (const width of [390, 320]) {
    await page.setViewportSize({width, height: 360})
    await page.goto("/stake")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await openMenu(page)
    const box = (await menu(page).boundingBox())!
    expect(box.y + box.height, `at ${width}`).toBeLessThanOrEqual(360)
    const signOut = menu(page).getByRole("button", {name: "Sign out"})
    await signOut.scrollIntoViewIfNeeded()
    await expect(signOut).toBeInViewport()
  }
})

// Narrower than 22.5rem the header has no room for the balance, so the account menu
// shows it, in the header's words, and the row opens the same Buy Credits panel.
test("on the narrowest phones the balance is in the account menu and opens Buy Credits", async ({page}) => {
  const problems = watch(page)
  await page.setViewportSize({width: 320, height: 900})
  await signIn(page)
  await expect(page.locator("#shell-credits-button")).toBeHidden()
  await openMenu(page)

  const row = page.locator("#account-menu-credits")
  await expect(row).toBeVisible()
  await expect(row).toContainText("Credits")
  await expect(row).toHaveAccessibleName(/\S/)
  expect((await row.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320)

  await row.click()
  await expect(menu(page)).toBeHidden()
  await expect(page.locator("#shell-credits")).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(page.locator("#shell-credits")).toBeHidden()
  await expect(page.locator("#account-chip")).toBeFocused()
  await problems.expect()
})

for (const width of [390, 1280]) {
  test(`wider than the narrowest phones the balance stays in the header, not the menu, at ${width}`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 900})
    await signIn(page)
    await expect(page.locator("#shell-credits-button")).toBeVisible()
    await openMenu(page)
    await expect(page.locator("#account-menu-credits")).toBeHidden()
    await page.keyboard.press("Escape")
    await page.locator("#shell-credits-button").click()
    await expect(page.locator("#shell-credits")).toBeVisible()
    await problems.expect()
  })
}
