import {test, expect} from "@playwright/test"

test.beforeEach(async ({page, baseURL}) => {
  await page.route("**/*", (route) => {
    const url = new URL(route.request().url())
    if (url.origin === new URL(baseURL!).origin || url.protocol === "data:")
      return route.continue()
    return route.abort("blockedbyclient")
  })
  await page.goto("/showcase")
  await expect(page.locator("[data-sc-value=accent]")).toHaveText("#161616")
})

test("eight palettes, editable colors and live updates retain their state", async ({
  page,
}) => {
  const errors: string[] = []
  page.on("pageerror", (error) => errors.push(error.message))
  for (const brand of ["platform", "autolaunch", "patchbay", "techtree"]) {
    for (const mode of ["light", "dark"]) {
      const theme = page.locator(`[data-sc-theme="${brand}:${mode}"]`)
      await theme.click()
      await expect(theme).toHaveAttribute("aria-pressed", "true")
      await expect(page.locator("[data-sc-theme][aria-pressed=true]")).toHaveCount(1)
      await expect(theme.locator(".sc-theme-sample")).toBeVisible()
      await expect(page.locator("[data-sc-theme] img")).toHaveCount(0)
      expect(await page.locator(".sc").evaluate(el => getComputedStyle(el).backgroundImage)).toBe("none")
      await expect(page.locator("html")).toHaveAttribute("data-brand", brand)
      await expect(page.locator("html")).toHaveAttribute("data-theme", mode)
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      ).toBe(true)
      const colors = await page
        .locator("[data-sc-color]")
        .evaluateAll((inputs) =>
          inputs.map((input) => (input as HTMLInputElement).value),
        )
      expect(colors).toHaveLength(4)
      const color = page.locator("[data-sc-color=accent]")
      await color.fill("#cc8877")
      await expect(page.locator("[data-sc-value=accent]")).toHaveText("#CC8877")
      await page.getByRole("button", {name: "Primary", exact: true}).click()
      await expect(
        page
          .getByRole("status", {name: ""})
          .filter({hasText: "Action received."}),
      ).toBeVisible()
      await expect(color).toHaveValue("#cc8877")
      await page.locator("[data-sc-reset]").click()
    }
  }
  await page.locator("[data-sc-brand=patchbay]").click()
  await page.locator("[data-sc-mode=light]").click()
  await page.locator("[data-sc-color=accent]").fill("#123456")
  await page.locator("[data-sc-brand=platform]").click()
  await expect(page.locator("[data-sc-color=accent]")).not.toHaveValue(
    "#123456",
  )
  await page.locator("[data-sc-brand=patchbay]").click()
  await expect(page.locator("[data-sc-color=accent]")).toHaveValue("#123456")
  await page.reload()
  await page.locator("[data-sc-brand=patchbay]").click()
  await page.locator("[data-sc-mode=light]").click()
  await expect(page.locator("[data-sc-color=accent]")).toHaveValue("#123456")
  expect(errors).toEqual([])
})

test("every wallet press reaches its isolated provider, including pending and failed requests", async ({
  page,
}) => {
  await page.locator("[data-demo-connect]").click()
  await page.locator("[data-demo-send]").click({clickCount: 2, delay: 40})
  await expect(
    page.locator("[data-demo-results] li", {hasText: "Wallet received"}),
  ).toHaveCount(2)
  await expect(
    page.locator("[data-demo-results] li", {hasText: "confirmed"}),
  ).toHaveCount(2)
  for (const outcome of ["rejected", "reverted"]) {
    await page.locator("[data-demo-outcome]").selectOption(outcome)
    await page.locator("[data-demo-send]").click()
    await expect(page.locator("[data-demo-results] li").first()).toContainText(
      outcome,
    )
  }
  await page.locator("[data-demo-disconnect]").click()
  await expect(page.locator("[data-demo-wallet]")).toHaveText("Disconnected")
  await page.locator("[data-demo-send]").click()
  await expect(page.locator("[data-demo-results] li").first()).toContainText(
    "Connect the fixture first",
  )
  expect(
    await page.evaluate(() => window.__ashPlatformTestWallet),
  ).toBeUndefined()
})

