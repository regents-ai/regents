import {decodeFunctionData, parseAbi, type Hex} from "viem"
import {expect, test, type Locator, type Page} from "./support/offline"

import {addressesOutOfCase, bareAddresses} from "./support/addresses"
import {identityTokenFor} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const otherWallet = "0x2222222222222222222222222222222222222222"
const sendsKey = "regent:test:staking-wallet-sends"
const disconnectedKey = "regent:wallet-disconnected:v1"
// The sign-in this page's staking bearer names is the wallet above.
const stakingBearer = "valid-staking"
const stakingContract = "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
const stakingAbi = parseAbi([
  "function approve(address spender,uint256 amount)",
  "function stake(uint256 amount,address receiver)",
  "function claimUSDC(address receiver)",
])
const bridgePattern =
  /\/assets\/js\/privy_bridge(?:-[a-f0-9]{32})?\.js\?(?:vsn=d&)?regent_retry=\d+$/
const bridgeStub = `
export async function startPrivyBridge() {
  return {async request() {}}
}
`
// The same stub, keeping a record of what the page asked Privy for.
const bridgeRecorder = `
window.__privyRequests = window.__privyRequests || []
export async function startPrivyBridge() {
  return {async request(kind) { window.__privyRequests.push(kind) }}
}
`

test("Stake sends each press straight to the signed-in wallet and follows it on Base", async ({page}) => {
  await installWallet(page)

  await page.goto("/stake")
  await expect(page.getByRole("heading", {name: "Put REGENT to work."})).toBeVisible()
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible()

  await selectWallet(page, otherWallet)
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  await expect(page.locator("#staking-signer-wallet-full")).toHaveText(otherWallet)

  await signIn(page)
  await page.evaluate(key => localStorage.setItem(key, "true"), disconnectedKey)
  await page.route(bridgePattern, route =>
    route.fulfill({contentType: "application/javascript", body: bridgeRecorder}),
  )
  await page.goto("/stake")
  const documentStarted = await page.evaluate(() => performance.timeOrigin)

  // A signed-in page opens on the account's own position, with no wallet open yet.
  await expect(page.locator(".stake-connect-flow")).toHaveCount(0)
  await expect(page.locator("#staking-signer-wallet-full")).toHaveText(wallet)
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  await expect(page.locator("#staking-wallet-controls")).toHaveCSS("animation-name", "stake-wallet-enter")
  await page.emulateMedia({reducedMotion: "reduce"})
  await expect(page.locator("#staking-wallet-controls")).toHaveCSS("animation-name", "none")
  await page.emulateMedia({reducedMotion: "no-preference"})

  // A press with no wallet open sends nothing, names the account's wallet to
  // open, and never opens the wallet app's connect step.
  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.locator("button.stake-primary").click()
  await expect(page.locator("#staking-press-notice")).toContainText(
    "You're signed in with 0x1111..1111",
  )
  await expect(page.locator("#staking-press-notice")).toContainText(
    ", but your wallet app has no wallet open.",
  )
  expect(await privyRequests(page)).not.toContain("connect-wallet")
  expect(await page.evaluate(() => performance.timeOrigin)).toBe(documentStarted)
  expect(await sendCount(page)).toBe(0)

  // The person opens that wallet in their wallet app.
  await page.evaluate(key => {
    localStorage.removeItem(key)
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, disconnectedKey)

  // The wallet position carries its own block, which is not the block the
  // shared contract reading was taken at.
  await expect(page.locator(".stake-wallet-block")).toContainText("Base block #1,240")
  await expect(page.locator(".stake-snapshot-note")).toContainText("Base block #1,234")

  const primary = page.locator("#staking-primary")
  const activity = page.locator("#staking-activity")

  // The test wallet reports zero allowance, so the button asks for the unlimited
  // approval first, and the stake once the approval is sent.
  await expect(primary).toHaveText(/Approve REGENT/)
  await expect(page.locator(".stake-approval-note")).toContainText("one-time REGENT approval first")
  await primary.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  expect(await sent(page, 1)).toEqual({
    to: "0x6f89bca4ea5931edfcb09786267b251dee752b07",
    call: {functionName: "approve", args: [stakingContract, 2n ** 256n - 1n]},
  })
  await expect(activity.locator(`#staking-activity-${expectedHash(1)}`)).toContainText("REGENT approval")
  await expect(activity.locator(`#staking-activity-${expectedHash(1)}`)).toContainText("Sent. Waiting for Base.")
  await expect(activity.locator(`#staking-activity-${expectedHash(1)} a`)).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(1)}`,
  )

  await expect(primary).toHaveText(/Stake REGENT/)
  await primary.click()
  await expect.poll(() => sendCount(page)).toBe(2)
  expect(await sent(page, 2)).toEqual({
    to: stakingContract,
    call: {functionName: "stake", args: [10n ** 18n, wallet]},
  })
  await expect(activity.locator(`#staking-activity-${expectedHash(2)}`)).toContainText("Stake 1 REGENT")

  // The same press again is a new request, not a deduplicated or locked one.
  await primary.click()
  await expect.poll(() => sendCount(page)).toBe(3)
  await expect(activity.locator(`#staking-activity-${expectedHash(3)}`)).toContainText("Stake 1 REGENT")

  // Every claim is offered whatever the last reading from Base said about it,
  // so no control is ever disabled and each names its own step.
  await expect(page.locator("#route-content button[data-onchain-step][disabled]")).toHaveCount(0)
  for (const action of ["claim_usdc", "claim_regent", "claim_and_restake_regent"]) {
    await expect(page.locator(`#staking-${action}[data-onchain-step="${action}"]`)).toBeEnabled()
  }

  await page.getByRole("button", {name: "Claim USDC (available)", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(4)
  expect(await sent(page, 4)).toEqual({
    to: stakingContract,
    call: {functionName: "claimUSDC", args: [wallet]},
  })
  const resultLink = activity.locator(`#staking-activity-${expectedHash(4)} a`)
  await expect(resultLink).toHaveAttribute("target", "_blank")
  await expect(resultLink).toHaveAttribute("rel", "noopener noreferrer")

  await page.reload()
  await expect(page.locator("#account-chip")).toBeVisible()
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  expect(await sendCount(page)).toBe(4)
})

// Nothing is sent for a visitor who has not signed in. Every control that would
// end in a wallet request opens the Privy sign-in instead, and the visitor
// chooses the action again once they are signed in.
test("Stake opens the Privy sign-in instead of sending for a visitor with no sign-in", async ({
  page,
}) => {
  await installWallet(page)
  await page.route(bridgePattern, route =>
    route.fulfill({body: bridgeRecorder, contentType: "application/javascript"}),
  )

  await page.goto("/stake")
  await selectWallet(page, wallet)

  // The position is read and shown; every control asks for the sign-in instead.
  await expect(page.locator(".stake-wallet-summary")).toContainText("Currently staked")
  await expect(page.locator("#route-content button[data-onchain-step]")).toHaveCount(0)
  await expect(page.locator("button.stake-submit")).toHaveAttribute(
    "data-account-target",
    "sign-in",
  )

  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.locator("button.stake-submit").click()

  // The click asks Privy for the sign-in, and this page never asks Privy for the
  // connect-only path at all.
  await expect.poll(() => privyRequests(page)).toContain("sign-in")
  expect(await privyRequests(page)).not.toContain("connect-wallet")
  expect(await sendCount(page)).toBe(0)
  await expect(page.locator(".stake-notice:visible")).toHaveCount(0)
})

// Signing out ends what the page may send. The same control that sent a
// transaction a moment ago asks for the sign-in again, and nothing reaches the
// wallet until the visitor has signed back in.
test("After sign-out Stake asks for the sign-in again and sends nothing", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.route(bridgePattern, route =>
    route.fulfill({body: bridgeRecorder, contentType: "application/javascript"}),
  )

  await page.goto("/stake")
  await expect(page.locator("#account-chip")).toBeVisible()
  await expect(page.locator("#staking-claim_usdc[data-onchain-step]")).toBeEnabled()

  await signOut(page)
  // A sign-out from elsewhere closes the page's connection, and LiveView reloads
  // the page 5 to 10 seconds later.
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible({
    timeout: 15_000,
  })
  await expect(page).toHaveURL(/\/stake$/)
  await expect(page.locator("#route-content button[data-onchain-step]")).toHaveCount(0)

  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.locator("button.stake-submit").click()

  await expect.poll(() => privyRequests(page)).toContain("sign-in")
  expect(await sendCount(page)).toBe(0)
})

// Privy's active wallet is the only one that acts. When it is not one of the
// account's wallets, the figures stay the account's, a press sends nothing and
// says what to do, and a note names both wallets.
test("Stake sends nothing from a wallet that is not the account's", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/stake")
  await selectWallet(page, wallet)
  await expect(page.locator(".shell-sending-wallet")).toHaveCount(0)

  await selectWallet(page, otherWallet)
  await expect(page.locator("#staking-signer-wallet-full")).toHaveText(wallet)
  const note = page.locator(".shell-sending-wallet").first()
  await expect(note).toContainText("0x2222..2222")
  await expect(note).toContainText("0x1111..1111")

  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.locator("button.stake-primary").click()
  await expect(page.locator("#staking-press-notice")).toContainText(
    "which isn't linked to this account",
  )
  expect(await sendCount(page)).toBe(0)

  await selectWallet(page, wallet)
  await expect(page.locator(".shell-sending-wallet")).toHaveCount(0)
  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(1)
  const transactions = await page.evaluate(() => (window as Window & {
    __ashStakingTransactions?: Record<string, {from: string}>
  }).__ashStakingTransactions!)
  expect(transactions[expectedHash(1)]!.from.toLowerCase()).toBe(wallet)
  await expect(page.locator("#staking-press-notice")).toHaveCount(0)
})

