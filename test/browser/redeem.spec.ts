import {expect, test, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const sendsKey = "regent:test:redemption-wallet-sends"
const holdKey = "regent:test:redemption-hold-receipt"

// Every submitted hash is unique for the life of the database and the browser
// database is never reset, so each run mints its own four.
const run = Date.now().toString(16).padStart(12, "0")
const hashes = [1, 2, 3, 4].map(
  nonce => `0x${run}${nonce.toString(16).padStart(4, "0")}${"0".repeat(48)}`,
)

test("each Animata action needs its own wallet action, and a reload never repeats one", async ({
  page,
}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-redemption")
  await page.addInitScript(
    ({wallet, hashes, sendsKey, holdKey}) => {
      // The send count lives in session storage so a document reload cannot
      // hide a second wallet request behind a fresh counter.
      const sends = () => Number(sessionStorage.getItem(sendsKey) ?? "0")

      ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = {
        address: wallet,
        provider: {
          request: async ({method}: {method: string; params?: unknown[]}) => {
            switch (method) {
              case "eth_chainId":
                return "0x2105"
              case "eth_accounts":
              case "eth_requestAccounts":
                return [wallet]
              case "eth_call":
                return `0x${"00".repeat(32)}`
              case "eth_sendTransaction": {
                const nth = sends() + 1
                sessionStorage.setItem(sendsKey, String(nth))
                return hashes[nth - 1]
              }
              case "eth_getTransactionReceipt":
                // A held receipt never arrives, so the transaction stays
                // submitted and unverified for the reload to recover.
                return sessionStorage.getItem(holdKey)
                  ? new Promise(() => undefined)
                  : {
                      blockHash: `0x${"01".repeat(32)}`,
                      blockNumber: "0x10",
                      contractAddress: null,
                      cumulativeGasUsed: "0x5208",
                      effectiveGasPrice: "0x1",
                      from: wallet,
                      gasUsed: "0x5208",
                      logs: [],
                      logsBloom: `0x${"00".repeat(256)}`,
                      status: "0x1",
                      to: wallet,
                      transactionHash: hashes[Math.max(sends() - 1, 0)],
                      transactionIndex: "0x0",
                      type: "0x2",
                    }
              case "eth_blockNumber":
                return "0x10"
              default:
                throw new Error(`Unexpected wallet RPC ${method}`)
            }
          },
        },
      }
    },
    {wallet, hashes, sendsKey, holdKey},
  )

  await auth.establishLocalSession()

  await page.goto("/redeem")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})
  await expect(page.getByRole("heading", {name: "Redeem Animata"})).toBeVisible()
  await expect(page.locator(".redeem-summary").getByText("1 REGENT", {exact: true}).first()).toBeVisible()

  await explicitAction(page, "Review NFT approval", "Approve NFT collection", 1)
  await explicitAction(page, "Review USDC approval", "Approve exactly 80 USDC", 2)

  await page.getByLabel("Token ID").fill("42")
  await expect(page.getByText("Animata I · Token #42", {exact: true})).toBeVisible()
  await explicitAction(page, "Review redemption", "Redeem Animata", 3)
  await expect(page.getByText("Result token #1123", {exact: true})).toBeVisible()

  // The last action reloads after its transaction was submitted: the exact hash
  // the server bound comes back, verification alone finishes it, and the wallet
  // is never asked again.
  await page.evaluate(key => sessionStorage.setItem(key, "1"), holdKey)
  await review(page, "Review REGENT claim", "Claim unlocked REGENT")
  expect(await sendCount(page)).toBe(3)
  await page.getByRole("button", {name: "Confirm in wallet"}).click()

  const submitted = page.locator(".redeem-submission")
  await expect(submitted.getByText(short(hashes[3]), {exact: true})).toBeVisible()
  await expect(page.getByRole("button", {name: "Retry verification"})).toBeVisible()
  expect(await sendCount(page)).toBe(4)

  // Browser storage is emptied first, so the hash that comes back after the
  // reload can only have come from the owning account's row in Postgres.
  await page.evaluate(() => sessionStorage.removeItem("regent:redemption:submitted"))
  await page.reload()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
  await expect(submitted.getByText(short(hashes[3]), {exact: true})).toBeVisible()
  expect(await sendCount(page)).toBe(4)

  await page.getByRole("button", {name: "Retry verification"}).click()
  await expect(page.getByText("Confirmed on Base. Your redemption details are current.")).toBeVisible()
  expect(await sendCount(page)).toBe(4)
})

async function review(page: Page, buttonName: string, reviewHeading: string): Promise<void> {
  await page.getByRole("button", {name: buttonName}).click()
  await expect(
    page.getByRole("region", {name: "Wallet action review"}).getByRole("heading", {name: reviewHeading}),
  ).toBeVisible()
}

async function explicitAction(
  page: Page,
  buttonName: string,
  reviewHeading: string,
  expectedSends: number,
): Promise<void> {
  await review(page, buttonName, reviewHeading)
  expect(await sendCount(page)).toBe(expectedSends - 1)
  await page.getByRole("button", {name: "Confirm in wallet"}).click()
  await expect(page.getByText("Confirmed on Base. Your redemption details are current.")).toBeVisible()
  expect(await sendCount(page)).toBe(expectedSends)
  await page.getByRole("button", {name: "Refresh redemption details"}).click()
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  await expect(page.getByRole("region", {name: "Redemption actions"})).toBeVisible()
  expect(await sendCount(page)).toBe(expectedSends)
}

function short(hash: string): string {
  return `${hash.slice(0, 8)}…${hash.slice(-4)}`
}

async function sendCount(page: Page): Promise<number> {
  return page.evaluate(key => Number(sessionStorage.getItem(key) ?? "0"), sendsKey)
}
