import {expect, test, type Page} from "@playwright/test"

const wallet = "0x1111111111111111111111111111111111111111"
const otherWallet = "0x2222222222222222222222222222222222222222"
const sendsKey = "regent:test:staking-wallet-sends"

test("Stake hands each click directly to the active Base wallet and presents every result", async ({page}) => {
  await installWallet(page)

  await page.goto("/stake")
  await expect(page.getByRole("heading", {name: "Put REGENT to work."})).toBeVisible()
  await expect(page.getByText("No Regent account or Privy login is required.")).toBeVisible()
  await expect(page.locator("[data-account-target='sign-in']")).toBeVisible()

  await selectWallet(page, otherWallet)
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  await expect(page.locator(".stake-signer")).toHaveAttribute("title", otherWallet)

  await selectWallet(page, wallet)
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  await page.getByLabel("Amount", {exact: true}).fill("1")

  // The test wallet reports zero allowance. One accepted Stake click therefore
  // receives the exact approval prompt immediately followed by the Stake prompt.
  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(2)

  const dialog = page.locator("#staking-result-dialog")
  await expect(dialog.getByText("REGENT spending was approved successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(1)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog.getByText("1 REGENT was staked successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(2)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog).toBeHidden()

  // An identical customer click is a new request, not a deduplicated or locked
  // operation. It receives the same two direct wallet prompts.
  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(4)

  await expect(dialog.getByText("REGENT spending was approved successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(3)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog.getByText("1 REGENT was staked successfully.")).toBeVisible()
  await expect(dialog.getByRole("link", {name: "View on BaseScan"})).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(4)}`,
  )
  await dialog.getByRole("button", {name: "Done"}).click()
  await expect(dialog).toBeHidden()

  await page.getByRole("button", {name: "Claim USDC", exact: true}).click()
  await expect.poll(() => sendCount(page)).toBe(5)

  await expect(dialog.getByText("Your available USDC rewards were claimed.")).toBeVisible()
  const resultLink = dialog.getByRole("link", {name: "View on BaseScan"})
  await expect(resultLink).toHaveAttribute(
    "href",
    `https://basescan.org/tx/${expectedHash(5)}`,
  )
  await expect(resultLink).toHaveAttribute("target", "_blank")
  await expect(resultLink).toHaveAttribute("rel", "noopener noreferrer")
  await page.mouse.click(1, 1)
  await expect(dialog).toBeHidden()

  await expect(page.locator(".stake-review, .stake-submission")).toHaveCount(0)
  await expect(page.getByText(/transaction hash|Confirmed on Base|Retry/i)).toHaveCount(0)
  expect(await page.evaluate(() => sessionStorage.getItem("regent:staking:submitted"))).toBeNull()

  await page.reload()
  await expect(page.locator("[data-account-target='sign-in']")).toBeVisible()
  await expect(page.getByLabel("Amount", {exact: true})).toBeVisible()
  expect(await sendCount(page)).toBe(5)
})

test("Anonymous Stake dashboard is public and fits desktop and mobile widths", async ({page}) => {
  const contract = "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  const regent = "0x6f89bca4ea5931edfcb09786267b251dee752b07"
  const usdc = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

  for (const width of [1280, 390]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/stake")

    await expect(page.getByRole("heading", {name: "Put REGENT to work."})).toBeVisible()
    await expect(page.getByText("Staking active")).toBeVisible()
    await expect(page.locator(".stake-total")).toContainText("100")
    await expect(page.locator(".stake-total")).toContainText("REGENT staked")
    await expect(page.getByText("1,000 REGENT", {exact: true})).toBeVisible()
    await expect(page.getByText("900 REGENT", {exact: true})).toBeVisible()
    await expect(page.getByText("Confirmed at Base block #1,234.")).toBeVisible()
    await expect(page.locator(".stake-benefit-card-primary")).toContainText("12%")
    await expect(page.locator(".stake-benefit-grid")).toContainText("125,000 USDC")
    await expect(page.locator(".stake-benefit-grid")).toContainText("250,000 REGENT")

    await page.locator(".stake-contract-details summary").click()
    await expect(page.getByText(contract, {exact: true})).toBeVisible()
    await expect(page.getByText(regent, {exact: true})).toBeVisible()
    await expect(page.getByText(usdc, {exact: true})).toBeVisible()

    const progress = page.getByRole("progressbar", {name: "Staking capacity utilization"})
    await expect(progress).toHaveAttribute("max", "100")
    await expect(progress).toHaveAttribute("value", "10")

    const contractLink = page.getByRole("link", {
      name: "View verified staking contract on BaseScan",
    })
    await expect(contractLink).toHaveAttribute(
      "href",
      `https://basescan.org/address/${contract}`,
    )
    await expect(contractLink).toHaveAttribute("target", "_blank")
    await expect(contractLink).toHaveAttribute("rel", "noopener noreferrer")

    await expect(page.getByText("No Regent account or Privy login is required.")).toBeVisible()
    await expect(page.getByRole("button", {name: "Connect wallet to stake"})).toBeVisible()
    await expect(page.getByText("Available REGENT", {exact: true})).toHaveCount(0)
    await expect(page.getByText("Currently staked", {exact: true})).toHaveCount(0)
    await expect(page.locator("button[data-staking-action]")).toHaveCount(0)
    await expect(page.locator("#regent-staking[data-staking-allowance]")).toHaveCount(0)

    const fit = await page.evaluate(viewport => {
      const addresses = [...document.querySelectorAll<HTMLElement>(".stake-contract-facts code")]
      return {
        addresses: addresses.map(node => node.scrollWidth - node.clientWidth),
        document: document.documentElement.scrollWidth - viewport,
      }
    }, width)

    expect(fit, `Stake dashboard at ${width}`).toEqual({
      addresses: [0, 0, 0, 0],
      document: 0,
    })

    const columns = await page
      .locator(".stake-layout")
      .evaluate(element => getComputedStyle(element).gridTemplateColumns.split(" ").length)
    expect(columns, `Stake dashboard columns at ${width}`).toBe(width > 768 ? 2 : 1)

    const presentation = await page.evaluate(() => {
      const total = document.querySelector<HTMLElement>(".stake-total strong")!
      const capacity = document.querySelector<HTMLElement>(".stake-capacity-facts dd")!
      const connect = document.querySelector<HTMLElement>("[data-stake-connect]")!
      const contractLink = document.querySelector<HTMLElement>(".stake-contract-link")!
      return {
        capacityFont: Number.parseFloat(getComputedStyle(capacity).fontSize),
        connectHeight: connect.getBoundingClientRect().height,
        contractLinkHeight: contractLink.getBoundingClientRect().height,
        totalFont: Number.parseFloat(getComputedStyle(total).fontSize),
      }
    })

    expect(presentation.totalFont).toBeGreaterThan(presentation.capacityFont * 2)
    expect(presentation.connectHeight).toBeGreaterThanOrEqual(44)
    expect(presentation.contractLinkHeight).toBeGreaterThanOrEqual(44)
  }
})

test("Public Redeem collection cards fit desktop, tablet and mobile widths", async ({page}) => {
  for (const width of [1280, 768, 390]) {
    await page.setViewportSize({width, height: 900})
    await page.goto("/redeem")
    await expect(page.locator(".redeem-collection-grid")).toBeVisible()

    const fit = await page.locator(".redeem-collection-card dd").first().evaluate(
      (node, viewport) => {
        node.textContent = "7390000000 memberships ready"
        const card = node.closest(".redeem-collection-card") as HTMLElement
        return {
          card: card.scrollWidth - card.clientWidth,
          document: document.documentElement.scrollWidth - viewport,
        }
      },
      width,
    )

    expect(fit, `/redeem at ${width}`).toEqual({card: 0, document: 0})

    const columns = await page
      .locator(".redeem-collection-grid")
      .evaluate(element => getComputedStyle(element).gridTemplateColumns.split(" ").length)
    expect(columns, `/redeem at ${width}`).toBe(width > 800 ? 3 : 1)

    const presentation = await page.locator(".redeem-collection-card").first().evaluate(element => {
      const cardStyle = getComputedStyle(element)
      return {
        background: cardStyle.backgroundColor,
        border: cardStyle.borderTopWidth,
      }
    })
    expect(presentation.background).not.toBe("rgba(0, 0, 0, 0)")
    expect(presentation.border).toBe("1px")
  }
})

test("Stake keeps an immediate approval failure inline instead of presenting a receipt", async ({page}) => {
  await installWallet(page)
  await page.goto("/stake")
  await selectWallet(page, wallet)
  await page.getByLabel("Amount", {exact: true}).fill("1")
  await page.evaluate(() => {
    ;(window as Window & {__ashStakingMalformedApproval?: boolean})
      .__ashStakingMalformedApproval = true
  })

  await page.locator("button.stake-primary").click()
  await expect.poll(() => sendCount(page)).toBe(1)
  await expect(page.locator("#staking-result-dialog")).toBeHidden()
  await expect(page.locator("#staking-transaction-progress")).toBeVisible()
  await expect(page.getByText("The submission outcome is unknown.")).toBeVisible()
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

function expectedHash(index: number): string {
  return `0x${index.toString(16).padStart(64, "0")}`
}

async function sendCount(page: Page): Promise<number> {
  return page.evaluate(key => Number(sessionStorage.getItem(key) ?? "0"), sendsKey)
}

async function selectWallet(page: Page, address: string): Promise<void> {
  await page.evaluate(next => {
    const seam = (window as Window & {__ashPlatformTestWallet?: {address: string}})
      .__ashPlatformTestWallet
    if (seam) seam.address = next
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, address)
}