// Sign out ends the wallet connection, and it stays ended across reloads
// while the browser wallet still reports the same account.
test("Sign out leaves Stake unconnected, and a reload keeps it that way", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/stake")
  await selectWallet(page, wallet)
  await expect(page.locator(".stake-wallet-summary")).toContainText("Currently staked")

  const sibling = await page.context().newPage()
  await installWallet(sibling)
  await sibling.route(bridgePattern, route => route.fulfill({body: bridgeStub, contentType: "application/javascript"}))
  await sibling.goto("/redeem")
  await expect(sibling.locator("#redemption-signer-wallet-full")).toHaveText(wallet)

  await page.locator("#account-chip").click()
  await page.getByRole("button", {name: "Sign out"}).click()

  await expectDisconnected(page)
  await expect(sibling.locator("#account-control [data-account-target='sign-in']")).toBeVisible()
  await expect(sibling.locator(".redeem-wallet-flow")).toHaveCount(0)
  await expect(sibling.locator("[data-onchain-step]")).toHaveCount(0)
  await sibling.close()
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
  await expect(page.getByRole("button", {name: "Connect wallet", exact: true})).toBeVisible()
  await expect(page.locator(".stake-wallet-summary")).toHaveCount(0)
  await expect(page.locator("#route-content button[data-onchain-step]")).toHaveCount(0)
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
      authorization: `Bearer ${stakingBearer}`,
      "privy-id-token": identityTokenFor(stakingBearer),
      "x-csrf-token": csrfToken,
    },
    data: {},
  })

  expect(response.status()).toBe(200)
}