test("Ash validation, utility outcomes, local database and disclosure fixtures work", async ({
  page,
  context,
}) => {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  await page.getByRole("button", {name: "Create item", exact: true}).click()
  await expect(page.locator("#empty-state-items")).toContainText("Workshop item 1")
  await page.getByRole("button", {name: "Add item", exact: true}).click()
  await expect(page.locator("#empty-state-items li")).toHaveCount(2)
  await page.getByRole("button", {name: "Reset items", exact: true}).click()
  await expect(page.locator("#empty-state-demo")).toContainText("Nothing here yet.")

  await page.locator("#showcase-chamber").getByRole("button", {name: "Edit", exact: true}).click()
  await expect(page.locator("#chamber-title")).toBeFocused()
  await page.locator("#chamber-title").fill("x")
  await page.getByRole("button", {name: "Save title", exact: true}).click()
  await expect(page.locator("#chamber-title")).toHaveAttribute("aria-invalid", "true")
  await expect(page.locator("#chamber-title")).toHaveValue("x")
  await page.locator("#chamber-title").fill("Updated local step")
  await page.getByRole("button", {name: "Save title", exact: true}).click()
  await expect(page.locator("#showcase-chamber")).toContainText("Updated local step")
  await page.locator("#showcase-chamber").getByRole("button", {name: "Edit", exact: true}).click()
  await page.locator("#chamber-title").fill("Discard this edit")
  await page.getByRole("button", {name: "Cancel", exact: true}).click()
  await expect(page.locator("#showcase-chamber")).not.toContainText("Discard this edit")

  await context.grantPermissions(["clipboard-read", "clipboard-write"])
  await page.locator("#showcase-ledger [data-sc-copy]").click()
  await expect(page.locator("#showcase-ledger [data-sc-copy]")).toHaveText("Copied")
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe("Network: Base\nState: Confirmed")

  const realAuth = page.locator("[data-sc-privy-mode]")
  await expect(realAuth).toHaveAttribute("data-sc-privy-mode", "fixture")
  await expect(realAuth).toContainText("Real sign-in is unavailable")
  await expect(realAuth.getByRole("button", {name: "Connect Privy"})).toBeDisabled()
  await expect(page.locator("#account-control [data-account-target]")).toHaveCount(0)

  await page.locator("#sample-title").fill("Test record")
  await page.locator("#sample-quantity").fill("2")
  await page.getByRole("button", {name: "Run create action"}).click()
  await expect(page.locator("#sample-records")).toContainText("Test record × 2")
  await page.locator("#sample-title").fill("x")
  await page.getByRole("button", {name: "Run create action"}).click()
  await expect(page.locator("#sample-title")).toHaveAttribute(
    "aria-invalid",
    "true",
  )
  for (const [kind, expected] of [
    ["amount", '"formatted": "1"'],
    ["calldata", "0x095ea7b3"],
    ["privy_valid", "Verified fixture"],
    ["privy_expired", "token_expired"],
    ["privy_audience", "invalid_audience"],
  ]) {
    await page.locator("#utility-kind").selectOption(kind)
    await page.getByRole("button", {name: "Run locally", exact: true}).click()
    await expect(page.locator("#utility-result")).toContainText(expected)
  }
  await page.getByRole("button", {name: "Check isolated database"}).click()
  await expect(page.locator("#utility-result")).toContainText("SELECT 1 passed")
  await page.locator("#comments-detail > summary").click()
  await page.locator("#comment-body").fill("   ")
  await page.getByRole("button", {name: "Post comment", exact: true}).click()
  await expect(page.locator("#comment-ledger-status")).toContainText("could not be posted")
  await expect(page.locator("#comment-body")).toHaveValue("   ")
  await page.locator("#comment-body").fill("A fixture comment")
  await page.getByRole("button", {name: "Post comment", exact: true}).click()
  await expect(page.locator(".comment-ledger__list")).toContainText(
    "A fixture comment",
  )
  await expect(page.locator(".comment-ledger__list")).toBeVisible()
  await page.locator("#connections-detail > summary").click()
  for (const provider of ["github", "x", "farcaster"]) {
    const control = page.locator(`#showcase-connections-${provider} button`)
    await control.click()
    await expect(control).toHaveText("Disconnect")
    await control.click()
    await expect(control).toHaveText("Connect")
  }
  page.once("dialog", dialog => dialog.accept())
  await page.locator(".comment-ledger__list").getByRole("button", {name: "Delete"}).click()
  await expect(page.locator(".comment-ledger__list")).toHaveCount(0)
  const catalog = await (await page.request.get("/showcase/catalog")).json()
  expect(
    catalog.components.some(
      (item: {function: string; attributes: string[]}) =>
        item.function === "field" && item.attributes.includes("label"),
    ),
  ).toBe(true)
  expect(
    await page.locator("#utility-inventory").evaluate((el) => el.textContent),
  ).toContain("RegentPrivy")
  await expect(page.locator("#utility-inventory")).not.toHaveAttribute("open")
  expect(errors).toEqual([])
})

