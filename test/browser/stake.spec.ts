import {expect, test, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const otherWallet = "0x2222222222222222222222222222222222222222"
const sendsKey = "regent:test:staking-wallet-sends"
const rejectKey = "regent:test:staking-reject-next"
const moveKey = "regent:test:staking-move-account"
const wrongChainKey = "regent:test:staking-wrong-chain"

// Every submitted hash is unique for the life of the database and the browser
// database is never reset, so each run mints its own. The file discriminator
// keeps a Stake run from colliding with a Redeem run in the same millisecond.
const run = `${Date.now().toString(16).padStart(12, "0")}5a`
const submittedHash = (nonce: number) =>
  `0x${run}${nonce.toString(16).padStart(4, "0")}${"0".repeat(46)}`
const approvalHash = submittedHash(1)
const stakeHash = submittedHash(2)
const claimHash = submittedHash(3)
const unstakeHash = submittedHash(4)

test("signed-in staking confirms once, survives a reload and never sends twice", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-staking")
  await page.addInitScript(
    ({wallet, otherWallet, hashes, sendsKey, rejectKey, moveKey, wrongChainKey}) => {
      // The send count lives in session storage so a document reload cannot
      // hide a second wallet request behind a fresh counter.
      const sends = () => Number(sessionStorage.getItem(sendsKey) ?? "0")
      // The seam stands in for Privy's active selection, so the address it
      // reports is the address the whole page has to follow.
      const active = () =>
        (window as Window & {__ashPlatformTestWallet?: {address: string}}).__ashPlatformTestWallet
          ?.address ?? wallet

      ;(window as Window & {__ashPlatformTestWallet?: unknown}).__ashPlatformTestWallet = {
        address: wallet,
        provider: {
          request: async ({method}: {method: string; params?: unknown[]}) => {
            switch (method) {
              case "eth_chainId":
                // A wallet parked on another chain, so Base has to be asked for.
                return sessionStorage.getItem(wrongChainKey) ? "0x1" : "0x2105"
              case "wallet_switchEthereumChain":
                // The chain-switch prompt is still only a prompt: rejecting it
                // leaves nothing signed and nothing broadcast.
                throw Object.assign(new Error("User rejected the request."), {code: 4001})
              case "eth_accounts":
              case "eth_requestAccounts": {
                // The account moves the moment after the claim: the first read
                // is the preflight that asked for it, the next one is the push.
                const moved = sessionStorage.getItem(moveKey)
                if (moved === null) return [active()]
                sessionStorage.setItem(moveKey, String(Number(moved) + 1))
                return Number(moved) > 0 ? [otherWallet] : [active()]
              }
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
              case "eth_blockNumber":
                return "0x10"
              default:
                throw new Error(`Unexpected wallet RPC ${method}`)
            }
          },
        },
      }
    },
    {
      wallet,
      otherWallet,
      hashes: [approvalHash, stakeHash, claimHash, unstakeHash],
      sendsKey,
      rejectKey,
      moveKey,
      wrongChainKey,
    },
  )

  await auth.establishLocalSession()

  await page.goto("/stake")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})
  await expect(page.getByRole("heading", {name: "Stake REGENT"})).toBeVisible()
  await expect(page.getByText("5 REGENT", {exact: true})).toBeVisible()

  // The wallet active in the browser is what /stake reads. Selecting a wallet
  // this account does not hold leaves no position and no action, and never
  // falls back to the account's stored wallet.
  await selectWallet(page, otherWallet)
  await expect(page.getByRole("button", {name: "Connect or switch wallet"})).toBeVisible()
  await expect(page.getByLabel("REGENT amount")).toHaveCount(0)

  await selectWallet(page, wallet)
  await expect(page.getByText("5 REGENT", {exact: true})).toBeVisible()

  // Max names the exact staked balance rather than a rounded rendering of it.
  await page.getByRole("button", {name: "Max"}).click()
  await expect(page.getByLabel("REGENT amount")).toHaveValue("10")

  await page.getByLabel("REGENT amount").fill("1")
  await page.getByRole("button", {name: "Review stake"}).click()
  await expect(page.getByRole("heading", {name: "Stake REGENT"}).last()).toBeVisible()
  await expect(page.getByText("1 REGENT", {exact: true})).toBeVisible()
  await expect(
    page.locator(".stake-review").getByText("0x1111…1111", {exact: true}).first(),
  ).toBeVisible()

  // One click. The approval is sent, the server verifies its receipt and the
  // exact allowance, and the stake follows automatically through the same
  // preflight — without a second approval and without a second stake.
  const confirm = page.getByRole("button", {name: "Confirm in wallet"})
  await confirm.evaluate(button => {
    button.click()
    button.click()
  })

  await expect(page.getByText("Confirmed on Base.")).toBeVisible()
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
  await expect(
    page.getByText("You rejected the request in your wallet. Nothing was sent."),
  ).toBeVisible()
  expect(await sendCount(page)).toBe(2)

  // The next claim meets a wallet that moved between the claim and the push, so
  // it was never asked for anything. The review is released rather than closed:
  // it stays on screen, and the very same review signs on its next attempt.
  await page.evaluate(key => sessionStorage.setItem(key, "0"), moveKey)
  await page.getByRole("button", {name: "Review USDC claim"}).click()
  await expect(page.getByText("Review the details before opening your wallet.")).toBeVisible()
  await page.getByRole("button", {name: "Confirm in wallet"}).click()

  await expect(page.getByText("Nothing was sent. You can try this action again.")).toBeVisible()
  await expect(page.locator(".stake-review")).toBeVisible()
  expect(await sendCount(page)).toBe(2)

  await page.evaluate(key => sessionStorage.removeItem(key), moveKey)
  await page.getByRole("button", {name: "Confirm in wallet"}).click()

  await expect(page.getByText("Confirmed on Base.")).toBeVisible()
  expect(await sendCount(page)).toBe(3)

  // The last action reports its hash and stops: the browser asks Base for
  // nothing, and the server's own read is what finishes it. Preparing it at all
  // proves the rejected operation closed: had the rejection been withheld, this
  // review would be refused as outstanding.
  await page.getByRole("button", {name: "Unstake", exact: true}).click()
  await page.getByLabel("REGENT amount").fill("1")
  await page.getByRole("button", {name: "Review unstake"}).click()
  await expect(
    page.locator(".stake-review").getByRole("heading", {name: "Unstake REGENT"}),
  ).toBeVisible()
  await expect(page.getByText("An earlier staking action is still outstanding")).toHaveCount(0)

  // A chain switch the customer rejected is still only a prompt. That exact
  // 4001 arrived before the send, so it releases the claim instead of ending it.
  await page.evaluate(key => sessionStorage.setItem(key, "1"), wrongChainKey)
  await page.getByRole("button", {name: "Confirm in wallet"}).click()

  await expect(page.getByText("Nothing was sent. You can try this action again.")).toBeVisible()
  await expect(
    page.locator(".stake-review").getByRole("heading", {name: "Unstake REGENT"}),
  ).toBeVisible()
  expect(await sendCount(page)).toBe(3)

  await page.evaluate(key => sessionStorage.removeItem(key), wrongChainKey)
  await page.getByRole("button", {name: "Confirm in wallet"}).click()

  const submitted = page.locator(".stake-submission")
  await expect(submitted.getByText(short(unstakeHash), {exact: true})).toBeVisible()
  await expect(page.getByText("Confirmed on Base.")).toBeVisible()
  expect(await sendCount(page)).toBe(4)

  // Stored browser state is evidence, never authority. A reload asks the owning
  // account's row to restore it, finds nothing outstanding, and clears the
  // stale entry rather than inventing a submitted transaction or sending again.
  await page.evaluate(
    key => sessionStorage.setItem(key, JSON.stringify({transaction_hash: "0xstale"})),
    "regent:staking:submitted",
  )
  await page.reload()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
  await expect(page.getByLabel("REGENT amount")).toBeVisible()
  await expect(page.locator(".stake-submission")).toHaveCount(0)

  await expect
    .poll(() => page.evaluate(key => sessionStorage.getItem(key), "regent:staking:submitted"))
    .toBeNull()

  expect(await sendCount(page)).toBe(4)
})

function short(hash: string): string {
  return `${hash.slice(0, 8)}…${hash.slice(-4)}`
}

async function sendCount(page: Page): Promise<number> {
  return page.evaluate(key => Number(sessionStorage.getItem(key) ?? "0"), sendsKey)
}

// Moves the browser's active wallet the way Privy does, then announces it the
// way the bridge does.
async function selectWallet(page: Page, address: string): Promise<void> {
  await page.evaluate(next => {
    const seam = (window as Window & {__ashPlatformTestWallet?: {address: string}})
      .__ashPlatformTestWallet
    if (seam) seam.address = next
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}
