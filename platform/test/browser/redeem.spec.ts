import {decodeFunctionData, parseAbi, type Hex} from "viem"
import {expect, test, type Locator, type Page} from "./support/offline"

import {identityTokenFor} from "./support/authenticated_privy"
import {boxes, coveredControls} from "./support/wallet_notes"

const wallet = "0x1111111111111111111111111111111111111111"
const otherWallet = "0x2222222222222222222222222222222222222222"
const sendsKey = "regent:test:redemption-wallet-sends"
const disconnectedKey = "regent:wallet-disconnected:v1"
// The sign-in this page's redemption bearer names is the wallet above.
const redemptionBearer = "valid-redemption"
const animataI = "0x78402119ec6349a0d41f12b54938de7bf783c923"
const redeemer = "0x71065b775a590c43933f10c0055dc7d74afabb0e"
const usdc = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
const redemptionAbi = parseAbi([
  "function setApprovalForAll(address operator,bool approved)",
  "function redeem(address collection,uint256 tokenId)",
  "function claim()",
  "function approve(address spender,uint256 amount)",
])
const bridgePattern =
  /\/assets\/js\/privy_bridge(?:-[a-f0-9]{32})?\.js\?(?:vsn=d&)?regent_retry=\d+$/
const bridgeStub = `
export async function startPrivyBridge() {
  return {async request() {}}
}
`

test("Redeem intro is bounded and still at reduced motion", async ({page}) => {
  await page.setViewportSize({width: 320, height: 720})
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.goto("/redeem")

  await expect(page.getByRole("heading", {name: "Redeem your Animata."})).toBeVisible()

  // Connecting a wallet here is the Privy sign-in, the same one the header runs.
  await expect(page.locator(".redeem-intro-actions").getByRole("button", {name: "Connect wallet"})).toHaveAttribute(
    "data-account-target",
    "sign-in",
  )

  for (const [name, href] of [
    ["Animata I", "https://opensea.io/collection/animata"],
    ["Animata II", "https://opensea.io/collection/regent-animata-ii"],
    ["Regents Club", "https://opensea.io/collection/regents-club"],
  ] as const) {
    const link = page
      .locator(".redeem-collection-card")
      .filter({has: page.getByRole("heading", {name, exact: true})})
      .getByRole("link", {name: "View collection on OpenSea"})
    await expect(link).toHaveAttribute("href", href)
    await expect(link).toHaveAttribute("target", "_blank")
    await expect(link).toHaveAttribute("rel", "noopener noreferrer")
  }

  await expect(page.locator(".redeem-intro-video")).toBeHidden()
  await expect(page.locator(".redeem-intro-poster")).toBeVisible()
  await expect(page.getByAltText("Animata I and II artwork")).toBeVisible()
  await expect(page.locator("#redemption-collections-heading")).toHaveText(
    "Animata I or II + USDC are redeemed for REGENT + Regents Club Digital Pass",
  )
  await expect(page.locator(".redeem-collection-card")).toHaveCount(3)
  await expect(page.locator(".redeem-collection-grid")).toContainText("Remaining Passes")
  await expect(page.locator(".redeem-collection-grid")).toContainText("327")
  await expect(page.locator(".redeem-collection-grid")).toContainText("284")
  await expect(page.locator(".redeem-collection-grid")).toContainText(
    "Regents Club Passes claimed",
  )
  await expect(page.locator(".redeem-collection-grid")).toContainText("1,610 / 1,998")

  const hasHorizontalOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
  )
  expect(hasHorizontalOverflow).toBe(false)
})

