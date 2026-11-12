import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// A "Pair New Agent" link (/pair?to=<page>): the person pairs their agent there,
// and the message they paste sends the agent to that page once it is paired. A
// link to anywhere but a page on this site opens plain pairing. Ported from
// ash-template's pair_link.spec.ts.
async function signIn(page: Page) {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
}

async function open(page: Page, path: string) {
  await page.goto(path)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
}

// Errors the page throws while the walk runs.
function watch(page: Page) {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  return {expect: async () => expect(errors).toEqual([])}
}

const message = (page: Page) => page.locator("#pair-pairing-box pre")

// The page opens on the list of agents, as the pairing window does. A choice
// closes the list, so the radio is looked for hidden too when its check is read.
async function choose(page: Page, agent: string) {
  const radio = page
    .locator("#pair-pairing-box")
    .getByRole("radio", {name: agent, exact: true, includeHidden: true})
  await expect(page.locator("#pair-pairing-box details")).toHaveAttribute("open", "")
  await radio.locator("xpath=ancestor::label").click()
  await expect(radio).toBeChecked()
}

test("the message sends the agent to the link's page once paired", async ({page}) => {
  const problems = watch(page)
  await signIn(page)
  await open(page, "/pair?to=%2Fstake")
  const start = page.locator("#pair-start a")
  await expect(start).toHaveText(/^https?:\/\/[^/]+\/stake$/)

  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  const text = (await message(page).innerText()).trimEnd()
  expect(text.endsWith(`\nOnce paired, start at ${await start.innerText()}`)).toBe(true)
  await problems.expect()
})

test("a link to another site opens plain pairing", async ({page}) => {
  const problems = watch(page)
  await signIn(page)
  await open(page, "/pair?to=%2F%2Fexample.com")
  await expect(page.locator("#pair-start")).toHaveCount(0)

  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  await expect(message(page)).not.toContainText("Once paired")
  await problems.expect()
})

test("a visitor signs in first, and still sees where their agent will start", async ({page}) => {
  const problems = watch(page)
  await open(page, "/pair?to=%2Fstake")
  await expect(page.locator("#pair-signed-out").getByRole("button", {name: "Sign in"})).toBeVisible()
  await expect(page.locator("#pair-start a")).toHaveText(/\/stake$/)
  await expect(message(page)).toHaveCount(0)
  await problems.expect()
})
