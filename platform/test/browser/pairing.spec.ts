import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// Pairing an agent, the way a person does it: from the Account page, the account
// menu or the start page's link, to the Account page's pairing box, then choosing
// their agent. Ported from ash-template's pairing.spec.ts.
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

const pairing = (page: Page) => page.locator("#account-pairing")
const message = (page: Page) => page.locator("#account-pairing-box pre")

// A person presses the agent's picture: the radio's label, whose name only
// screen readers hear.
async function choose(page: Page, agent: string) {
  const radio = pairing(page).getByRole("radio", {name: agent, exact: true})
  await radio.locator("xpath=ancestor::label").click()
  await expect(radio).toBeChecked()
}

const pairButton = (page: Page) =>
  page.locator("#account-agents").getByRole("link", {name: "Pair New Agent"})

const scrollToTop = (page: Page) =>
  page.locator("#app-shell-scroller").evaluate(scroller => scroller.scrollTo({top: 0}))

// Keyfleet, 27 Oct 2026: pressed a second time, after scrolling away from the
// pairing box, Pair New Agent did nothing a person could see.
for (const width of [1280, 390, 320]) {
  test(`Pair New Agent on the Account page moves to the pairing box, every press, at ${width}`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 500})
    await signIn(page, "/account")
    await pairButton(page).click()
    await expect(pairing(page)).toBeInViewport()

    await scrollToTop(page)
    await expect(pairing(page).getByRole("heading", {name: "Pair New Agent"})).not.toBeInViewport()
    await pairButton(page).click()
    await expect(pairing(page)).toBeInViewport()
    await problems.expect()
  })
}

// Keyfleet, 27 Oct 2026: the keyboard starts on the agent choice, the chosen agent
// once there is one.
test("Pair New Agent gives focus to the chosen agent, or the first", async ({page}) => {
  const problems = watch(page)
  await signIn(page, "/account")
  await pairButton(page).click()
  await expect(pairing(page).getByRole("radio").first()).toBeFocused()

  await choose(page, "Dots")
  await page.evaluate(() => (document.activeElement as HTMLElement | null)?.blur())
  await scrollToTop(page)
  await pairButton(page).click()
  await expect(pairing(page).getByRole("radio", {name: "Dots", exact: true})).toBeFocused()
  await problems.expect()
})

// The page starts at the box the link names, and stays there once it is ready.
test("an agent guide's link lands on the pairing box", async ({page}) => {
  const problems = watch(page)
  await page.setViewportSize({width: 1280, height: 500})
  await signIn(page, "/account#account-pairing")
  await expect(pairing(page)).toBeInViewport()
  await expect(page.locator("#account-identity")).not.toBeInViewport()
  await expect(pairing(page).getByRole("radio").first()).toBeFocused()
  await problems.expect()
})

// The start page's Pair New Agent leads to the same box on the Account page.
for (const width of [1280, 390]) {
  test(`Pair New Agent on the start page lands on the pairing box at ${width}`, async ({page}) => {
    const problems = watch(page)
    await page.setViewportSize({width, height: 500})
    await signIn(page, "/start")
    await page.locator("#agent-start-page").getByRole("link", {name: "Pair New Agent"}).click()
    await expect(page).toHaveURL(/\/account#account-pairing$/)
    await expect(pairing(page)).toBeInViewport()
    await expect(pairing(page).getByRole("radio").first()).toBeFocused()
    await problems.expect()
  })
}

test("each agent keeps its own code until a new one is asked for", async ({page}) => {
  const problems = watch(page)
  await signIn(page, "/account")
  await expect(message(page)).toHaveCount(0)

  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  const first = await message(page).innerText()

  await choose(page, "Hermes")
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)

  // Coming back shows the same code, so a message already pasted still works.
  await choose(page, "Dots")
  await expect(message(page)).toHaveText(first)

  await pairing(page).getByRole("button", {name: "Make a new code"}).click()
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  await problems.expect()
})

// A reconnecting page sends the pairing form back with no agent picked, and a
// submit can come before a choice. Neither may crash the pairing box (Sentinel,
// 23 Oct 2026, from Patchbay's error mail; ash-template 13379ab).
test("the pairing form with nothing chosen leaves the box as it is", async ({page}) => {
  const problems = watch(page)
  const crashes: string[] = []
  page.on("websocket", socket =>
    socket.on("framereceived", frame => {
      if (String(frame.payload).includes('"phx_error"')) crashes.push(String(frame.payload).slice(0, 120))
    }),
  )
  await signIn(page, "/account")
  const form = page.locator("form#account-pairing-box")
  await expect(form.getByRole("radio", {checked: true})).toHaveCount(0)

  await form.getByRole("radio").first().dispatchEvent("input")
  await form.evaluate(element => (element as HTMLFormElement).requestSubmit())

  // The box still answers: choosing an agent shows its code.
  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  expect(crashes).toEqual([])
  await problems.expect()
})
