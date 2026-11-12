import {expect, test} from "./support/offline"

type Page = import("@playwright/test").Page

const waitForHomepage = async (page: Page) => {
  const home = page.locator("#public-home")
  await expect(home).toBeVisible()
  // The suite's browser draws no picture, so the panel stands open once the page knows that.
  await expect(page.locator("#home-glass")).toHaveCSS("opacity", "1")
  await page.evaluate(async () => {
    await document.fonts.ready
    await Promise.all(
      [...document.images]
        .filter(image => !image.complete)
        .map(image => image.decode()),
    )
  })
  return home
}

// The four product sites, in the order the panel's tabs list them before Protocol.
const products = [
  {name: "Patchbay", site: "https://patchbay.help"},
  {name: "Autolaunch", site: "https://autolaunch.sh"},
  {name: "Techtree", site: "https://techtree.sh"},
  {name: "Keyfleet", site: "https://keyfleet.ai"},
]

const assertNoOverflow = async (page: Page) => {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth),
  ).toBe(0)
}

const boxOf = (page: Page, selector: string) =>
  page.locator(selector).first().evaluate(element => element.getBoundingClientRect().toJSON() as DOMRect)

test("[U2] homepage is server-readable: name, line, actions, agent prompt and products", async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false})
  const page = await context.newPage()
  await page.goto("/")

  const glass = page.locator("#home-glass")
  await expect(page.getByRole("heading", {level: 1})).toHaveText("Regents Labs")
  await expect(glass.locator(".rl-statement__line")).toHaveText(
    "We build tools for people and their agents. REGENT stakers share in the revenue.",
  )
  await expect(glass.getByRole("link", {name: "Enter App"})).toHaveAttribute("href", "/stake")
  await expect(glass.getByRole("heading", {level: 2, name: "Agent prompt"})).toBeVisible()
  await expect(glass.locator("#home-prompt-text")).toContainText("Help me get started")
  await expect(glass.getByRole("button", {name: "Copy"})).toBeVisible()
  await expect(glass.getByRole("button", {name: "Agent Tools"})).toBeVisible()

  const tabs = glass.getByRole("navigation", {name: "Products"}).getByRole("link")
  await expect(tabs).toHaveCount(6)
  for (const [index, {name, site}] of products.entries()) {
    await expect(tabs.nth(index)).toHaveText(`${name}, opens in a new tab`)
    await expect(tabs.nth(index)).toHaveAttribute("href", site)
    await expect(tabs.nth(index)).toHaveAttribute("target", "_blank")
    await expect(tabs.nth(index)).toHaveAttribute("rel", "noopener noreferrer")
  }
  await expect(tabs.nth(4)).toHaveText("Protocol")
  await expect(tabs.nth(4)).toHaveAttribute("href", "/stake")
  await expect(tabs.nth(5)).toHaveText("Cloak")
  await expect(tabs.nth(5)).toHaveAttribute("href", "/cloak")

  await expect(glass.getByRole("heading", {level: 2, name: "Products"})).toBeVisible()
  // The copyright stands outside the panel, at the window's bottom right.
  await expect(page.locator("#public-home > .home__copyright")).toHaveText("© 2026 Regents Labs")
  // Without scripts the picture is the server's still one, behind the panel.
  await expect(page.locator(".home__still")).toBeVisible()
  await expect(page.locator("#home-canvas")).toBeHidden()

  await context.close()
})

