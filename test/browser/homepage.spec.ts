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
  const home = page.locator('#public-home[data-hero-enhanced="true"][data-hero-motion="settled"]')
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

// Above this width the three products stand side by side; below it they read as one column.
const CARD_ROW_WIDTH = 960

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
  await expect(page.locator(".rl-hero-copy p")).toHaveText(
    "The community-owned agentic product lab",
  )
  await expect(page.locator("#home-products-label")).toHaveText("Agentic Products")
  await expect(page.getByRole("heading", {name: "Prove what makes an agent better."})).toBeVisible()

  const cards = page.locator("[data-home-hero-card]")
  await expect(cards).toHaveCount(3)
  expect(await cards.evaluateAll(elements => elements.map(element => element.id))).toEqual([
    "home-card-autolaunch",
    "home-card-techtree",
    "home-card-patchbay",
  ])

  // techtree is the one site that is open, so it is the one live site link.
  const open = page.locator("#home-card-techtree a.rl-action")
  await expect(open).toHaveText("Open techtree ↗")
  await expect(open).toHaveAttribute("href", "https://techtree.sh")
  await expect(open).toHaveAttribute("target", "_blank")
  await expect(open).toHaveAttribute("rel", "noopener noreferrer")

  const unopened = page.locator("[data-home-hero-card] button.rl-action")
  await expect(unopened).toHaveCount(2)
  await expect(unopened).toHaveText(["Open autolaunch ↗", "Open patchbay ↗"])
  for (const name of ["autolaunch", "patchbay"]) {
    const button = page.locator(`#home-card-${name} button.rl-action`)
    await expect(button).toBeDisabled()
    await expect(button).toHaveAttribute("aria-disabled", "true")
    // The label is there to read; the tab stop is not there to reach.
    expect(
      await button.evaluate(element => {
        element.focus()
        return document.activeElement === element
      }),
    ).toBe(false)
  }
  await expect(page.locator("[data-home-hero-card] a.rl-action")).toHaveCount(1)

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
  await expect(page.locator("#home-closing a.rl-action--strong")).toHaveAttribute("href", "#home-products")
  await context.close()
})

// A tab is only useful if its section arrives below the sticky header rather than under it.
test("[U1] a navigation tab lands its section clear of the sticky header", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  await page.locator("#home-nav-about").click()
  await expect(page).toHaveURL(/#home-closing$/)

  await expect
    .poll(() =>
      page.evaluate(() => {
        const header = document.querySelector(".rl-header")!.getBoundingClientRect()
        const section = document.querySelector("#home-closing")!.getBoundingClientRect()
        return section.top - header.bottom
      }),
    )
    .toBeGreaterThanOrEqual(0)
})

// The founder asked for the tagline in capitals. The capitals are painted on by the
// stylesheet, so the sentence anyone reads, copies or translates is the sentence as written.
test("[U1][U2] the tagline is shouted by the stylesheet, not by the sentence", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)

  const tagline = page.locator(".rl-hero-copy p")
  await expect(tagline).toHaveText("The community-owned agentic product lab")
  expect(await tagline.evaluate(element => getComputedStyle(element).textTransform)).toBe(
    "uppercase",
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

test("[U3] the public landing is one page for everyone, pinned dark", async ({browser}) => {
  const landing = async (saved?: "light" | "dark") => {
    const context = await browser.newContext()
    if (saved) {
      await context.addCookies([
        {name: "regent_theme", value: saved, url: "http://127.0.0.1:4002"},
      ])
    }
    const served = await (await context.request.get("/")).text()
    await context.close()
    return served
  }

  const [none, light, dark] = await Promise.all([landing(), landing("light"), landing("dark")])

  expect(stableRender(light)).toBe(stableRender(none))
  expect(stableRender(dark)).toBe(stableRender(none))

  for (const served of [none, light, dark]) {
    expect(served).toContain('data-theme="dark"')
    expect(served).toContain('content="dark"')
    expect(served).not.toContain("data-brand")
  }
})

test("[U3] the landing keeps its dark paint and the visitor's saved theme", async ({browser}) => {
  const context = await browser.newContext()
  await context.addCookies([
    {name: "regent_theme", value: "light", url: "http://127.0.0.1:4002"},
  ])
  const page = await context.newPage()

  await page.goto("/")
  await waitForHomepage(page)

  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await expect(page.locator("html")).not.toHaveAttribute("data-brand", /.+/)
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
  ).toContain("GeistPixel Circle")
})