test("Redeem sends each press straight to the signed-in wallet and follows it on Base", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/redeem")
  await expect(page.getByRole("heading", {name: "Redeem your Animata."})).toBeVisible()
  await expect(page.locator("#account-chip")).toBeVisible()
  await expect(page.getByLabel("Collection", {exact: true})).toBeVisible()
  await expect(page.getByLabel("Token ID")).toBeVisible()

  await page.getByLabel("Token ID").fill("42")
  // Every step is offered; the latest reading from Base picks the one that leads.
  const next = page.locator(".redeem-next-step button.redeem-primary")
  await expect(next).toHaveCount(1)
  await expect(next).toHaveText(/Approve NFT collection/)
  await expect(next).toHaveAttribute("data-onchain-step", "approve_nft_collection")
  await expect(page.getByRole("button", {name: "Approve 80 USDC"})).toBeEnabled()
  await expect(page.locator("#route-content button[data-onchain-step][disabled]")).toHaveCount(0)
  const claim = page.locator("#redemption-claim")
  await expect(claim).toHaveAttribute("data-onchain-step", "claim")
  await expect(claim).toBeEnabled()

  const activity = page.locator("#redemption-activity")
  await expect(activity).toBeHidden()

  await next.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  expect(await sent(page, 1)).toEqual({
    to: animataI,
    call: {functionName: "setApprovalForAll", args: [redeemer, true]},
  })
  const first = page.locator(`#redemption-activity-${expectedHash(1)}`)
  await expect(first).toContainText("Animata I approval")
  await expect(first).toContainText("Sent. Waiting for Base.")
  await expectResultLink(first, 1)
  // Only the pressed step says it is confirming; the others keep their names.
  await expect(page.getByRole("button", {name: "Approve 80 USDC"})).toBeVisible()
  await expect(page.getByRole("button", {name: "Redeem Animata"})).toBeVisible()

  // The same press again is a new request, not a deduplicated or locked one.
  await next.click()
  await expect.poll(() => sendCount(page)).toBe(2)
  await expect(page.locator(`#redemption-activity-${expectedHash(2)}`)).toContainText(
    "Animata I approval",
  )
  await expect(first).toBeVisible()

  // The claim's result sits beside the claim, not beside the redemption steps.
  await claim.click()
  await expect.poll(() => sendCount(page)).toBe(3)
  expect(await sent(page, 3)).toEqual({to: redeemer, call: {functionName: "claim", args: []}})
  const claimed = page.locator(`#redemption-claim-activity-${expectedHash(3)}`)
  await expect(claimed).toContainText("REGENT claim")
  await expectResultLink(claimed, 3)
  await expect(activity.locator("li")).toHaveCount(2)

  // The other two steps are offered beside the lead one and reach the wallet too.
  await page.locator("#redemption-approve_exact_usdc").click()
  await expect.poll(() => sendCount(page)).toBe(4)
  expect(await sent(page, 4)).toEqual({
    to: usdc,
    call: {functionName: "approve", args: [redeemer, 80_000_000n]},
  })
  await page.locator("#redemption-redeem").click()
  await expect.poll(() => sendCount(page)).toBe(5)
  expect(await sent(page, 5)).toEqual({
    to: redeemer,
    call: {functionName: "redeem", args: [animataI, 42n]},
  })

  await page.reload()
  await expect(page.locator("#account-chip")).toBeVisible()
  await expect(page.getByLabel("Token ID")).toBeVisible()
  expect(await sendCount(page)).toBe(5)
})

// A control is offered whenever its calldata can be built: both approvals as
// soon as a wallet is connected, Redeem once a token is selected too.
test("Redeem offers both approvals at once and Redeem once a token is selected", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.goto("/redeem")

  const controls = page.locator(".redeem-next-step button")
  await expect(controls).toHaveCount(2)
  await expect(page.getByRole("button", {name: "Approve NFT collection"})).toBeEnabled()
  await expect(page.getByRole("button", {name: "Approve 80 USDC"})).toBeEnabled()
  await expect(page.getByRole("button", {name: "Redeem Animata"})).toHaveCount(0)
  await expect(page.locator(".redeem-next-step h3")).toHaveText("Select an Animata")

  await page.getByLabel("Token ID").fill("42")
  await expect(controls).toHaveCount(3)
  for (const control of await controls.all()) await expect(control).toBeEnabled()
  await expect(page.locator(".redeem-next-step button.redeem-primary")).toHaveAttribute(
    "data-onchain-step",
    "approve_nft_collection",
  )

  await page.getByLabel("Token ID").fill("")
  await expect(controls).toHaveCount(2)
  await expect(page.getByRole("button", {name: "Redeem Animata"})).toHaveCount(0)
  await expect(page.locator(".redeem-next-step p").last()).toHaveText(
    "Enter a token ID from 1 to 999 to redeem. Both approvals can be sent now.",
  )
  await expect(page.locator("#redemption-claim")).toBeEnabled()
})