// The panel's product tabs and its Enter App button lead to their places, by keyboard and
// at phone width.
for (const {name, width, height} of [
  {name: "desktop", width: 1440, height: 900},
  {name: "mobile-390", width: 390, height: 844},
]) {
  test(`[R12] homepage product tabs and Enter App lead to their places at ${name}`, async ({page}) => {
    await page.setViewportSize({width, height})

    await page.goto("/")
    const tabs = page.getByRole("navigation", {name: "Products"}).getByRole("link")
    await expect(tabs).toHaveText([
      "Patchbay, opens in a new tab",
      "Autolaunch, opens in a new tab",
      "Techtree, opens in a new tab",
      "Keyfleet, opens in a new tab",
      "Protocol",
      "Cloak",
    ])
    await expect(page.locator("#home-content a.rl-hero-cta")).toHaveAttribute("href", "/stake")
    await assertNoOverflow(page)

    const patchbay = page.locator("#home-nav-patchbay")
    await expect(patchbay).toHaveAttribute("href", "https://patchbay.help")
    await expect(patchbay).toHaveAttribute("target", "_blank")

    await page.locator("#home-nav-protocol").focus()
    await page.keyboard.press("Enter")
    await expect(page).toHaveURL(/\/stake$/)
    await expect(page.locator("#regent-staking")).toBeVisible()

    await page.goto("/")
    await page.locator("#home-content a.rl-hero-cta").click()
    await expect(page).toHaveURL(/\/stake$/)
    await expect(page.locator("#regent-staking")).toBeVisible()
  })
}

// Display titles and body copy keep their separate canonical typographic roles.
test("[U1][U2] the mission line retains its sentence case", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)

  const line = page.locator("#home-content .rl-statement__line")
  await expect(line).toHaveText(
    "We build tools for people and their agents. REGENT stakers share in the revenue.",
  )
  expect(await line.evaluate(element => getComputedStyle(element).textTransform)).toBe("none")
})

// With less motion asked for, the picture stays the server's still one and the panel
// stands open at its full size from the start.
test("[U2] homepage keeps the still picture and an open panel for reduced motion", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/")
  await waitForHomepage(page)
  await expect(page.locator(".phx-connected").first()).toBeAttached()
  await expect(page.locator(".home__still")).toBeVisible()
  await expect(page.locator("#public-home")).not.toHaveAttribute("data-datascape-ready", "true")
  const glass = page.locator("#home-glass")
  await expect(glass).toHaveCSS("opacity", "1")
  await expect(glass).toHaveCSS("transform", "none")
  await expect(glass).toHaveCSS("pointer-events", "auto")
  await context.close()
})

// A page whose script never arrives keeps the panel out of sight for four seconds, like a
// page still starting, then brings it in by itself, so its links are never lost.
test("[U2] homepage brings the panel in by itself when its script never arrives", async ({page}) => {
  await page.route("**/assets/js/app.js*", route => route.abort())
  await page.goto("/")
  const glass = page.locator("#home-glass")
  await expect(glass).toHaveCSS("opacity", "0")
  await expect(glass).toHaveCSS("pointer-events", "none")
  await expect(glass).toHaveCSS("opacity", "1", {timeout: 6000})
  await expect(glass).toHaveCSS("transform", "none")
  await expect(glass).toHaveCSS("pointer-events", "auto")
  await expect(page.locator("#public-home")).not.toHaveAttribute("data-datascape-glass-state")
})

// Everything a landing render is allowed to differ by: the CSRF token and the
// LiveView handshake, all minted per request.
const stableRender = (html: string) =>
  html
    .replace(/csrf-token" content="[^"]*"/g, 'csrf-token" content="TOKEN"')
    .replace(/data-phx-session="[^"]*"/g, 'data-phx-session="SESSION"')
    .replace(/data-phx-static="[^"]*"/g, 'data-phx-static="STATIC"')
    .replace(/id="phx-[^"]*"/g, 'id="ID"')

// The landing is a dark-only composition: whatever palette the visitor saved, every render
// is the same dark page, and only the per-request tokens differ.
test("[U3] the public landing renders the same dark page for every saved palette", async ({browser}) => {
  const landing = async (saved?: "light" | "dark") => {
    const context = await browser.newContext()
    if (saved) {
      await context.addCookies([
        {name: "regent_theme", value: saved, url: test.info().project.use.baseURL as string},
      ])
    }
    const served = await (await context.request.get("/")).text()
    await context.close()
    return served
  }

  const [none, light, dark] = await Promise.all([landing(), landing("light"), landing("dark")])

  const main = (html: string) => stableRender(html).match(/<main[\s\S]*?<\/main>/)?.[0]
  expect(main(dark)).toContain('id="home-content"')
  expect(main(light)).toBe(main(dark))
  expect(main(none)).toBe(main(dark))

  for (const served of [none, light, dark]) {
    expect(served).toContain('data-theme="dark"')
    expect(served).toContain('data-home-theme-locked="true"')
    expect(served).toContain('<meta name="color-scheme" content="dark"')
    expect(served).toContain('data-brand="platform"')
  }
})

// The lock is not a rewrite of the visitor's preference: a saved light theme still renders
// the dark landing, offers no switch, and leaves the saved choice for the other pages.
test("[U3] the landing stays dark and preserves the visitor's saved theme", async ({browser}) => {
  const context = await browser.newContext()
  await context.addCookies([
    {name: "regent_theme", value: "light", url: test.info().project.use.baseURL as string},
  ])
  const page = await context.newPage()

  await page.goto("/")
  await waitForHomepage(page)

  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await expect(page.locator("html")).toHaveAttribute("data-home-theme-locked", "true")
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  await expect(page.locator("[data-theme-switch]:visible")).toHaveCount(0)
  const saved = (await context.cookies()).find(cookie => cookie.name === "regent_theme")
  expect(saved?.value).toBe("light")
  await context.close()
})

test("the landing keeps its opted-in display face for headings", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  expect(
    await page
      .locator("#home-title")
      .evaluate(element => getComputedStyle(element).fontFamily),
  ).toContain("Geist Serif")
})