test("Anonymous Stake dashboard is public and fits desktop and mobile widths", async ({page}) => {
  const contract = "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  const regent = "0x6f89bca4ea5931edfcb09786267b251dee752b07"
  const usdc = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

  for (const width of [1280, 390]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/stake")

    await expect(page.getByRole("heading", {name: "Put REGENT to work."})).toBeVisible()
    await expect(page.locator("#staking-contract-overview")).toContainText("REGENT supply")
    // The contract reading every visitor is shown, with the block it came from
    // and how old it is. An anonymous visitor is offered no way to replace it.
    await expect(page.locator(".stake-snapshot-note")).toContainText(
      /Confirmed at Base block #1,234, read (just now|\d+ \w+ ago)\./,
    )
    await expect(page.locator("button.stake-shared-refresh")).toHaveCount(0)

    // The hero is the two cards the contract answers for.
    const earned = page.locator(".stake-benefit-card-primary")
    await expect(earned).toContainText("USDC revenue")
    await expect(earned).toContainText("Last 7 days")
    await expect(earned).toContainText("1,250.50 USDC")
    await expect(earned).toContainText("Lifetime")
    await expect(earned).toContainText("5,074.87 USDC")
    await expect(earned).toContainText("Paid to stakers (lifetime)")
    await expect(earned).toContainText("353.24 USDC")

    // How it pays names the contract's own divisor, reward pool and Safe, each
    // read at the same block, and both addresses can be copied in full.
    const pays = page.locator("#staking-how-it-pays")
    await expect(pays).toContainText("÷ 1k.")
    await expect(pays).toContainText("a reward pool, 5 billion today")
    await expect(pays).toContainText("Regent Safe (2 of 3 signers)")
    await expect(pays.locator("#staking-how-safe")).toBeVisible()
    await expect(page.locator(".stake-benefit-grid")).toContainText("REGENT Staked")
    await expect(page.locator(".stake-benefit-grid")).toContainText("100 REGENT")

    // The supply block: three figures and one bar carrying both proportions.
    const supply = page.locator(".stake-supply-facts")
    await expect(supply).toContainText("Circulating supply")
    await expect(supply).toContainText("35 billion REGENT")
    await expect(supply).toContainText("Total supply")
    await expect(supply).toContainText("100 billion REGENT")
    await expect(page.locator("#staking-supply-bar")).toContainText(
      "Circulating supply staked",
    )

    await page.locator(".stake-contract-details summary").click()
    const details = page.locator("#stake-contract-details")
    await expect(details.locator("#stake-details-contract-full")).toHaveText(contract)
    await expect(details.locator("#stake-details-regent-full")).toHaveText(regent)
    await expect(details.locator("#stake-details-usdc-full")).toHaveText(usdc)

    const bar = page.locator("#staking-supply-bar").getByRole("meter")
    await expect(bar).toHaveAttribute("aria-valuenow", "0")
    await expect(bar).toHaveAttribute("aria-valuetext", "Circulating supply staked: 0%; Circulating supply unstaked: 100%")

    const contractLink = page.getByRole("link", {
      name: "View verified staking contract on BaseScan",
    })
    await expect(contractLink).toHaveAttribute(
      "href",
      `https://basescan.org/address/${contract}`,
    )
    await expect(contractLink).toHaveAttribute("target", "_blank")
    await expect(contractLink).toHaveAttribute("rel", "noopener noreferrer")

    const connect = page.getByRole("button", {name: "Connect wallet", exact: true})
    await expect(connect).toBeVisible()
    // Connecting a wallet here is the Privy sign-in, the same one the header runs.
    await expect(connect).toHaveAttribute("data-account-target", "sign-in")
    await expect(page.getByText("Available REGENT", {exact: true})).toHaveCount(0)
    await expect(page.getByText("Currently staked", {exact: true})).toHaveCount(0)
    await expect(page.locator("#route-content button[data-onchain-step]")).toHaveCount(0)

    const fit = await page.evaluate(viewport => {
      const addresses = [...document.querySelectorAll<HTMLElement>(
        ".stake-contract-facts :is(code, .rg-address)",
      )]
      return {
        addresses: addresses.map(node => node.scrollWidth - node.clientWidth),
        document: document.documentElement.scrollWidth - viewport,
      }
    }, width)

    expect(fit, `Stake dashboard at ${width}`).toEqual({
      addresses: [0, 0, 0, 0],
      document: 0,
    })

    const columns = await page
      .locator(".stake-layout")
      .evaluate(element => getComputedStyle(element).gridTemplateColumns.split(" ").length)
    expect(columns, `Stake dashboard columns at ${width}`).toBe(width > 768 ? 2 : 1)

    const presentation = await page.evaluate(() => {
      const staked = document.querySelector<HTMLElement>(
        ".stake-benefit-card:not(.stake-benefit-card-primary) dd",
      )!
      const supply = document.querySelector<HTMLElement>(".stake-supply-facts dd")!
      const contractLink = document.querySelector<HTMLElement>(".stake-contract-link")!
      return {
        contractLinkHeight: contractLink.getBoundingClientRect().height,
        supplyFont: Number.parseFloat(getComputedStyle(supply).fontSize),
        stakedFont: Number.parseFloat(getComputedStyle(staked).fontSize),
      }
    })

    // The staked figure leads in the hero card and is repeated at reading size
    // in the supply block, so the hero has to be the larger of the two.
    expect(presentation.stakedFont).toBeGreaterThan(presentation.supplyFont)
    expect(presentation.contractLinkHeight).toBeGreaterThanOrEqual(44)
  }
})

