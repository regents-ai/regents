import {expect, test, type Locator, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const sendsKey = "regent:test:redemption-wallet-sends"

test("Redeem intro is bounded and still at reduced motion", async ({page}) => {
  await page.setViewportSize({width: 320, height: 720})
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.goto("/redeem")

  await expect(
    page.getByRole("heading", {name: "See Animata Collection I and II on OpenSea"}),
  ).toBeVisible()

  for (const [name, href] of [
    ["Animata I", "https://opensea.io/collection/animata"],
    ["Animata II", "https://opensea.io/collection/regent-animata-ii"],
    ["seen here", "https://opensea.io/collection/regents-club"],
  ] as const) {
    const link = page.getByRole("link", {name, exact: true})
    await expect(link).toHaveAttribute("href", href)
    await expect(link).toHaveAttribute("target", "_blank")
    await expect(link).toHaveAttribute("rel", "noopener noreferrer")
  }

  await expect(page.locator(".redeem-intro-video")).toBeHidden()
  await expect(page.locator(".redeem-intro-poster")).toBeVisible()
  await expect(page.getByLabel("Animata Collection I and II artwork")).toBeVisible()

  const hasHorizontalOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
  )
  expect(hasHorizontalOverflow).toBe(false)
})

test("Redeem sends each click and presents successful results in click order", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-redemption")
  await installWallet(page)
  await auth.establishLocalSession()

  await page.goto("/redeem")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})
  await expect(page.getByRole("heading", {name: "Redeem Animata"})).toBeVisible()
  await expect(page.getByLabel("Collection", {exact: true})).toBeVisible()
  await expect(page.getByLabel("Token ID")).toBeVisible()

  await page.getByLabel("Token ID").fill("42")
  await expect(page.locator(".redeem-next-step button")).toHaveText("Approve NFT")
  await expect(page.getByRole("button", {name: "Approve 80 USDC"})).toHaveCount(0)
  await expect(page.getByRole("button", {name: "Redeem", exact: true})).toHaveCount(0)

  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionFirstReceiptPending?: boolean})
      .__ashRedemptionFirstReceiptPending = true
  })

  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(1)

  // The UI does not predict chain changes from a prompt. Refresh rereads Base,
  // and the deterministic browser chain still reports NFT approval as next.
  await page.getByRole("button", {name: "Refresh", exact: true}).click()
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  await expect(page.getByRole("status")).toHaveText(
    "Refresh complete. Data is current at Base safe block 1,234.",
  )
  await expect(page.locator(".redeem-next-step button")).toHaveText("Approve NFT")
  expect(await sendCount(page)).toBe(1)

  // Repeating the customer's explicit click is allowed and produces one more
  // wallet request; no persisted operation locks or deduplicates it.
  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(2)

  await page.getByRole("button", {name: "Claim unlocked REGENT", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(3)

  const dialog = page.getByRole("dialog", {name: "Redemption result"})
  await page.waitForTimeout(2_500)
  await expect(dialog).toBeHidden()
  await expect(dialog).toBeVisible({timeout: 7_000})
  await expect(dialog.getByText("NFT approval succeeded on Base.")).toBeVisible()
  await expectResultLink(dialog, 1)

  await page.keyboard.press("Escape")
  await expect(dialog.getByText("NFT approval succeeded on Base.")).toBeVisible()
  await expectResultLink(dialog, 2)

  await page.mouse.click(1, 1)
  await expect(dialog.getByText("REGENT claim succeeded on Base.")).toBeVisible()
  await expectResultLink(dialog, 3)

  await dialog.getByRole("button", {name: "Close"}).click()
  await expect(dialog).toBeHidden()

  await expect(page.locator(".redeem-review, .redeem-submission")).toHaveCount(0)
  await expect(page.getByText(/transaction hash|Confirmed on Base|Retry/i)).toHaveCount(0)
  expect(await page.evaluate(() => sessionStorage.getItem("regent:redemption:submitted"))).toBeNull()

  await page.reload()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
  await expect(page.getByLabel("Token ID")).toBeVisible()
  expect(await sendCount(page)).toBe(3)
})