// The founder's hero: the sentences on one side and the crown on the other where there is
// room for both, and the same three things in reading order where there is not.
test("[U1][U2] the hero sets its words beside the crown, and above it on a phone", async ({page}) => {
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
      const copy = await boxOf("[data-home-hero-copy]")
      const label = await boxOf("#home-products-label")
      const cards = await boxOf("#home-products")
      const stakers = await boxOf(".rl-hero-stakers")
      const crown = await boxOf("#home-prism")

      expect(copy.left).toBeGreaterThanOrEqual(hero.left)
      expect(copy.right, "the words stay in the left half").toBeLessThanOrEqual(
        hero.left + hero.width / 2,
      )
      expect(label.left, "the products label starts on the same edge as the words").toBeCloseTo(
        copy.left,
        0,
      )
      expect(cards.left, "the products start on that edge too").toBeCloseTo(copy.left, 0)
      expect(cards.right, "the products take the whole frame").toBeGreaterThan(
        hero.left + hero.width / 2,
      )
      expect(label.top, "the label comes under the words").toBeGreaterThanOrEqual(copy.bottom)
      expect(cards.top, "the products come under their label").toBeGreaterThanOrEqual(label.bottom)
      expect(stakers.top, "the stakers band closes the hero").toBeGreaterThanOrEqual(cards.bottom)
      expect(crown.left).toBeLessThanOrEqual(hero.left)
      expect(crown.right).toBeGreaterThanOrEqual(hero.right)
    })
  }

  for (const width of [390, 375]) {
    await test.step(`${width} wide`, async () => {
      await page.setViewportSize({width, height: 844})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      // On a phone the copy block hands its own lines to the hero stack, so it has no box
      // of its own: the heading stands for the words above the crown.
      const title = await boxOf("#home-title")
      const tagline = await boxOf(".rl-hero-copy p")
      const crown = await boxOf("#home-prism")
      const label = await boxOf("#home-products-label")
      const cards = await boxOf("#home-products")
      const stakers = await boxOf(".rl-hero-stakers")

      expect(title.bottom, "the heading sits above the tagline").toBeLessThanOrEqual(tagline.top)
      expect(tagline.bottom, "the tagline sits above the crown").toBeLessThanOrEqual(crown.top)
      expect(crown.bottom, "the crown sits above the products label").toBeLessThanOrEqual(label.top)
      expect(label.bottom, "the label sits above the products").toBeLessThanOrEqual(cards.top)
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
      viewport.width > CARD_ROW_WIDTH ? 1 : 3,
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
        if (viewport.width > CARD_ROW_WIDTH) {
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

// Pointing at a product is what recolours the hero: the section says which product it is
// showing, and only that card takes the colour.
test("[U2] pointing at a product colours the hero for it, and nothing else", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)

  const hero = page.locator(".rl-hero")
  const colorOf = (product: string) =>
    page.locator(`#home-card-${product}`).evaluate(element => {
      const style = getComputedStyle(element)
      return {color: style.color, edge: style.borderInlineStartColor}
    })

  await expect(hero).not.toHaveAttribute("data-hero-product", /.+/)
  const resting = await colorOf("techtree")

  const taken: Record<string, {color: string; edge: string}> = {}
  for (const product of ["autolaunch", "techtree", "patchbay"]) {
    await page.locator(`#home-card-${product} strong`).hover()
    await expect(hero).toHaveAttribute("data-hero-product", product)

    const hovered = await colorOf(product)
    expect(hovered.color, `${product} takes its own colour`).not.toBe(resting.color)
    expect(hovered.edge, `${product} marks its own edge`).toBe(hovered.color)
    taken[product] = hovered

    for (const other of ["autolaunch", "techtree", "patchbay"]) {
      if (other === product) continue
      expect((await colorOf(other)).color, `${other} stays at rest`).toBe(resting.color)
    }
  }

  // Three products, three colours: no two share one.
  expect(new Set(Object.values(taken).map(value => value.color)).size).toBe(3)

  await page.mouse.move(0, 0)
  await expect(hero).not.toHaveAttribute("data-hero-product", /.+/)
  expect((await colorOf("techtree")).color).toBe(resting.color)
})

// The founder reads the first screen without scrolling: the heading, the three products and
// the stakers band with both of its buttons all have to end above the fold.
test("[U1][U2] the hero ends above the fold on every desktop size", async ({page}) => {
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
          tagline: bottom(".rl-hero-copy p"),
          products: bottom("#home-products"),
          stakers: bottom(".rl-hero-stakers"),
          stakersActions: bottom(".rl-stakers-actions"),
        }
      })

      expect(edges.scrolled, "nothing has scrolled away").toBe(0)
      for (const [part, edge] of Object.entries(edges)) {
        if (part === "scrolled") continue
        expect(edge, `${part} ends above the fold`).toBeLessThanOrEqual(viewport.height)
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

  const framing = await page.locator(".rl-hero-stakers").evaluate(element => {
    const style = getComputedStyle(element)
    const card = getComputedStyle(document.querySelector(".rl-hero-card")!)
    return {
      background: style.backgroundColor,
      cardBackground: card.backgroundColor,
      sides: [
        style.borderBlockStartStyle,
        style.borderInlineEndStyle,
        style.borderBlockEndStyle,
        style.borderInlineStartStyle,
      ],
      width: Number.parseFloat(style.borderBlockStartWidth),
    }
  })

  expect(framing.sides).toEqual(["solid", "solid", "solid", "solid"])
  expect(framing.width).toBeGreaterThanOrEqual(1)
  expect(framing.background, "the band is panelled like a card").toBe(framing.cardBackground)

  const sentence = (await page.locator(".rl-hero-stakers > p").boundingBox())!
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

// The Techtree chapter reads as description then supporting line: both muted, both distinct from
// the heading, with the proof story standing between the two card grids.
test("[U1] the Techtree chapter keeps its proofs under muted body copy", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  await expect(page.locator("#techtree .rl-proof-grid")).toHaveCount(1)
  await expect(page.locator("#techtree .rl-proof-grid article")).toHaveCount(3)
  await expect(page.locator("#techtree .rl-story h3")).toHaveText("Climb in public. Verify before you ship.")
  await expect(page.locator("#techtree .rl-proof-state", {hasText: "Working prototype"})).toHaveCount(3)

  const body = page.locator("#techtree .rl-chapter-intro div > p:not(.rl-overline)")
  await expect(body).toHaveCount(3)

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
      sizes: elements.map(element => Number.parseFloat(getComputedStyle(element).fontSize)),
    }
  })

  // The mode rail (second paragraph) speaks in full ink; everything else stays muted.
  expect(type.colors).toEqual([type.muted, type.ink, type.muted])
  expect(type.colors.filter((_, index) => index !== 1)).not.toContain(type.heading)

  const [description, , caption] = type.sizes
  expect(caption, "the rail caption reads quieter than the description").toBeLessThan(description)
})

