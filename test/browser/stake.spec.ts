import {expect, test, type Page} from "@playwright/test"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const wallet = "0x1111111111111111111111111111111111111111"
const otherWallet = "0x2222222222222222222222222222222222222222"
const sendsKey = "regent:test:staking-wallet-sends"
const observationsKey = "regent:test:staking-wallet-observations"

test("Stake hands each click directly to the active Base wallet and presents FIFO results", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-staking")
  await installWallet(page)
  await auth.establishLocalSession()

  await page.goto("/stake")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})
  await expect(page.getByRole("heading", {name: "Stake REGENT"})).toBeVisible()
  await expect(
    page.getByText("Stake $REGENT. Receive revenue tokens equal to your staked percentage."),
  ).toBeVisible()

  await selectWallet(page, otherWallet)
  await expect(page.getByRole("button", {name: "Connect or switch wallet"})).toBeVisible()
  await expect(page.getByLabel("REGENT amount")).toHaveCount(0)

  await selectWallet(page, wallet)
  await expect(page.getByLabel("REGENT amount")).toBeVisible()
  await page.getByLabel("REGENT amount").fill("1")

  // The test wallet reports zero allowance. One accepted Stake click therefore
  // receives the exact approval prompt immediately followed by the Stake prompt.
  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(2)

  // An identical customer click is a new request, not a deduplicated or locked
  // operation. It receives the same two direct wallet prompts.
  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(4)

  await page.getByRole("button", {name: "Claim USDC", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(5)

  const dialog = page.getByRole("dialog", {name: "Staking result"})
  await expect(dialog).toBeVisible()
  await expect(dialog.getByText("Stake succeeded on Base.")).toBeVisible()
  const resultLink = dialog.getByRole("link", {name: "View on BaseScan"})
  await expect(resultLink).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(2)}`,
  )
  await expect(resultLink).toHaveAttribute("target", "_blank")
  await expect(resultLink).toHaveAttribute("rel", "noopener noreferrer")

  await page.keyboard.press("Escape")
  await expect(dialog.getByText("Stake succeeded on Base.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(4)}`,
  )

  await dialog.getByRole("button", {name: "Close"}).click()
  await expect(dialog.getByText("USDC claim succeeded on Base.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(5)}`,
  )
  await page.mouse.click(1, 1)
  await expect(dialog).toBeHidden()
  await expect(page.getByText(/REGENT approval (succeeded|reverted)/)).toHaveCount(0)

  expect(await observedHashes(page, "eth_getTransactionByHash")).toEqual([
    expectedHash(2),
    expectedHash(4),
    expectedHash(5),
  ])
  expect(await observedHashes(page, "eth_getTransactionReceipt")).toEqual([
    expectedHash(2),
    expectedHash(4),
    expectedHash(5),
  ])
  expect(await observedHashes(page, "eth_getBlockByHash")).toHaveLength(3)

  await expect(page.locator(".stake-review, .stake-submission")).toHaveCount(0)
  await expect(page.getByText(/transaction hash|Confirmed on Base|Retry/i)).toHaveCount(0)
  expect(await page.evaluate(() => sessionStorage.getItem("regent:staking:submitted"))).toBeNull()

  await page.reload()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
  await expect(page.getByLabel("REGENT amount")).toBeVisible()
  expect(await sendCount(page)).toBe(5)
})

test("Stake and Redeem cards fit desktop, tablet and mobile widths", async ({page}) => {
  const surfaces = [
    {route: "/stake", summary: ".stake-summary", layout: ".stake-layout", cell: "dd"},
    {
      route: "/redeem",
      summary: ".redeem-summary",
      layout: ".redeem-layout",
      cell: ".redeem-metric-value",
    },
  ]

  for (const width of [1280, 768, 390]) {
    await page.setViewportSize({width, height: 900})

    for (const {route, summary, layout, cell} of surfaces) {
      await page.goto(route)
      await expect(page.locator(summary)).toBeVisible()

      const fit = await page.locator(`${summary} ${cell}`).first().evaluate(
        (node, {summary, viewport}) => {
          node.textContent = "7390000000.123456789012345678 REGENT"
          const card = node.closest(summary) as HTMLElement
          return {
            card: card.scrollWidth - card.clientWidth,
            document: document.documentElement.scrollWidth - viewport,
          }
        },
        {summary, viewport: width},
      )

      expect(fit, `${route} at ${width}`).toEqual({card: 0, document: 0})

      const columns = await page
        .locator(layout)
        .evaluate(element => getComputedStyle(element).gridTemplateColumns.split(" ").length)
      expect(columns, `${route} at ${width}`).toBe(width > 768 ? 2 : 1)

      if (route === "/redeem") {
        const presentation = await page.locator(summary).evaluate(element => {
          const metric = element.querySelector(".redeem-metric") as HTMLElement
          const summaryStyle = getComputedStyle(element)
          const metricStyle = getComputedStyle(metric)
          return {
            background: summaryStyle.backgroundColor,
            border: summaryStyle.borderTopWidth,
            separator: metricStyle.boxShadow,
          }
        })
        expect(presentation.background).toBe("rgba(0, 0, 0, 0)")
        expect(presentation.border).toBe("1px")
        expect(presentation.separator).not.toBe("none")
      }
    }
  }
})

