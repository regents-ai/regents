import {expect, test} from "./support/offline"

// CLOAK_PAGE: a visitor on a phone sees the download off with its reason beside
// it, and the page is no wider than the screen.
test("[CLOAK] the Cloak page fits and reads on a phone", async ({page}) => {
  await page.setViewportSize({width: 390, height: 900})
  await page.goto("/cloak")

  const download = page.getByRole("button", {name: "Download for Mac"})
  await expect(download).toBeVisible()
  await expect(download).toBeDisabled()
  await expect(page.locator("#cloak-download-soon")).toBeVisible()
  await expect(page.locator("#cloak-page .product-proof")).toHaveCount(6)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
})
