import {expect, test, type Page} from "@playwright/test"

// Overview and $REGENT are public pages inside the persistent shell. These
// checks cover what the founder asked to see: both routes by direct load and by
// sidebar, sidebar order and highlighting, patch/back/forward without a new
// LiveView, disclosures by keyboard, long addresses that never scroll sideways,
// product links, and content while the staking reading is absent.

const viewports = {
  desktop: {width: 1280, height: 900},
  mobile: {width: 390, height: 844},
} as const

async function ready(page: Page) {
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
}

async function chooseTheme(page: Page, choice: "light" | "dark") {
  if ((await page.locator("html").getAttribute("data-theme")) !== choice) {
    await page.locator("#theme-control [data-theme-toggle]").click()
  }
  await expect(page.locator("html")).toHaveAttribute("data-theme", choice)
}

function noHorizontalOverflow(page: Page) {
  return page.evaluate(() => {
    const scroller = document.querySelector("#app-shell-scroller") ?? document.documentElement
    return {
      documentOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      scrollerOverflow: scroller.scrollWidth - scroller.clientWidth,
    }
  })
}

test("$REGENT loads directly inside the shell with its facts server-rendered", async ({page}) => {
  await page.goto("/regent")
  await ready(page)

  const token = page.locator("#regent-token")
  await expect(token.getByRole("heading", {level: 1, name: "$REGENT"})).toBeVisible()
  await expect(token).toContainText("0x6f89bcA4eA5931EdFCB09786267b251DeE752b07")
  await expect(token.getByRole("link", {name: /Blockscout/}).first()).toHaveAttribute(
    "href",
    /base\.blockscout\.com/,
  )
  await expect(token.getByRole("link", {name: /BaseScan/})).toHaveAttribute("href", /basescan\.org/)
  await expect(token.getByRole("img", {name: "20% Liquidity, 40% Labs allocation, 40% Vault"})).toBeVisible()
  await expect(token).toContainText("6 Nov 2026, 16:01:07 UTC")
  await expect(token).toContainText("5 Nov 2028, 16:01:07 UTC")
  await expect(token.getByRole("table")).toContainText("Clanker vault")
  await expect(token.getByRole("link", {name: "Stake", exact: true})).toHaveAttribute("href", "/stake")
  await expect(token.getByRole("link", {name: "Redeem", exact: true})).toHaveAttribute(
    "href",
    "/redeem",
  )

  // Disclosures start closed, and their content is in the HTML before any opens.
  await expect(token.locator("details.regent-token-details[open]")).toHaveCount(0)
  await expect(token.locator("details .regent-token-signers li")).toHaveCount(3)
  await expect(token).toContainText("0x8C172cA4b5Dd9449217C636A953727eACD690e37", {useInnerText: false})

  // No sign-in was demanded to see any of it.
  await expect(page.locator("#account-control [data-account-target='sign-in']")).toBeVisible()
  await expect(page).toHaveURL(/\/regent$/)
})

test("the sidebar lists $REGENT before Stake and marks the current page", async ({page}) => {
  await page.goto("/app")
  await ready(page)

  const sidebar = page.locator("#shell-sidebar")
  const destinations = await sidebar
    .locator("ul > li a")
    .evaluateAll(links => links.map(link => link.getAttribute("href")))
  expect(destinations.indexOf("/app")).toBeLessThan(destinations.indexOf("/regent"))
  expect(destinations.indexOf("/regent")).toBe(destinations.indexOf("/stake") - 1)

  await expect(sidebar.getByRole("link", {name: "Overview"})).toHaveAttribute("aria-current", "page")
  await expect(sidebar.getByRole("link", {name: "$REGENT"})).not.toHaveAttribute("aria-current", "page")

  const instance = await page.locator("#app-shell").getAttribute("data-shell-instance")

  await sidebar.getByRole("link", {name: "$REGENT"}).click()
  await expect(page).toHaveURL(/\/regent$/)
  await expect(page.locator("#regent-token h1")).toHaveText("$REGENT")
  await expect(sidebar.getByRole("link", {name: "$REGENT"})).toHaveAttribute("aria-current", "page")
  await expect(sidebar.getByRole("link", {name: "Overview"})).not.toHaveAttribute("aria-current", "page")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", instance!)

  await page.goBack()
  await expect(page).toHaveURL(/\/app$/)
  await expect(page.locator("#regent-ops-overview h1")).toBeVisible()
  await expect(sidebar.getByRole("link", {name: "Overview"})).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", instance!)

  await page.goForward()
  await expect(page).toHaveURL(/\/regent$/)
  await expect(page.locator("#regent-token h1")).toHaveText("$REGENT")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", instance!)
})