test("mobile, keyboard, reduced motion, retired backgrounds and isolated previews", async ({
  page,
}, testInfo) => {
  await page.setViewportSize({width: 390, height: 844})
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.locator("#disclosure-example > summary").focus()
  await page.keyboard.press("Enter")
  await expect(page.locator("#disclosure-example")).toHaveAttribute("open", "")
  expect(
    await page
      .locator("#disclosure-example > summary")
      .evaluate((el) => getComputedStyle(el).outlineStyle),
  ).not.toBe("none")
  expect(
    await page
      .locator("#disclosure-example .rg-chevron")
      .evaluate((el) => getComputedStyle(el).transitionDuration),
  ).toBe("0s")
  await page.locator("#backgrounds-detail > summary").click()
  await expect(page.locator(".sc-backgrounds figure")).toHaveCount(2)
  await page.locator("#shell-detail > summary").click()
  const shell = page.frameLocator("#shell-preview")
  await expect(shell.locator("#app-shell")).toBeVisible()
  await expect(shell.locator("[data-account-target=sign-in]")).toHaveCount(0)
  await shell.locator("[data-theme-toggle]").click()
  for (let i = 0; i < 3; i++) {
    await page.locator(`#product-preview-${i} > summary`).click()
    await expect(page.locator(`#product-preview-${i} iframe`)).toHaveAttribute(
      "sandbox",
      "",
    )
    await expect(
      page.frameLocator(`#product-preview-${i} iframe`).locator("[inert]"),
    ).toBeVisible()
  }
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true)
  await page.locator("[data-sc-mode=light]").click()
  await page.evaluate(() => window.scrollTo(0, 0))
  await page.screenshot({
    path: testInfo.outputPath("mobile-light.png"),
    fullPage: true,
  })
})

test("comments typeset Markdown and LaTeX on live updates without enabling HTML or unsafe math", async ({
  page,
}) => {
  await page.locator("#comments-detail > summary").click()
  await page.locator("#comment-body").fill(
    String.raw`## Proof

**Energy** is $E=mc^2$.

$$\frac{1}{2} + \sqrt{x}$$

> Formatted locally.

| Input | Output |
| --- | --- |
| x | 2 |

Code stays literal: ` + "`$not_math$`.",
  )
  await page.getByRole("button", {name: "Post comment", exact: true}).click()
  const body = page.locator(".comment-ledger__body").first()
  await expect(body.locator("h2")).toHaveText("Proof")
  await expect(body.locator("strong")).toHaveText("Energy")
  await expect(body.locator("table")).toBeVisible()
  await expect(body.locator(".katex")).toHaveCount(2)
  await expect(body.locator(".katex-display math")).toBeVisible()
  await expect(body.locator("code")).toHaveText("$not_math$")
  await expect(body.locator("annotation").last()).toContainText(
    String.raw`\frac{1}{2}`,
  )

  // A later comment must not corrupt the already-rendered one.
  await page
    .locator("#comment-body")
    .fill(
      String.raw`$\href{javascript:alert(1)}{click}$ $\includegraphics{https://example.com/x.png}$ $\notACommand{x}$`,
    )
  await page.getByRole("button", {name: "Post comment", exact: true}).click()
  await expect(page.locator(".comment-ledger__body")).toHaveCount(2)
  const unsafe = page.locator(".comment-ledger__body").first()
  await expect(unsafe.locator("[data-math-rendered]")).toHaveCount(3)
  await expect(
    unsafe.locator("a, img, script, [onclick], [onerror]"),
  ).toHaveCount(0)
  await expect(unsafe).toContainText("notACommand")
  await expect(
    page.locator(".comment-ledger__body").last().locator(".katex"),
  ).toHaveCount(2)
  await page.setViewportSize({width: 390, height: 844})
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true)
})


test("math source remains readable when its optional renderer cannot load", async ({page}) => {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  await page.route("**/comment_math-*.js", route => route.abort("failed"))
  await page.locator("#comments-detail > summary").click()
  await page.locator("#comment-body").fill("A formula: $x^2$")
  await Promise.all([
    page.waitForEvent("requestfailed", request => request.url().includes("comment_math-")),
    page.getByRole("button", {name: "Post comment", exact: true}).click(),
  ])
  await expect(page.locator(".comment-ledger__body")).toContainText("A formula: x^2")
  await expect(page.locator(".comment-ledger__body .katex")).toHaveCount(0)
  expect(errors).toEqual([])
})
