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

const assertNoOverflow = async (page: import("@playwright/test").Page) => {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
  ).toBe(true)
}

test("[U2] homepage is server-readable and keeps the three product gateways", async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false})
  const page = await context.newPage()
  await page.goto("/")

  await expect(page.getByRole("heading", {name: "Prove the edge. Fund the agent. Keep it running."})).toBeVisible()
  await expect(page.getByRole("heading", {name: "Turn agent evaluations into public, checkable proof."})).toBeVisible()
  await expect(page.locator("[data-home-hero-card]")).toHaveCount(3)
  await expect(page.locator("#home-card-techtree")).toHaveAttribute("href", "#techtree")
  await expect(page.locator("#home-card-autolaunch")).toHaveAttribute("href", "#autolaunch")
  await expect(page.locator("#home-card-regent")).toHaveAttribute("href", "#regent")
  await expect(page.locator("#techtree, #autolaunch, #regent")).toHaveCount(3)
  await expect(page.locator(".rl-hero-actions a")).toHaveAttribute("href", "#home-products")
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

test("[U2] homepage settles immediately for reduced motion", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/")
  await waitForHomepage(page)
  await expect(page.locator("[data-home-hero-copy]")).toBeVisible()
  await expect(page.locator("[data-home-hero-card]")).toHaveCount(3)
  await context.close()
})

test("[U3] public landing stays light and unbranded without changing saved appearance", async ({browser}) => {
  const context = await browser.newContext()
  await context.addInitScript(() => localStorage.setItem("regent:theme", "dark"))
  const page = await context.newPage()

  const served = await (await context.request.get("/")).text()
  expect(served).toContain('data-theme="light"')
  expect(served).not.toContain("data-brand")

  await page.goto("/")
  await waitForHomepage(page)

  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await expect(page.locator("html")).not.toHaveAttribute("data-brand", /.+/)
  expect(await page.evaluate(() => localStorage.getItem("regent:theme"))).toBe("dark")
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

    if (viewport.width <= 390) {
      expect(new Set(boxes.map(box => Math.round(box.top))).size).toBe(3)
      const collisionCount = await cards.evaluateAll(elements =>
        elements.reduce((count, card) => {
          const voxels = card.querySelector(".rl-card-voxels")?.getBoundingClientRect()
          const tagline = card.querySelector(":scope > span:not(.rl-card-head, .rl-card-arrow, .rl-card-voxels)")?.getBoundingClientRect()
          if (!voxels || !tagline) return count
          const overlaps = !(voxels.right <= tagline.left || voxels.left >= tagline.right || voxels.bottom <= tagline.top || voxels.top >= tagline.bottom)
          return count + Number(overlaps)
        }, 0),
      )
      expect(collisionCount).toBe(0)
    }

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

test("[U1][U2] the hero bento ranks Techtree, then Autolaunch, then Regent at every viewport", async ({page}) => {
  const area = (card: {height: number; width: number}) => card.width * card.height
  const declaredArea = (card: {declaredHeight: number; width: number}) =>
    card.width * card.declaredHeight

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
            declaredHeight: Number.parseFloat(getComputedStyle(element).minHeight),
            height: box.height,
            id: element.id,
            left: box.left,
            top: box.top,
            width: box.width,
          }
        }),
      )

      expect(cards.map(card => card.id)).toEqual([
        "home-card-techtree",
        "home-card-autolaunch",
        "home-card-regent",
      ])

      const [lead, second, ...secondary] = cards
      expect(lead.top).toBeLessThanOrEqual(Math.min(...cards.map(card => card.top)))
      expect(lead.left).toBeLessThanOrEqual(Math.min(...cards.map(card => card.left)))

      for (const card of cards) {
        expect(card.height, `${card.id} renders at least its stylesheet height`)
          .toBeGreaterThanOrEqual(card.declaredHeight)
      }

      expect(area(lead)).toBeGreaterThan(area(second))
      expect(declaredArea(lead)).toBeGreaterThan(declaredArea(second))

      for (const card of secondary) {
        expect(area(second), `Autolaunch outranks ${card.id}`).toBeGreaterThan(area(card))
        expect(declaredArea(second)).toBeGreaterThan(declaredArea(card))
      }

      // Where the lead shares its row band, it spans the whole band: both stacked ranks fit beside it.
      if (Math.round(lead.top) === Math.round(second.top)) {
        expect(lead.height).toBeGreaterThanOrEqual(
          second.height + Math.max(...secondary.map(card => card.height)),
        )
      }
    })
  }
})