// From a small phone to a desktop, everything in the collections, redemption and
// account panels sits inside the panel and each button shows its whole name. Each
// collection card's link sits whole on one line in its header, under the name, and
// the three headers are one height.
test("Redeem keeps each panel's cards, steps, fields and buttons inside it", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  for (const width of [320, 360, 390, 1280]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/redeem")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await page.getByLabel("Token ID").fill("42")
    await expect(page.locator("#redemption-redeem")).toBeVisible()
    await expect(page.locator("#redemption-claim")).toBeVisible()

    const fit = await page.evaluate(() => {
      const panels = ".redeem-collections, .redeem-actions, .redeem-position"
      const headings = [...document.querySelectorAll<HTMLElement>(".redeem-collection-card .rg-panel__heading")]
      return {
        document: document.documentElement.scrollWidth - window.innerWidth,
        collectionLinks: headings.map(heading => {
          const box = heading.getBoundingClientRect()
          const end = box.right - parseFloat(getComputedStyle(heading).paddingRight)
          const title = heading.querySelector("h3")!.getBoundingClientRect()
          const link = heading.querySelector<HTMLAnchorElement>("a[href^='https://opensea.io/collection/']")!
          const words = link.getBoundingClientRect()
          return {
            underTitle: words.top >= title.bottom && Math.abs(words.left - title.left) < 0.5,
            whole: link.getClientRects().length === 1 && words.right <= end && words.bottom <= box.bottom,
          }
        }),
        headerHeights: new Set(headings.map(heading => Math.round(heading.getBoundingClientRect().height))).size,
        panels: [...document.querySelectorAll<HTMLElement>(panels)].map(panel => {
          const box = panel.getBoundingClientRect()
          const style = getComputedStyle(panel)
          const start = box.left + parseFloat(style.borderLeftWidth) + parseFloat(style.paddingLeft)
          const end = box.right - parseFloat(style.borderRightWidth) - parseFloat(style.paddingRight)
          const shown = [...panel.querySelectorAll<HTMLElement>("*")].filter(
            node => !node.closest(".visually-hidden") && node.checkVisibility(),
          )
          return {
            outside: shown
              .map(node => node.getBoundingClientRect())
              .filter(rect => rect.width > 0 && (rect.left < start - 0.5 || rect.right > end + 0.5))
              .length,
            cutNames: shown.filter(
              node => node.matches(".rg-button__label") && node.scrollWidth > node.clientWidth,
            ).length,
          }
        }),
      }
    })

    expect(fit, `/redeem at ${width}`).toEqual({
      document: 0,
      collectionLinks: Array(3).fill({underTitle: true, whole: true}),
      headerHeights: 1,
      panels: [
        {outside: 0, cutNames: 0},
        {outside: 0, cutNames: 0},
        {outside: 0, cutNames: 0},
      ],
    })
  }
})

test("Redeem refresh retains the current snapshot and scroll position", async ({page}) => {
  await page.setViewportSize({width: 390, height: 600})
  await installWallet(page)
  await signIn(page)

  await page.goto("/redeem")
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  await expect(page.locator("#redemption-refresh-status")).toBeHidden()

  const refresh = page.getByRole("button", {name: "Refresh Data", exact: true})
  await refresh.scrollIntoViewIfNeeded()
  const scroller = page.locator("#app-shell-scroller")
  const summary = page.locator(".redeem-summary")
  const before = await scrollSnapshot(scroller, summary)
  expect(before.top).toBeGreaterThan(0)

  await refresh.click()
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  await expect(page.locator("#redemption-refresh-status")).toHaveText(
    "Refresh complete. Data is current at Base block 1,234.",
  )

  const afterRefresh = await scrollSnapshot(scroller, summary)
  expect(Math.abs(afterRefresh.top - before.top)).toBeLessThanOrEqual(2)
  expect(Math.abs(afterRefresh.anchor - before.anchor)).toBeLessThanOrEqual(2)
  expect(afterRefresh.height).toBe(before.height)

  const tokenId = page.getByLabel("Token ID")
  await tokenId.scrollIntoViewIfNeeded()
  const beforeSelection = await scrollSnapshot(scroller, summary)
  await tokenId.fill("42")
  await expect(page.locator(".redeem-next-step button")).toHaveCount(3)
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  const afterSelection = await scrollSnapshot(scroller, summary)
  expect(Math.abs(afterSelection.top - beforeSelection.top)).toBeLessThanOrEqual(16)

  const action = page.locator(".redeem-next-step button.redeem-primary")
  await expect(action).toBeEnabled()
  await action.scrollIntoViewIfNeeded()
  await action.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  await expect(page.locator(`#redemption-activity-${expectedHash(1)}`)).toContainText(
    "Sent. Waiting for Base.",
  )
})

