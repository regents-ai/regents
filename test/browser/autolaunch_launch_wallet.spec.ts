import {expect, test, type Locator, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The seeded browser account for the Autolaunch draft fixtures holds this wallet.
const wallet = "0x3333333333333333333333333333333333333333"
// A second wallet, to select while a draft is being written.
const otherWallet = "0x4444444444444444444444444444444444444444"
// Lowercase on purpose: mixed case asserts an EIP-55 checksum, and a launch
// review refuses an address whose checksum does not hold.
const treasury = "0xabcdef0000000000000000000000000000000001"

const sendsKey = "regent:test:launch-sends"
const rejectKey = "regent:test:launch-reject-next"

// Every submitted hash is unique for the life of the database and the browser
// database is never reset, so each run mints its own. Each test also gets its
// own slot, because the per-context send counter restarts with every test and
// would otherwise mint a hash an earlier test already bound.
const run = `${Date.now().toString(16).padStart(12, "0")}c4`
let slot = 0

async function installWallet(page: Page, testSlot: number) {
  await page.addInitScript(
    ({wallet, sendsKey, rejectKey, run, testSlot}) => {
      // The send count lives in session storage so a document reload cannot hide
      // a second wallet request behind a fresh counter.
      const sends = () => Number(sessionStorage.getItem(sendsKey) ?? "0")

      ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = {
        address: wallet,
        provider: {
          request: async ({method}: {method: string; params?: unknown[]}) => {
            switch (method) {
              case "eth_chainId":
                return "0x2105"
              case "wallet_switchEthereumChain":
                return null
              case "eth_accounts":
              case "eth_requestAccounts":
                return [wallet]
              case "eth_sendTransaction": {
                // A real wallet rejection: nothing is broadcast and nothing is
                // counted, exactly as EIP-1193 4001 means.
                if (sessionStorage.getItem(rejectKey)) {
                  sessionStorage.removeItem(rejectKey)
                  throw Object.assign(new Error("User rejected the request."), {code: 4001})
                }
                const nonce = sends() + 1
                sessionStorage.setItem(sendsKey, String(nonce))
                const suffix = `${testSlot.toString(16).padStart(2, "0")}${nonce
                  .toString(16)
                  .padStart(4, "0")}`
                return `0x${run}${suffix}${"0".repeat(44)}`
              }
              default:
                return null
            }
          },
        },
      }

      window.addEventListener("ash:wallet-connect", () => {
        window.dispatchEvent(new CustomEvent("ash:wallet-state"))
      })
    },
    {wallet, sendsKey, rejectKey, run, testSlot},
  )
}

// Privy's selection changing under the page, announced the way the shell
// announces it.
async function selectWallet(page: Page, address: string) {
  await page.evaluate(next => {
    const test = window as Window & {__ashPlatformTestWallet?: {address: string}}
    test.__ashPlatformTestWallet!.address = next
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}

async function signedIn(page: Page) {
  slot += 1
  const auth = await installAuthenticatedPrivy(page, "valid-autolaunch-draft")
  await installWallet(page, slot)
  await auth.establishLocalSession()
  return auth
}

/**
 * One saved draft, written through the real form, with its own launch card.
 *
 * The account keeps one open launch and this database is never reset between
 * runs, so whatever an earlier test left in flight is ended first. That the
 * server shows it at all, in a browser with no stored hint, is the recovery this
 * proves.
 */
async function draftCard(page: Page): Promise<Locator> {
  await page.goto("/autolaunch/create")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const saved = page.locator("#launch-drafts article").filter({hasText: draftName})
  if (!(await saved.count())) await saveDraft(page)
  await expect(saved).toBeVisible()

  const card = saved.locator(".launch-wallet")
  await endAnyOpenLaunch(page)
  await expect(card.getByRole("button", {name: "Review launch"})).toBeVisible({timeout: 15_000})

  return card
}

// The one draft this proof owns, written through the real form. The browser
// database is never reset, so it is reused rather than piled up.
const draftName = "Launch wallet browser draft"

async function saveDraft(page: Page) {
  const form = page.locator("#create-launch-draft")
  await form.getByLabel("Name", {exact: true}).fill(draftName)
  await form.getByLabel("Symbol", {exact: true}).fill("LWD")
  await form.getByLabel("Description", {exact: true}).fill("A launch awaiting review.")
  await form.getByLabel("Website", {exact: true}).fill("https://example.test/launch-wallet")
  await form.getByLabel("Image", {exact: true}).fill("https://example.test/launch-wallet.png")
  await form.getByLabel("Treasury", {exact: true}).fill(treasury)
  await form.getByLabel("Required raise in REGENT", {exact: true}).fill("1000.5")
  await form.getByRole("button", {name: "Save draft"}).click()

  await expect(page.getByText("Draft saved.")).toBeVisible()
}

// A launch this account left open on any draft blocks a new review, so it is
// ended through whichever control the server is currently offering.
async function endAnyOpenLaunch(page: Page) {
  // Every card offers this prompt until the server has adopted the wallet its
  // hook published, and that same render replays whatever launch this account
  // has open. Reading the controls earlier finds none and leaves it standing.
  await expect(page.locator(".launch-wallet [data-launch-wallet-connect]")).toHaveCount(0, {
    timeout: 15_000,
  })

  const controls = [
    'button[phx-click="clear_launch"]',
    'button[phx-click="cancel_launch_review"]',
    'button[phx-click="start_new_launch"]',
  ]
    .map(selector => `.launch-wallet ${selector}`)
    .join(", ")

  for (let attempt = 0; attempt < 4; attempt += 1) {
    if (!(await page.locator(controls).count())) return

    const control = page.locator(controls).first()
    await control.click()

    // Wait for the re-render this click causes rather than for a clock, so the
    // next pass reads the card the server actually sent.
    await control.waitFor({state: "detached", timeout: 10_000}).catch(() => undefined)
  }
}

async function reviewed(page: Page): Promise<Locator> {
  const card = await draftCard(page)
  await card.getByRole("button", {name: "Review launch"}).click()
  await expect(card.locator(".launch-wallet-review")).toBeVisible({timeout: 15_000})
  return card
}

test("a signed-in founder reviews, sends once, and reads the outcome from the server", async ({
  page,
}) => {
  await signedIn(page)
  const card = await reviewed(page)

  // Everything a founder needs, in plain English, before anything is signed.
  await expect(card).toContainText("1000.5 REGENT")
  await expect(card).toContainText("Two transactions")
  await expect(card).toContainText("Base")
  await expect(card).toContainText("Bidding opens a fixed delay after your launch transaction")
  await expect(card).toContainText("The pool fee is 0.30%.")

  // The two reviewed steps are both on screen, in order.
  await expect(card.locator('li[data-step="approval"]')).toBeVisible()
  await expect(card.locator('li[data-step="launch"]')).toBeVisible()

  // No selector or calldata is ever put in front of the customer.
  await expect(card).not.toContainText("0x783eed53")
  await expect(card).not.toContainText("0x095ea7b3")

  await card.locator("[data-launch-wallet-send]").click()

  // The browser reports the hash and stops; the outcome is the server's own read.
  await expect(card).toContainText("Sent", {timeout: 15_000})
  await expect(card.locator('a[href^="https://basescan.org/tx/"]')).toBeVisible()

  // Exactly one wallet send happened, and the claimed step is not offered again.
  expect(await page.evaluate(key => sessionStorage.getItem(key), sendsKey)).toBe("1")
  await expect(card.locator("[data-launch-wallet-send]")).toHaveCount(0)

  // Nothing claims the launch is already published, and no internal wording
  // reaches the customer.
  await expect(card).not.toContainText("waiting for index")
  await expect(card).not.toContainText("Launched")
})

test("a reload recovers the open launch and never sends it a second time", async ({page}) => {
  await signedIn(page)
  const card = await reviewed(page)

  await card.locator("[data-launch-wallet-send]").click()
  await expect(card).toContainText("Sent", {timeout: 15_000})

  const sendsBefore = await page.evaluate(key => sessionStorage.getItem(key), sendsKey)

  await page.reload()

  // The same launch comes back from the owning account's own row, still sent,
  // and the reload asked no wallet for anything.
  const restored = page.locator(".launch-wallet").filter({hasText: "Review this launch"})
  await expect(restored).toContainText("Sent", {timeout: 15_000})
  await expect(restored.locator('a[href^="https://basescan.org/tx/"]')).toBeVisible()
  expect(await page.evaluate(key => sessionStorage.getItem(key), sendsKey)).toBe(sendsBefore)
  await expect(restored.locator("[data-launch-wallet-send]")).toHaveCount(0)
})

test("an explicit wallet rejection ends the launch and broadcasts nothing", async ({page}) => {
  await signedIn(page)
  const card = await reviewed(page)

  await page.evaluate(key => sessionStorage.setItem(key, "1"), rejectKey)
  await card.locator("[data-launch-wallet-send]").click()

  await expect(card).toContainText("Your wallet declined this.", {timeout: 15_000})
  expect(await page.evaluate(key => sessionStorage.getItem(key), sendsKey)).toBeNull()
  await expect(card.locator("[data-launch-wallet-send]")).toHaveCount(0)
})

test("every technical value stays behind the one disclosure", async ({page}) => {
  await signedIn(page)
  const card = await reviewed(page)

  const details = card.locator("details")
  await expect(details).toBeVisible()
  await details.locator("summary").click()

  await expect(details).toContainText("Calldata digest")
  await expect(details).toContainText("Floor price q96")
  await expect(details).toContainText("Max reachable raise")
})

test("a blank draft starts from the connected wallet and keeps whatever is typed", async ({
  page,
}) => {
  await signedIn(page)
  await page.goto("/autolaunch/create")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  // The Treasury field opens as the wallet Privy has selected, ready to save.
  const field = page.locator("#create-launch-draft-treasury")
  await expect(field).toHaveValue(wallet)

  // Nothing has been typed yet, so selecting another wallet simply moves the
  // starting point with it.
  await selectWallet(page, otherWallet)
  await expect(field).toHaveValue(otherWallet)

  // An address the founder enters is theirs, and a later wallet change leaves it
  // exactly as typed.
  await field.fill(treasury)
  await selectWallet(page, wallet)
  await expect(field).toHaveValue(treasury)
})

test("a refused save keeps the Treasury it sent back, whatever the wallet does next", async ({
  page,
}) => {
  await signedIn(page)
  await page.goto("/autolaunch/create")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const form = page.locator("#create-launch-draft")
  const field = page.locator("#create-launch-draft-treasury")
  await expect(field).toHaveValue(wallet)

  // Every field valid except the raise, with the Treasury left exactly as it was
  // found.
  await form.getByLabel("Name", {exact: true}).fill("Launch wallet echo draft")
  await form.getByLabel("Symbol", {exact: true}).fill("LWE")
  await form.getByLabel("Description", {exact: true}).fill("A draft the server refuses.")
  await form.getByLabel("Website", {exact: true}).fill("https://example.test/echo")
  await form.getByLabel("Image", {exact: true}).fill("https://example.test/echo.png")
  await form.getByLabel("Required raise in REGENT", {exact: true}).fill("0")
  await form.getByRole("button", {name: "Save draft"}).click()

  // The raise is what failed, and the server sent the whole form back with the
  // address it was given.
  await expect(page.getByText("That draft could not be saved.")).toBeVisible()
  await expect(page.locator("#create-launch-draft-required_regent_raised-error")).toContainText(
    "must be greater than zero",
  )
  await expect(form).toHaveAttribute("data-draft-errors", "true")
  await expect(field).toHaveValue(wallet)

  // Selecting a different wallet now changes nothing. The address on screen came
  // back from the server and belongs to the founder, not to the default.
  await selectWallet(page, otherWallet)
  await expect(field).toHaveValue(wallet)
})

test("a signed-out visitor is offered no launch control at all", async ({page}) => {
  await page.goto("/autolaunch/create")

  await expect(page.locator("#autolaunch-create")).toContainText("Sign in to prepare your launch.")
  await expect(page.locator("[data-launch-wallet-send]")).toHaveCount(0)
  await expect(page.locator(".launch-wallet")).toHaveCount(0)
})

test("the card fits a 390 pixel viewport and a desktop one without overflowing", async ({page}) => {
  await signedIn(page)
  await page.setViewportSize({width: 390, height: 844})

  const card = await reviewed(page)
  await card.locator("details summary").click()

  // The same reviewed card, measured at both widths, so the two measurements are
  // of one layout rather than of two separately prepared ones.
  for (const viewport of [
    {width: 390, height: 844},
    {width: 1440, height: 900},
  ]) {
    await page.setViewportSize(viewport)

    // Layout width, not the bounding box: the shell animates route content, and
    // a transform mid-flight would make a box measurement lie about the layout.
    const layout = await page.evaluate(() => {
      const node = document.querySelector(".launch-wallet-review")?.closest(
        ".launch-wallet",
      ) as HTMLElement

      return {
        card: node.offsetWidth,
        page: document.documentElement.clientWidth,
        sideways: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        clipped: [node, ...node.querySelectorAll("*")]
          .filter(child => child.scrollWidth > child.clientWidth + 1)
          .map(child => `${child.tagName}.${child.className || "-"}`),
        controls: node.querySelectorAll("button, a, details").length,
      }
    })

    // The page never scrolls sideways, the card fits the screen, and nothing
    // inside it is cut off.
    expect(layout.controls).toBeGreaterThan(0)
    expect(layout.sideways).toBeLessThanOrEqual(0)
    expect(layout.card).toBeLessThanOrEqual(layout.page)
    expect(layout.clipped).toEqual([])
  }

  await endAnyOpenLaunch(page)
})