// Revenue, Nous and the closing frame carry no chapter number, so their copy has to be placed into
// the headline column explicitly — and released from it when the grid collapses to one column, or it
// would open an implicit column and push the page sideways.
test("[U1][U3] numberless sections share the chapter headline column", async ({page}) => {
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
        .locator("#techtree h2, #revenue h2, #nous h2, #home-closing h2")
        .evaluateAll(elements =>
          elements.map(element => Math.round(element.getBoundingClientRect().left)),
        )
      expect(edges).toHaveLength(4)
      expect(new Set(edges).size, "every section starts on one left edge").toBe(1)

      const copy = await page
        .locator("#revenue .rl-chapter-intro > div")
        .evaluate(element => ({
          column: getComputedStyle(element).gridColumnStart,
          parentRight: element.parentElement!.getBoundingClientRect().right,
          right: element.getBoundingClientRect().right,
        }))

      expect(copy.column).toBe(viewport.width > 704 ? "2" : "1")
      expect(copy.right).toBeLessThanOrEqual(copy.parentRight + 0.5)
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
            return {id: element.id, height: box.height, left: box.left, right: box.right}
          }),
        )

      expect(boxes.map(box => box.id)).toEqual(["patchbay-source"])
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

test("[U2][U3] pinned-dark homepage is identical in light and dark preferences", async ({browser}, testInfo) => {
  const capture = async (colorScheme: "dark" | "light", filename: string) => {
    const context = await browser.newContext({colorScheme, viewport: {width: 1440, height: 1000}})
    const page = await context.newPage()
    await page.goto("/")
    await waitForHomepage(page)
    const screenshot = await page.screenshot({path: testInfo.outputPath(filename), fullPage: true})
    const colors = await page.locator("#public-home").evaluate(element => {
      const style = getComputedStyle(element)
      return {background: style.backgroundColor, color: style.color}
    })
    await context.close()
    return {colors, screenshot}
  }

  const dark = await capture("dark", "final-desktop-dark.png")
  const light = await capture("light", "final-desktop-light.png")
  expect(light.colors).toEqual(dark.colors)
  expect(Buffer.compare(light.screenshot, dark.screenshot)).toBe(0)
})

