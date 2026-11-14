import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// Forms and scales (ash-template's forms rollout, 12 Nov 2026): a field is checked
// when the person leaves it and on submit, never while they type, and its error line
// keeps its room so nothing below it moves; the docs tables stand as cards under
// 768px; on a touch screen every press is at least 44px.
async function signIn(page: Page, path: string) {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await page.goto(path)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
}

// Errors the page throws while the walk runs.
function watch(page: Page) {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  return {expect: async () => expect(errors).toEqual([])}
}

const top = (page: Page, selector: string) =>
  page.locator(selector).evaluate(element => element.getBoundingClientRect().top)

for (const width of [1280, 390, 320]) {
  test(`a name is checked when the person leaves the field, not while typing (${width})`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 900})
    await signIn(page, "/account/names")
    const input = page.locator("#account-claim-name")
    const errors = page.locator("#account-claim-name-errors")
    const below = await top(page, "#account-claim-submit")

    await input.fill("ab")
    await page.waitForTimeout(600)
    await expect(errors).toBeEmpty()
    await expect(input).not.toHaveAttribute("aria-invalid", "true")

    await input.blur()
    await expect(errors).toContainText("Use at least 3 characters.")
    await expect(input).toHaveAttribute("aria-invalid", "true")
    expect(await top(page, "#account-claim-submit")).toBe(below)
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
    await problems.expect()
  })
}

test("under 768px a docs table stands as one card a row, each cell naming its column", async ({page}) => {
  const problems = watch(page)
  await page.setViewportSize({width: 390, height: 900})
  await signIn(page, "/docs/errors")
  const table = page.locator(".docs-table table").first()
  await expect(table).toHaveAttribute("role", "table")
  const cell = table.locator("tbody td").first()
  await expect(cell).toHaveAttribute("role", "cell")
  await expect(cell).toHaveAttribute("data-label", "Status")
  expect(await cell.evaluate(element => getComputedStyle(element, "::before").content)).toBe('"Status"')
  expect(await table.locator("thead").evaluate(element => element.getBoundingClientRect().height)).toBeLessThanOrEqual(1)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)

  await page.setViewportSize({width: 1280, height: 900})
  expect(await table.locator("thead").evaluate(element => element.getBoundingClientRect().height)).toBeGreaterThan(1)
  await problems.expect()
})

test.describe("on a touch phone", () => {
  test.use({hasTouch: true, isMobile: true, viewport: {width: 390, height: 844}})

  test("every press on the Account and docs pages is at least 44px", async ({page}) => {
    const problems = watch(page)
    await signIn(page, "/account")
    for (const path of ["/account", "/account/agents", "/docs/errors"]) {
      await page.goto(path)
      await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
      const small = await page.evaluate(() =>
        [...document.querySelectorAll<HTMLElement>("a[href], button, summary, select")]
          .filter(element => {
            const box = element.getBoundingClientRect()
            if (box.width === 0 || box.height === 0) return false
            // A link inside a sentence keeps the sentence's line (WCAG 2.5.8's inline exception).
            if (element.closest("p, li > p, td")) return false
            return box.height < 44 || box.width < 44
          })
          .map(element => `${element.tagName} ${element.textContent?.trim().slice(0, 30)}`),
      )
      expect(small, path).toEqual([])
    }
    await problems.expect()
  })
})
