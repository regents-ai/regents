import {expect, test, type Locator, type Page} from "@playwright/test"

const wallet = "0x1111111111111111111111111111111111111111"
const sendsKey = "regent:test:redemption-wallet-sends"
const revertedHash = `0x${"f".repeat(64)}`

test("Redeem intro is bounded and still at reduced motion", async ({page}) => {
  await page.setViewportSize({width: 320, height: 720})
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.goto("/redeem")

  await expect(page.getByRole("heading", {name: "Redeem your Animata."})).toBeVisible()

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
  await expect(page.locator(".redeem-collection-card")).toHaveCount(3)
  await expect(page.locator(".redeem-collection-grid")).toContainText("327 held by redeemer")
  await expect(page.locator(".redeem-collection-grid")).toContainText("284 held by redeemer")
  await expect(page.locator(".redeem-collection-grid")).toContainText("388 memberships ready")

  const hasHorizontalOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
  )
  expect(hasHorizontalOverflow).toBe(false)
})

test("Redeem sends each click and presents successful results in click order", async ({page}) => {
  await installWallet(page)

  await page.goto("/redeem")
  await expect(page.getByRole("heading", {name: "Redeem your Animata."})).toBeVisible()
  await expect(page.getByText("No Regent account or Privy login is required.")).toBeVisible()
  await expect(page.locator("[data-account-target='sign-in']")).toBeVisible()
  await expect(page.getByLabel("Collection", {exact: true})).toBeVisible()
  await expect(page.getByLabel("Token ID")).toBeVisible()

  await page.getByLabel("Token ID").fill("42")
  await expect(page.locator(".redeem-next-step button")).toHaveText("Approve NFT collection")
  await expect(page.getByRole("button", {name: "Approve 80 USDC"})).toHaveCount(0)
  await expect(page.getByRole("button", {name: "Redeem", exact: true})).toHaveCount(0)
  await expect(page.locator("[data-redemption-action][disabled]")).toHaveCount(0)
  await expect(page.getByRole("button", {name: "Claim unlocked REGENT", exact: true})).toBeEnabled()

  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(1)

  const dialog = page.locator("#redemption-result-dialog")
  await expect(dialog.getByText("The selected NFT collection was approved successfully.")).toBeVisible()
  await expectResultLink(dialog, 1)
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog).toBeHidden()

  // The UI does not predict chain changes from a prompt. Refresh rereads Base,
  // and the deterministic browser chain still reports NFT approval as next.
  await page.getByRole("button", {name: "Refresh wallet data", exact: true}).click()
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  await expect(page.locator("#redemption-refresh-status")).toHaveText(
    "Refresh complete. Data is current at Base block 1,234.",
  )
  await expect(page.locator(".redeem-next-step button")).toHaveText("Approve NFT collection")
  expect(await sendCount(page)).toBe(1)

  // Repeating the customer's explicit click is allowed and produces one more
  // wallet request; no persisted operation locks or deduplicates it.
  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(2)

  await expect(dialog.getByText("The selected NFT collection was approved successfully.")).toBeVisible()
  await expectResultLink(dialog, 2)
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog).toBeHidden()

  await page.getByRole("button", {name: "Claim unlocked REGENT", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(3)

  await expect(dialog).toBeVisible({timeout: 10_000})
  await expect(dialog.getByText("Your unlocked REGENT was claimed successfully.")).toBeVisible()
  await expectResultLink(dialog, 3)

  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog).toBeHidden()

  await expect(page.locator(".redeem-review, .redeem-submission")).toHaveCount(0)
  await expect(page.getByText(/transaction hash|Confirmed on Base|Retry/i)).toHaveCount(0)
  expect(await page.evaluate(() => sessionStorage.getItem("regent:redemption:submitted"))).toBeNull()

  await page.reload()
  await expect(page.locator("[data-account-target='sign-in']")).toBeVisible()
  await expect(page.getByLabel("Token ID")).toBeVisible()
  expect(await sendCount(page)).toBe(3)
})

// A control is offered whenever its calldata can be built, which needs only a
// connected wallet and a selected token. Nothing else withholds one.
test("Redeem offers its step controls only once a token is selected", async ({page}) => {
  await installWallet(page)
  await page.goto("/redeem")

  const controls = page.locator(".redeem-next-step button")
  await expect(controls).toHaveCount(0)
  await expect(page.locator(".redeem-next-step h3")).toHaveText("Select an Animata")

  await page.getByLabel("Token ID").fill("42")
  await expect(controls).toHaveCount(1)
  await expect(controls).toHaveAttribute("data-redemption-action", "approve_nft_collection")
  await expect(controls).toBeEnabled()

  await page.getByLabel("Token ID").fill("")
  await expect(controls).toHaveCount(0)
  await expect(page.locator(".redeem-next-step p").last()).toHaveText(
    "Choose an eligible Animata collection and token ID.",
  )
  await expect(page.getByRole("button", {name: "Claim unlocked REGENT", exact: true})).toBeEnabled()
})

