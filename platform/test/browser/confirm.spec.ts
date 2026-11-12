import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The site's own confirm window asks before an action that can't be undone, never the
// browser's grey box. The walk's "other-account" person has one agent, Leaving Agent
// (Regents.BrowserAgents), which this walk unpairs. Ported from ash-template's
// polls.spec.ts, which presses End in the same window.
async function signIn(page: Page) {
  const auth = await installAuthenticatedPrivy(page, "other-account")
  await auth.establishLocalSession()
  await page.goto("/account/agents")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
}

// Errors the page throws, and any box the browser itself opens, while the walk runs.
function watch(page: Page) {
  const problems: string[] = []
  page.on("pageerror", error => problems.push(error.message))
  page.on("dialog", dialog => {
    problems.push(`the browser asked: ${dialog.message()}`)
    void dialog.dismiss()
  })
  return {expect: async () => expect(problems).toEqual([])}
}

const confirmWindow = (page: Page) => page.locator("#rg-confirm")
const unpair = (page: Page) => page.getByRole("button", {name: "Unpair Leaving Agent"})
const agent = (page: Page) => page.locator("#account-agents").getByText("Leaving Agent")

for (const width of [1280, 390, 320]) {
  test(`Unpair asks in the site's window, and Cancel and Escape keep the agent (${width})`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 800})
    await signIn(page)

    await unpair(page).click()
    await expect(confirmWindow(page)).toBeVisible()
    await expect(confirmWindow(page)).toContainText("Unpair Leaving Agent?")
    await expect(confirmWindow(page).getByRole("button", {name: "Unpair"})).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)

    await confirmWindow(page).getByRole("button", {name: "Cancel"}).click()
    await expect(confirmWindow(page)).toBeHidden()
    await expect(unpair(page)).toBeFocused()
    await expect(agent(page)).toBeVisible()

    await page.keyboard.press("Enter")
    await expect(confirmWindow(page)).toBeVisible()
    await page.keyboard.press("Escape")
    await expect(confirmWindow(page)).toBeHidden()
    await expect(unpair(page)).toBeFocused()
    await expect(agent(page)).toBeVisible()
    await problems.expect()
  })
}

test("Unpair in the window unpairs the agent once", async ({page}) => {
  const problems = watch(page)
  await page.setViewportSize({width: 390, height: 800})
  await signIn(page)

  await unpair(page).click()
  await confirmWindow(page).getByRole("button", {name: "Unpair"}).click()
  await expect(confirmWindow(page)).toBeHidden()
  await expect(unpair(page)).toHaveCount(0)
  await expect(page.locator("#account-agents")).toContainText("Leaving Agent is unpaired.")
  await problems.expect()
})