test("Redeem refresh retains the current snapshot and scroll position", async ({page}) => {
  await page.setViewportSize({width: 390, height: 600})
  const auth = await installAuthenticatedPrivy(page, "valid-redemption")
  await installWallet(page)
  await auth.establishLocalSession()

  await page.goto("/redeem")
  await auth.expectAuthenticatedSession()
  await expect(page.locator(".redeem-summary")).toContainText("100 USDC")
  await expect(page.locator("#redemption-refresh-status")).toBeHidden()

  const refresh = page.getByRole("button", {name: "Refresh", exact: true})
  await refresh.scrollIntoViewIfNeeded()
  const scroller = page.locator("#app-shell-scroller")
  const summary = page.locator(".redeem-summary")
  const before = await scrollSnapshot(scroller, summary)
  expect(before.top).toBeGreaterThan(0)

  await refresh.click()
  await expect(page.locator(".redeem-summary")).toContainText("100 USDC")
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  await expect(page.locator("#redemption-refresh-status")).toHaveText(
    "Refresh complete. Data is current at Base safe block 1,234.",
  )

  const afterRefresh = await scrollSnapshot(scroller, summary)
  expect(Math.abs(afterRefresh.top - before.top)).toBeLessThanOrEqual(2)
  expect(Math.abs(afterRefresh.anchor - before.anchor)).toBeLessThanOrEqual(2)
  expect(afterRefresh.height).toBe(before.height)

  await page.getByLabel("Token ID").fill("42")
  await expect(page.locator(".redeem-summary")).toContainText("100 USDC")
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  const afterSelection = await scrollSnapshot(scroller, summary)
  expect(Math.abs(afterSelection.top - before.top)).toBeLessThanOrEqual(2)

  const action = page.locator(".redeem-next-step button")
  await expect(action).toBeEnabled()
  await action.scrollIntoViewIfNeeded()
  const beforeAction = await scrollSnapshot(scroller, summary)
  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionReceiptMode?: string}).__ashRedemptionReceiptMode =
      "pending"
  })
  await action.click()
  await expect.poll(() => sendCount(page)).toBe(1)
  const afterAction = await scrollSnapshot(scroller, summary)
  expect(Math.abs(afterAction.top - beforeAction.top)).toBeLessThanOrEqual(2)
})

test("Redeem discards an unresolved result when the active wallet changes", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-redemption")
  await installWallet(page)
  await auth.establishLocalSession()

  await page.goto("/redeem")
  await page.getByLabel("Token ID").fill("42")
  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionReceiptMode?: string}).__ashRedemptionReceiptMode =
      "pending"
  })
  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(1)

  await selectWallet(page, "0x2222222222222222222222222222222222222222")
  await expect(page.getByRole("button", {name: "Connect or switch wallet"})).toBeVisible()
  await page.waitForTimeout(2_500)
  await expect(page.getByRole("dialog", {name: "Redemption result"})).toBeHidden()
  expect(await observationCount(page)).toBe(0)

  await selectWallet(page, wallet)
  await expect(page.getByLabel("Token ID")).toBeVisible()
  await page.getByLabel("Token ID").fill("43")
  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(2)
  await signOutWallet(page)
  await expect(page.getByRole("button", {name: "Connect or switch wallet"})).toBeVisible()
  await page.waitForTimeout(2_500)
  await expect(page.getByRole("dialog", {name: "Redemption result"})).toBeHidden()
  expect(await observationCount(page)).toBe(0)
})

