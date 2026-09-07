import {expect, test, type Page} from "@playwright/test"

// The Overview is a public product map inside the persistent shell. These
// checks cover disclosures by keyboard, product links, and both viewports in
// both themes without horizontal overflow.

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

test("Overview disclosures open and close from the keyboard and show a turned chevron", async ({page}) => {
  await page.goto("/app")
  await ready(page)

  const fit = page.locator("details.regent-ops-fit")
  const summary = fit.locator("summary")
  await summary.focus()
  await expect(summary).toBeFocused()
  await expect(fit).not.toHaveAttribute("open", "")

  await page.keyboard.press("Enter")
  await expect(fit).toHaveAttribute("open", "")
  await expect(fit.locator(".regent-ops-details-body")).toBeVisible()
  const turned = await fit.locator(".regent-ops-chevron").evaluate(el => getComputedStyle(el).transform)
  expect(turned).not.toBe("none")

  await page.keyboard.press("Space")
  await expect(fit).not.toHaveAttribute("open", "")
})

test("the Overview links every product to its real home", async ({page}) => {
  await page.goto("/app")
  await ready(page)

  const products = page.getByRole("list", {name: "Products"})
  await expect(products.getByRole("listitem")).toHaveCount(4)
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

  const instance = await page.locator("#app-shell").getAttribute("data-shell-instance")
  await products.getByRole("link", {name: "Stake"}).click()
  await expect(page).toHaveURL(/\/stake$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", instance!)
})

for (const [device, viewport] of Object.entries(viewports)) {
  for (const theme of ["light", "dark"] as const) {
    test(`${device} ${theme}: the Overview fits the viewport and is captured`, async ({page}, testInfo) => {
      await page.setViewportSize(viewport)
      await page.goto("/app")
      await ready(page)
      await chooseTheme(page, theme)
      await expect(page.locator("#regent-ops-overview h1")).toBeVisible()

      await page.locator("#regent-ops-overview details").evaluateAll(all =>
        all.forEach(el => el.setAttribute("open", "")),
      )
      expect(await noHorizontalOverflow(page), `${device} ${theme}`).toEqual({
        documentOverflow: 0,
        scrollerOverflow: 0,
      })

      await page.screenshot({path: testInfo.outputPath(`overview-${device}-${theme}.png`), fullPage: true})
    })
  }
}