// Every address Stake and Redeem show opens and copies in full: the dashboard,
// its supply window, both Verification lists, the wallet each panel acts for,
// the notes that name a wallet and the Buy Credits window's paying wallet,
// signed out and signed in, at both widths.
test("Stake and Redeem draw every address with the address primitive", async ({page}) => {
  await installWallet(page)

  const walk = async (signedIn: boolean, width: number) => {
    const at = `${signedIn ? "signed in" : "signed out"} at ${width}`

    await page.goto("/stake")
    await expect(page.getByRole("heading", {name: "Put REGENT to work."})).toBeVisible()
    await selectWallet(page, signedIn ? otherWallet : wallet)
    await expect(page.locator(".stake-signer")).toBeVisible()
    if (signedIn) {
      // A wallet the account does not link: the notes name both wallets.
      await expect(page.locator(".shell-sending-wallet").first()).toBeVisible()
      await page.getByLabel("Amount", {exact: true}).fill("1")
      await page.locator("button.stake-primary").click()
      await expect(page.locator("#staking-press-notice")).toContainText("isn't linked to this account")
    }
    await page.locator(".stake-contract-details summary").click()
    await expect(page.locator(".stake-contract-facts")).toBeVisible()
    await page.getByRole("button", {name: "What is not circulating"}).first().click()
    const supply = page.locator("#staking-supply-dialog")
    await expect(supply.locator(".stake-holdings")).toBeVisible()
    expect(await bareAddresses(page), `/stake ${at}`).toEqual([])
    expect(await addressesOutOfCase(page), `/stake ${at}`).toEqual([])
    await supply.getByRole("button", {name: "Done"}).click()
    await expect(supply).toBeHidden()
    if (signedIn) {
      // The Buy Credits window names the wallet it pays from.
      const credits = page.locator("#shell-credits")
      await page.locator("#shell-credits-button").click()
      await expect(credits.locator(".credits-panel__wallet .rg-address")).toBeVisible()
      expect(await bareAddresses(page), `Buy Credits ${at}`).toEqual([])
      expect(await addressesOutOfCase(page), `Buy Credits ${at}`).toEqual([])
      await credits.getByRole("button", {name: "Close"}).click()
      await expect(credits).toBeHidden()
    }

    await page.goto("/redeem")
    await expect(page.locator("#redemption-collections")).toBeVisible()
    await selectWallet(page, signedIn ? otherWallet : wallet)
    await expect(page.locator(".redeem-signer")).toBeVisible()
    if (signedIn) await expect(page.locator(".shell-sending-wallet").first()).toBeVisible()
    await page.locator(".redeem-contract-details summary").click()
    await expect(page.locator(".redeem-contract-details dl")).toBeVisible()
    expect(await bareAddresses(page), `/redeem ${at}`).toEqual([])
    expect(await addressesOutOfCase(page), `/redeem ${at}`).toEqual([])
  }

  for (const width of [1280, 390]) {
    await page.setViewportSize({width, height: 900})
    await walk(false, width)
  }

  await signIn(page)
  for (const width of [1280, 390]) {
    await page.setViewportSize({width, height: 900})
    await walk(true, width)
  }
})

// The other address a stake goes to shows in two forms. The warning in its window
// shows every character, wrapping, for the person to check, with the copy icon
// and Basescan arrow after it. Under "Rewards go to" the compact form holds the
// short form and the copy icon, beside Change. Both copy the whole address, and
// a copy press neither ticks the warning nor unticks the choice. No label on the
// page holds a button or link: the warning's words tick its box, and the box is
// named by the sentence alone. Nothing on the page names the address outside
// the primitive or scrolls sideways, signed out and signed in, at every width,
// light and dark.
test("Stake shows the other address in full in the warning and compact under Rewards go to", async ({page}) => {
  // Twelve walks (signed out and in, light and dark, three widths) take about 25 seconds alone.
  test.setTimeout(120_000)
  await page.context().grantPermissions(["clipboard-read", "clipboard-write"])
  await installWallet(page)
  const toggle = page.locator("#staking-for-other")
  const dialog = page.locator("#staking-recipient-dialog")
  const acknowledgment = page.locator("#staking-recipient-acknowledged")
  const full = page.locator("#staking-recipient-address")
  const compact = page.locator("#staking-for-other-address")
  const copied = async (icon: Locator) => {
    await page.evaluate(() => navigator.clipboard.writeText(""))
    await icon.click()
    return page.evaluate(() => navigator.clipboard.readText())
  }
  const sideways = () => page.evaluate(() => document.documentElement.scrollWidth > innerWidth)

  const walk = async (at: string) => {
    await page.goto("/stake")
    await selectWallet(page, wallet)
    await page.getByLabel("Amount", {exact: true}).fill("1")
    await toggle.check()
    await expect(dialog).toBeVisible()
    await page.getByLabel("Receiving Ethereum address", {exact: true}).fill(otherWallet)

    await expect(full, at).toHaveClass(/\brg-address--full\b/)
    await expect(full.locator(".rg-address__words"), at).toHaveText(otherWallet)
    await expect(full.locator(".rg-address__explorer"), at).toBeVisible()
    // Every character sits inside the window: none cut off or hidden past its edge.
    const inside = await full.evaluate(address => {
      const window = address.closest("dialog")!.getBoundingClientRect()
      const words = document.createRange()
      words.selectNodeContents(address.querySelector(".rg-address__words")!)
      const icons = [...address.querySelectorAll(".rg-copy--icon, .rg-address__explorer")].map(icon =>
        icon.getBoundingClientRect(),
      )
      return [...words.getClientRects(), ...icons].every(
        line => line.left >= window.left && line.right <= window.right && line.width > 0,
      )
    })
    expect(inside, at).toBe(true)
    expect(await sideways(), at).toBe(false)
    expect(await bareAddresses(page), `warning ${at}`).toEqual([])
    expect(await addressesOutOfCase(page), `warning ${at}`).toEqual([])
    expect(await copied(full.locator(".rg-copy--icon")), at).toBe(otherWallet)
    await expect(acknowledgment, at).not.toBeChecked()
    // No press inside a label anywhere on the page, and the box is named by the
    // warning's sentence with the address read once, never by its icons.
    await expect(page.locator("label :is(button, a)"), at).toHaveCount(0)
    await expect(acknowledgment, at).toHaveAccessibleName(
      `Warning: the wallet ${otherWallet} will accrue the USDC revenue and REGENT rewards, and only that wallet may withdraw the tokens.`,
    )
    // The hidden copy that holds the warning's room is exactly as tall, so the
    // window keeps one height whichever of the two shows.
    const [room, shown] = await page
      .locator(".stake-recipient-note > .stake-check")
      .evaluateAll(checks => checks.map(check => check.getBoundingClientRect().height))
    expect(Math.abs(room - shown), at).toBeLessThan(0.5)
    await dialog.screenshot({path: test.info().outputPath(`warning-${at.replaceAll(" ", "-")}.png`)})
    // The warning's words tick the box.
    await page.locator("#staking-recipient-warning-text").getByText("will accrue the USDC revenue").click()
    await expect(acknowledgment, at).toBeChecked()
    await dialog.getByRole("button", {name: "Done", exact: true}).click()
    await expect(dialog).toBeHidden()

    await expectRewardsGoTo(page)
    await expect(compact, at).toHaveClass(/\brg-address--compact\b/)
    await expect(compact.locator(".rg-address__explorer"), at).toHaveCount(0)
    // The short form shows whole, and the row stays inside the form.
    const fits = await compact.evaluate(address => {
      const label = address.querySelector(".rg-address__label")!
      const form = document.querySelector("#staking-amount-form")!.getBoundingClientRect()
      const row = address.closest(".stake-for-other")!.getBoundingClientRect()
      return label.scrollWidth <= label.clientWidth && row.left >= form.left && row.right <= form.right
    })
    expect(fits, at).toBe(true)
    expect(await sideways(), at).toBe(false)
    expect(await bareAddresses(page), `row ${at}`).toEqual([])
    expect(await addressesOutOfCase(page), `row ${at}`).toEqual([])
    expect(await copied(compact.locator(".rg-copy--icon")), at).toBe(otherWallet)
    await expect(toggle, at).toBeChecked()
    await expect(page.locator("label :is(button, a)"), `row ${at}`).toHaveCount(0)
    await page
      .locator("#staking-amount-form")
      .screenshot({path: test.info().outputPath(`rewards-go-to-${at.replaceAll(" ", "-")}.png`)})
  }

  for (const signedIn of [false, true]) {
    if (signedIn) await signIn(page)
    for (const theme of ["light", "dark"]) {
      await page.context().addCookies([
        {name: "regent_theme", value: theme, url: test.info().project.use.baseURL as string},
      ])
      for (const width of [1280, 390, 320]) {
        await page.setViewportSize({width, height: 900})
        await walk(`${signedIn ? "signed in" : "signed out"} ${theme} ${width}`)
      }
    }
  }
})

