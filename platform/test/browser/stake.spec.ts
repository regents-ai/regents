import {decodeFunctionData, parseAbi, type Hex} from "viem"
import {expect, test, type Page} from "@playwright/test"

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
  await expect(page.locator(".stake-signer")).toHaveAttribute("title", otherWallet)

  await signIn(page)
  await page.evaluate(key => localStorage.setItem(key, "true"), disconnectedKey)
  await page.route(bridgePattern, route => route.fulfill({
    contentType: "application/javascript",
    body: `export async function startPrivyBridge() {
      return {async request(kind) {
        if (kind !== "connect-wallet") return;
        localStorage.removeItem("${disconnectedKey}");
        window.dispatchEvent(new CustomEvent("ash:wallet-state"));
      }};
    }`,
  }))
  await page.goto("/stake")
  const documentStarted = await page.evaluate(() => performance.timeOrigin)

  // A signed-in page opens on the account's own position, with no wallet open yet.
  await expect(page.locator(".stake-connect-flow")).toHaveCount(0)
  await expect(page.locator(".stake-signer")).toHaveAttribute("title", wallet)
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  await expect(page.locator("#staking-wallet-controls")).toHaveCSS("animation-name", "stake-wallet-enter")
  await page.emulateMedia({reducedMotion: "reduce"})
  await expect(page.locator("#staking-wallet-controls")).toHaveCSS("animation-name", "none")
  await page.emulateMedia({reducedMotion: "no-preference"})

  // A press with no wallet open asks the wallet app to connect, in place.
  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.locator("button.stake-primary").click()
  await expect
    .poll(() => page.evaluate(key => localStorage.getItem(key), disconnectedKey))
    .toBeNull()
  expect(await page.evaluate(() => performance.timeOrigin)).toBe(documentStarted)
  expect(await sendCount(page)).toBe(0)

  // The wallet position carries its own block, which is not the block the
  // shared contract reading was taken at.
  await expect(page.locator(".stake-wallet-block")).toContainText("Base block #1,240")
  await expect(page.locator(".stake-snapshot-note")).toContainText("Base block #1,234")

  const primary = page.locator("#staking-primary")
  const activity = page.locator("#staking-activity")

  // The test wallet reports zero allowance, so the button asks for the exact
  // approval first, and the stake once the approval is sent.
  await expect(primary).toHaveText(/Approve REGENT/)
  await expect(page.locator(".stake-approval-note")).toContainText("exact REGENT approval first")
  await primary.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  expect(await sent(page, 1)).toEqual({
    to: "0x6f89bca4ea5931edfcb09786267b251dee752b07",
    call: {functionName: "approve", args: [stakingContract, 10n ** 18n]},
  })
  await expect(activity.locator(`#staking-sent-${expectedHash(1)}`)).toContainText("REGENT approval")
  await expect(activity.locator(`#staking-sent-${expectedHash(1)}`)).toContainText("Sent. Waiting for Base.")
  await expect(activity.locator(`#staking-sent-${expectedHash(1)} a`)).toHaveAttribute(
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
  await expect(activity.locator(`#staking-sent-${expectedHash(2)}`)).toContainText("Stake 1 REGENT")

  // The same press again is a new request, not a deduplicated or locked one.
  await primary.click()
  await expect.poll(() => sendCount(page)).toBe(3)
  await expect(activity.locator(`#staking-sent-${expectedHash(3)}`)).toContainText("Stake 1 REGENT")

  // Every claim is offered whatever the last reading from Base said about it,
  // so no control is ever disabled and each names its own step.
  await expect(page.locator("button[data-onchain-step][disabled]")).toHaveCount(0)
  for (const action of ["claim_usdc", "claim_regent", "claim_and_restake_regent"]) {
    await expect(page.locator(`#staking-${action}[data-onchain-step="${action}"]`)).toBeEnabled()
  }

  await page.getByRole("button", {name: "Claim USDC (available)", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(4)
  expect(await sent(page, 4)).toEqual({
    to: stakingContract,
    call: {functionName: "claimUSDC", args: [wallet]},
  })
  const resultLink = activity.locator(`#staking-sent-${expectedHash(4)} a`)
  await expect(resultLink).toHaveAttribute("target", "_blank")
  await expect(resultLink).toHaveAttribute("rel", "noopener noreferrer")

  await page.reload()
  await expect(page.locator("#account-menu")).toBeVisible()
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
  await expect(page.locator("button[data-onchain-step]")).toHaveCount(0)
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
  await expect(page.locator(".stake-notice")).toHaveCount(0)
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
  await expect(page.locator("#account-menu")).toBeVisible()
  await expect(page.locator("#staking-claim_usdc[data-onchain-step]")).toBeEnabled()

  await signOut(page)
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible()
  await expect(page).toHaveURL(/\/stake$/)
  await expect(page.locator("button[data-onchain-step]")).toHaveCount(0)

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
  await expect(page.locator(".stake-signer")).toHaveAttribute("title", wallet)
  const note = page.locator(".shell-sending-wallet").first()
  await expect(note).toContainText("0x2222..2222")
  await expect(note).toContainText("0x1111..1111")

  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.locator("button.stake-primary").click()
  await expect(page.locator("#staking-press-notice")).toContainText(
    "Switch to a wallet on your account in your wallet app",
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

// Disconnect ends the wallet connection, and it stays ended across reloads
// while the browser wallet still reports the same account.
test("Disconnect leaves Stake unconnected, and a reload keeps it that way", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/stake")
  await selectWallet(page, wallet)
  await expect(page.locator(".stake-wallet-summary")).toContainText("Currently staked")

  const sibling = await page.context().newPage()
  await installWallet(sibling)
  await sibling.route(bridgePattern, route => route.fulfill({body: bridgeStub, contentType: "application/javascript"}))
  await sibling.goto("/redeem")
  await expect(sibling.locator(".redeem-signer")).toHaveAttribute("title", wallet)

  await page.locator("#account-menu summary").click()
  await page.getByRole("button", {name: "Disconnect"}).click()

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
        (window as Window & {__ashPlatformTestWallet?: {address: string}})
          .__ashPlatformTestWallet?.address,
    ),
  ).toBe(wallet)

  await page.reload()
  await expectDisconnected(page)
})

async function expectDisconnected(page: Page): Promise<void> {
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible()
  await expect(page.getByRole("button", {name: "Connect wallet", exact: true})).toBeVisible()
  await expect(page.locator(".stake-wallet-summary")).toHaveCount(0)
  await expect(page.locator("button[data-onchain-step]")).toHaveCount(0)
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
      /Confirmed at Base block #1,234, read .+ ago\./,
    )
    await expect(page.locator("button.stake-shared-refresh")).toHaveCount(0)

    // The hero is the two cards the contract answers for.
    const earned = page.locator(".stake-benefit-card-primary")
    await expect(earned).toContainText("Regent Labs USDC Earned")
    await expect(earned).toContainText("Last 7 days")
    await expect(earned).toContainText("1,250.50 USDC")
    await expect(earned).toContainText("Lifetime")
    await expect(earned).toContainText("5,074.87 USDC")
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
    await expect(details.getByText(contract, {exact: true})).toBeVisible()
    await expect(details.getByText(regent, {exact: true})).toBeVisible()
    await expect(details.getByText(usdc, {exact: true})).toBeVisible()

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
    await expect(page.locator("button[data-onchain-step]")).toHaveCount(0)

    const fit = await page.evaluate(viewport => {
      const addresses = [...document.querySelectorAll<HTMLElement>(".stake-contract-facts code")]
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
      const connect = document.querySelector<HTMLElement>(".stake-connect-flow .stake-primary")!
      const contractLink = document.querySelector<HTMLElement>(".stake-contract-link")!
      return {
        connectHeight: connect.getBoundingClientRect().height,
        contractLinkHeight: contractLink.getBoundingClientRect().height,
        supplyFont: Number.parseFloat(getComputedStyle(supply).fontSize),
        stakedFont: Number.parseFloat(getComputedStyle(staked).fontSize),
      }
    })

    // The staked figure leads in the hero card and is repeated at reading size
    // in the supply block, so the hero has to be the larger of the two.
    expect(presentation.stakedFont).toBeGreaterThan(presentation.supplyFont)
    expect(presentation.connectHeight).toBeGreaterThanOrEqual(44)
    expect(presentation.contractLinkHeight).toBeGreaterThanOrEqual(44)
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
  await expect(page.locator(`#staking-sent-${expectedHash(2)}`)).toContainText("REGENT approval")
  await expect(page.locator("#staking-press-notice")).toHaveCount(0)
})