test("disclosures open and close from the keyboard and show a turned chevron", async ({page}) => {
  await page.goto("/regent")
  await ready(page)

  const details = page.locator("details.regent-token-details").first()
  const summary = details.locator("summary")
  await summary.focus()
  await expect(summary).toBeFocused()
  await expect(details).not.toHaveAttribute("open", "")

  await page.keyboard.press("Enter")
  await expect(details).toHaveAttribute("open", "")
  await expect(details.getByText("Original allocation plan").first()).toBeVisible()
  await expect(details.getByText("10% Animata program")).toBeVisible()
  const turned = await details.locator(".regent-token-chevron").evaluate(el => getComputedStyle(el).transform)
  expect(turned).not.toBe("none")

  await page.keyboard.press("Space")
  await expect(details).not.toHaveAttribute("open", "")

  // The Overview's product disclosure works the same way.
  await page.goto("/app")
  await ready(page)
  const fit = page.locator("details.regent-ops-fit")
  await fit.locator("summary").focus()
  await page.keyboard.press("Enter")
  await expect(fit).toHaveAttribute("open", "")
  await expect(fit.locator(".regent-ops-details-body")).toBeVisible()
})

test("the Overview links every product to its real home", async ({page}) => {
  await page.goto("/app")
  await ready(page)

  const products = page.getByRole("list", {name: "Products"})
  await expect(products.getByRole("listitem")).toHaveCount(4)
  await expect(products.getByRole("link", {name: "$REGENT"})).toHaveAttribute("href", "/regent")
  await expect(products.getByRole("link", {name: "Stake"})).toHaveAttribute("href", "/stake")
  await expect(products.getByRole("link", {name: "Redeem"})).toHaveAttribute("href", "/redeem")
  for (const [name, href] of [
    ["Open Autolaunch", "https://autolaunch.sh"],
    ["Open Techtree", "https://techtree.sh"],
    ["Open Patchbay", "https://patchbay.help"],
  ] as const) {
    const link = products.getByRole("link", {name})
    await expect(link).toHaveAttribute("href", href)
    await expect(link).toHaveAttribute("rel", "noopener noreferrer")
  }

  await products.getByRole("link", {name: "$REGENT"}).click()
  await expect(page).toHaveURL(/\/regent$/)
  await expect(page.locator("#regent-token h1")).toHaveText("$REGENT")
})

for (const [device, viewport] of Object.entries(viewports)) {
  for (const theme of ["light", "dark"] as const) {
    test(`${device} ${theme}: both pages fit the viewport and are captured`, async ({page}, testInfo) => {
      await page.setViewportSize(viewport)
      await page.goto("/app")
      await ready(page)
      await chooseTheme(page, theme)

      for (const [route, id] of [
        ["/app", "#regent-ops-overview"],
        ["/regent", "#regent-token"],
      ] as const) {
        await page.goto(route)
        await ready(page)
        await expect(page.locator(`${id} h1`)).toBeVisible()

        // Open every disclosure so the long addresses inside them are measured too.
        await page.locator(`${id} details`).evaluateAll(all =>
          all.forEach(el => el.setAttribute("open", "")),
        )
        expect(await noHorizontalOverflow(page), `${route} ${device} ${theme}`).toEqual({
          documentOverflow: 0,
          scrollerOverflow: 0,
        })

        const name = `${route === "/app" ? "overview" : "regent"}-${device}-${theme}.png`
        await page.screenshot({path: testInfo.outputPath(name), fullPage: true})
      }
    })
  }
}