// The panel stands in the middle of the window and holds the whole page: its header, the
// name and actions, then the products at its foot, each inside its edges at every
// width. A panel taller than the window scrolls the page while the picture stays put.
for (const viewport of [
  {name: "mobile-320", width: 320, height: 568},
  {name: "mobile-390", width: 390, height: 844},
  {name: "tablet-768", width: 768, height: 1024},
  {name: "desktop", width: 1440, height: 900},
]) {
  test(`[U1][U2][U3] homepage fits ${viewport.name} with usable focus targets`, async ({page}, testInfo) => {
    await page.setViewportSize({width: viewport.width, height: viewport.height})
    await page.goto("/")
    await waitForHomepage(page)
    await assertNoOverflow(page)

    const glass = await boxOf(page, "#home-glass")
    expect(Math.abs(glass.left - (viewport.width - glass.right)), "centred across").toBeLessThan(2)
    expect(glass.width).toBeLessThanOrEqual(Math.min(704, viewport.width - 32) + 1)
    // A page that fits the window holds the panel in its middle; a taller one scrolls.
    const fits = await page.evaluate(() => document.scrollingElement!.scrollHeight <= innerHeight)
    if (fits) {
      expect(Math.abs(glass.top - (viewport.height - glass.bottom)), "centred down").toBeLessThan(2)
    }

    const parts = await Promise.all(
      [
        ".rl-header",
        "#home-title",
        ".rl-hero-cta",
        ".rl-hero-prompt",
        ".rl-hero-tools",
        "#home-products-title",
        ".rl-product-tabs",
      ].map(selector =>
        boxOf(page, selector),
      ),
    )
    for (const [index, box] of parts.entries()) {
      expect(box.left, `${viewport.name} part ${index} inside the panel`).toBeGreaterThanOrEqual(glass.left)
      expect(box.right, `${viewport.name} part ${index} inside the panel`).toBeLessThanOrEqual(glass.right)
      if (index > 0) expect(box.top, `${viewport.name} part ${index} in order`).toBeGreaterThanOrEqual(parts[index - 1]!.top)
    }
    for (const selector of [".rl-product-tab", ".rl-header-links > *"]) {
      const boxes = await page.locator(selector).evaluateAll(elements =>
        elements.map(element => element.getBoundingClientRect().toJSON() as DOMRect),
      )
      expect(
        boxes.every(box => box.left >= glass.left - 0.5 && box.right <= glass.right + 0.5),
        `${viewport.name} ${selector} inside the panel`,
      ).toBe(true)
    }

    // The whole panel can be scrolled into view, and the picture stays put behind it.
    await page.evaluate(() => window.scrollTo(0, document.scrollingElement!.scrollHeight))
    const scrolled = await boxOf(page, "#home-glass")
    expect(scrolled.bottom, `${viewport.name} panel's foot reachable`).toBeLessThanOrEqual(viewport.height + 1)
    const copyright = await boxOf(page, ".home__copyright")
    expect(copyright.bottom, `${viewport.name} copyright inside the window`).toBeLessThanOrEqual(viewport.height)
    expect(copyright.right, `${viewport.name} copyright inside the window`).toBeLessThanOrEqual(viewport.width)
    if (!fits) {
      const foot = await boxOf(page, ".home__foot")
      expect(foot.bottom, `${viewport.name} panel's foot ends above the copyright`).toBeLessThanOrEqual(copyright.top)
    }
    const still = await boxOf(page, ".home__still")
    expect(still.top).toBe(0)
    expect(still.height).toBe(viewport.height)
    await page.evaluate(() => window.scrollTo(0, 0))

    await page.keyboard.press("Tab")
    await expect(page.locator(":focus-visible")).toBeVisible()

    if (viewport.width === 320) {
      await page.screenshot({
        path: testInfo.outputPath("final-mobile-320-dark.png"),
        fullPage: true,
      })
    }
  })
}

