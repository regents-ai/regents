import {expect, test} from "./support/offline"

// CLOAK_PAGE: a visitor on a phone sees the download off with its reason beside
// it, leaves an email address for updates from the keyboard and is thanked, and
// the page is no wider than the screen.
test("[CLOAK] the Cloak page fits and reads on a phone", async ({page}) => {
  await page.setViewportSize({width: 390, height: 900})
  await page.goto("/cloak")

  const download = page.getByRole("button", {name: "Download for Mac"})
  await expect(download).toBeVisible()
  await expect(download).toBeDisabled()
  await expect(page.locator("#cloak-download-soon")).toBeVisible()
  await expect(page.locator("#cloak-page .product-proof")).toHaveCount(6)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)

  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const updates = page.locator("#cloak-updates")
  const address = updates.getByRole("textbox", {name: "Email"})
  await address.fill(`cloak-${Date.now()}@example.com`)
  await address.press("Enter")
  await expect(updates.getByRole("status").locator("#cloak-updates-done")).toBeVisible()
  await expect(page.locator("#cloak-updates-form")).toHaveCount(0)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
})
