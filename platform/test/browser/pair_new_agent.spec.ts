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