// Privy's active wallet is the only one that acts. When it is not one of the
// account's wallets, the figures stay the account's, a press sends nothing and
// says what to do, and a note names both wallets.
test("Redeem sends nothing from a wallet that is not the account's", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/redeem")
  await page.getByLabel("Token ID").fill("42")
  await selectWallet(page, wallet)
  await expect(page.locator(".shell-sending-wallet")).toHaveCount(0)

  await selectWallet(page, otherWallet)
  await expect(page.locator("#redemption-signer-wallet-full")).toHaveText(wallet)
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  const note = page.locator(".shell-sending-wallet").first()
  await expect(note).toContainText("0x2222..2222")
  await expect(note).toContainText("0x1111..1111")

  await page.locator("#redemption-approve_nft_collection").click()
  await expect(page.locator("#redemption-activity-press")).toContainText(
    "which isn't linked to this account",
  )
  expect(await sendCount(page)).toBe(0)

  await selectWallet(page, wallet)
  await expect(page.locator(".shell-sending-wallet")).toHaveCount(0)
  await page.locator("#redemption-approve_nft_collection").click()
  await expect.poll(() => sendCount(page)).toBe(1)
  expect((await sent(page, 1)).to).toBe(animataI)
  await expect(page.locator("#redemption-activity-press")).toHaveCount(0)
})

test("Redeem keeps sent results when the active wallet changes", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/redeem")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.getByLabel("Token ID").fill("42")
  await page.locator("#redemption-approve_nft_collection").click()
  await expect.poll(() => sendCount(page)).toBe(1)

  const first = page.locator(`#redemption-activity-${expectedHash(1)}`)
  await selectWallet(page, otherWallet)
  await expect(page.locator("#redemption-signer-wallet-full")).toHaveText(wallet)
  await expect(page.locator(".shell-sending-wallet").first()).toContainText("0x2222..2222")
  await expect(first).toContainText("Animata I approval")

  // The press waits until the page has taken the account's wallet back.
  await selectWallet(page, wallet)
  await expect(page.locator(".shell-sending-wallet")).toHaveCount(0)
  await page.getByLabel("Token ID").fill("43")
  await page.locator("#redemption-approve_nft_collection").click()
  await expect.poll(() => sendCount(page)).toBe(2)
  await signOutWallet(page)
  await expect(page.locator("#redemption-signer-wallet-full")).toHaveText(wallet)
  await expect(first).toBeVisible()
  await expect(page.locator(`#redemption-activity-${expectedHash(2)}`)).toContainText(
    "Animata I approval",
  )
})

// A wallet answer that is not a transaction hash may still have been sent, and
// a declined prompt sent nothing. Each says so beside the button pressed, and
// the next press the wallet takes clears it.
test("Redeem says what the wallet did when a press is not sent", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.goto("/redeem")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.getByLabel("Token ID").fill("42")
  const press = page.locator("#redemption-activity-press")

  await setWalletAnswer(page, "malformed")
  await page.locator("#redemption-approve_nft_collection").click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(press).toHaveText("Your wallet may have sent this. Check your wallet activity.")
  await expect(page.locator("#redemption-activity li")).toHaveCount(0)

  await setWalletAnswer(page, "declined")
  await page.locator("#redemption-claim").click()
  await expect.poll(() => sendCount(page)).toBe(2)
  await expect(page.locator("#redemption-claim-activity-press")).toHaveText(
    "Your wallet declined this. Nothing was sent.",
  )

  await setWalletAnswer(page, "hash")
  await page.locator("#redemption-approve_nft_collection").click()
  await expect.poll(() => sendCount(page)).toBe(3)
  await expect(page.locator(`#redemption-activity-${expectedHash(3)}`)).toContainText(
    "Animata I approval",
  )
  await expect(press).toHaveCount(0)
})

// The note beside the buttons shakes once when the wallet turns a press down,
// and stays still when the wallet may have sent it or is not the account's. The
// button takes a press while the note is shaking.
test("Redeem shakes the note when the wallet turns a press down", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.goto("/redeem")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await page.getByLabel("Token ID").fill("42")
  const press = page.locator("#redemption-activity-press")
  const approve = page.locator("#redemption-approve_nft_collection")
  await watchShakes(page)

  await setWalletAnswer(page, "malformed")
  await approve.click()
  await expect(press).toContainText("may have sent")
  await page.waitForTimeout(600)
  expect(await shakes(page)).toBe(0)
  expect(await sendCount(page)).toBe(1)

  // The third send is the press made on the shake's first frame.
  await setWalletAnswer(page, "declined")
  await approve.click()
  await expect(press).toContainText("declined")
  await expect.poll(() => shakes(page)).toBe(1)
  await expect.poll(() => sendCount(page)).toBe(3)

  await selectWallet(page, otherWallet)
  await approve.click()
  await expect(press).toContainText("isn't linked to this account")
  await page.waitForTimeout(600)
  expect(await shakes(page)).toBe(1)
  expect(await sendCount(page)).toBe(3)
})

