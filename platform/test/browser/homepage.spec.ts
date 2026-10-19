import {expect, test} from "./support/offline"

const focusViewports = [
  {name: "desktop", width: 1440, height: 900},
  {name: "review-1024x768", width: 1024, height: 768},
  {name: "mobile-320", width: 320, height: 720},
  {name: "mobile-390", width: 390, height: 844},
  {name: "short-landscape", width: 844, height: 390},
  {name: "zoom-200", width: 640, height: 900},
]

const waitForHomepage = async (page: import("@playwright/test").Page) => {
  const home = page.locator("#public-home")
  await expect(home).toBeVisible()
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

// The six worlds in the order the hero lists them, each with the cube face its room is behind.
const worlds = [
  {face: "0", name: "Autolaunch", site: "https://autolaunch.sh"},
  {face: "1", name: "Techtree", site: "https://techtree.sh"},
  {face: "2", name: "Patchbay", site: "https://patchbay.help"},
  {face: "5", name: "Keyfleet", site: "https://keyfleet.ai"},
  {face: "4", name: "Staking", site: /\/stake$/},
  {face: "3", name: "Regents on X", site: "https://x.com/regents_sh"},
]

// From this width up the list of worlds stands three across, in two rows; below it the
// worlds read as one column.
const WORLD_GRID_MIN_WIDTH = 768
const worldRowsAt = (width: number) => (width >= WORLD_GRID_MIN_WIDTH ? 2 : 6)

// The list of worlds is the hero wherever the cube is not drawn. A visitor who asks for
// less motion always gets it, so a test that reads the list asks for that first.
const keepTheListOfWorlds = (page: import("@playwright/test").Page) =>
  page.emulateMedia({reducedMotion: "reduce"})

const assertNoOverflow = async (page: import("@playwright/test").Page) => {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
  ).toBe(true)
}

test("[U2] homepage is server-readable and lists all six worlds", async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false})
  const page = await context.newPage()
  await page.goto("/")

  await expect(page.getByRole("heading", {name: "Regents Labs", level: 1})).toBeVisible()
  await expect(page.locator(".rl-hero-copy .rl-hero-description")).toHaveText(
    "The community-owned agentic product lab",
  )

  const listed = page.locator("#home-worlds .world-cube__world")
  await expect(listed).toHaveCount(6)
  expect(
    await listed.evaluateAll(elements =>
      elements.map(element => (element as HTMLElement).dataset.world),
    ),
  ).toEqual(worlds.map(world => world.face))

  // Every world is open, so every one carries a live new-tab link.
  for (const {face, name, site} of worlds) {
    const world = page.locator(`#home-worlds [data-world="${face}"]`)
    await expect(world.getByRole("heading", {level: 3})).toHaveText(name)
    const link = world.locator("a")
    await expect(link).toHaveText(`Visit ${name}, opens in a new tab`)
    await expect(link).toHaveAttribute("href", site)
    await expect(link).toHaveAttribute("target", "_blank")
    await expect(link).toHaveAttribute("rel", "noopener noreferrer")
  }

  await context.close()
})

// Each homepage header control leads to its place, by keyboard and at phone width.
for (const {name, width, height} of [focusViewports[0], focusViewports[3]]) {
  test(`[R12] homepage header tabs and App lead to their places at ${name}`, async ({page}) => {
    await page.setViewportSize({width, height})

    await page.goto("/")
    const tabs = page.getByRole("navigation", {name: "Products and staking"}).getByRole("link")
    await expect(tabs).toHaveText([
      "Autolaunch, opens in a new tab",
      "Techtree, opens in a new tab",
      "Patchbay, opens in a new tab",
      "Keyfleet, opens in a new tab",
      "Protocol",
    ])
    await expect(page.locator(".rl-header-links a.rl-action")).toHaveAttribute("href", "/stake")
    await assertNoOverflow(page)

    const patchbay = page.locator("#home-nav-patchbay")
    await expect(patchbay).toHaveAttribute("href", "https://patchbay.help")
    await expect(patchbay).toHaveAttribute("target", "_blank")

    await page.locator("#home-nav-protocol").focus()
    await page.keyboard.press("Enter")
    await expect(page).toHaveURL(/\/stake$/)
    await expect(page.locator("#regent-staking")).toBeVisible()

    await page.goto("/")
    await page.locator(".rl-header-links a.rl-action").click()
    await expect(page).toHaveURL(/\/stake$/)
    await expect(page.locator("#regent-staking")).toBeVisible()
  })
}

