import {expect, test} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const approvalHash = `0x${"cd".repeat(32)}`
const stakingHash = `0x${"ab".repeat(32)}`

test("signed-in staking uses a deterministic wallet, confirms once and refreshes", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-staking")
  await page.addInitScript(
    ({wallet, approvalHash, stakingHash}) => {
      let sends = 0
      const receipt = (hash: string) => ({
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
        to: "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5",
        transactionHash: hash,
        transactionIndex: "0x0",
        type: "0x2",
      })

      ;(window as Window & {__ashPlatformWalletSends?: number; __ashPlatformTestWallet?: unknown})
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
                sends += 1
                ;(window as Window & {__ashPlatformWalletSends?: number}).__ashPlatformWalletSends = sends
                return sends === 1 ? approvalHash : stakingHash
              }
              case "eth_getTransactionReceipt":
                return receipt(sends === 1 ? approvalHash : stakingHash)
              case "eth_blockNumber":
                return "0x10"
              default:
                throw new Error(`Unexpected wallet RPC ${method}`)
            }
          },
        },
      }
    },
    {wallet, approvalHash, stakingHash},
  )

  await auth.establishLocalSession()

  await page.goto("/stake")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})
  await expect(page.getByRole("heading", {name: "Stake REGENT"})).toBeVisible()
  await expect(page.getByText("5 REGENT", {exact: true})).toBeVisible()

  await page.getByLabel("REGENT amount").fill("1")
  await page.getByRole("button", {name: "Review stake"}).click()
  await expect(page.getByRole("heading", {name: "Stake REGENT"}).last()).toBeVisible()
  await expect(page.getByText("1 REGENT", {exact: true})).toBeVisible()
  await expect(page.locator(".stake-review").getByText("0x1111…1111", {exact: true}).first()).toBeVisible()

  const confirm = page.getByRole("button", {name: "Confirm in wallet"})
  await confirm.evaluate(button => {
    button.click()
    button.click()
  })

  const continueAfterApproval = page.getByRole("button", {name: "Continue after approval"})
  await expect(continueAfterApproval).toBeVisible()
  expect(
    await page.evaluate(
      () => (window as Window & {__ashPlatformWalletSends?: number}).__ashPlatformWalletSends,
    ),
  ).toBe(1)
  await continueAfterApproval.click()

  await expect(page.getByText("Confirmed on Base. Your staking details are current.")).toBeVisible()
  expect(await page.evaluate(() => (window as Window & {__ashPlatformWalletSends?: number}).__ashPlatformWalletSends)).toBe(2)
})
