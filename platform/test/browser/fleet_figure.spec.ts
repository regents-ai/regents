import {expect, test, type Page} from "./support/offline"

// The home page's web of cards: five cards, each a name and a slogan, joined
// by six labelled lines. It stays in the top half of the first screen, no card
// or label covers another at any width, and without a GPU frame the still
// lines are the picture.

const figure = (page: Page) => page.locator("#fleet-figure")
const cards = (page: Page) => figure(page).locator("[data-card]")
const words = (page: Page) => figure(page).locator("[data-line]")

type Box = {x: number; y: number; width: number; height: number}

const overlaps = (a: Box, b: Box) =>
  a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height

for (const [width, height] of [
  [1440, 900],
  [1024, 768],
  [390, 844],
  [320, 640],
]) {
  test(`cards and labels stand clear of each other (${width})`, async ({page}) => {
    await page.setViewportSize({width, height})
    await page.goto("/")

    await expect(cards(page)).toHaveCount(5)
    await expect(words(page)).toHaveCount(6)

    const boxes = [
      ...(await cards(page).evaluateAll(els => els.map(el => el.getBoundingClientRect().toJSON()))),
      ...(await words(page).evaluateAll(els => els.map(el => el.getBoundingClientRect().toJSON()))),
    ] as Box[]
    const map = (await figure(page).locator(".fleet-web__map").boundingBox())!

    boxes.forEach((box, i) => {
      expect(box.x).toBeGreaterThanOrEqual(map.x - 1)
      expect(box.x + box.width).toBeLessThanOrEqual(map.x + map.width + 1)
      expect(box.y).toBeGreaterThanOrEqual(map.y - 1)
      expect(box.y + box.height).toBeLessThanOrEqual(map.y + map.height + 1)
      boxes.slice(i + 1).forEach((other, j) => {
        expect(overlaps(box, other), `items ${i} and ${i + j + 1} overlap`).toBe(false)
      })
    })

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
    expect(overflow).toBeLessThanOrEqual(0)
  })
}

test("on a computer the figure fits in the top half of the first screen", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  const map = (await figure(page).locator(".fleet-web__map").boundingBox())!
  expect(map.height).toBeLessThanOrEqual(450)
})

test("each card is a name and a slogan, and opens its app", async ({page}) => {
  await page.goto("/")
  await expect(figure(page).locator('[data-card="keyfleet"]')).toHaveAttribute("href", "/keyfleet")
  await expect(figure(page).locator('[data-card="staking"]')).toHaveAttribute("href", "#staking-actions")
  for (const card of await cards(page).all()) {
    await expect(card.locator("> span")).toHaveCount(2)
  }
})

test("without a GPU frame the still lines are the picture", async ({page}) => {
  await page.goto("/")
  await expect(figure(page)).toHaveAttribute("data-fleet-ready", "false")
  await expect(figure(page).locator(".fleet-web__still")).toBeVisible()
  await expect(figure(page).locator(".fleet-web__canvas")).toBeHidden()
})
