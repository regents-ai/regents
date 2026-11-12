import {expect, test} from "./support/offline"

// CLOAK_PAGE and CLOAK_GUIDE: a visitor on a phone sees the
// download off with its reason beside it, goes to the guide in one press, and
// neither page is wider than the screen.
test("[CLOAK] the Cloak page and its guide fit and read on a phone", async ({page}) => {
  await page.setViewportSize({width: 390, height: 900})
  await page.goto("/cloak")

  const download = page.getByRole("button", {name: "Download for Mac"})
  await expect(download).toBeVisible()
  await expect(download).toBeDisabled()
  await expect(page.locator("#cloak-download-soon")).toBeVisible()
  await expect(page.locator("#cloak-page .product-proof")).toHaveCount(6)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)

  await page.getByRole("link", {name: "Set up with your agent"}).click()
  await expect(page).toHaveURL(/\/cloak\/guide$/)
  await expect(page.locator("#cloak-guide h1")).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
})