test("Public Redeem collection cards fit desktop, tablet and mobile widths", async ({page}) => {
  for (const width of [1280, 768, 390]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/redeem")
    await expect(page.locator(".redeem-collection-grid")).toBeVisible()

    const fit = await page.locator(".redeem-collection-card dd").first().evaluate(
      (node, viewport) => {
        node.textContent = "7,390,000,000 / 7,390,000,000"
        const card = node.closest(".redeem-collection-card") as HTMLElement
        return {
          card: card.scrollWidth - card.clientWidth,
          document: document.documentElement.scrollWidth - viewport,
        }
      },
      width,
    )

    expect(fit, `/redeem at ${width}`).toEqual({card: 0, document: 0})

    const columns = await page
      .locator(".redeem-collection-grid")
      .evaluate(element => getComputedStyle(element).gridTemplateColumns.split(" ").length)
    expect(columns, `/redeem at ${width}`).toBe(width > 800 ? 3 : 1)

    // The shared panel paints its fill and its 1px edge in pseudo-elements, so the
    // card's own box stays transparent and borderless by design.
    const presentation = await page.locator(".redeem-collection-card .rg-panel").first().evaluate(element => ({
      edge: getComputedStyle(element, "::before").backgroundColor,
      fill: getComputedStyle(element, "::after").backgroundColor,
      host: getComputedStyle(element).backgroundColor,
    }))
    expect(presentation.fill).not.toBe("rgba(0, 0, 0, 0)")
    expect(presentation.edge).not.toBe("rgba(0, 0, 0, 0)")
    expect(presentation.edge).not.toBe(presentation.fill)
    expect(presentation.host).toBe("rgba(0, 0, 0, 0)")
  }
})

// An approval whose wallet answer is not a transaction hash may still have been
// sent, so the page says to check the wallet, and leaves the amount exactly
// where the customer typed it so the same press can be made again.
test("Stake says to check the wallet when an approval returns no usable hash", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.goto("/stake")
  await selectWallet(page, wallet)
  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.evaluate(() => {
    ;(window as Window & {__ashStakingMalformedApproval?: boolean})
      .__ashStakingMalformedApproval = true
  })

  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(page.locator("#staking-press-notice")).toHaveText(
    "Your wallet may have sent this. Check your wallet activity.",
  )
  await expect(page.locator("#staking-activity li")).toHaveCount(0)
  await expect(page.locator("button.stake-submit")).toBeEnabled()
  await expect(page.locator("button.stake-submit")).toHaveText(/Approve REGENT/)
  await expect(page.getByLabel("Amount", {exact: true})).toHaveValue("1")
  expect(await sendCount(page)).toBe(1)
})

// The approval prompt a customer dismisses, or never finds behind the browser
// window, is the common way a stake stops before it starts.
test("Stake says the wallet declined when the approval is rejected", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.goto("/stake")
  await selectWallet(page, wallet)
  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.evaluate(() => {
    ;(window as Window & {__ashStakingRejectedApproval?: boolean})
      .__ashStakingRejectedApproval = true
  })

  const primary = page.locator("button.stake-primary")
  await primary.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(page.locator("#staking-press-notice")).toHaveText(
    "Your wallet declined this. Nothing was sent.",
  )
  await expect(primary).toHaveText(/Approve REGENT/)

  // The next press — the wallet takes this one — clears the notice.
  await primary.click()
  await expect.poll(() => sendCount(page)).toBe(2)
  await expect(page.locator(`#staking-activity-${expectedHash(2)}`)).toContainText("REGENT approval")
  await expect(page.locator("#staking-press-notice")).toHaveCount(0)
})