// Display titles and body copy keep their separate canonical typographic roles.
test("[U1][U2] the tagline retains its sentence case", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)

  const tagline = page.locator(".rl-hero-copy .rl-hero-description")
  await expect(tagline).toHaveText("The community-owned agentic product lab")
  expect(await tagline.evaluate(element => getComputedStyle(element).textTransform)).toBe(
    "none",
  )
})

test("[U2] homepage settles immediately for reduced motion", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/")
  await waitForHomepage(page)
  await expect(page.locator(".rl-hero-copy")).toBeVisible()
  await expect(page.locator("#home-worlds .world-cube__world")).toHaveCount(6)
  await context.close()
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

  const main = (html: string) => stableRender(html).match(/<main>[\s\S]*?<\/main>/)?.[0]
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
  await expect(page.locator("[data-theme-toggle]:visible")).toHaveCount(0)
  const saved = (await context.cookies()).find(cookie => cookie.name === "regent_theme")
  expect(saved?.value).toBe("light")
  await context.close()
})

test("the landing keeps its opted-in display face for headings", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  expect(
    await page
      .locator(".rl-hero-copy h1")
      .evaluate(element => getComputedStyle(element).fontFamily),
  ).toContain("Geist Pixel Square")
})

// The founder's hero: on a wide screen the words stand over the top-left of the cube's stage;
// a phone stacks the words above the stage. The worlds come under the words at every width.
test("[U1][U2] the hero sets its words over the cube's stage", async ({page}) => {
  const boxOf = (selector: string) =>
    page.locator(selector).evaluate(element => {
      const box = element.getBoundingClientRect()
      return {
        bottom: box.bottom,
        left: box.left,
        right: box.right,
        top: box.top,
        width: box.width,
      }
    })

  for (const {width, height} of [
    {width: 1440, height: 900},
    {width: 1024, height: 900},
    {width: 390, height: 844},
    {width: 375, height: 844},
  ]) {
    await test.step(`${width} wide`, async () => {
      await page.setViewportSize({width, height})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const hero = await boxOf(".rl-hero")
      const title = await boxOf("#home-title")
      const tagline = await boxOf(".rl-hero-copy .rl-hero-description")
      const stage = await boxOf("#home-worlds")
      const listed = await boxOf("#home-worlds .world-cube__worlds")

      expect(title.left).toBeGreaterThanOrEqual(hero.left)
      expect(title.bottom, "the heading sits above the tagline").toBeLessThanOrEqual(tagline.top)
      expect(stage.left, "the stage stands behind the words").toBeLessThanOrEqual(title.left)
      if (width >= 768) {
        expect(stage.top).toBeLessThanOrEqual(title.top)
      } else {
        expect(stage.top, "a phone stacks the stage under the words").toBeGreaterThanOrEqual(
          tagline.bottom,
        )
      }
      expect(stage.right, "and crosses the midline").toBeGreaterThan(hero.left + hero.width / 2)
      expect(stage.right).toBeLessThanOrEqual(hero.right)
      expect(listed.top, "the worlds come under the words").toBeGreaterThanOrEqual(tagline.bottom)
      expect(listed.bottom, "and stay on the stage").toBeLessThanOrEqual(stage.bottom)

      if (width >= 1024) {
        expect(title.right, "the words stay in the left half").toBeLessThanOrEqual(
          hero.left + hero.width / 2,
        )
      }
    })
  }
})

