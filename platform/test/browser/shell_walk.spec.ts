import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// R04 acceptance: one live session walks every page the shell's features own,
// and each page still paints its own content after the others were visited.
const pages: Array<[string, string]> = [
  ["/stake", "#staking-actions"],
  ["/redeem", "#redemption-collections"],
  ["/redeem/gallery", "#gallery-heading"],
  ["/account", "#account-agents"],
  ["/app", "#regent-ops-overview"],
  ["/paper-pro-daily", "#paper-daily-title"],
  ["/literature", "#literature-chart"],
  ["/stake", "#staking-actions"],
  ["/redeem", "#redemption-collections"],
  ["/account", "#account-agents"],
  ["/redeem", "#redemption-collections"],
]

// The link sits outside the live view, so no update of the page can remove it
// before the click; LiveView follows a patch link anywhere in the document.
async function patchTo(page: Page, path: string) {
  await page.evaluate(destination => {
    document.querySelector("#patch-probe")?.remove()
    const link = document.createElement("a")
    link.id = "patch-probe"
    link.href = destination
    link.textContent = destination
    link.dataset.phxLink = "patch"
    link.dataset.phxLinkState = "push"
    link.style.cssText = "position: fixed; inset: 0 auto auto 0; z-index: var(--rg-layer-skip)"
    document.body.append(link)
  }, path)
  await page.locator("#patch-probe").click()
}

async function walk(page: Page, signedIn: boolean) {
  const problems: string[] = []
  // The lab has no real Privy app, so a visitor's sign-in widget says so. Leaving
  // /redeem before its muted intro video starts makes Chrome note that the play
  // was interrupted; the visitor sees nothing.
  const note = (text: string) => {
    if (text.includes("invalid Privy app ID")) return
    if (text.includes("The play() request was interrupted because the media was removed from the document")) return
    problems.push(text)
  }
  page.on("pageerror", error => note(error.message))
  page.on("console", message => {
    if (message.type() === "error") note(message.text())
  })

  await page.goto("/stake")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await page.evaluate(() => ((window as any).__r04Walk = true))

  for (const [path, marker] of pages) {
    if (path === "/account" && !signedIn) continue
    await patchTo(page, path)
    await expect(page).toHaveURL(new RegExp(`${path.replace("/", "\\/")}$`))
    await expect(page.locator(marker)).toBeVisible()
  }

  // Every step was a patch inside one live session, never a reload.
  expect(await page.evaluate(() => (window as any).__r04Walk)).toBe(true)
  await expect(page.locator(".phx-error")).toHaveCount(0)
  await expect(page.getByText("Redemption details are unavailable right now.")).toHaveCount(0)
  expect(problems).toEqual([])
}

test("[R04] a visitor walks Stake, Redeem, the gallery and Overview in one visit", async ({page}) => {
  await walk(page, false)
})

test("[R04] a signed-in person walks every page, Account included, in one visit", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await walk(page, true)
})

// Every page with the side panel carries the whole of it: the agents, the
// pairing box and the Credits button, opened straight from its own address.
test("a signed-in person sees the whole side panel on every shell page", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()

  for (const path of ["/app", "/stake", "/redeem", "/account", "/articles", "/start", "/paper-pro-daily", "/literature"]) {
    await page.goto(path)
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await expect(page.locator("#shell-agents-reader"), path).toBeAttached()
    await expect(page.locator("#shell-pairing"), path).toBeAttached()
    await expect(page.locator("#shell-credits-button"), path).toBeVisible()
  }
})