test("Stake never presents an immediate approval outcome", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-staking")
  await installWallet(page)
  await auth.establishLocalSession()
  await page.goto("/stake")
  await selectWallet(page, wallet)
  await page.getByLabel("REGENT amount").fill("1")
  await page.evaluate(() => {
    ;(window as Window & {__ashStakingMalformedApproval?: boolean})
      .__ashStakingMalformedApproval = true
  })

  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(page.getByRole("dialog", {name: "Staking result"})).toBeHidden()
  await expect(page.getByText("The submission outcome is unknown.")).toHaveCount(0)
  expect(await observedHashes(page, "eth_getTransactionByHash")).toEqual([])
  expect(await observedHashes(page, "eth_getTransactionReceipt")).toEqual([])
  expect(await observedHashes(page, "eth_getBlockByHash")).toEqual([])
})

async function installWallet(page: Page): Promise<void> {
  await page.addInitScript(
    ({wallet, sendsKey, observationsKey}) => {
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
              case "eth_getTransactionByHash": {
                const hash = params?.[0] as string
                recordObservation(method, hash)
                const transaction = (window as Window & {
                  __ashStakingTransactions?: Record<string, {
                    from: string
                    to: string
                    data: string
                    value: string
                  }>
                }).__ashStakingTransactions?.[hash]
                if (!transaction) return null
                return {
                  hash,
                  from: transaction.from,
                  to: transaction.to,
                  input: transaction.data,
                  value: transaction.value,
                  blockHash: `0x${"cd".repeat(32)}`,
                  blockNumber: "0x10",
                }
              }
              case "eth_getTransactionReceipt": {
                const hash = params?.[0] as string
                recordObservation(method, hash)
                const transaction = (window as Window & {
                  __ashStakingTransactions?: Record<string, {
                    from: string
                    to: string
                  }>
                }).__ashStakingTransactions?.[hash]
                if (!transaction) return null
                return {
                  transactionHash: hash,
                  from: transaction.from,
                  to: transaction.to,
                  status: "0x1",
                  blockHash: `0x${"cd".repeat(32)}`,
                  blockNumber: "0x10",
                }
              }
              case "eth_getBlockByHash": {
                recordObservation(method, params?.[0] as string)
                const transactions = Object.keys(
                  (window as Window & {__ashStakingTransactions?: Record<string, unknown>})
                    .__ashStakingTransactions ?? {},
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

            function recordObservation(method: string, hash: string): void {
              const observations = JSON.parse(sessionStorage.getItem(observationsKey) ?? "[]")
              observations.push({method, hash})
              sessionStorage.setItem(observationsKey, JSON.stringify(observations))
            }
          },
        },
      }
    },
    {wallet, sendsKey, observationsKey},
  )
}

function expectedHash(index: number): string {
  return `0x${index.toString(16).padStart(64, "0")}`
}

async function sendCount(page: Page): Promise<number> {
  return page.evaluate(key => Number(sessionStorage.getItem(key) ?? "0"), sendsKey)
}

async function observedHashes(page: Page, method: string): Promise<string[]> {
  return page.evaluate(
    ({key, method}) =>
      (JSON.parse(sessionStorage.getItem(key) ?? "[]") as Array<{
        method: string
        hash: string
      }>).filter(entry => entry.method === method).map(entry => entry.hash),
    {key: observationsKey, method},
  )
}

async function selectWallet(page: Page, address: string): Promise<void> {
  await page.evaluate(next => {
    const seam = (window as Window & {__ashPlatformTestWallet?: {address: string}})
      .__ashPlatformTestWallet
    if (seam) seam.address = next
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}