// The Techtree chapter reads as description then supporting line: both muted, both distinct from
// the heading, with the proof story standing between the two card grids.
test("[U1] the Techtree chapter keeps its proofs under muted body copy", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  await expect(page.locator("#techtree .rl-proof-grid")).toHaveCount(2)
  await expect(page.locator("#techtree .rl-proof-grid article")).toHaveCount(15)
  await expect(page.locator("#techtree .rl-story h3")).toHaveText("A controlled comparison people can inspect.")

  for (const state of ["Live web", "Working prototype", "In build", "Planned"]) {
    await expect(page.locator("#techtree .rl-proof-state", {hasText: state}).first()).toBeVisible()
  }

  const body = page.locator("#techtree .rl-chapter-intro div > p:not(.rl-overline)")
  await expect(body).toHaveCount(2)

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
      muted,
      sizes: elements.map(element => Number.parseFloat(getComputedStyle(element).fontSize)),
    }
  })

  expect(type.colors).toEqual([type.muted, type.muted])
  expect(type.colors).not.toContain(type.heading)

  const [description, supporting] = type.sizes
  expect(supporting, "the supporting line reads quieter than the description").toBeLessThan(description)
})

// Revenue, Nous, the product summary, the evidence section and the closing frame carry no chapter
// number, so their copy has to be placed into the headline column explicitly — and released from it
// when the grid collapses to one column, or it would open an implicit column and push the page
// sideways.
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
        .locator("#techtree h2, #evidence h2, #revenue h2, #nous h2, #product-summary h2, #home-closing h2")
        .evaluateAll(elements =>
          elements.map(element => Math.round(element.getBoundingClientRect().left)),
        )
      expect(edges).toHaveLength(6)
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

test("[U2] the evidence section reads with scripts disabled", async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false})
  const page = await context.newPage()
  await page.goto("/")

  await expect(page.getByRole("heading", {name: "Built on open systems with distinct jobs."})).toBeVisible()
  await expect(page.locator("#evidence .rl-evidence-rail")).toHaveCount(8)
  await expect(page.locator("#evidence .rl-evidence-rail h3").first()).toHaveText("Evaluation truth")
  await expect(page.getByRole("heading", {name: "Research context, verified by primary sources."})).toBeVisible()
  await expect(page.locator("#evidence .rl-evidence-entry")).toHaveCount(7)
  await context.close()
})

// The page reset strips colour and underline from every link, so a source link only reads as a
// link if its own rules outrank that reset.
test("[U1][U2] evidence source links survive the page link reset", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  const links = await page.locator("#evidence .rl-evidence-source").evaluateAll(elements => {
    const ink = getComputedStyle(document.querySelector("#public-home")!).color
    return elements.map(element => {
      const style = getComputedStyle(element)
      return {color: style.color, decoration: style.textDecorationLine, ink}
    })
  })

  expect(links).toHaveLength(7)
  expect(links.every(link => link.decoration === "underline")).toBe(true)
  expect(links.every(link => link.color !== link.ink)).toBe(true)
})

test("[U1][U3] evidence rails and entries stay inside every tested viewport", async ({page}) => {
  for (const viewport of focusViewports) {
    await test.step(viewport.name, async () => {
      await page.setViewportSize({width: viewport.width, height: viewport.height})
      await page.goto("/")
      await waitForHomepage(page)
      await assertNoOverflow(page)

      const boxes = await page
        .locator("#evidence .rl-evidence-rail, #evidence .rl-evidence-entry")
        .evaluateAll(elements =>
          elements.map(element => {
            const box = element.getBoundingClientRect()
            return {left: box.left, right: box.right, width: box.width}
          }),
        )

      expect(boxes).toHaveLength(15)
      expect(
        boxes.every(box => box.left >= 0 && box.right <= viewport.width && box.width > 0),
      ).toBe(true)
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
  const action = page.getByRole("link", {name: "See how it works"})
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

test("[U1] white primary actions have a square high-contrast keyboard focus ring", async ({page}, testInfo) => {
  for (const viewport of focusViewports) {
    await page.setViewportSize({width: viewport.width, height: viewport.height})
    await page.goto("/")
    await waitForHomepage(page)

    const primaryActions = page.locator(".rl-action--strong")
    await expect(primaryActions).toHaveCount(2)

    const reached = new Set<string>()
    const focusableCount = await page.locator("a, button, input, select, textarea, [tabindex]:not([tabindex='-1'])").count()

    for (let tab = 0; tab <= focusableCount && reached.size < 2; tab += 1) {
      await page.keyboard.press("Tab")
      const focused = page.locator(".rl-action--strong:focus-visible")
      if (await focused.count() === 0) continue

      const identity = await focused.evaluate(element =>
        element.closest(".rl-closing") ? "closing" : "hero",
      )
      if (reached.has(identity)) continue
      reached.add(identity)
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

    expect([...reached].sort()).toEqual(["closing", "hero"])

    if (["desktop", "review-1024x768", "mobile-390", "zoom-200"].includes(viewport.name)) {
      await page.screenshot({
        path: testInfo.outputPath(`focus-${viewport.name}.png`),
        fullPage: true,
      })
    }
  }
})
