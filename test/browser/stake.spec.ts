import {expect, test, type Page} from "@playwright/test"

import {identityTokenFor} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const otherWallet = "0x2222222222222222222222222222222222222222"
const sendsKey = "regent:test:staking-wallet-sends"
const disconnectedKey = "regent:wallet-disconnected:v1"
// The sign-in this page's staking bearer names is the wallet above.
const stakingBearer = "valid-staking"
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

test("Stake hands each click directly to the active Base wallet and presents every result", async ({page}) => {
  await installWallet(page)

  await page.goto("/stake")
  await expect(page.getByRole("heading", {name: "Put REGENT to work."})).toBeVisible()
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible()

  await selectWallet(page, otherWallet)
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  await expect(page.locator(".stake-signer")).toHaveAttribute("title", otherWallet)

  await signIn(page)
  await page.goto("/stake")
  await selectWallet(page, wallet)
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()

  // The wallet position carries its own block, which is not the block the
  // shared contract reading was taken at.
  await expect(page.locator(".stake-wallet-block")).toContainText("Base block #1,240")
  await expect(page.locator(".stake-snapshot-note")).toContainText("Base block #1,234")

  await page.getByLabel("Amount", {exact: true}).fill("1")

  // The test wallet reports zero allowance. One accepted Stake click therefore
  // receives the exact approval prompt immediately followed by the Stake prompt.
  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(2)

  const dialog = page.locator("#staking-result-dialog")
  await expect(dialog.getByText("REGENT spending was approved successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(1)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog.getByText("1 REGENT was staked successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(2)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog).toBeHidden()

  // An identical customer click is a new request, not a deduplicated or locked
  // operation. It receives the same two direct wallet prompts.
  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(4)

  await expect(dialog.getByText("REGENT spending was approved successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(3)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog.getByText("1 REGENT was staked successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(4)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog).toBeHidden()

  // Every claim is offered whatever the last reading from Base said about it,
  // so no control is ever disabled and each carries its own action for the hook.
  await expect(page.locator("button[data-staking-action][disabled]")).toHaveCount(0)
  for (const action of ["claim_usdc", "claim_regent", "claim_and_restake_regent"]) {
    await expect(page.locator(`button[data-staking-action="${action}"]`)).toBeEnabled()
  }

  await page.getByRole("button", {name: "Claim USDC (available)", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(5)

  await expect(dialog.getByText("Your available USDC rewards were claimed.")).toBeVisible()
  const resultLink = dialog.getByRole("link", {name: "View on BaseScan"})
  await expect(resultLink).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(5)}`,
  )
  await expect(resultLink).toHaveAttribute("target", "_blank")
  await expect(resultLink).toHaveAttribute("rel", "noopener noreferrer")
  await page.mouse.click(1, 1)
  await expect(dialog).toBeHidden()

  await expect(page.locator(".stake-review, .stake-submission")).toHaveCount(0)
  await expect(page.getByText(/transaction hash|Confirmed on Base|Retry/i)).toHaveCount(0)
  expect(await page.evaluate(() => sessionStorage.getItem("regent:staking:submitted"))).toBeNull()

  await page.reload()
  await expect(page.locator("#account-menu")).toBeVisible()
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  expect(await sendCount(page)).toBe(5)
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

  // The position is read and shown; nothing a transaction could be built from is.
  await expect(page.locator(".stake-wallet-summary")).toContainText("Currently staked")
  await expect(page.locator("button[data-staking-action]")).toHaveCount(0)
  await expect(page.locator("#regent-staking[data-staking-signer]")).toHaveCount(0)
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

// A sign-in stays fixed to the account it was made with. Nothing this page
// sends can come from a different wallet than the one the header names.
test("Stake refuses every action while the sign-in and the active wallet differ", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/stake")
  await selectWallet(page, otherWallet)
  await expect(page.locator(".stake-signer")).toHaveAttribute("title", otherWallet)

  // Reading this wallet still works while nothing may be sent from it.
  await expect(page.locator(".stake-wallet-summary")).toContainText("Currently staked")
  await expect(page.locator("button[data-staking-action]")).toHaveCount(0)
  await expect(page.locator("#regent-staking[data-staking-signer]")).toHaveCount(0)

  await page.locator("button.stake-submit").click()
  await expect(page.locator(".stake-notice")).toHaveText(
    "You must disconnect 0x1111…1111 and connect again with wallet address 0x2222…2222.",
  )
  expect(await sendCount(page)).toBe(0)

  // Connecting again with the wallet the sign-in names restores every action.
  await selectWallet(page, wallet)
  await expect(page.locator("button[data-staking-action='stake']")).toBeVisible()
  await expect(page.locator(".stake-notice")).toHaveCount(0)
})

// Disconnect ends the wallet connection, and it stays ended across reloads
// while the browser wallet still reports the same account.
test("Disconnect leaves Stake unconnected, and a reload keeps it that way", async ({page}) => {
  await installWallet(page)
  await signIn(page)

  await page.goto("/stake")
  await selectWallet(page, wallet)
  await expect(page.locator(".stake-wallet-summary")).toContainText("Currently staked")

  await page.locator("#account-menu summary").click()
  await page.getByRole("button", {name: "Disconnect"}).click()

  await expectDisconnected(page)
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
  await expect(page.getByRole("button", {name: "Connect wallet to stake"})).toBeVisible()
  await expect(page.locator(".stake-wallet-summary")).toHaveCount(0)
  await expect(page.locator("#regent-staking[data-staking-signer]")).toHaveCount(0)
  await expect(page.locator("button[data-staking-action]")).toHaveCount(0)
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
    await expect(page.getByText("Staking active")).toBeVisible()
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
    await expect(page.locator(".stake-supply-heading")).toContainText(
      "0% of circulating supply staked",
    )

    await page.locator(".stake-contract-details summary").click()
    await expect(page.getByText(contract, {exact: true})).toBeVisible()
    await expect(page.getByText(regent, {exact: true})).toBeVisible()
    await expect(page.getByText(usdc, {exact: true})).toBeVisible()

    const bar = page.getByRole("img", {
      name: "0% of circulating supply staked, and 35% of total supply circulating",
    })
    await expect(bar).toHaveAttribute(
      "style",
      "--circulating-share: 35%; --staked-share: 0%",
    )

    const contractLink = page.getByRole("link", {
      name: "View verified staking contract on BaseScan",
    })
    await expect(contractLink).toHaveAttribute(
      "href",
      `https://basescan.org/address/${contract}`,
    )
    await expect(contractLink).toHaveAttribute("target", "_blank")
    await expect(contractLink).toHaveAttribute("rel", "noopener noreferrer")

    const connect = page.getByRole("button", {name: "Connect wallet to stake"})
    await expect(connect).toBeVisible()
    // Connecting a wallet here is the Privy sign-in, the same one the header runs.
    await expect(connect).toHaveAttribute("data-account-target", "sign-in")
    await expect(page.getByText("Available REGENT", {exact: true})).toHaveCount(0)
    await expect(page.getByText("Currently staked", {exact: true})).toHaveCount(0)
    await expect(page.locator("button[data-staking-action]")).toHaveCount(0)
    await expect(page.locator("#regent-staking[data-staking-allowance]")).toHaveCount(0)

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
        node.textContent = "7390000000 memberships ready"
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

    const presentation = await page.locator(".redeem-collection-card").first().evaluate(element => {
      const cardStyle = getComputedStyle(element)
      return {
        background: cardStyle.backgroundColor,
        border: cardStyle.borderTopWidth,
      }
    })
    expect(presentation.background).not.toBe("rgba(0, 0, 0, 0)")
    expect(presentation.border).toBe("1px")
  }
})

// An approval is a wallet prerequisite, not a staking result. One that never
// returns a usable hash buys nothing on Base, so the page must not hand out a
// receipt for it, must not send the stake behind it, and must leave the amount
// exactly where the customer typed it.
test("Stake presents no receipt when an approval returns no usable hash", async ({page}) => {
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
  await expect(page.locator("#staking-result-dialog")).toBeHidden()
  await expect(page.locator("button.stake-submit")).toBeEnabled()
  await expect(page.getByLabel("Amount", {exact: true})).toHaveValue("1")

  // The wallet is offered again only once the click is over, so the count here
  // is final: the approval was the one and only transaction the wallet saw.
  expect(await sendCount(page)).toBe(1)
})

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
