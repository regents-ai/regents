import {expect, test, type Page} from "@playwright/test"

import {installAuthenticatedPrivy} from "./support/authenticated_privy"

function cleanBrowser(page: Page) {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  page.on("console", message => message.type() === "error" && errors.push(message.text()))
  return () => expect(errors).toEqual([])
}

async function stubEnsRpc(page: Page) {
  await page.route("https://ethereum-rpc.publicnode.com/**", async route => {
    const body = route.request().postDataJSON() as {id: number}
    await route.fulfill({
      contentType: "application/json",
      headers: {"access-control-allow-origin": "*"},
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: body.id,
        error: {code: -32000, message: "ENS name not found in browser fixture"},
      }),
    })
  })
}

test("launchpad presents Graduated, Active auctions, and Explore with canonical search history", async ({
  page,
}) => {
  const assertCleanBrowser = cleanBrowser(page)
  await stubEnsRpc(page)
  await page.goto("/autolaunch")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  await expect(page.locator("#launchpad-graduated")).toContainText("Graduated")
  await expect(page.locator("#launchpad-active")).toContainText("Active auctions")
  await expect(page.locator("#launchpad-explore")).toContainText("Explore")
  await expect(page.locator(".launchpad-create-link")).toHaveAttribute(
    "href",
    "/autolaunch/create",
  )

  const search = page.getByRole("searchbox", {
    name: "Search auctions, tokens, addresses, or creators",
  })
  await search.fill("literal % _ 研究")
  await expect(page).toHaveURL(url => url.pathname === "/autolaunch" && url.searchParams.get("q") === "literal % _ 研究")
  await expect(page.locator("#launchpad-graduated")).toContainText(
    "No matching auctions or tokens.",
  )
  await expect(page.locator("#launchpad-active")).toContainText(
    "No matching auctions or tokens.",
  )
  await expect(page.locator("#launchpad-explore")).toContainText(
    "No matching auctions or tokens.",
  )

  await page.evaluate(() => window.scrollTo(0, 360))
  const searchedScroll = await page.evaluate(() => window.scrollY)
  await search.fill("second search")
  await expect(page).toHaveURL(url => url.searchParams.get("q") === "second search")

  await page.goBack()
  await expect(search).toHaveValue("literal % _ 研究")
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(searchedScroll)

  await page.goForward()
  await expect(search).toHaveValue("second search")
  await page.getByRole("button", {name: "Clear"}).click()
  await expect(page).toHaveURL(url => url.pathname === "/autolaunch" && url.search === "")
  await expect(page.locator("#launchpad-graduated")).toBeVisible()
  await expect(page.locator("#launchpad-active")).toBeVisible()
  await expect(page.locator("#launchpad-explore")).toBeVisible()
  assertCleanBrowser()
})

test("signed-in wallet controls show a short address, copy action, and Disconnect", async ({page}) => {
  const assertCleanBrowser = cleanBrowser(page)
  await stubEnsRpc(page)
  const auth = await installAuthenticatedPrivy(page, "other-account")
  await auth.establishLocalSession()
  await page.goto("/autolaunch")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const account = page.locator("#account-control")
  await account.locator("summary").click()
  await expect(account.locator("[data-account-identity-address]")).toHaveText(
    /0x[0-9a-f]{4}…[0-9a-f]{4}/i,
  )
  await expect(account.getByRole("button", {name: "Copy address"})).toBeVisible()
  await expect(account.getByRole("button", {name: "Disconnect"})).toBeVisible()
  await expect(account.getByRole("link", {name: "Profile"})).toHaveCount(0)
  await expect(account.getByRole("link", {name: "Settings"})).toHaveCount(0)
  assertCleanBrowser()
})
