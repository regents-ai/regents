import {expect, test} from "./support/offline"

// DOCS: a reader finds a topic with the search box, reaches every docs page from
// the sidebar on a phone and a computer, copies or opens the page as Markdown,
// and no docs page is wider than the screen.
test("[DOCS] search finds a topic and opens it at its heading", async ({page}) => {
  await page.setViewportSize({width: 1280, height: 900})
  await page.goto("/docs/pairing")

  await page.keyboard.press("/")
  await expect(page.locator("#docs-search-input")).toBeFocused()
  await page.keyboard.type("rate limit")
  await expect(page.locator("#docs-search-results [role=option]").first()).toContainText("Limits")
  await page.keyboard.press("Enter")
  await expect(page).toHaveURL(/\/docs\/limits#/)

  await page.keyboard.press("Control+k")
  await page.keyboard.type("zzqx")
  await expect(page.locator("#docs-search-results")).toContainText("No results")
  await page.keyboard.press("Escape")
  await expect(page.locator("#docs-search-results")).toBeHidden()
})

test("[DOCS] Copy for LLM and View as Markdown give the page's Markdown", async ({page, context}) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"])
  await page.setViewportSize({width: 1280, height: 900})
  await page.goto("/docs/errors")

  await page.getByRole("button", {name: "Copy for LLM"}).click()
  await expect(page.locator("#docs-copy")).toHaveAttribute("data-copy-state", "copied")
  expect(await page.evaluate(() => navigator.clipboard.readText())).toMatch(/^# Errors\n/)

  const [markdown] = await Promise.all([
    context.waitForEvent("page"),
    page.getByRole("button", {name: "View as Markdown"}).click(),
  ])
  await expect(markdown.locator("body")).toContainText("# Errors")
  await markdown.close()
})

for (const width of [390, 1280]) {
  test(`[DOCS] every docs page is reached from the sidebar and fits at ${width} wide`, async ({page}) => {
    await page.setViewportSize({width, height: 900})
    await page.goto("/docs")
    const paths = await page.locator(".docs-nav__group a").evaluateAll(links => links.map(link => link.getAttribute("href")))
    expect(paths.length).toBeGreaterThan(10)

    for (const path of paths.slice(1)) {
      if (width === 390) await page.getByRole("button", {name: "Menu"}).click()
      const link = page.locator(`#docs-nav a[href="${path}"]`)
      if (!(await link.isVisible())) await link.locator("xpath=ancestor::details[1]/summary").click()
      await link.click()
      await expect(page).toHaveURL(new RegExp(`${path}$`))
      await expect(page.locator("h1.docs-title")).toBeVisible()
      await expect(page.locator("#docs-nav")).toBeVisible({visible: width !== 390})
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
    }
  })
}