test("Redeem refresh retains the current snapshot and scroll position", async ({page}) => {
  await page.setViewportSize({width: 390, height: 600})
  await installWallet(page)

  await page.goto("/redeem")
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  await expect(page.locator("#redemption-refresh-status")).toBeHidden()

  const refresh = page.getByRole("button", {name: "Refresh wallet data", exact: true})
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

  await page.getByLabel("Token ID").fill("42")
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  const afterSelection = await scrollSnapshot(scroller, summary)
  expect(Math.abs(afterSelection.top - before.top)).toBeLessThanOrEqual(16)

  const action = page.locator(".redeem-next-step button")
  await expect(action).toBeEnabled()
  await action.scrollIntoViewIfNeeded()
  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionReceiptMode?: string}).__ashRedemptionReceiptMode =
      "pending"
  })
  await action.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(page.locator(".redeem-summary")).toContainText("100.00 USDC")
  await expect(page.locator("#redemption-transaction-progress")).toBeVisible()
})

test("Redeem keeps submitted results when the active wallet changes", async ({page}) => {
  await installWallet(page)

  await page.goto("/redeem")
  await page.getByLabel("Token ID").fill("42")
  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(1)

  await selectWallet(page, "0x2222222222222222222222222222222222222222")
  await expect(page.locator(".redeem-signer")).toHaveAttribute(
    "title",
    "0x2222222222222222222222222222222222222222",
  )
  await expect(page.getByLabel("Token ID")).toBeVisible()
  const dialog = page.locator("#redemption-result-dialog")
  await expect(dialog.getByText("The selected NFT collection was approved successfully.")).toBeVisible()
  await expectResultLink(dialog, 1)
  await dialog.getByRole("button", {name: "Done"}).click()

  await selectWallet(page, wallet)
  await expect(page.getByLabel("Token ID")).toBeVisible()
  await page.getByLabel("Token ID").fill("43")
  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(2)
  await signOutWallet(page)
  await expect(page.getByRole("button", {name: "Connect wallet", exact: true})).toBeVisible()
  await expect(dialog.getByText("The selected NFT collection was approved successfully.")).toBeVisible()
  await expectResultLink(dialog, 2)
})

test("Redeem distinguishes an unknown submission from a canonical revert", async ({page}) => {
  await installWallet(page)
  await page.goto("/redeem")
  await page.getByLabel("Token ID").fill("42")

  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionReceiptMode?: string}).__ashRedemptionReceiptMode =
      "send_error"
  })
  await page.locator(".redeem-next-step button").click()
  const dialog = page.locator("#redemption-result-dialog")
  await expect(dialog.getByText("The submission outcome is unknown.")).toBeVisible()
  await expect(dialog.locator("[data-redemption-result-link]")).toBeHidden()
  await dialog.getByRole("button", {name: "Done"}).click()

  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionReceiptMode?: string}).__ashRedemptionReceiptMode =
      "revert"
  })
  await page.locator(".redeem-next-step button").click()
  await expect(
    dialog.getByText("Base included the transaction, but the contract reverted it."),
  ).toBeVisible({timeout: 7_000})
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${revertedHash}`,
  )
})

async function installWallet(page: Page): Promise<void> {
  await page.addInitScript(
    ({wallet, sendsKey, revertedHash}) => {
      ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = {
        address: wallet,
        provider: {
          request: async ({method, params}: {method: string; params?: unknown[]}) => {
            switch (method) {
              case "eth_chainId":
                return "0x2105"
              case "eth_accounts":
              case "eth_requestAccounts":
                return [wallet]
              case "eth_call":
                return `0x${"00".repeat(32)}`
              case "eth_sendTransaction": {
                const next = Number(sessionStorage.getItem(sendsKey) ?? "0") + 1
                sessionStorage.setItem(sendsKey, String(next))
                if (
                  (window as Window & {__ashRedemptionReceiptMode?: string})
                    .__ashRedemptionReceiptMode === "send_error"
                ) throw new Error("wallet transport failed")
                const hash =
                  (window as Window & {__ashRedemptionReceiptMode?: string})
                    .__ashRedemptionReceiptMode === "revert"
                    ? revertedHash
                    : `0x${next.toString(16).padStart(64, "0")}`
                const transactions = ((window as Window & {
                  __ashRedemptionTransactions?: Record<string, unknown>
                }).__ashRedemptionTransactions ??= {})
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
    {wallet, sendsKey, revertedHash},
  )
}

async function expectResultLink(
  dialog: Locator,
  index: number,
): Promise<void> {
  const link = dialog.getByRole("link", {name: "View on BaseScan"})
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
    const testWindow = window as Window & {
      __ashPlatformTestWallet?: {address: string; provider: unknown}
    }
    const seam = testWindow
      .__ashPlatformTestWallet
    if (seam) testWindow.__ashPlatformTestWallet = {...seam, address: next}
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}

async function signOutWallet(page: Page): Promise<void> {
  await page.evaluate(() => {
    ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = undefined
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