// Enter App is the one large action: beside the name and its line in a wide panel, full
// width under them on a phone. Under it, the agent prompt copies with its button, and the
// quiet Agent Tools link opens the tools window.
test("[U2] Enter App leads, then the agent prompt and Agent Tools", async ({browser}) => {
  for (const {width, height} of [
    {width: 1440, height: 900},
    {width: 390, height: 844},
    {width: 320, height: 700},
  ]) {
    await test.step(`${width} wide`, async () => {
      const context = await browser.newContext({viewport: {width, height}})
      await context.grantPermissions(["clipboard-read", "clipboard-write"])
      const page = await context.newPage()
      await page.goto("/")
      await waitForHomepage(page)
      await expect(page.locator(".phx-connected").first()).toBeAttached()
      await assertNoOverflow(page)

      const [statement, cta, prompt, tools, main] = await Promise.all(
        [".rl-statement", ".rl-hero-cta", ".rl-hero-prompt", ".rl-hero-tools", "#home-content"].map(selector =>
          boxOf(page, selector),
        ),
      )
      if (width >= 1024) {
        expect(cta.left, "Enter App stands right of the name").toBeGreaterThan(statement.right)
        expect(cta.top, "level with the name and its line").toBeLessThan(statement.bottom)
      } else {
        expect(cta.top, "Enter App under the line").toBeGreaterThanOrEqual(statement.bottom)
        expect(cta.width, "across the panel").toBeGreaterThan(main.width - 80)
      }
      expect(cta.height).toBeGreaterThanOrEqual(56)
      expect(prompt.top, "the prompt under Enter App").toBeGreaterThanOrEqual(cta.bottom)
      expect(tools.top, "Agent Tools under the prompt").toBeGreaterThanOrEqual(prompt.bottom)
      expect(tools.height, "a full tap target").toBeGreaterThanOrEqual(44)

      const copy = page.locator("#home-prompt-copy")
      expect((await copy.boundingBox())!.height, "a full tap target").toBeGreaterThanOrEqual(44)
      // The answer takes the label's place without moving the words under it.
      const before = await boxOf(page, "#home-prompt-text")
      await copy.click()
      await expect(copy).toHaveAccessibleName("Copied")
      expect(await boxOf(page, "#home-prompt-text")).toEqual(before)
      const copied = await page.evaluate(() => navigator.clipboard.readText())
      expect(copied).toBe((await page.locator("#home-prompt-text").textContent())!.trim())
      expect(copied).toMatch(/^Read https?:\/\/[^ ]+\/llms\.txt\. /)
      expect(copied).toContain("/start shows how")

      await page.getByRole("button", {name: "Agent Tools"}).click()
      await expect(page.getByRole("dialog", {name: /^Agents see \d+ WebMCP Tools$/})).toBeVisible()
      await context.close()
    })
  }
})

test("[U1][U2][U3] homepage remains usable at effective 200 percent zoom", async ({page}, testInfo) => {
  await page.setViewportSize({width: 640, height: 900})
  await page.goto("/")
  await waitForHomepage(page)
  await assertNoOverflow(page)
  await page.screenshot({
    path: testInfo.outputPath("final-zoom-200-dark.png"),
    fullPage: true,
  })
})