test("Alternate stake requires fresh address consent and credits that address", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.goto("/stake")
  await selectWallet(page, wallet)
  await page.getByLabel("Amount", {exact: true}).fill("1")
  const toggle = page.locator("#staking-for-other")
  const row = page.locator(".stake-for-other")
  const change = page.locator("#staking-recipient-change")
  const dialog = page.locator("#staking-recipient-dialog")
  const done = dialog.getByRole("button", {name: "Done", exact: true})
  const receiver = page.getByLabel("Receiving Ethereum address", {exact: true})
  const acknowledgment = page.locator("#staking-recipient-acknowledged")
  const warning = page.locator("#staking-recipient-warning")
  const notice = page.locator("#staking-press-notice")
  const submit = page.locator("button.stake-submit")

  // Ticking the box opens the window with the address field ready to type in.
  await expect(dialog).toBeHidden()
  await toggle.focus()
  await page.keyboard.press("Space")
  await expect(dialog).toBeVisible()
  await expect(receiver).toBeFocused()
  await expect(page.locator(".stake-preview")).toBeHidden()
  for (const invalid of ["alice.eth", "0x1234", "0x" + "0".repeat(40)]) {
    if (!(await dialog.isVisible())) await change.click()
    await receiver.fill(invalid)
    await expect(receiver).toHaveAttribute("aria-invalid", "true")
    await expect(warning).toBeHidden()
    await done.click()
    await expect(dialog).toBeHidden()
    await expect(row).toHaveText(/No address yet\s*Add/)
    await submit.click()
    await expect(notice).toHaveText("Enter a valid receiving address. Nothing was sent.")
    expect(await sendCount(page)).toBe(0)
  }

  await change.click()
  await receiver.fill(otherWallet)
  await expect(warning).toContainText(
    `the wallet ${otherWallet} will accrue the USDC revenue and REGENT rewards, and only that wallet may withdraw the tokens`,
  )
  // Escape closes the window as Done does.
  await page.keyboard.press("Escape")
  await expect(dialog).toBeHidden()
  await expect(row).toHaveText(/No address yet\s*Add/)
  await submit.click()
  await expect(notice).toHaveText("Tick the warning about the receiving address first. Nothing was sent.")
  expect(await sendCount(page)).toBe(0)

  await change.click()
  await acknowledgment.check()
  await receiver.fill(wallet)
  await expect(warning).toContainText(`the wallet ${wallet} will accrue`)
  await receiver.fill(otherWallet)
  await expect(warning).toContainText(`the wallet ${otherWallet} will accrue`)
  await expect(acknowledgment).not.toBeChecked()
  await acknowledgment.check()
  await done.click()
  await expectRewardsGoTo(page)
  await toggle.uncheck()
  await expect(dialog).toBeHidden()
  await expect(row).toHaveText("Stake for a different address")
  await toggle.check()
  await expect(dialog).toBeVisible()
  await expect(acknowledgment).not.toBeChecked()
  await acknowledgment.check()
  await done.click()
  const unstakeTab = page.getByRole("tab", {name: "Unstake", exact: true})
  await unstakeTab.click()
  await expect(toggle).toBeHidden()
  // The chosen mode's fill glides to the tab that was pressed.
  await expect
    .poll(async () => {
      const ink = await page.locator(".stake-mode__ink").boundingBox()
      const tab = await unstakeTab.boundingBox()
      return ink && tab && Math.abs(ink.x - tab.x)
    })
    .toBeLessThan(1)
  await page.getByRole("tab", {name: "Stake", exact: true}).click()
  await expect(acknowledgment).not.toBeChecked()
  await expect(row).toHaveText(/No address yet\s*Add/)
  await change.click()
  await acknowledgment.check()
  await done.click()
  // The signed-in position stays put while the open wallet changes, so the
  // chosen destination and its acknowledgment stay too.
  await selectWallet(page, otherWallet)
  await selectWallet(page, wallet)
  await expect(page.locator("#staking-signer-wallet-full")).toHaveText(wallet)
  await expect(receiver).toHaveValue(otherWallet)
  await expect(acknowledgment).toBeChecked()
  // A normal LiveView amount update preserves the acknowledged destination.
  await page.getByLabel("Amount", {exact: true}).fill("2")
  await expect(page.locator(".stake-preview")).toBeHidden()
  await expect(acknowledgment).toBeChecked()
  await expectRewardsGoTo(page)

  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({width, height: 900})
    await change.click()
    await expect(warning).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    const box = (await dialog.boundingBox())!
    expect(box.x).toBeGreaterThanOrEqual(0)
    expect(box.x + box.width).toBeLessThanOrEqual(width)
    if (width === 390) {
      await page.emulateMedia({reducedMotion: "reduce"})
      await acknowledgment.focus()
      await expect(acknowledgment).toBeFocused()
      await dialog.screenshot({path: test.info().outputPath("stake-recipient-mobile.png")})
    }
    await done.click()
    await expect(dialog).toBeHidden()
  }
  await page.setViewportSize({width: 390, height: 900})
  await submit.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(submit).toHaveText(/Stake REGENT/)
  await submit.click()
  await expect.poll(() => sendCount(page)).toBe(2)
  const forOther = page.locator(`#staking-activity-${expectedHash(2)}`)
  await expect(forOther).toContainText("Stake 2 REGENT for")
  // The address the stake went to opens and copies in full.
  await expect(forOther.locator("strong .rg-address__full")).toHaveText(otherWallet)
  expect(await bareAddresses(page, "#staking-activity")).toEqual([])
  // The list's own link style leaves the address's Basescan arrow the size of its copy icon.
  const [copyHeight, arrowHeight] = await forOther.locator("strong .rg-address").evaluate(address =>
    [".rg-copy--icon", ".rg-address__explorer"].map(icon => address.querySelector(icon)!.getBoundingClientRect().height),
  )
  expect(arrowHeight).toBe(copyHeight)
  expect(await sent(page, 2)).toEqual({
    to: stakingContract,
    call: {functionName: "stake", args: [2n * 10n ** 18n, otherWallet]},
  })
  await toggle.uncheck()
  await expect(dialog).toBeHidden()
  await expect(row).toHaveText("Stake for a different address")
  await expect(page.locator(".stake-preview")).toBeVisible()
})

