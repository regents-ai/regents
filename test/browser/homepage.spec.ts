import {expect, test} from "@playwright/test"

const screenshotDirectory = "docs/design/founder-shell/homepage-prime-reference"

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

test("homepage is server-readable and keeps the four product gateways", async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false})
  const page = await context.newPage()
  await page.goto("/")

  await expect(page.getByRole("heading", {name: "Build agents that can own their work."})).toBeVisible()
  await expect(page.locator("[data-home-hero-card]")).toHaveCount(4)
  await expect(page.locator("#home-card-formation")).toHaveAttribute("href", "/formation")
  await expect(page.locator("#home-card-autolaunch")).toHaveAttribute("href", "/autolaunch")
  await expect(page.locator("#home-card-techtree")).toHaveAttribute("href", "/techtree")
  await expect(page.locator("#home-card-regent")).toHaveAttribute("href", "/app")
  await expect(page.locator("#formation, #autolaunch, #techtree, #regents-labs")).toHaveCount(4)
  await context.close()
})

test("homepage settles immediately for reduced motion", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/")
  await waitForHomepage(page)
  await expect(page.locator("[data-home-hero-copy]")).toBeVisible()
  await expect(page.locator("[data-home-hero-card]")).toHaveCount(4)
  await context.close()
})

for (const viewport of [
  {name: "mobile-320", width: 320, height: 720},
  {name: "mobile-390", width: 390, height: 844},
  {name: "tablet-768", width: 768, height: 1024},
  {name: "desktop", width: 1440, height: 1000},
]) {
  test(`homepage fits ${viewport.name} with usable focus targets`, async ({page}) => {
    await page.setViewportSize({width: viewport.width, height: viewport.height})
    await page.goto("/")
    await waitForHomepage(page)
    await assertNoOverflow(page)

    const cards = page.locator("[data-home-hero-card]")
    await expect(cards).toHaveCount(4)
    const boxes = await cards.evaluateAll(elements =>
      elements.map(element => {
        const box = element.getBoundingClientRect()
        return {height: box.height, left: box.left, right: box.right, top: box.top}
      }),
    )
    expect(boxes.every(box => box.height >= 44 && box.left >= 0 && box.right <= viewport.width)).toBe(true)

    if (viewport.width <= 390) {
      expect(new Set(boxes.map(box => Math.round(box.top))).size).toBe(2)
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
        path: `${screenshotDirectory}/final-mobile-320-dark.png`,
        fullPage: true,
      })
    }
  })
}

test("homepage remains usable at effective 200 percent zoom", async ({page}) => {
  await page.setViewportSize({width: 640, height: 900})
  await page.goto("/")
  await waitForHomepage(page)
  await assertNoOverflow(page)
  await page.screenshot({
    path: `${screenshotDirectory}/final-zoom-200-dark.png`,
    fullPage: true,
  })
})

test("pinned-dark homepage is identical in light and dark preferences", async ({browser}) => {
  const capture = async (colorScheme: "dark" | "light", path: string) => {
    const context = await browser.newContext({colorScheme, viewport: {width: 1440, height: 1000}})
    const page = await context.newPage()
    await page.goto("/")
    await waitForHomepage(page)
    const screenshot = await page.screenshot({path, fullPage: true})
    const colors = await page.locator("#public-home").evaluate(element => {
      const style = getComputedStyle(element)
      return {background: style.backgroundColor, color: style.color}
    })
    await context.close()
    return {colors, screenshot}
  }

  const dark = await capture("dark", `${screenshotDirectory}/final-desktop-dark.png`)
  const light = await capture("light", `${screenshotDirectory}/final-desktop-light.png`)
  expect(light.colors).toEqual(dark.colors)
  expect(Buffer.compare(light.screenshot, dark.screenshot)).toBe(0)
})

test("homepage captures the accepted mobile and tablet states", async ({browser}) => {
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
    await page.screenshot({path: `${screenshotDirectory}/${capture.name}`, fullPage: true})
    await context.close()
  }
})

test("the primary homepage action keeps its contrast on hover", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)
  const action = page.getByRole("link", {name: "Form a Regent"}).first()
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

test("white primary actions have a square high-contrast keyboard focus ring", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)

  const primaryActions = page.locator(".rl-header-entry--strong, .rl-action--strong")
  await expect(primaryActions).toHaveCount(2)

  for (const action of await primaryActions.all()) {
    await action.focus()
    const geometry = await action.evaluate(element => {
      const style = getComputedStyle(element)
      const rgb = (value: string) => {
        const canvas = document.createElement("canvas")
        canvas.width = 1
        canvas.height = 1
        const context = canvas.getContext("2d", {willReadFrequently: true})
        if (!context) return [0, 0, 0]
        context.fillStyle = value
        context.fillRect(0, 0, 1, 1)
        return [...context.getImageData(0, 0, 1, 1).data].slice(0, 3)
      }
      const luminance = (channels: number[]) => {
        const linear = channels.map(channel => {
          const value = channel / 255
          return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
        })
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
      }
      const foreground = luminance(rgb(style.outlineColor))
      const background = luminance(rgb(style.backgroundColor))
      const contrast = (Math.max(foreground, background) + 0.05) /
        (Math.min(foreground, background) + 0.05)

      return {
        borderRadius: Number.parseFloat(style.borderRadius || "0"),
        contrast,
        outlineStyle: style.outlineStyle,
        outlineWidth: Number.parseFloat(style.outlineWidth),
      }
    })

    expect(geometry.outlineStyle).toBe("solid")
    expect(geometry.outlineWidth).toBeGreaterThanOrEqual(2)
    expect(geometry.contrast).toBeGreaterThanOrEqual(3)
    expect(geometry.borderRadius).toBeLessThanOrEqual(4)
  }
})