for (const viewport of [
  {name: "mobile-320", width: 320, height: 720},
  {name: "mobile-390", width: 390, height: 844},
  {name: "tablet-768", width: 768, height: 1024},
  {name: "desktop", width: 1440, height: 1000},
]) {
  test(`[U1][U2][U3] homepage fits ${viewport.name} with usable focus targets`, async ({page}, testInfo) => {
    await page.setViewportSize({width: viewport.width, height: viewport.height})
    await keepTheListOfWorlds(page)
    await page.goto("/")
    await waitForHomepage(page)
    await assertNoOverflow(page)

    const listed = page.locator("#home-worlds .world-cube__world")
    await expect(listed).toHaveCount(6)
    const boxes = await listed.evaluateAll(elements =>
      elements.map(element => {
        const box = element.getBoundingClientRect()
        return {height: box.height, left: box.left, right: box.right, top: box.top}
      }),
    )
    expect(boxes.every(box => box.height >= 44 && box.left >= 0 && box.right <= viewport.width)).toBe(true)

    // Three across where the frame is wide enough, one column below that.
    expect(new Set(boxes.map(box => Math.round(box.top))).size).toBe(worldRowsAt(viewport.width))

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

test("[U1][U2] the worlds read in the founder's order at every viewport", async ({page}) => {
  await keepTheListOfWorlds(page)
  for (const viewport of focusViewports) {
    await test.step(viewport.name, async () => {
      await page.setViewportSize({width: viewport.width, height: viewport.height})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const listed = await page.locator("#home-worlds .world-cube__world").evaluateAll(elements =>
        elements.map(element => {
          const box = element.getBoundingClientRect()
          return {
            left: box.left,
            name: element.querySelector("h3")!.textContent!.trim(),
            top: box.top,
          }
        }),
      )

      expect(listed.map(world => world.name)).toEqual(worlds.map(world => world.name))

      // The worlds read in the founder's order, row by row: each starts a new row on the first
      // world's left edge or follows the one before it on the same row.
      expect(new Set(listed.map(world => Math.round(world.top))).size).toBe(
        worldRowsAt(viewport.width),
      )
      for (const [index, world] of listed.entries()) {
        if (index === 0) continue
        const before = listed[index - 1]
        if (Math.round(world.top) === Math.round(before.top)) {
          expect(world.left).toBeGreaterThan(before.left)
        } else {
          expect(world.top).toBeGreaterThan(before.top)
          expect(world.left).toBeCloseTo(listed[0].left, 0)
        }
      }
    })
  }
})

// Pointing at a world never recolours its heading.
test("[U2] world hover leaves the heading ink alone", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await keepTheListOfWorlds(page)
  await page.goto("/")
  await waitForHomepage(page)
  for (const {face} of worlds.slice(0, 3)) {
    const heading = page.locator(`#home-worlds [data-world="${face}"] h3`)
    const ink = await heading.evaluate(e => getComputedStyle(e).color)
    await heading.hover()
    expect(await heading.evaluate(e => getComputedStyle(e).color)).toBe(ink)
  }
})
// Generous compartments stay in natural flow rather than shrinking to a viewport budget.
test("[U1][U2] the complete hero grows in document flow on desktop", async ({page}) => {
  for (const viewport of [
    {name: "1280x640", width: 1280, height: 640},
    {name: "1280x720", width: 1280, height: 720},
    {name: "1440x900", width: 1440, height: 900},
    {name: "1920x1080", width: 1920, height: 1080},
  ]) {
    await test.step(viewport.name, async () => {
      await page.setViewportSize({width: viewport.width, height: viewport.height})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const edges = await page.evaluate(() => {
        const bottom = (selector: string) =>
          document.querySelector(selector)!.getBoundingClientRect().bottom
        return {
          scrolled: window.scrollY,
          heading: bottom("#home-title"),
          tagline: bottom(".rl-hero-copy .rl-hero-description"),
          worlds: bottom("#home-worlds"),
        }
      })

      expect(edges.scrolled, "nothing has scrolled away").toBe(0)
      for (const [part, edge] of Object.entries(edges)) {
        if (part === "scrolled") continue
        expect(edge, `${part} remains in the document`).toBeGreaterThan(0)
      }
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
// every control in the hero.
test("[U1] every hero control retains visible paired keyboard focus", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await keepTheListOfWorlds(page)
  await page.goto("/")
  await waitForHomepage(page)
  const count = await page.locator("a, button").count()
  const reached = new Set<string>()
  for (let tab = 0; tab <= count; tab += 1) {
    await page.keyboard.press("Tab")
    const result = await page.evaluate(() => {
      const e = document.activeElement as HTMLElement
      if (!e?.closest(".rl-hero") || !e.matches(":focus-visible")) return null
      const style = getComputedStyle(e)
      const name = e.getAttribute("aria-label") ?? e.textContent?.trim().replace(/\s+/g, " ") ?? ""
      return {name, width: parseFloat(style.outlineWidth), outline: style.outlineStyle, opacity: style.opacity}
    })
    if (!result) continue
    reached.add(result.name)
    expect(result.width).toBeGreaterThanOrEqual(2)
    expect(result.outline).toBe("solid")
    expect(Number(result.opacity)).toBeGreaterThan(0)
  }
  expect([...reached]).toEqual(
    expect.arrayContaining(["Visit Techtree, opens in a new tab"]),
  )
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