// Choices never change the height: whatever the different-address box shows,
// the Stake panel keeps one height, so nothing below it moves. A stake of your
// own leaves no blank room below the form; a stake for someone else holds only
// the room of the position preview it has no figures for.
test("Stake keeps one height whatever the different-address box shows", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/stake")
    await selectWallet(page, wallet)
    await page.getByLabel("Amount", {exact: true}).fill("1")
    const panel = page.locator(".stake-actions")
    const toggle = page.locator("#staking-for-other")
    const row = page.locator(".stake-for-other")
    const dialog = page.locator("#staking-recipient-dialog")
    const receiver = page.getByLabel("Receiving Ethereum address", {exact: true})
    const height = async () => (await panel.boundingBox())!.height
    // The room between the form's last shown row and its foot.
    const band = () =>
      page.evaluate(() => {
        const form = document.querySelector("#staking-amount-form")!
        const shown = [...form.children].filter(
          child => child.tagName !== "DIALOG" && child.checkVisibility({visibilityProperty: true}),
        )
        const last = Math.max(...shown.map(child => child.getBoundingClientRect().bottom))
        return form.getBoundingClientRect().bottom - last
      })
    // The choice's words and its box share the first line. Once an address is
    // set, it sits under the words with Change beside it; until then Add sits
    // beside the words. All of it stays inside the form and clear of "Amount".
    const rows = async () => {
      const fit = await page.evaluate(() => {
        const words = (el: Element) => {
          if (el.tagName !== "BUTTON") return el.getBoundingClientRect()
          // Add or Change's own words, not the taller press area around them.
          const range = document.createRange()
          range.selectNodeContents(el)
          return range.getBoundingClientRect()
        }
        const middle = (rect: DOMRect) => rect.top + rect.height / 2
        const row = document.querySelector(".stake-for-other")!
        const form = document.querySelector("#staking-amount-form")!.getBoundingClientRect()
        const label = document.querySelector("label[for='staking-amount']")!.getBoundingClientRect()
        const box = document.querySelector("#staking-for-other")!.getBoundingClientRect()
        const text = document.querySelector("#staking-for-other-text")!.getBoundingClientRect()
        const button = document.querySelector("#staking-recipient-change")
        const change = button && words(button)
        const named = document.querySelector("#staking-for-other-address")
        const address = named?.getBoundingClientRect()
        const parts = [box, text, change, address, ...[...row.querySelectorAll(".rg-address__label, .rg-copy--icon")].map(words)].filter(
          (part): part is DOMRect => !!part,
        )
        const overlaps = (a: DOMRect, b: DOMRect) =>
          a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
        return {
          boxBesideWords: Math.abs(middle(box) - middle(text)),
          changeLine: change ? Math.abs(middle(change) - middle(address ?? text)) : 0,
          addressUnderWords: address ? address.top - text.bottom : 0,
          addressFromWords: address ? Math.abs(address.left - text.left) : 0,
          past: Math.max(0, ...parts.map(part => Math.max(form.left - part.left, part.right - form.right))),
          clear: parts.every(part => !overlaps(part, label)),
        }
      })
      expect(fit.clear).toBe(true)
      expect(fit.past).toBeLessThan(0.5)
      expect(fit.boxBesideWords).toBeLessThan(4)
      expect(fit.changeLine).toBeLessThan(4)
      expect(fit.addressUnderWords).toBeGreaterThanOrEqual(-0.5)
      expect(fit.addressFromWords).toBeLessThan(1)
    }
    await expect(page.locator(".stake-preview")).toBeVisible()
    const unticked = await height()
    const previewRoom = (await page.locator(".stake-preview").boundingBox())!.height
    expect(await band()).toBeLessThan(1)
    await rows()
    // What is available stays readable beside or above 50% and Max, never under them.
    const available = await page.evaluate(() => {
      const line = document.querySelector("#staking-available")!
      const words = document.createRange()
      words.selectNodeContents(line)
      const text = words.getBoundingClientRect()
      const shortcuts = document.querySelector(".stake-amount-shortcuts")!.getBoundingClientRect()
      return {
        under:
          text.left < shortcuts.right &&
          shortcuts.left < text.right &&
          text.top < shortcuts.bottom &&
          shortcuts.top < text.bottom,
        lines: Math.round(text.height / Number.parseFloat(getComputedStyle(line).lineHeight)),
      }
    })
    expect(available.under, `Available at ${width}`).toBe(false)
    expect(available.lines, `Available at ${width}`).toBeLessThanOrEqual(2)

    await toggle.check()
    await expect(dialog).toBeVisible()
    expect(await height()).toBeCloseTo(unticked, 0)

    await receiver.fill("0x1234")
    await expect(receiver).toHaveAttribute("aria-invalid", "true")
    expect(await height()).toBeCloseTo(unticked, 0)

    await receiver.fill(otherWallet)
    await expect(page.locator("#staking-recipient-warning")).toBeVisible()
    expect(await height()).toBeCloseTo(unticked, 0)
    await page.keyboard.press("Escape")
    await expect(row).toHaveText(/No address yet\s*Add/)
    expect(await height()).toBeCloseTo(unticked, 0)
    await rows()
    await page.locator("#staking-recipient-change").click()

    await page.locator("#staking-recipient-acknowledged").check()
    await dialog.getByRole("button", {name: "Done", exact: true}).click()
    await expectRewardsGoTo(page)
    expect(await height()).toBeCloseTo(unticked, 0)
    expect(await band()).toBeLessThanOrEqual(previewRoom + 12)
    await rows()
    // A mouse keeps the choice and Change at the size of their words.
    for (const area of await pressAreas(page)) {
      expect(area.height, `${area.selector} at ${width}`).toBeLessThan(30)
    }
    // The form alone fits the screen at every width, so its picture is whole.
    await page
      .locator("#staking-amount-form")
      .screenshot({path: test.info().outputPath(`stake-other-address-${width}.png`)})

    // Tab from Amount to the Stake button only lands on rows a person can see,
    // ticked here and unticked below.
    const tabToStake = async () => {
      await page.getByLabel("Amount", {exact: true}).focus()
      let reachedSubmit = false
      for (let press = 0; press < 8 && !reachedSubmit; press++) {
        await page.keyboard.press("Tab")
        const focused = await page.evaluate(() => {
          const el = document.activeElement as HTMLElement
          return {
            seen: el.checkVisibility({visibilityProperty: true}) && !el.closest("[inert]"),
            submit: el.matches("button.stake-submit"),
          }
        })
        expect(focused.seen).toBe(true)
        reachedSubmit = focused.submit
      }
      expect(reachedSubmit).toBe(true)
    }
    await tabToStake()

    await toggle.uncheck()
    await expect(dialog).toBeHidden()
    expect(await height()).toBeCloseTo(unticked, 0)
    expect(await band()).toBeLessThan(1)
    await tabToStake()

    // Unstake has its own height, whichever way the box was left on Stake.
    const unstakeTab = page.getByRole("tab", {name: "Unstake", exact: true})
    const stakeTab = page.getByRole("tab", {name: "Stake", exact: true})
    await unstakeTab.click()
    await expect(toggle).toBeHidden()
    const unstake = await height()
    await stakeTab.click()
    await toggle.check()
    await page.keyboard.press("Escape")
    await expect(dialog).toBeHidden()
    await unstakeTab.click()
    await expect(toggle).toBeHidden()
    expect(await height()).toBeCloseTo(unstake, 0)
  }
})

