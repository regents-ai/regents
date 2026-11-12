import {chromium} from "@playwright/test"
import {expect, test} from "./support/offline"

// Each product page's six cards, the ones its own site shows, at a desktop and two
// phone widths. The suite's browser draws no GPU picture, so each card stands on its
// still frame: every still arrives, the cards fill the row's columns, each card opens
// its product's site in a new tab, and nothing reaches past the screen's edge.
const products: Record<string, string> = {
  "/patchbay": "patchbay.help",
  "/autolaunch": "autolaunch.sh",
  "/techtree": "techtree.sh",
  "/keyfleet": "keyfleet.ai",
}

for (const [path, host] of Object.entries(products)) {
  for (const {width, columns} of [
    {width: 1280, columns: 3},
    {width: 390, columns: 1},
    {width: 320, columns: 1},
  ]) {
    test(`[U2] ${path} shows its six cards on a ${width}px screen`, async ({page}) => {
      await page.setViewportSize({width, height: 900})
      await page.goto(path)
      await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

      const cards = page.locator("#product-cards > li")
      await expect(cards).toHaveCount(6)

      for (const link of await page.locator("#product-cards a.value-card__face").all()) {
        const href = new URL((await link.getAttribute("href"))!)
        expect(`${href.protocol}//${href.host}`).toBe(`https://${host}`)
        await expect(link).toHaveAttribute("target", "_blank")
      }

      for (const still of await page.locator("#product-cards .value-card__still").all()) {
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
}

// Cloak's four cards, which have no site to open: each still arrives, four cards fill a
// three-across row on a desktop and one column on a phone, a press scrolls to the
// page's Protections, and nothing reaches past the screen's edge.
for (const {width, columns} of [
  {width: 1280, columns: 3},
  {width: 390, columns: 1},
  {width: 320, columns: 1},
]) {
  test(`[U2] /cloak shows its four cards on a ${width}px screen`, async ({page}) => {
    await page.setViewportSize({width, height: 900})
    await page.goto("/cloak")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

    const cards = page.locator("#product-cards > li")
    await expect(cards).toHaveCount(4)

    for (const still of await page.locator("#product-cards .value-card__still").all()) {
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

    await page.locator("#product-cards a.value-card__face").first().click()
    await expect(page).toHaveURL(/\/cloak#protections$/)
    await expect(page.locator("#protections")).toBeInViewport()
  })
}

// A browser that can draw the pictures: the Overview's panels draw from this site's own
// and Cloak's, and each product page's draw from that product's panels, which arrive
// only on a page that shows one. The suite's own browser draws no picture, so this one
// asks for WebGPU, and the test stands aside on a machine whose browser still cannot draw it.
test("[U2] the Overview's panels and each product page's panels draw", async ({}, testInfo) => {
  const drawing = await chromium.launch({
    args: ["--enable-unsafe-webgpu", "--enable-features=Vulkan", "--use-angle=metal"],
  })
  try {
    const context = await drawing.newContext({
      baseURL: testInfo.project.use.baseURL,
      viewport: {width: 1280, height: 900},
    })
    const outside: string[] = []
    await context.route(url => !["127.0.0.1", "localhost"].includes(url.hostname), route => {
      outside.push(route.request().url())
      return route.fulfill({status: 204})
    })
    const page = await context.newPage()
    const panelSets: string[] = []
    page.on("request", request => {
      const set = request.url().match(/\/assets\/js\/(patchbay|autolaunch|techtree|keyfleet|cloak)-\w+\.js$/)
      if (set) panelSets.push(set[1]!)
    })

    const drawn = async (path: string, count = 6) => {
      await page.goto(path)
      await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
      const cards = page.locator(".value-cards > li")
      await expect(cards).toHaveCount(count)
      const flags = []
      for (const card of await cards.all()) {
        await card.scrollIntoViewIfNeeded()
        await expect(card).toHaveAttribute("data-value-card-ready", /^(true|false)$/, {timeout: 20_000})
        flags.push(await card.getAttribute("data-value-card-ready"))
      }
      return flags
    }

    const overview = await drawn("/app")
    test.skip(overview.includes("false"), "this machine's browser cannot draw the pictures")
    expect(overview).toEqual(Array(6).fill("true"))
    expect(panelSets, "product panels the Overview asked for").toEqual(["cloak"])

    for (const path of Object.keys(products)) {
      panelSets.length = 0
      expect(await drawn(path), path).toEqual(Array(6).fill("true"))
      expect(panelSets, `product panels ${path} asked for`).toEqual([path.slice(1)])
    }

    panelSets.length = 0
    expect(await drawn("/cloak", 4), "/cloak").toEqual(Array(4).fill("true"))
    expect(panelSets, "product panels /cloak asked for").toEqual(["cloak"])

    expect(outside, "requests that left the test machine").toEqual([])
  } finally {
    await drawing.close()
  }
})