test("Alternate stake requires fresh address consent and credits that address", async ({page}) => {
  await installWallet(page)
  await signIn(page)
  await page.goto("/stake")
  await selectWallet(page, wallet)
  await page.getByLabel("Amount", {exact: true}).fill("1")
  const toggle = page.getByLabel("Stake for a different address", {exact: true})
  const receiver = page.getByLabel("Receiving Ethereum address", {exact: true})
  const acknowledgment = page.locator("#staking-recipient-acknowledged")
  const warning = page.locator("#staking-recipient-warning")
  const notice = page.locator("#staking-press-notice")
  const submit = page.locator("button.stake-submit")

  await expect(receiver).toBeHidden()
  await toggle.focus()
  await page.keyboard.press("Space")
  await expect(receiver).toBeVisible()
  await expect(page.locator(".stake-preview")).toBeHidden()
  for (const invalid of ["alice.eth", "0x1234", "0x" + "0".repeat(40)]) {
    await receiver.fill(invalid)
    await expect(receiver).toHaveAttribute("aria-invalid", "true")
    await expect(warning).toBeHidden()
    await submit.click()
    await expect(notice).toHaveText("Enter a valid receiving address. Nothing was sent.")
    expect(await sendCount(page)).toBe(0)
  }

  await receiver.fill(otherWallet)
  await expect(warning).toContainText(
    `the wallet ${otherWallet} will accrue the USDC revenue and REGENT rewards, and only that wallet may withdraw the tokens`,
  )
  await submit.click()
  await expect(notice).toHaveText("Tick the warning about the receiving address first. Nothing was sent.")
  expect(await sendCount(page)).toBe(0)

  await acknowledgment.check()
  await receiver.fill(wallet)
  await expect(warning).toContainText(`the wallet ${wallet} will accrue`)
  await receiver.fill(otherWallet)
  await expect(warning).toContainText(`the wallet ${otherWallet} will accrue`)
  await expect(acknowledgment).not.toBeChecked()
  await acknowledgment.check()
  await toggle.uncheck()
  await toggle.check()
  await expect(acknowledgment).not.toBeChecked()
  await acknowledgment.check()
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
  await acknowledgment.check()
  // The signed-in position stays put while the open wallet changes, so the
  // chosen destination and its acknowledgment stay too.
  await selectWallet(page, otherWallet)
  await selectWallet(page, wallet)
  await expect(page.locator(".stake-signer")).toHaveAttribute("title", wallet)
  await expect(receiver).toHaveValue(otherWallet)
  await expect(acknowledgment).toBeChecked()
  // A normal LiveView amount update preserves the acknowledged destination.
  await page.getByLabel("Amount", {exact: true}).fill("2")
  await expect(page.locator(".stake-preview")).toBeHidden()
  await expect(acknowledgment).toBeChecked()

  for (const width of [1280, 390]) {
    await page.setViewportSize({width, height: 900})
    await expect(warning).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  }
  await page.emulateMedia({reducedMotion: "reduce"})
  await acknowledgment.focus()
  await expect(acknowledgment).toBeFocused()
  await page.locator("#staking-amount-form").screenshot({path: test.info().outputPath("stake-recipient-mobile.png")})
  await submit.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(submit).toHaveText(/Stake REGENT/)
  await submit.click()
  await expect.poll(() => sendCount(page)).toBe(2)
  await expect(page.locator(`#staking-sent-${expectedHash(2)}`)).toContainText("Stake 2 REGENT for 0x2222..2222")
  expect(await sent(page, 2)).toEqual({
    to: stakingContract,
    call: {functionName: "stake", args: [2n * 10n ** 18n, otherWallet]},
  })
  await toggle.uncheck()
  await expect(receiver).toBeHidden()
  await expect(page.locator(".stake-preview")).toBeVisible()
})

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
      ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = {
        address: wallet,
        provider: {
          request: async ({method, params}: {method: string; params?: unknown[]}) => {
            switch (method) {
              case "eth_chainId":
                return "0x2105"
              case "eth_accounts":
              case "eth_requestAccounts":
                return [
                  (window as Window & {__ashPlatformTestWallet?: {address: string}})
                    .__ashPlatformTestWallet?.address ?? wallet,
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
    const seam = (window as Window & {__ashPlatformTestWallet?: {address: string}})
      .__ashPlatformTestWallet
    if (seam) seam.address = next
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}
