import {expect, test} from "@playwright/test"

const wallet = "0x1111111111111111111111111111111111111111"
const hashes = ["aa", "bb", "cc", "dd"].map(byte => `0x${byte.repeat(32)}`)

test("each Animata approval, redemption and claim requires its own wallet action", async ({page}) => {
  await page.addInitScript(
    ({wallet, hashes}) => {
      let sends = 0
      ;(window as Window & {__ashRedemptionSends?: number; __ashPlatformTestWallet?: unknown})
        .__ashPlatformTestWallet = {
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
                const hash = hashes[sends]
                sends += 1
                ;(window as Window & {__ashRedemptionSends?: number}).__ashRedemptionSends = sends
                return hash
              }
              case "eth_getTransactionReceipt": {
                const transactionHash = hashes[Math.max(sends - 1, 0)]
                return {
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
                  transactionHash,
                  transactionIndex: "0x0",
                  type: "0x2",
                }
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
    {wallet, hashes},
  )

  const csrfResponse = await page.request.get("/auth/csrf")
  const {csrf_token: csrfToken} = (await csrfResponse.json()) as {csrf_token: string}
  const session = await page.request.post("/auth/privy/session", {
    headers: {authorization: "Bearer valid-redemption", "x-csrf-token": csrfToken},
  })
  expect(session.ok()).toBe(true)

  await page.goto("/redeem")
  await expect(page.getByRole("heading", {name: "Redeem Animata"})).toBeVisible()
  await expect(page.locator(".redeem-summary").getByText("1 REGENT", {exact: true}).first()).toBeVisible()

  await explicitAction(page, "Review NFT approval", "Approve NFT collection", 1)
  await explicitAction(page, "Review USDC approval", "Approve exactly 80 USDC", 2)

  await page.getByLabel("Token ID").fill("42")
  await expect(page.getByText("Animata I · Token #42", {exact: true})).toBeVisible()
  await explicitAction(page, "Review redemption", "Redeem Animata", 3)
  await expect(page.getByText("Result token #1123", {exact: true})).toBeVisible()
  await explicitAction(page, "Review REGENT claim", "Claim unlocked REGENT", 4)

  expect(await sendCount(page)).toBe(4)
})

async function explicitAction(
  page: import("@playwright/test").Page,
  buttonName: string,
  reviewHeading: string,
  expectedSends: number,
): Promise<void> {
  await page.getByRole("button", {name: buttonName}).click()
  await expect(
    page
      .getByRole("region", {name: "Wallet action review"})
      .getByRole("heading", {name: reviewHeading}),
  ).toBeVisible()
  expect(await sendCount(page)).toBe(expectedSends - 1)
  await page.getByRole("button", {name: "Confirm in wallet"}).click()
  await expect(page.getByText("Confirmed on Base. Your redemption details are current.")).toBeVisible()
  expect(await sendCount(page)).toBe(expectedSends)
  await page.getByRole("button", {name: "Refresh redemption details"}).click()
  await expect(page.locator(".redeem-status[aria-busy=true]")).toHaveCount(0)
  await expect(page.getByRole("region", {name: "Redemption actions"})).toBeVisible()
  expect(await sendCount(page)).toBe(expectedSends)
}

async function sendCount(page: import("@playwright/test").Page): Promise<number> {
  return (
    (await page.evaluate(
      () => (window as Window & {__ashRedemptionSends?: number}).__ashRedemptionSends,
    )) ?? 0
  )
}
