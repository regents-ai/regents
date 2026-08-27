import {expect, test, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const sendsKey = "regent:test:redemption-wallet-sends"

test("Redeem exposes and sends only the current Base step", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-redemption")
  await installWallet(page)
  await auth.establishLocalSession()

  await page.goto("/redeem")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})
  await expect(page.getByRole("heading", {name: "Redeem Animata"})).toBeVisible()
  await expect(page.getByLabel("Collection")).toBeVisible()
  await expect(page.getByLabel("Token ID")).toBeVisible()

  await page.getByLabel("Token ID").fill("42")
  await expect(page.locator(".redeem-next-step button")).toHaveText("Approve NFT")
  await expect(page.getByRole("button", {name: "Approve 80 USDC"})).toHaveCount(0)
  await expect(page.getByRole("button", {name: "Redeem", exact: true})).toHaveCount(0)

  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(1)

  // The UI does not predict chain changes from a prompt. Refresh rereads Base,
  // and the deterministic browser chain still reports NFT approval as next.
  await page.getByRole("button", {name: "Refresh", exact: true}).click()
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  await expect(page.locator(".redeem-next-step button")).toHaveText("Approve NFT")
  expect(await sendCount(page)).toBe(1)

  // Repeating the customer's explicit click is allowed and produces one more
  // wallet request; no persisted operation locks or deduplicates it.
  await page.locator(".redeem-next-step button").click()
  await expect.poll(() => sendCount(page)).toBe(2)

  await page.getByRole("button", {name: "Claim unlocked REGENT", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(3)

  await expect(page.locator(".redeem-review, .redeem-submission")).toHaveCount(0)
  await expect(page.getByText(/transaction hash|Confirmed on Base|Retry/i)).toHaveCount(0)
  expect(await page.evaluate(() => sessionStorage.getItem("regent:redemption:submitted"))).toBeNull()

  await page.reload()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
  await expect(page.getByLabel("Token ID")).toBeVisible()
  expect(await sendCount(page)).toBe(3)
})

async function installWallet(page: Page): Promise<void> {
  await page.addInitScript(
    ({wallet, sendsKey}) => {
      ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = {
        address: wallet,
        provider: {
          request: async ({method}: {method: string}) => {
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
                return `0x${next.toString(16).padStart(64, "0")}`
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

async function sendCount(page: Page): Promise<number> {
  return page.evaluate(key => Number(sessionStorage.getItem(key) ?? "0"), sendsKey)
}
