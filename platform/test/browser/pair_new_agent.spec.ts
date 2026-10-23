import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The page's Pair New Agent button points to the agents to choose from in the
// side panel: their box comes into view and flashes, on every press.
const choices = "#shell-pairing .rg-account__choices"

async function openAccount(page: Page) {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await page.goto("/account")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator("#account-agents")).toBeVisible()
}

const pairNewAgent = (page: Page) =>
  page.locator("#account-agents").getByRole("button", {name: "Pair New Agent"})

// The box is inside the panel's visible part and inside the window.
async function expectInView(page: Page) {
  const inView = await page.evaluate(selector => {
    const box = document.querySelector(selector)!.getBoundingClientRect()
    const panel = document.querySelector("#shell-aside")!.getBoundingClientRect()
    return box.top >= panel.top && box.bottom <= panel.bottom && box.bottom <= window.innerHeight
  }, choices)
  expect(inView).toBe(true)
}

for (const width of [1280, 390]) {
  test(`Pair New Agent flashes the agents to choose from at ${width}`, async ({page}) => {
    await page.setViewportSize({width, height: 480})
    await openAccount(page)

    if (width === 1280) {
      // On a computer the panel opens beside the page first.
      await page.locator("#shell-aside-button").click()
      await expect(page.locator("#shell-aside")).toBeVisible()
    } else {
      // On a phone the panel covers the page, so it is shut until the press opens it.
      await expect(page.locator("#shell-aside")).toBeHidden()
    }

    await pairNewAgent(page).click()
    await expect(page.locator("#shell-aside")).toBeVisible()
    await expect(page.locator(choices)).toHaveAttribute("data-flash", "")
    await expect(page.locator(choices)).toHaveCSS("animation-name", "shell-pairing-flash")
    await expectInView(page)
    await expect(page.locator(choices)).not.toHaveAttribute("data-flash", /.*/, {timeout: 3000})

    // A second press, after the panel was scrolled away from the agents, flashes
    // again. On a phone the panel is shut first, since it covers the button.
    if (width === 390) {
      await page.locator("#shell-aside-button").click()
      await expect(page.locator("#shell-aside")).toBeHidden()
    }
    await page.locator("#shell-aside").evaluate(panel => (panel.scrollTop = 0))
    await pairNewAgent(page).click()
    await expect(page.locator(choices)).toHaveAttribute("data-flash", "")
    await expectInView(page)
  })
}

test("with less motion asked for, the agents' box stays marked without flashing", async ({page}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.setViewportSize({width: 1280, height: 760})
  await openAccount(page)
  await page.locator("#shell-aside-button").click()

  await pairNewAgent(page).click()
  const box = page.locator(choices)
  await expect(box).toHaveAttribute("data-flash", "")
  await expect(box).toHaveCSS("animation-name", "none")
  expect(await box.evaluate(el => getComputedStyle(el).outlineStyle)).toBe("solid")
  await expect(box).not.toHaveAttribute("data-flash", /.*/, {timeout: 3000})
})

// Pairing as a person does it: choosing their agent in the side panel's box.
const pairingBox = (page: Page) => page.locator("#shell-pairing")
const message = (page: Page) => page.locator("#shell-pairing-box pre")

// A person presses the agent's picture: the radio's label, whose name only
// screen readers hear.
async function choose(page: Page, agent: string) {
  const radio = pairingBox(page).getByRole("radio", {name: agent, exact: true})
  await radio.locator("xpath=ancestor::label").click()
  await expect(radio).toBeChecked()
}

async function openPairing(page: Page) {
  await page.setViewportSize({width: 1280, height: 900})
  await openAccount(page)
  await page.locator("#shell-aside-button").click()
  await pairNewAgent(page).click()
}

test("each agent keeps its own code until a new one is asked for", async ({page}) => {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  await openPairing(page)
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

  await pairingBox(page).getByRole("button", {name: "Make a new code"}).click()
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  expect(errors).toEqual([])
})

// A reconnecting page sends the pairing form back with no agent picked, and a
// submit can come before a choice. Neither may crash the side panel (Sentinel,
// 23 Oct 2026, from Patchbay's error mail; ash-template 13379ab).
test("the pairing form with nothing chosen leaves the box as it is", async ({page}) => {
  const crashes: string[] = []
  page.on("websocket", socket =>
    socket.on("framereceived", frame => {
      if (String(frame.payload).includes('"phx_error"')) crashes.push(String(frame.payload).slice(0, 120))
    }),
  )
  await openPairing(page)
  const form = page.locator("form#shell-pairing-box")
  await expect(form.getByRole("radio", {checked: true})).toHaveCount(0)

  await form.getByRole("radio").first().dispatchEvent("input")
  await form.evaluate(element => (element as HTMLFormElement).requestSubmit())

  // The box still answers: choosing an agent shows its code.
  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  expect(crashes).toEqual([])
})
