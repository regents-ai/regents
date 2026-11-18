import {cloakInstaller as installer, expect, test} from "./support/offline"

// CLOAK_PAGE: a visitor on a phone presses Download for Mac on /cloak and lands
// on /cloak/download, where the installer starts by itself without taking focus
// and the two install steps show; they leave an email address for news from the
// keyboard and are thanked, and neither page is wider than the screen. The
// installer's address answers with a stand-in file (support/offline.ts), so the
// walk never depends on the real one.
test("[CLOAK] Download for Mac starts the installer and shows the steps on a phone", async ({page}) => {
  const sideways = () => page.evaluate(() => document.documentElement.scrollWidth)

  await page.setViewportSize({width: 390, height: 900})
  await page.goto("/cloak")
  await expect(page.locator("#cloak-page .product-proof")).toHaveCount(6)
  expect(await sideways()).toBeLessThanOrEqual(390)

  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  const started = page.waitForEvent("download")
  await page.getByRole("link", {name: "Download for Mac"}).click()
  await expect(page).toHaveURL(/\/cloak\/download$/)
  expect((await started).url()).toBe(installer)

  const direct = page.getByRole("link", {name: "Download it directly"})
  await expect(direct).toHaveAttribute("href", installer)
  await expect(direct).not.toBeFocused()
  await expect(page.getByRole("heading", {level: 1})).toBeVisible()
  await expect(page.locator(".cloak-steps > li")).toHaveCount(2)
  for (const step of await page.locator(".cloak-steps > li").all()) await expect(step).toBeVisible()
  expect(await sideways()).toBeLessThanOrEqual(390)

  const again = page.waitForEvent("download")
  await direct.click()
  expect((await again).url()).toBe(installer)

  const updates = page.locator("#cloak-updates")
  const address = updates.getByRole("textbox", {name: "Email"})
  await address.fill(`cloak-${Date.now()}@example.com`)
  await address.press("Enter")
  await expect(updates.getByRole("status").locator("#cloak-updates-done")).toBeVisible()
  await expect(page.locator("#cloak-updates-form")).toHaveCount(0)
  expect(await sideways()).toBeLessThanOrEqual(390)
})
