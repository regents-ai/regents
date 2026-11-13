import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// R04 acceptance: one live session walks every page the shell's features own,
// and each page still paints its own content after the others were visited.
const pages: Array<[string, string]> = [
  ["/stake", "#staking-actions"],
  ["/redeem", "#redemption-collections"],
  ["/redeem/gallery", "#gallery-heading"],
  ["/account", "#account-identity"],
  ["/account/agents", "#account-agents"],
  ["/account/points", "#points-page"],
  ["/account/wallets", "#account-wallets-title"],
  ["/account/connections", "#account-verified-connections"],
  ["/pair", "#pair-page"],
  ["/names", "#account-names-title"],
  ["/app", "#regent-ops-overview"],
  ["/paper-pro-daily", "#paper-daily-title"],
  ["/literature", "#literature-chart"],
  ["/docs/limits", "#docs-article"],
  ["/about", "#about-page"],
  ["/stake", "#staking-actions"],
  ["/redeem", "#redemption-collections"],
  ["/account/agents", "#account-agents"],
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
  // Privy's servers answer the lab as unavailable (support/offline.ts), so Chrome
  // notes each refused request to them. Leaving /redeem before its muted intro
  // video starts makes Chrome note that the play was interrupted. The visitor
  // sees neither.
  const note = (text: string) => {
    if (text.includes("The play() request was interrupted because the media was removed from the document")) return
    problems.push(text)
  }
  page.on("pageerror", error => note(error.message))
  page.on("console", message => {
    if (message.type() === "error" && !message.location().url.startsWith("https://auth.privy.io/")) note(message.text())
  })

  await page.goto("/stake")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await page.evaluate(() => ((window as any).__r04Walk = true))

  for (const [path, marker] of pages) {
    if ((path.startsWith("/account") || path === "/names") && !signedIn) continue
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

// Every shell page carries the whole account menu, its agents and Pair New Agent,
// opened straight from its own address.
test("a signed-in person has the whole account menu on every shell page", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()

  for (const path of ["/app", "/stake", "/redeem", "/account", "/articles", "/start", "/paper-pro-daily", "/literature"]) {
    await page.goto(path)
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await expect(page.locator("#shell-agents-reader"), path).toBeAttached()
    await expect(page.locator("#account-menu button[data-pair-open]"), path).toBeAttached()
    await expect(page.locator("#shell-pairing #shell-pairing-box"), path).toBeAttached()
  }
})

// The Account tabs and Names fit a phone, with nothing pushing the page sideways.
test("the Account tabs and Names fit a phone", async ({page}, testInfo) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await page.setViewportSize({width: 390, height: 900})

  for (const [path, marker] of pages.filter(([path]) => path.startsWith("/account") || path === "/names")) {
    await page.goto(path)
    await expect(page.locator(marker), path).toBeVisible()
    const sideways = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    expect(sideways, path).toBeLessThanOrEqual(0)
    await page.screenshot({
      path: testInfo.outputPath(`${path.slice(1).replaceAll("/", "-")}-390.png`),
      fullPage: true,
    })
  }
})

// On the narrowest phone a product page's buttons, the gallery's and the chart's
// axis names stay inside their panels, so nothing pushes the page sideways.
test.describe("on a 320 touch phone", () => {
  test.use({hasTouch: true, isMobile: true, viewport: {width: 320, height: 800}})

  test("product pages, the gallery, Literature, Docs and About fit without sideways scroll", async ({page}) => {
    const fits: Array<[string, string]> = [
      ["/patchbay", "#product-heading"],
      ["/autolaunch", "#product-heading"],
      ["/techtree", "#product-heading"],
      ["/keyfleet", "#product-heading"],
      ["/cloak", "#product-heading"],
      ["/redeem/gallery", "#gallery-heading"],
      ["/literature", "#literature-chart"],
      ["/docs/limits", "#docs-article"],
      ["/about", "#about-page"],
    ]

    for (const [path, marker] of fits) {
      await page.goto(path)
      await expect(page.locator(marker), path).toBeVisible()
      const sideways = await page.locator("#app-shell-scroller").evaluate(scroller => scroller.scrollWidth - scroller.clientWidth)
      expect(sideways, `${path} at 320`).toBeLessThanOrEqual(0)
    }
  })
})
