import {expect, test} from "@playwright/test"

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

// From this width up the three products stand side by side; below it they read as one column.
const CARD_ROW_MIN_WIDTH = 768

const assertNoOverflow = async (page: import("@playwright/test").Page) => {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
  ).toBe(true)
}

test("[U2] homepage is server-readable and lists all three products", async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false})
  const page = await context.newPage()
  await page.goto("/")

  await expect(page.getByRole("heading", {name: "Regents Labs", level: 1})).toBeVisible()
  await expect(page.locator(".rl-hero-copy .rl-hero-description")).toHaveText(
    "The community-owned agentic product lab",
  )
  await expect(page.getByRole("heading", {name: "Prove what makes an agent better."})).toBeVisible()

  const cards = page.locator("[data-home-hero-card]")
  await expect(cards).toHaveCount(3)
  expect(await cards.evaluateAll(elements => elements.map(element => element.id))).toEqual([
    "home-card-autolaunch",
    "home-card-techtree",
    "home-card-patchbay",
  ])

  // Every product site is open, so every card carries a live new-tab link.
  const open = page.locator("[data-home-hero-card] a.rl-action")
  await expect(open).toHaveCount(3)
  await expect(open).toHaveText(["Open autolaunch ↗", "Open techtree ↗", "Open patchbay ↗"])
  for (const [name, site] of [
    ["autolaunch", "https://autolaunch.sh"],
    ["techtree", "https://techtree.sh"],
    ["patchbay", "https://patchbay.help"],
  ]) {
    const link = page.locator(`#home-card-${name} a.rl-action`)
    await expect(link).toHaveText(`Open ${name} ↗`)
    await expect(link).toHaveAttribute("href", site)
    await expect(link).toHaveAttribute("target", "_blank")
    await expect(link).toHaveAttribute("rel", "noopener noreferrer")
  }

  const sources = page.locator("[data-home-hero-card] a.rl-card-source")
  await expect(sources).toHaveCount(3)
  expect(
    await sources.evaluateAll(elements => elements.map(element => element.getAttribute("href"))),
  ).toEqual([
    "https://github.com/regents-ai/autolaunch",
    "https://github.com/regents-ai/techtree",
    "https://github.com/regents-ai/patchbay",
  ])

  const buy = page.locator(".rl-stakers-actions a", {hasText: "Buy REGENT"})
  await expect(buy).toHaveAttribute("href", /^https:\/\/app\.uniswap\.org\/explore\/tokens\/base\//)
  await expect(buy).toHaveAttribute("target", "_blank")
  const chart = page.locator(".rl-stakers-actions a", {hasText: "View Chart"})
  await expect(chart).toHaveAttribute("href", /^https:\/\/dexscreener\.com\//)
  await expect(chart).toHaveAttribute("target", "_blank")
  const stake = page.locator(".rl-stakers-actions a", {hasText: "Stake REGENT"})
  await expect(stake).toHaveAttribute("href", "/stake")
  await expect(stake).not.toHaveAttribute("target", /.+/)

  await expect(page.locator("#techtree, #autolaunch, #patchbay")).toHaveCount(3)
  await expect(page.locator("#regent a.rl-action--strong")).toHaveAttribute("href", "/stake")
  await context.close()
})

// A tab is only useful if its section actually arrives in view.
test("[U1] a navigation tab brings its section into view", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  await page.locator("#home-nav-regent").click()
  await expect(page).toHaveURL(/#regent$/)

  await expect
    .poll(() =>
      page.evaluate(() => {
        const section = document.querySelector("#regent")!.getBoundingClientRect()
        return section.top < window.innerHeight && section.bottom > 0
      }),
    )
    .toBe(true)
})

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
  await expect(page.locator("[data-home-hero-copy]")).toBeVisible()
  await expect(page.locator("[data-home-hero-card]")).toHaveCount(3)
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