test("[U2][U3] homepage captures the accepted mobile and tablet states", async ({browser}, testInfo) => {
  for (const capture of [
    {colorScheme: "dark" as const, height: 844, name: "final-mobile-390-dark.png", width: 390},
    {colorScheme: "light" as const, height: 1024, name: "final-tablet-768-light.png", width: 768},
  ]) {
    const context = await browser.newContext({
      colorScheme: capture.colorScheme,
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
  const action = page.getByRole("link", {name: "Explore the system"})
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
test("[U1] every hero control keeps the page's own focus ring, whatever colour the hero is wearing", async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900})
  await page.goto("/")
  await waitForHomepage(page)

  const asRgb = (color: string) =>
    page.evaluate(value => {
      const canvas = document.createElement("canvas")
      canvas.width = 1
      canvas.height = 1
      const context = canvas.getContext("2d", {willReadFrequently: true})
      if (!context) return "unreadable"
      context.fillStyle = value
      context.fillRect(0, 0, 1, 1)
      return [...context.getImageData(0, 0, 1, 1).data].slice(0, 3).join(",")
    }, color)

  const pageMark = await asRgb("#e5e3d2")
  const productColors = {
    techtree: await asRgb("#aecacd"),
    autolaunch: await asRgb("#ff5b19"),
    patchbay: await asRgb("#b9b7a6"),
  }
  expect(Object.values(productColors)).not.toContain(pageMark)
  await expect(page.locator(".rl-root")).toHaveCSS("--rl-ink", "#e5e3d2")

  const rings = new Map<
    string,
    {heroProduct: string | undefined; outlineColor: string; color: string}
  >()
  const focusableCount = await page
    .locator("a, button, input, select, textarea, [tabindex]:not([tabindex='-1'])")
    .count()

  for (let tab = 0; tab <= focusableCount; tab += 1) {
    await page.keyboard.press("Tab")
    const seen = await page.evaluate(() => {
      const element = document.activeElement
      const hero = element instanceof HTMLElement ? element.closest<HTMLElement>(".rl-hero") : null
      if (!hero || !element || !(element as HTMLElement).matches(":focus-visible")) return null
      const control = element as HTMLElement
      const style = getComputedStyle(control)
      return {
        heroProduct: hero.dataset.heroProduct,
        name: control.getAttribute("aria-label") ?? control.textContent?.replace(/\s+/g, " ").trim() ?? "",
        outlineColor: style.outlineColor,
        color: style.color,
      }
    })
    if (!seen) continue
    rings.set(seen.name, {
      heroProduct: seen.heroProduct,
      outlineColor: seen.outlineColor,
      color: seen.color,
    })
  }

  expect([...rings.keys()]).toEqual([
    "autolaunch on GitHub",
    "Open techtree ↗",
    "techtree on GitHub",
    "patchbay on GitHub",
    "Buy REGENT ↗",
    "View Chart ↗",
    "Stake REGENT",
  ])

  for (const [name, ring] of rings) {
    expect(`${name}: ${await asRgb(ring.outlineColor)}`).toBe(`${name}: ${pageMark}`)
  }

  // The techtree card really is wearing its blue while its own button is focused, and the
  // ring is still the page's own mark against it — the exact case the review caught.
  const techtree = rings.get("Open techtree ↗")!
  expect(techtree.heroProduct).toBe("techtree")
  expect(await asRgb(techtree.color)).toBe(productColors.techtree)
  expect(await asRgb(techtree.outlineColor)).not.toBe(productColors.techtree)
})
