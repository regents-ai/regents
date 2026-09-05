import {expect, test, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const owner = "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
const other = "0x1111111111111111111111111111111111111111"
const successHash = `0x${"ab".repeat(32)}`
const revertHash = `0x${"de".repeat(32)}`
const sendsKey = "regent:test:regents-club-metadata-sends"

test("an authenticated human uses the exact selected signer and sees every terminal outcome", async ({
  page,
}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await installWallet(page, other)
  await auth.establishLocalSession()
  await page.goto("/regents-club/metadata-cutover")
  await auth.expectAuthenticatedSession()

  await expect(page.getByRole("heading", {name: "Regents Club metadata cutover"})).toBeVisible()
  await expect(page.getByText(`Selected Privy wallet: ${other.toLowerCase()}`)).toBeVisible()
  await expect(page.getByRole("button", {name: "Review with selected wallet"})).toBeVisible()
  expect(await sends(page)).toHaveLength(0)

  await setMode(page, "cancel")
  await reviewAndConfirm(page)
  await expect(page.getByText("The wallet request was canceled. It will not be retried.")).toBeVisible()
  expect(await sends(page)).toHaveLength(1)

  await setMode(page, "revert")
  await reviewAndConfirm(page)
  await expect(page.getByText("The selected wallet transaction reverted", {exact: false})).toBeVisible()
  expect(await sends(page)).toHaveLength(2)

  await setMode(page, "unknown")
  await reviewAndConfirm(page)
  await expect(page.getByRole("heading", {name: "Submission outcome unknown"})).toBeVisible()
  expect(await sends(page)).toHaveLength(3)

  await page.reload()
  await selectWallet(page, owner)
  await setMode(page, "success")
  await reviewAndConfirm(page)

  await expect(
    page.getByRole("heading", {name: "Cutover finalized and this route is closed"}),
  ).toBeVisible()

  const recorded = await sends(page)
  expect(recorded).toHaveLength(4)
  expect(recorded.slice(0, 3).map(transaction => transaction.from)).toEqual([
    other.toLowerCase(),
    other.toLowerCase(),
    other.toLowerCase(),
  ])
  expect(recorded[3]).toEqual({
    from: owner.toLowerCase(),
    to: "0x2208aadbdecd47d3b4430b5b75a175f6d885d487",
    data:
      "0x55f804b30000000000000000000000000000000000000000000000000000000000000020" +
      "0000000000000000000000000000000000000000000000000000000000000022" +
      "68747470733a2f2f6d656469612e726567656e74732e73682f6d657461646174612f" +
      "000000000000000000000000000000000000000000000000000000000000",
    value: "0x0",
  })
})

async function reviewAndConfirm(page: Page): Promise<void> {
  await page.getByRole("button", {name: "Review with selected wallet"}).click()
  const review = page.getByRole("region", {name: "Founder transaction review"})
  await expect(review).toBeVisible()
  await expect(review).toContainText("Base (8453)")
  await expect(review).toContainText("0 ETH")
  await expect(review).toContainText(
    "0x6deed736ab66e25b399711cd1e6ab10d4c7380d283a0b49f68e367189cde78ce",
  )
  await review.getByRole("button", {name: "Confirm and open selected wallet"}).click()
}

async function setMode(page: Page, mode: "cancel" | "unknown" | "revert" | "success") {
  await page.evaluate(value => {
    ;(window as Window & {__regentsClubMetadataMode?: string}).__regentsClubMetadataMode = value
  }, mode)
}

async function selectWallet(page: Page, address: string) {
  await page.evaluate(selected => {
    const state = window as Window & {
      __ashPlatformTestWallet?: {address: string; provider: unknown}
    }
    if (state.__ashPlatformTestWallet) state.__ashPlatformTestWallet.address = selected
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}

async function sends(page: Page): Promise<Array<Record<string, string>>> {
  return page.evaluate(key => JSON.parse(sessionStorage.getItem(key) || "[]"), sendsKey)
}

async function installWallet(page: Page, initialAddress: string): Promise<void> {
  await page.addInitScript(
    ({initialAddress, successHash, revertHash, sendsKey}) => {
      const provider = {
        async request({method, params}: {method: string; params?: Array<Record<string, string>>}) {
          const wallet = (window as Window & {__ashPlatformTestWallet?: {address: string}})
            .__ashPlatformTestWallet
          if (method === "eth_chainId") return "0x2105"
          if (method === "eth_accounts") return [wallet?.address || initialAddress]
          if (method !== "eth_sendTransaction") throw new Error(`unexpected ${method}`)

          const transaction = params?.[0] || {}
          const recorded = JSON.parse(sessionStorage.getItem(sendsKey) || "[]")
          recorded.push({
            from: transaction.from?.toLowerCase(),
            to: transaction.to?.toLowerCase(),
            data: transaction.data?.toLowerCase(),
            value: transaction.value,
          })
          sessionStorage.setItem(sendsKey, JSON.stringify(recorded))

          const mode = (window as Window & {__regentsClubMetadataMode?: string})
            .__regentsClubMetadataMode
          if (mode === "cancel") throw {code: 4001}
          if (mode === "unknown") throw new Error("provider lost hash")
          return mode === "revert" ? revertHash : successHash
        },
      }

      ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = {
        address: initialAddress,
        provider,
      }
    },
    {initialAddress, successHash, revertHash, sendsKey},
  )
}
