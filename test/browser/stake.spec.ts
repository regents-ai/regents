import {expect, test, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const sendsKey = "regent:test:staking-wallet-sends"
const holdKey = "regent:test:staking-hold-receipt"
const rejectKey = "regent:test:staking-reject-next"

// Every submitted hash is unique for the life of the database and the browser
// database is never reset, so each run mints its own. The file discriminator
// keeps a Stake run from colliding with a Redeem run in the same millisecond.
const run = `${Date.now().toString(16).padStart(12, "0")}5a`
const submittedHash = (nonce: number) =>
  `0x${run}${nonce.toString(16).padStart(4, "0")}${"0".repeat(46)}`
const approvalHash = submittedHash(1)
const stakeHash = submittedHash(2)
const unstakeHash = submittedHash(3)

test("signed-in staking confirms once, survives a reload and never sends twice", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-staking")
  await page.addInitScript(
    ({wallet, hashes, sendsKey, holdKey, rejectKey}) => {
      // The send count lives in session storage so a document reload cannot
      // hide a second wallet request behind a fresh counter.
      const sends = () => Number(sessionStorage.getItem(sendsKey) ?? "0")

      const receipt = (transactionHash: string) => ({
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
        transactionHash,
        transactionIndex: "0x0",
        type: "0x2",
      })

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
                // A real wallet rejection: nothing is broadcast and nothing is
                // counted, exactly as EIP-1193 4001 means.
                if (sessionStorage.getItem(rejectKey)) {
                  sessionStorage.removeItem(rejectKey)
                  throw Object.assign(new Error("User rejected the request."), {code: 4001})
                }
                const nth = sends() + 1
                sessionStorage.setItem(sendsKey, String(nth))
                return hashes[nth - 1]
              }
              case "eth_getTransactionReceipt":
                // A held receipt never arrives, so the transaction stays
                // submitted and unverified for the reload to recover.
                return sessionStorage.getItem(holdKey)
                  ? new Promise(() => undefined)
                  : receipt(hashes[sends() - 1])
              case "eth_blockNumber":
                return "0x10"
              default:
                throw new Error(`Unexpected wallet RPC ${method}`)
            }
          },
        },
      }
    },
    {wallet, hashes: [approvalHash, stakeHash, unstakeHash], sendsKey, holdKey, rejectKey},
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
  expect(await sendCount(page)).toBe(1)
  await continueAfterApproval.click()

  await expect(page.getByText("Confirmed on Base. Your staking details are current.")).toBeVisible()
  expect(await sendCount(page)).toBe(2)

  // A second action in the same page session, rejected in the wallet with the
  // exact EIP-1193 4001 while the completed stake's hash is still in browser
  // memory. The server claimed this dispatch before the wallet opened, so the
  // rejection has to reach it: the review clearing is that fact arriving.
  await page.evaluate(key => sessionStorage.setItem(key, "1"), rejectKey)
  await page.getByRole("button", {name: "Review USDC claim"}).click()
  await expect(page.locator(".stake-review")).toBeVisible()
  await page.getByRole("button", {name: "Confirm in wallet"}).click()

  await expect(page.locator(".stake-review")).toHaveCount(0)
  expect(await sendCount(page)).toBe(2)

  // A reload after a submitted phase recovers the exact hash the server bound,
  // finishes through verification alone, and never opens the wallet again.
  // Preparing it at all proves the rejected operation closed: had the rejection
  // been withheld, this review would be refused as outstanding.
  await page.evaluate(key => sessionStorage.setItem(key, "1"), holdKey)
  await page.getByRole("button", {name: "Review unstake"}).click()
  await expect(page.locator(".stake-review").getByRole("heading", {name: "Unstake REGENT"})).toBeVisible()
  await expect(page.getByText("An earlier staking action is still outstanding")).toHaveCount(0)
  await page.getByRole("button", {name: "Confirm in wallet"}).click()

  const submitted = page.locator(".stake-submission")
  await expect(submitted.getByText(short(unstakeHash), {exact: true})).toBeVisible()
  await expect(page.getByRole("button", {name: "Retry verification"})).toBeVisible()
  expect(await sendCount(page)).toBe(3)

  // Browser storage is emptied first, so the hash that comes back after the
  // reload can only have come from the owning account's row in Postgres.
  await page.evaluate(() => sessionStorage.removeItem("regent:staking:submitted"))
  await page.reload()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
  await expect(submitted.getByText(short(unstakeHash), {exact: true})).toBeVisible()
  expect(await sendCount(page)).toBe(3)

  await page.getByRole("button", {name: "Retry verification"}).click()
  await expect(page.getByText("Confirmed on Base. Your staking details are current.")).toBeVisible()
  expect(await sendCount(page)).toBe(3)
})

function short(hash: string): string {
  return `${hash.slice(0, 8)}…${hash.slice(-4)}`
}

async function sendCount(page: Page): Promise<number> {
  return page.evaluate(key => Number(sessionStorage.getItem(key) ?? "0"), sendsKey)
}