// The note for a press the wallet declined floats just under its panel, the flow's
// under the flow and the claim's under the account: it moves nothing on the page,
// covers no control, and goes when the next press is sent.
test("Redeem's note for a declined press moves nothing and covers no control", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  const flowNote = page.locator("#redemption-activity-press")
  const claimNote = page.locator("#redemption-claim-activity-press")
  const approve = page.locator("#redemption-approve_nft_collection")
  const claim = page.locator("#redemption-claim")

  for (const width of [320, 1280]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/redeem")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
    await page.getByLabel("Token ID").fill("42")
    await expect(page.locator("#redemption-redeem")).toBeVisible()
    await setWalletAnswer(page, "declined")

    for (const [button, note] of [[approve, flowNote], [claim, claimNote]] as const) {
      await button.scrollIntoViewIfNeeded()
      const before = await boxes(page, ".redeem-page")
      await button.click()
      await expect(note).toHaveText("Your wallet declined this. Nothing was sent.")
      await expect(button).not.toHaveAttribute("data-awaiting-wallet")
      // Read once the pressed button's own squeeze has played out.
      await expect.poll(() => boxes(page, ".redeem-page"), `Redeem at ${width}`).toEqual(before)
      expect(await coveredControls(page), `Redeem at ${width}`).toEqual([])
    }
    await expect(flowNote).toHaveCount(0)

    await setWalletAnswer(page, "hash")
    await claim.click()
    await expect(page.locator("#redemption-claim-activity li")).toHaveCount(1)
    await expect(claimNote).toHaveCount(0)
    await expect(page.locator("[data-leaving]")).toHaveCount(0)
  }
})

// Sign out ends the wallet connection, and it stays ended across reloads
// while the browser wallet still reports the same account.
test("Sign out leaves Redeem unconnected, and a reload keeps it that way", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/redeem")
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")

  await page.locator("#account-chip").click()
  await page.getByRole("button", {name: "Sign out"}).click()

  await expectDisconnected(page)
  expect(await page.evaluate(key => localStorage.getItem(key), disconnectedKey)).toBe("true")

  // The wallet app still reports the same account to this page, and it is still
  // not this page's wallet.
  expect(
    await page.evaluate(
      () =>
        (window as Window & {__regentsTestWallet?: {address: string}})
          .__regentsTestWallet?.address,
    ),
  ).toBe(wallet)

  await page.reload()
  await expectDisconnected(page)
})

async function expectDisconnected(page: Page): Promise<void> {
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible()
  await expect(page.locator(".redeem-intro-actions").getByRole("button", {name: "Connect wallet"})).toHaveAttribute(
    "data-account-target",
    "sign-in",
  )
  await expect(page.locator(".redeem-signer")).toHaveCount(0)
  await expect(page.locator("#redemption-selection")).toHaveCount(0)
}

// A signed-in document asks for the Privy bridge on load. These acceptance
// runs answer with a bridge that does nothing, so the wallet under test stays
// the deterministic one this file installs.
async function signIn(page: Page): Promise<void> {
  await page.route(bridgePattern, route =>
    route.fulfill({body: bridgeStub, contentType: "application/javascript"}),
  )

  const csrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: csrfToken} = (await csrfResponse.json()) as {csrf_token: string}
  const response = await page.request.post("/auth/privy/session", {
    headers: {
      authorization: `Bearer ${redemptionBearer}`,
      "privy-id-token": identityTokenFor(redemptionBearer),
      "x-csrf-token": csrfToken,
    },
    data: {},
  })

  expect(response.status()).toBe(200)
}

