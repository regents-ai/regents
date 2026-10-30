import {expect, test} from "./support/offline"

// CLOAK_PAGE and CLOAK_GUIDE: a visitor on a phone or a computer sees the
// download off with its reason beside it, goes to the guide in one press, and
// neither page is wider than the screen.
for (const width of [390, 1280]) {
  test(`[CLOAK] the Cloak page and its guide fit and read at ${width} wide`, async ({page}) => {
    await page.setViewportSize({width, height: 900})
    await page.goto("/cloak")

    const download = page.getByRole("button", {name: "Download for Mac"})
    await expect(download).toBeVisible()
    await expect(download).toBeDisabled()
    await expect(page.locator("#cloak-download-soon")).toBeVisible()
    await expect(page.locator("#cloak-page .product-proof")).toHaveCount(6)
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)

    await page.getByRole("link", {name: "Set up with your agent"}).click()
    await expect(page).toHaveURL(/\/cloak\/guide$/)
    await expect(page.locator("#cloak-guide h1")).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
  })
}
