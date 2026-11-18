import type {Page} from "@playwright/test"
import {expect, test} from "./support/offline"
import {card, next, open, standing, title} from "./support/tour"

// The Stake page's guided tour (RegentsWeb.Components.Tour): the first time a
// browser opens Stake it plays by itself, Next rings each of its three parts in
// turn, and Skip, Escape and Done end it for good. The tour only points: every
// link and button of the page off its card takes a press at every step, and
// stake.spec.ts proves a press on Stake under it reaches the wallet. Every other
// walk starts with the tour marked seen (playwright.config.ts); these start with
// nothing kept.
test.use({storageState: {cookies: [], origins: []}})

const steps: [string, string][] = [
  ["Stake", "#staking-actions"],
  ["Share", "#staking-how-split"],
  ["Claim", "#staking-how-claim"],
]

const seen = (page: Page) => page.evaluate(() => localStorage.getItem("regent:tour:stake"))

const frames = (page: Page) =>
  page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))))

// Walks the tour from its first step to Done, checking each step as it goes.
async function walk(page: Page, {still = false} = {}) {
  for (const [index, [name, selector]] of steps.entries()) {
    await expect(title(page)).toHaveText(name)
    // With less motion asked for, the ring is round its part on the next frame,
    // with no glide to it.
    if (still) {
      await frames(page)
      expect((await standing(page, selector)).ringOff).toBeLessThanOrEqual(1.5)
    }
    await expect.poll(async () => (await standing(page, selector)).ringOff).toBeLessThanOrEqual(1.5)
    const now = await standing(page, selector)
    expect(now.covers).toBe(false)
    expect(now.onScreen).toBe(true)
    expect(now.overflow).toBe(false)
    expect(now.blocked).toEqual([])
    await expect(next(page)).toHaveText(index === steps.length - 1 ? "Done" : "Next")
    await next(page).click()
  }
  await expect(card(page)).toBeHidden()
}

test("the first press on Stake plays the tour once, ringing each part in turn, and Done ends it for good", async ({
  page,
}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(card(page)).toHaveCount(0)

  await page.locator("#shell-sidebar a[href='/stake']").click()
  await expect(page).toHaveURL(/\/stake$/)
  await expect(card(page)).toBeVisible()
  await expect(next(page)).toBeFocused()
  await expect(page.locator(".tour__dots > li")).toHaveCount(steps.length)
  await walk(page)
  expect(await seen(page)).toBe("seen")

  await page.reload()
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await frames(page)
  await expect(card(page)).toBeHidden()
})

test("Skip ends the tour and a reload leaves it ended; a browser that keeps nothing sees it again, and Escape ends it", async ({
  page,
}) => {
  await open(page)
  await expect(title(page)).toHaveText("Stake")
  await next(page).click()
  await expect(title(page)).toHaveText("Share")
  await page.locator(".tour [data-tour-back]").click()
  await expect(title(page)).toHaveText("Stake")
  await next(page).click()
  await page.locator(".tour [data-tour-skip]").click()
  await expect(card(page)).toBeHidden()
  expect(await seen(page)).toBe("seen")

  await page.reload()
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await frames(page)
  await expect(card(page)).toBeHidden()

  await page.evaluate(() => localStorage.clear())
  await page.reload()
  await expect(title(page)).toHaveText("Stake")
  await page.keyboard.press("Escape")
  await expect(card(page)).toBeHidden()
  expect(await seen(page)).toBe("seen")
})

test("with less motion asked for, and on a 320 wide phone, the card stays on the screen and the ring is simply there", async ({
  page,
}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.setViewportSize({width: 320, height: 640})
  await open(page)

  await expect(card(page)).toBeVisible()
  await walk(page, {still: true})
  // Less motion keeps the light off: the ring is the page's own lines.
  await expect(page.locator(".tour")).not.toHaveAttribute("data-tour-ready", "true")
})