// The founder's hero: the words in the left half with the crown drawn across the whole stage
// behind them and the products underneath where there is room, and the same things in reading
// order, crown between words and products, where there is not.
test("[U1][U2] the hero sets its words over the crown, and above it on a phone", async ({page}) => {
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

  for (const width of [1440, 1024]) {
    await test.step(`${width} wide`, async () => {
      await page.setViewportSize({width, height: 900})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const hero = await boxOf(".rl-hero")
      const copy = await boxOf("#home-title")
      const cards = await boxOf("#home-products")
      const stakers = await boxOf(".rl-hero-stakers")
      const crown = await boxOf("#home-prism")

      expect(copy.left).toBeGreaterThanOrEqual(hero.left)
      expect(copy.right, "the words stay in the left half").toBeLessThanOrEqual(
        hero.left + hero.width / 2,
      )
      expect(cards.left, "the products start on the words' edge").toBeCloseTo(copy.left, 0)
      expect(cards.right, "the products cross the midline").toBeGreaterThan(
        hero.left + hero.width / 2,
      )
      expect(cards.top, "the products come under the words").toBeGreaterThanOrEqual(copy.bottom)
      expect(stakers.top, "the stakers band closes the hero").toBeGreaterThanOrEqual(cards.bottom)
      expect(crown.left, "the crown stands behind the words").toBeLessThanOrEqual(copy.left)
      expect(crown.top).toBeLessThanOrEqual(copy.top)
      expect(crown.right, "and behind the products").toBeGreaterThanOrEqual(cards.right)
      expect(crown.bottom).toBeGreaterThanOrEqual(cards.bottom)
      expect(crown.right).toBeLessThanOrEqual(hero.right)
    })
  }

  for (const width of [390, 375]) {
    await test.step(`${width} wide`, async () => {
      await page.setViewportSize({width, height: 844})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      // On a phone the crown takes a row of its own between the words and the products.
      const title = await boxOf("#home-title")
      const tagline = await boxOf(".rl-hero-copy .rl-hero-description")
      const crown = await boxOf("#home-prism")
      const cards = await boxOf("#home-products")
      const stakers = await boxOf(".rl-hero-stakers")

      expect(title.bottom, "the heading sits above the tagline").toBeLessThanOrEqual(tagline.top)
      expect(tagline.bottom, "the tagline sits above the crown").toBeLessThanOrEqual(crown.top)
      expect(crown.bottom, "the crown sits above the products").toBeLessThanOrEqual(cards.top)
      expect(cards.bottom, "the products sit above the stakers band").toBeLessThanOrEqual(
        stakers.top,
      )
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
    await page.goto("/")
    await waitForHomepage(page)
    await assertNoOverflow(page)

    const cards = page.locator("[data-home-hero-card]")
    await expect(cards).toHaveCount(3)
    const boxes = await cards.evaluateAll(elements =>
      elements.map(element => {
        const box = element.getBoundingClientRect()
        return {height: box.height, left: box.left, right: box.right, top: box.top}
      }),
    )
    expect(boxes.every(box => box.height >= 44 && box.left >= 0 && box.right <= viewport.width)).toBe(true)

    // Three across where the frame is wide enough, one column below that.
    expect(new Set(boxes.map(box => Math.round(box.top))).size).toBe(
      viewport.width >= CARD_ROW_MIN_WIDTH ? 1 : 3,
    )

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

test("[U1][U2] the products read autolaunch, techtree, patchbay at every viewport", async ({page}) => {
  for (const viewport of focusViewports) {
    await test.step(viewport.name, async () => {
      await page.setViewportSize({width: viewport.width, height: viewport.height})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const cards = await page.locator("[data-home-hero-card]").evaluateAll(elements =>
        elements.map(element => {
          const box = element.getBoundingClientRect()
          return {
            id: element.id,
            left: box.left,
            product: element.dataset.homeHeroCard,
            top: box.top,
          }
        }),
      )

      expect(cards.map(card => card.product)).toEqual(["autolaunch", "techtree", "patchbay"])
      expect(cards.map(card => card.id)).toEqual([
        "home-card-autolaunch",
        "home-card-techtree",
        "home-card-patchbay",
      ])

      // Side by side the cards share one top and step to the right; stacked they share one
      // left edge and step down. Either way they read in the founder's order.
      for (const [index, card] of cards.entries()) {
        if (index === 0) continue
        if (viewport.width >= CARD_ROW_MIN_WIDTH) {
          expect(card.top).toBeCloseTo(cards[0].top, 0)
          expect(card.left).toBeGreaterThan(cards[index - 1].left)
        } else {
          expect(card.top).toBeGreaterThan(cards[index - 1].top)
          expect(card.left).toBeCloseTo(cards[0].left, 0)
        }
      }
    })
  }
})

// Pointing at a product never recolours its heading.
test("[U2] card hover leaves the heading ink alone", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)
  for (const product of ["autolaunch", "techtree", "patchbay"]) {
    const heading = page.locator(`#home-card-${product} h2`)
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
          products: bottom("#home-products"),
          stakers: bottom(".rl-hero-stakers"),
          stakersActions: bottom(".rl-stakers-actions"),
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

// What staking pays and the two ways to take part are one thing, so they stand in one
// container built like a product card, with the controls under the sentence.
test("[U2] the stakers band is one container with its ways in underneath", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)

  const framing = await page.locator(".rl-hero-stakers").evaluate(element => ({
    clip: getComputedStyle(element, "::after").clipPath,
    overflow: getComputedStyle(element).overflow,
    fill: getComputedStyle(element, "::after").backgroundColor,
    host: getComputedStyle(element).backgroundColor,
  }))
  expect(framing.clip).toContain("polygon")
  expect(framing.overflow).toBe("visible")
  // Chromium serialises an opaque computed colour as rgb(); any alpha below 1 becomes rgba().
  expect(framing.fill, "the panel paints an opaque surface").toMatch(/^rgb\(\d+, \d+, \d+\)$/)
  expect(framing.host, "on a box that carries none of its own").toBe("rgba(0, 0, 0, 0)")

  const sentence = (await page.locator(".rl-regent-copy").boundingBox())!
  const actions = (await page.locator(".rl-stakers-actions").boundingBox())!
  expect(actions.y, "the ways in stand under the sentence").toBeGreaterThanOrEqual(
    sentence.y + sentence.height,
  )
  expect(actions.x, "and start on the same edge").toBeCloseTo(sentence.x, 0)
  await expect(page.locator(".rl-stakers-actions a")).toHaveCount(3)
})

// The picture behind the hero is a grey line drawing with no ground of its own, so it takes
// whatever the page is painted and reads the same in a light theme as in a dark one. The file
// itself has to be that, with nothing on the page correcting it after the fact.
test("[U2] the picture behind the hero carries no colour and no ground of its own", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)

  const picture = await page.locator(".rl-hero-art").evaluate(element => {
    const image = element as HTMLImageElement
    const meanBrightnessOver = (ground: string | null) => {
      const canvas = document.createElement("canvas")
      canvas.width = image.naturalWidth
      canvas.height = image.naturalHeight
      const context = canvas.getContext("2d", {willReadFrequently: true})!
      if (ground) {
        context.fillStyle = ground
        context.fillRect(0, 0, canvas.width, canvas.height)
      }
      context.drawImage(image, 0, 0)
      const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data
      let total = 0
      let widestChannelSpread = 0
      for (let index = 0; index < pixels.length; index += 4) {
        const channels = [pixels[index], pixels[index + 1], pixels[index + 2]]
        total += (channels[0] + channels[1] + channels[2]) / 3
        if (pixels[index + 3] === 0) continue
        widestChannelSpread = Math.max(
          widestChannelSpread,
          Math.max(...channels) - Math.min(...channels),
        )
      }
      return {mean: total / (pixels.length / 4), widestChannelSpread}
    }

    const onWhite = meanBrightnessOver("#ffffff")
    const onBlack = meanBrightnessOver("#000000")
    return {
      greyOnItsOwn: meanBrightnessOver(null).widestChannelSpread,
      greyOnWhite: onWhite.widestChannelSpread,
      groundShowsThrough: onWhite.mean - onBlack.mean,
      correction: getComputedStyle(image).filter,
    }
  })

  expect(picture.greyOnItsOwn, "every mark in the file is grey").toBe(0)
  expect(picture.greyOnWhite, "and stays grey over a light page").toBe(0)
  expect(
    picture.groundShowsThrough,
    "the page behind it is what fills the frame, not a slab of its own",
  ).toBeGreaterThan(200)
  expect(picture.correction, "with nothing on the page correcting it").toBe("none")
})

// The Techtree chapter reads as an ink heading over one muted description, with its three
// proofs in the grid below.
test("[U1] the Techtree chapter keeps its proofs under muted body copy", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  await expect(page.locator("#techtree .rl-proof-grid")).toHaveCount(1)
  await expect(page.locator("#techtree .rl-proof-grid article")).toHaveCount(3)

  const body = page.locator("#techtree .rl-chapter-intro div > p:not(.rl-overline)")
  await expect(body).toHaveCount(1)

  const type = await body.evaluateAll(elements => {
    // The probe lives outside the chapter so the muted rule cannot claim it and make the
    // comparison tautological.
    const probe = document.createElement("p")
    probe.style.color = "var(--rl-muted)"
    document.querySelector(".rl-root")!.append(probe)
    const muted = getComputedStyle(probe).color
    probe.remove()
    return {
      colors: elements.map(element => getComputedStyle(element).color),
      heading: getComputedStyle(elements[0].parentElement!.querySelector("h2")!).color,
      ink: getComputedStyle(document.querySelector(".rl-root")!).color,
      muted,
    }
  })

  expect(type.colors).toEqual([type.muted])
  expect(type.heading).toBe(type.ink)
  expect(type.muted).not.toBe(type.heading)
})

// The closing frame carries no chapter number, so its headline has to be placed on the chapter
// headline edge explicitly at every width, or the page would read as two columns of sections.
test("[U1][U3] the numberless closing shares the chapter headline column", async ({page}) => {
  for (const viewport of [
    {name: "desktop", width: 1440, height: 1000},
    {name: "review-1024x768", width: 1024, height: 768},
    {name: "mobile-390", width: 390, height: 844},
    {name: "mobile-320", width: 320, height: 720},
  ]) {
    await test.step(viewport.name, async () => {
      await page.setViewportSize({width: viewport.width, height: viewport.height})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const edges = await page
        .locator("#autolaunch h2, #techtree h2, #patchbay h2, #regent h2")
        .evaluateAll(elements =>
          elements.map(element => Math.round(element.getBoundingClientRect().left)),
        )
      expect(edges).toHaveLength(4)
      expect(new Set(edges).size, "every section starts on one left edge").toBe(1)
    })
  }
})

test("[U5] the Patchbay action stays contained and reachable at every tested viewport", async ({page}) => {
  for (const viewport of focusViewports) {
    await test.step(viewport.name, async () => {
      await page.setViewportSize({width: viewport.width, height: viewport.height})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const boxes = await page
        .locator("#patchbay .rl-chapter-actions a")
        .evaluateAll(elements =>
          elements.map(element => {
            const box = element.getBoundingClientRect()
            return {
              height: box.height,
              href: element.getAttribute("href"),
              left: box.left,
              right: box.right,
              text: element.textContent?.trim(),
            }
          }),
        )

      expect(boxes.map(box => [box.href, box.text])).toEqual([["https://patchbay.help", "Open patchbay ↗"]])
      expect(boxes.every(box => box.left >= 0 && box.right <= viewport.width)).toBe(true)
      expect(boxes.every(box => box.height >= 44)).toBe(true)
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

test("[U2] the primary homepage action keeps its contrast on hover", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)
  const action = page.locator(".rl-closing").getByRole("link", {name: "Explore staking"})
  const before = await action.evaluate(element => {
    const style = getComputedStyle(element)
    return {backgroundColor: style.backgroundColor, color: style.color}
  })
  await action.hover()
  await expect.poll(() => action.evaluate(element => {
    const style = getComputedStyle(element)
    return {backgroundColor: style.backgroundColor, color: style.color}
  })).toEqual(before)
})

test("[U1] the block primary action has a square high-contrast keyboard focus ring", async ({page}, testInfo) => {
  for (const viewport of focusViewports) {
    await page.setViewportSize({width: viewport.width, height: viewport.height})
    await page.goto("/")
    await waitForHomepage(page)

    // Closing the page is the only beat that asks for something, so it is the page's one
    // white action.
    await expect(page.locator(".rl-action--strong")).toHaveCount(1)
    await expect(page.locator(".rl-closing .rl-action--strong")).toHaveCount(1)

    let reached = false
    const focusableCount = await page.locator("a, button, input, select, textarea, [tabindex]:not([tabindex='-1'])").count()

    for (let tab = 0; tab <= focusableCount && !reached; tab += 1) {
      await page.keyboard.press("Tab")
      const focused = page.locator(".rl-action--strong:focus-visible")
      if (await focused.count() === 0) continue

      reached = true
      await expect(focused).toBeVisible()

      const geometry = await focused.evaluate(element => {
        const style = getComputedStyle(element)
        const root = document.querySelector(".rl-root")
        const rgb = (value: string) => {
          const canvas = document.createElement("canvas")
          canvas.width = 1
          canvas.height = 1
          const context = canvas.getContext("2d", {willReadFrequently: true})
          if (!context) return {alpha: 0, channels: [0, 0, 0]}
          context.fillStyle = value
          context.fillRect(0, 0, 1, 1)
          const pixel = [...context.getImageData(0, 0, 1, 1).data]
          return {alpha: pixel[3], channels: pixel.slice(0, 3)}
        }
        const luminance = (channels: number[]) => {
          const linear = channels.map(channel => {
            const value = channel / 255
            return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
          })
          return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        const contrast = (foreground: number[], background: number[]) => {
          const foregroundLuminance = luminance(foreground)
          const backgroundLuminance = luminance(background)
          return (Math.max(foregroundLuminance, backgroundLuminance) + 0.05) /
            (Math.min(foregroundLuminance, backgroundLuminance) + 0.05)
        }
        const outlineWidth = Number.parseFloat(style.outlineWidth)
        const outlineOffset = Number.parseFloat(style.outlineOffset)
        const outline = rgb(style.outlineColor)
        const borderColors = style.borderTopStyle === "none" ? [] : [style.borderTopColor]
        const adjacentValues = outlineOffset < 0
          ? [style.backgroundColor, ...borderColors]
          : [style.backgroundColor, ...borderColors, root ? getComputedStyle(root).backgroundColor : "transparent"]
        const adjacent = adjacentValues
          .map(rgb)
          .filter(color => color.alpha === 255)
        const rect = element.getBoundingClientRect()
        const extent = Math.max(0, outlineWidth + outlineOffset)
        const ring = {
          bottom: rect.bottom + extent,
          left: rect.left - extent,
          right: rect.right + extent,
          top: rect.top - extent,
        }
        const viewport = {bottom: window.innerHeight, left: 0, right: window.innerWidth, top: 0}
        const clippingAncestors = []
        for (let ancestor = element.parentElement; ancestor && ancestor !== document.body; ancestor = ancestor.parentElement) {
          const ancestorStyle = getComputedStyle(ancestor)
          const clips = [ancestorStyle.overflow, ancestorStyle.overflowX, ancestorStyle.overflowY]
            .some(value => ["auto", "clip", "hidden", "scroll"].includes(value))
          if (!clips) continue
          const ancestorRect = ancestor.getBoundingClientRect()
          clippingAncestors.push({
            bottom: ancestorRect.bottom,
            left: ancestorRect.left,
            right: ancestorRect.right,
            top: ancestorRect.top,
          })
        }
        const contains = (bounds: typeof viewport) =>
          ring.left >= bounds.left && ring.right <= bounds.right && ring.top >= bounds.top && ring.bottom <= bounds.bottom

        return {
          adjacentContrasts: adjacent.map(color => contrast(outline.channels, color.channels)),
          borderRadius: Number.parseFloat(style.borderRadius || "0"),
          focusVisible: element.matches(":focus-visible"),
          outlineVisible: outline.alpha > 0 && style.visibility !== "hidden" && Number.parseFloat(style.opacity || "1") > 0,
          outlineStyle: style.outlineStyle,
          outlineWidth,
          ringFitsViewport: contains(viewport),
          ringFitsClippingAncestors: clippingAncestors.every(contains),
        }
      })

      expect(geometry.focusVisible).toBe(true)
      expect(geometry.outlineStyle).toBe("solid")
      expect(geometry.outlineVisible).toBe(true)
      expect(geometry.outlineWidth).toBeGreaterThanOrEqual(2)
      expect(geometry.adjacentContrasts.every(contrast => contrast >= 3)).toBe(true)
      expect(geometry.borderRadius).toBeLessThanOrEqual(4)
      expect(geometry.ringFitsViewport).toBe(true)
      expect(geometry.ringFitsClippingAncestors).toBe(true)
    }

    expect(reached, "the primary action is reachable by keyboard").toBe(true)

    if (["desktop", "review-1024x768", "mobile-390", "zoom-200"].includes(viewport.name)) {
      await page.screenshot({
        path: testInfo.outputPath(`focus-${viewport.name}.png`),
        fullPage: true,
      })
    }
  }
})

// The hero tints its own words for the product under the pointer or the keyboard, but
// the focus ring belongs to the whole page. Both of the palette's accents are a product's
// colour here, so the ring is set in Text — the one colour the page wears whichever card
// is being read — and it has to stay that same mark on every control, including the card
// whose colour the page is currently wearing.
test("[U1] every hero control retains visible paired keyboard focus", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
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
      return {name: e.getAttribute("aria-label") ?? e.textContent?.trim() ?? "", width: parseFloat(style.outlineWidth), outline: style.outlineStyle, opacity: style.opacity}
    })
    if (!result) continue
    reached.add(result.name)
    expect(result.width).toBeGreaterThanOrEqual(2)
    expect(result.outline).toBe("solid")
    expect(Number(result.opacity)).toBeGreaterThan(0)
  }
  expect([...reached]).toEqual(expect.arrayContaining(["Open techtree ↗", "Stake REGENT", "autolaunch on GitHub"]))
})