test("Redeem distinguishes an unknown submission from a canonical revert", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-redemption")
  await installWallet(page)
  await auth.establishLocalSession()
  await page.goto("/redeem")
  await page.getByLabel("Token ID").fill("42")

  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionReceiptMode?: string}).__ashRedemptionReceiptMode =
      "send_error"
  })
  await page.locator(".redeem-next-step button").click()
  const dialog = page.getByRole("dialog", {name: "Redemption result"})
  await expect(dialog.getByText("The submission outcome is unknown.")).toBeVisible()
  await expect(dialog.locator("[data-redemption-result-link]")).toBeHidden()
  await dialog.getByRole("button", {name: "Close"}).click()

  await page.evaluate(() => {
    ;(window as Window & {__ashRedemptionReceiptMode?: string}).__ashRedemptionReceiptMode =
      "revert"
  })
  await page.locator(".redeem-next-step button").click()
  await expect(dialog.getByText("NFT approval reverted on Base.")).toBeVisible({timeout: 7_000})
  await expectResultLink(dialog, 2)
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
                const hash = `0x${next.toString(16).padStart(64, "0")}`
                const transactions = ((window as Window & {
                  __ashRedemptionTransactions?: Record<string, unknown>
                }).__ashRedemptionTransactions ??= {})
                transactions[hash] = params?.[0]
                return hash
              }
              case "eth_getTransactionByHash": {
                incrementObservationCount()
                const hash = params?.[0] as string
                const transaction = (window as Window & {
                  __ashRedemptionTransactions?: Record<string, {
                    from: string
                    to: string
                    data: string
                    value: string
                  }>
                  __ashRedemptionReceiptMode?: string
                }).__ashRedemptionTransactions?.[hash]
                if (!transaction) return null
                const pending = (window as Window & {__ashRedemptionReceiptMode?: string})
                  .__ashRedemptionReceiptMode === "pending"
                return {
                  hash,
                  from: transaction.from,
                  to: transaction.to,
                  input: transaction.data,
                  value: transaction.value,
                  blockHash: pending ? null : `0x${"cd".repeat(32)}`,
                  blockNumber: pending ? null : "0x10",
                }
              }
              case "eth_getTransactionReceipt": {
                incrementObservationCount()
                if (
                  (window as Window & {__ashRedemptionReceiptMode?: string})
                    .__ashRedemptionReceiptMode === "pending"
                ) return null
                const hash = params?.[0] as string
                const calls = ((window as Window & {
                  __ashRedemptionReceiptCalls?: Record<string, number>
                }).__ashRedemptionReceiptCalls ??= {})
                calls[hash] = (calls[hash] ?? 0) + 1
                if (
                  (window as Window & {__ashRedemptionFirstReceiptPending?: boolean})
                    .__ashRedemptionFirstReceiptPending &&
                  hash === `0x${"1".padStart(64, "0")}` &&
                  calls[hash] === 1
                ) return null
                const transaction = (window as Window & {
                  __ashRedemptionTransactions?: Record<string, {from: string; to: string}>
                }).__ashRedemptionTransactions?.[hash]
                if (!transaction) return null
                return {
                  transactionHash: hash,
                  from: transaction.from,
                  to: transaction.to,
                  status:
                    (window as Window & {__ashRedemptionReceiptMode?: string})
                      .__ashRedemptionReceiptMode === "revert" ? "0x0" : "0x1",
                  blockHash: `0x${"cd".repeat(32)}`,
                  blockNumber: "0x10",
                }
              }
              case "eth_getBlockByHash": {
                incrementObservationCount()
                const transactions = Object.keys(
                  (window as Window & {__ashRedemptionTransactions?: Record<string, unknown>})
                    .__ashRedemptionTransactions ?? {},
                )
                return {
                  hash: `0x${"cd".repeat(32)}`,
                  number: "0x10",
                  transactions,
                }
              }
              default:
                throw new Error(`Unexpected wallet RPC ${method}`)
            }
          },
        },
      }

      function incrementObservationCount(): void {
        const testWindow = window as Window & {__ashRedemptionObservationCalls?: number}
        testWindow.__ashRedemptionObservationCalls =
          (testWindow.__ashRedemptionObservationCalls ?? 0) + 1
      }
    },
    {wallet, sendsKey},
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

async function observationCount(page: Page): Promise<number> {
  return page.evaluate(
    () => (window as Window & {__ashRedemptionObservationCalls?: number})
      .__ashRedemptionObservationCalls ?? 0,
  )
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