async function installWallet(page: Page): Promise<void> {
  await page.addInitScript(
    ({wallet, sendsKey}) => {
      ;(window as Window & {__regentsTestWallet?: unknown}).__regentsTestWallet = {
        address: wallet,
        provider: {
          request: async ({method, params}: {method: string; params?: unknown[]}) => {
            const testWindow = window as Window & {
              __regentsTestWallet?: {address: string}
              __ashRedemptionWalletAnswer?: string
              __ashRedemptionTransactions?: Record<string, unknown>
            }
            switch (method) {
              case "eth_chainId":
                return "0x2105"
              case "eth_accounts":
              case "eth_requestAccounts":
                return [testWindow.__regentsTestWallet?.address ?? wallet]
              case "eth_call":
                return `0x${"00".repeat(32)}`
              case "eth_sendTransaction": {
                const next = Number(sessionStorage.getItem(sendsKey) ?? "0") + 1
                sessionStorage.setItem(sendsKey, String(next))
                if (testWindow.__ashRedemptionWalletAnswer === "malformed") return "0x1"
                if (testWindow.__ashRedemptionWalletAnswer === "declined") throw {code: 4001}
                const hash = `0x${next.toString(16).padStart(64, "0")}`
                ;(testWindow.__ashRedemptionTransactions ??= {})[hash] = params?.[0]
                return hash
              }
              default:
                throw new Error(`Unexpected wallet RPC ${method}`)
            }
          },
        },
      }
    },
    {wallet, sendsKey},
  )
}

async function setWalletAnswer(page: Page, answer: "hash" | "malformed" | "declined"): Promise<void> {
  await page.evaluate(next => {
    ;(window as Window & {__ashRedemptionWalletAnswer?: string}).__ashRedemptionWalletAnswer = next
  }, answer)
}

// The `index`th transaction the wallet sent: where it went and the call it made.
async function sent(page: Page, index: number): Promise<{to: string; call: unknown}> {
  const transaction = await page.evaluate(hash => (window as Window & {
    __ashRedemptionTransactions?: Record<string, {from: string; to: string; data: Hex}>
  }).__ashRedemptionTransactions![hash]!, expectedHash(index))
  expect(transaction.from.toLowerCase()).toBe(wallet)
  const {functionName, args = []} = decodeFunctionData({abi: redemptionAbi, data: transaction.data})
  return {
    to: transaction.to.toLowerCase(),
    call: {functionName, args: args.map(arg => (typeof arg === "string" ? arg.toLowerCase() : arg))},
  }
}

async function expectResultLink(entry: Locator, index: number): Promise<void> {
  const link = entry.getByRole("link")
  await expect(link).toHaveAttribute("href", `https://basescan.org/tx/${expectedHash(index)}`)
  await expect(link).toHaveAttribute("target", "_blank")
  await expect(link).toHaveAttribute("rel", "noopener noreferrer")
}

function expectedHash(index: number): string {
  return `0x${index.toString(16).padStart(64, "0")}`
}

async function sendCount(page: Page): Promise<number> {
  return page.evaluate(key => Number(sessionStorage.getItem(key) ?? "0"), sendsKey)
}

async function selectWallet(page: Page, address: string): Promise<void> {
  await page.evaluate(next => {
    const seam = (window as Window & {__regentsTestWallet?: {address: string}})
      .__regentsTestWallet
    if (seam) seam.address = next
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}

// Counts each shake of the note beside the Redeem buttons, read every frame.
// On the first frame of each shake the approval button is pressed, so the
// press lands while the note is moving. A shake ends after ten still frames, so
// a frame that passes through the resting place mid-shake does not count twice.
async function watchShakes(page: Page): Promise<void> {
  await page.evaluate(() => {
    const testWindow = window as Window & {__redeemShakes?: number}
    testWindow.__redeemShakes = 0
    let stillFrames = Infinity
    const frame = () => {
      const note = document.querySelector("#redemption-activity-press")
      const transform = note ? getComputedStyle(note).transform : "none"
      if (transform === "none" || transform === "matrix(1, 0, 0, 1, 0, 0)") {
        stillFrames += 1
      } else {
        if (stillFrames >= 10) {
          testWindow.__redeemShakes! += 1
          document.querySelector<HTMLElement>("#redemption-approve_nft_collection")!.click()
        }
        stillFrames = 0
      }
      requestAnimationFrame(frame)
    }
    requestAnimationFrame(frame)
  })
}

async function shakes(page: Page): Promise<number> {
  return page.evaluate(() => (window as Window & {__redeemShakes?: number}).__redeemShakes!)
}

async function signOutWallet(page: Page): Promise<void> {
  await page.evaluate(() => {
    ;(window as Window & {__regentsTestWallet?: unknown}).__regentsTestWallet = undefined
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  })
}

async function scrollSnapshot(
  scroller: Locator,
  anchor: Locator,
): Promise<{top: number; height: number; anchor: number}> {
  const [scroll, anchorTop] = await Promise.all([
    scroller.evaluate(element => ({top: element.scrollTop, height: element.scrollHeight})),
    anchor.evaluate(element => element.getBoundingClientRect().top),
  ])
  return {...scroll, anchor: anchorTop}
}