// The choice and Change each take a press 44 px tall, and Change 44 px wide, at
// every edge of that area, on a touch phone.
test.describe("on a touch phone", () => {
  test.use({hasTouch: true, isMobile: true})

  test("Stake gives the different-address choice finger-sized press areas", async ({page}) => {
    await installWallet(page)
    await signIn(page)

    for (const width of [390, 320]) {
      await page.setViewportSize({width, height: 900})
      await page.goto("/stake")
      await selectWallet(page, wallet)
      await page.getByLabel("Amount", {exact: true}).fill("1")
      await page.locator("#staking-for-other").check()
      await page.getByLabel("Receiving Ethereum address", {exact: true}).fill(otherWallet)
      await page.locator("#staking-recipient-acknowledged").check()
      await page.locator("#staking-recipient-dialog").getByRole("button", {name: "Done", exact: true}).click()
      await expectRewardsGoTo(page)
      await page.locator(".stake-for-other").scrollIntoViewIfNeeded()

      const areas = await pressAreas(page)
      for (const area of areas) {
        expect(area.height, `${area.selector} at ${width}`).toBeGreaterThanOrEqual(44)
        expect(area.pressed, `${area.selector} at ${width}`).toBe(true)
      }
      expect(areas[1].width, `Change at ${width}`).toBeGreaterThanOrEqual(44)
    }
  })
})

// The choice names the other address under "Rewards go to", in its compact
// form, with Change beside it.
async function expectRewardsGoTo(page: Page): Promise<void> {
  await expect(page.locator("#staking-for-other-text")).toHaveText("Rewards go to")
  await expect(page.locator("#staking-for-other-address .rg-address__label")).toHaveText("0x2222..2222")
  await expect(page.locator("#staking-for-other-address .rg-address__full")).toHaveText(otherWallet)
  await expect(page.locator("#staking-recipient-change")).toHaveText("Change")
}

// The size of the choice and of Change, and whether a press at every edge of
// each lands on it.
function pressAreas(page: Page) {
  return page.evaluate(() =>
    ["label[for='staking-for-other']", "#staking-recipient-change"].map(selector => {
      const control = document.querySelector(selector)!
      const box = control.getBoundingClientRect()
      const middle = {x: box.left + box.width / 2, y: box.top + box.height / 2}
      const edges = [
        [middle.x, box.top + 1],
        [middle.x, box.bottom - 1],
        [box.left + 1, middle.y],
        [box.right - 1, middle.y],
      ]
      return {
        selector,
        width: box.width,
        height: box.height,
        pressed: edges.every(([x, y]) => control.contains(document.elementFromPoint(x, y))),
      }
    }),
  )
}

async function signOut(page: Page): Promise<void> {
  const csrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: csrfToken} = (await csrfResponse.json()) as {csrf_token: string}
  const response = await page.request.delete("/auth/privy/session", {
    headers: {"x-csrf-token": csrfToken},
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
            switch (method) {
              case "eth_chainId":
                return "0x2105"
              case "eth_accounts":
              case "eth_requestAccounts":
                return [
                  (window as Window & {__regentsTestWallet?: {address: string}})
                    .__regentsTestWallet?.address ?? wallet,
                ]
              case "eth_call":
                return `0x${"00".repeat(32)}`
              case "eth_sendTransaction": {
                const next = Number(sessionStorage.getItem(sendsKey) ?? "0") + 1
                sessionStorage.setItem(sendsKey, String(next))
                if (
                  next === 1 &&
                  (window as Window & {__ashStakingMalformedApproval?: boolean})
                    .__ashStakingMalformedApproval
                ) return "0x1"
                if (
                  next === 1 &&
                  (window as Window & {__ashStakingRejectedApproval?: boolean})
                    .__ashStakingRejectedApproval
                ) throw {code: 4001}
                const hash = `0x${next.toString(16).padStart(64, "0")}`
                const transactions = ((window as Window & {
                  __ashStakingTransactions?: Record<string, unknown>
                }).__ashStakingTransactions ??= {})
                transactions[hash] = params?.[0]
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

// The `index`th transaction the wallet sent: where it went and the call it made.
async function sent(page: Page, index: number): Promise<{to: string; call: unknown}> {
  const transaction = await page.evaluate(hash => (window as Window & {
    __ashStakingTransactions?: Record<string, {from: string; to: string; data: Hex}>
  }).__ashStakingTransactions![hash]!, expectedHash(index))
  expect(transaction.from.toLowerCase()).toBe(wallet)
  const {functionName, args} = decodeFunctionData({abi: stakingAbi, data: transaction.data})
  return {
    to: transaction.to.toLowerCase(),
    call: {functionName, args: args.map(arg => (typeof arg === "string" ? arg.toLowerCase() : arg))},
  }
}

function expectedHash(index: number): string {
  return `0x${index.toString(16).padStart(64, "0")}`
}

async function privyRequests(page: Page): Promise<string[]> {
  return page.evaluate(
    () => (window as Window & {__privyRequests?: string[]}).__privyRequests ?? [],
  )
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

test("Stake shows when Base was last read and reads it again on the icon", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  for (const width of [1280, 390]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/stake")
    await selectWallet(page, wallet)

    const lastRead = page.locator("#stake-read")
    await expect(lastRead.locator("time")).toHaveText(/Updated \d{1,2} \w{3}, \d{2}:\d{2} UTC/)
    const again = page.getByRole("button", {name: "Read Base again", exact: true})
    await expect(again).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)

    await again.click()
    await expect(page.locator(".stake-supply-facts")).toBeVisible()
    await expect(page.getByText("Couldn’t update just now.")).toHaveCount(0)
    await page.screenshot({path: `${process.env.REGENTS_SHOT_DIR ?? "test-results"}/stake-read-${width}.png`})
  }
})
