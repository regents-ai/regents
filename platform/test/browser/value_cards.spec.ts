import {expect, test} from "./support/offline"

// The Overview's six product cards at a desktop and two phone widths. The suite's
// browser draws no GPU picture, so each card stands on its still frame: every
// still arrives, the cards fill the row's columns, and nothing reaches past the
// screen's edge.
for (const {width, columns} of [
  {width: 1280, columns: 3},
  {width: 390, columns: 1},
  {width: 320, columns: 1},
]) {
  test(`[U2] the Overview's product cards fit a ${width}px screen`, async ({page}) => {
    await page.setViewportSize({width, height: 900})
    await page.goto("/app")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

    const cards = page.locator('ul[aria-label="Products"] > li')
    await expect(cards).toHaveCount(6)

    const stills = page.locator('ul[aria-label="Products"] .value-card__still')
    for (const still of await stills.all()) {
      await still.scrollIntoViewIfNeeded()
      await expect.poll(() => still.evaluate((image: HTMLImageElement) => image.naturalWidth)).toBeGreaterThan(0)
    }

    const lefts = new Set(
      await cards.evaluateAll(items => items.map(item => Math.round(item.getBoundingClientRect().left))),
    )
    expect(lefts.size).toBe(columns)

    expect(
      await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth),
    ).toBe(0)
    const scroller = page.locator("#app-shell-scroller")
    expect(await scroller.evaluate(element => element.scrollWidth - element.clientWidth)).toBe(0)
  })
}