test("[U2][U3] homepage captures the accepted mobile and tablet states", async ({browser}, testInfo) => {
  for (const capture of [
    {height: 844, name: "final-mobile-390-dark.png", width: 390},
    {height: 1024, name: "final-tablet-768-dark.png", width: 768},
  ]) {
    const context = await browser.newContext({
      colorScheme: "dark",
      viewport: {width: capture.width, height: capture.height},
    })
    const page = await context.newPage()
    await page.goto("/")
    await waitForHomepage(page)
    await assertNoOverflow(page)
    await page.screenshot({path: testInfo.outputPath(capture.name), fullPage: true})
    await context.close()
  }
})

// The focus ring belongs to the whole page: it is set in Text and stays that same mark on
// every control in the panel. A filled button (Enter App) draws the shared cut ring
// around its corners instead of an outline.
test("[U1] every panel control retains visible paired keyboard focus", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)
  const count = await page.locator("a, button").count()
  const reached = new Set<string>()
  for (let tab = 0; tab <= count; tab += 1) {
    await page.keyboard.press("Tab")
    const result = await page.evaluate(() => {
      const element = document.activeElement as HTMLElement | null
      if (!element?.closest("#home-glass") || !element.matches(":focus-visible")) return null
      const style = getComputedStyle(element)
      const ring = getComputedStyle(element, "::before")
      const name = element.getAttribute("aria-label") ?? element.textContent?.trim().replace(/\s+/g, " ") ?? ""
      const outlined = style.outlineStyle === "solid" && parseFloat(style.outlineWidth) >= 2
      const ringed = ring.borderTopStyle === "solid" && parseFloat(ring.borderTopWidth) >= 2
      return {name, marked: outlined || ringed, opacity: style.opacity}
    })
    if (!result) continue
    reached.add(result.name)
    expect(result.marked, result.name).toBe(true)
    expect(Number(result.opacity)).toBeGreaterThan(0)
  }
  expect([...reached]).toEqual(
    expect.arrayContaining(["Enter App", "Techtree, opens in a new tab", "Protocol"]),
  )
})

// The first Tab shows "Skip to content" on top of the page, and Enter moves the
// keyboard on to the panel's own controls, as on every other page.
test("the first Tab on the homepage shows Skip to content", async ({page}) => {
  for (const width of [1440, 390]) {
    await page.setViewportSize({width, height: 844})
    await page.goto("/")
    await waitForHomepage(page)
    const skip = page.getByRole("link", {name: "Skip to content"})
    await expect(skip).toHaveCSS("clip-path", "inset(50%)")
    await page.keyboard.press("Tab")
    await expect(skip).toBeFocused()
    await expect(skip).toHaveCSS("clip-path", "none")
    const box = (await skip.boundingBox())!
    expect(
      await page.evaluate(([x, y]) => document.elementFromPoint(x, y)?.closest(".shell-skip") !== null, [
        box.x + box.width / 2,
        box.y + box.height / 2,
      ] as const),
      `at ${width} wide`,
    ).toBe(true)
    await page.keyboard.press("Enter")
    await expect(page).toHaveURL(/#home-content$/)
    await page.keyboard.press("Tab")
    await expect(page.locator("#home-content :focus")).toBeVisible()
  }
})

// COPY_BUTTON: the $REGENT menu copies the contract address with the shared
// copy button, which answers "Copied" in place of its label.
test("[R14] the $REGENT menu copies the contract address", async ({browser}) => {
  const context = await browser.newContext({viewport: {width: 1440, height: 900}})
  await context.grantPermissions(["clipboard-read", "clipboard-write"])
  const page = await context.newPage()
  await page.goto("/")
  await waitForHomepage(page)

  const menu = page.locator("details.rl-token-menu").first()
  await menu.locator("summary").hover()
  const copy = menu.getByRole("button", {name: "Copy $REGENT contract address"})
  await copy.click()

  await expect(copy.locator(".rg-copy__copied")).toBeVisible()
  expect(await page.evaluate(() => navigator.clipboard.readText())).toMatch(/^0x[0-9a-fA-F]{40}$/)
  await context.close()
})
