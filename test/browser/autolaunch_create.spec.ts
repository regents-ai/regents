import {readFileSync} from "node:fs"

import {expect, test} from "@playwright/test"

import {installAuthenticatedPrivy} from "./support/authenticated_privy"

const treasury = "0xabcdef0000000000000000000000000000000001"

const png = readFileSync(
  "priv/static/notebooks/2152a57337000ef5b8e2233d4cad237d4edbd92131cdec553437aef422719f3b/favicon-16x16.png",
)

test("account-owned launch setup persists and gates only the wallet stage", async ({page}) => {
  // This identity has no seeded Regent: Create belongs directly to the Human account.
  const auth = await installAuthenticatedPrivy(page, "other-account")
  await auth.establishLocalSession()
  await page.goto("/autolaunch/create")

  const stages = page.getByRole("navigation", {name: "Launch stages"})
  const tokenStage = stages.getByRole("button", {name: /Token Details/})
  const treasuryStage = stages.getByRole("button", {name: /Treasury Address/})
  const transactionsStage = stages.getByRole("button", {name: /Launch Transactions/})

  await expect(tokenStage).toBeVisible()
  await expect(treasuryStage).toBeEnabled()

  await tokenStage.click()
  const tokenForm = page.locator("#launch-token-details")
  await tokenForm.getByLabel("Name", {exact: true}).fill("")
  await expect(transactionsStage).toBeDisabled()
  await expect(page.getByText("Form your Regent")).toHaveCount(0)
  await expect(page.getByText("Open Formation")).toHaveCount(0)
  await expect(page.getByText("Recommended: 400 × 400 px")).toBeVisible()

  await treasuryStage.click()
  await expect(page.locator("#launch-treasury-details")).toBeVisible()
  await tokenStage.click()

  await tokenForm.getByLabel("Name", {exact: true}).fill("Browser Research")
  await tokenForm.getByLabel("Symbol", {exact: true}).fill("BROWSE")
  await tokenForm.getByLabel("Description", {exact: true}).fill("A persisted browser launch.")
  await tokenForm.getByLabel("Website", {exact: true}).fill("https://example.test/browser")
  await tokenForm.getByLabel("Required raise in REGENT", {exact: true}).fill("1000.5")
  await tokenForm.locator('input[type="file"]').setInputFiles({
    name: "browser-token.png",
    mimeType: "image/png",
    buffer: png,
  })

  await expect(tokenForm.getByRole("img", {name: "Saved token image"})).toBeVisible()
  await expect(page.getByRole("status")).toContainText("Saved to your account.")

  await treasuryStage.click()
  const treasuryForm = page.locator("#launch-treasury-details")
  await treasuryForm.getByLabel("Immutable treasury recipient", {exact: true}).fill(treasury)

  await expect(transactionsStage).toBeEnabled()
  await transactionsStage.click()
  await expect(page.locator("#launch-transactions .launch-wallet")).toBeVisible()

  await page.reload()
  await tokenStage.click()
  await expect(page.locator("#launch-token-details-name")).toHaveValue("Browser Research")
  await expect(page.locator("#launch-token-details-symbol")).toHaveValue("BROWSE")
  await expect(page.locator("#launch-token-details-description")).toHaveValue(
    "A persisted browser launch.",
  )

  await treasuryStage.click()
  await expect(page.locator("#launch-treasury-details-treasury")).toHaveValue(treasury)
})
