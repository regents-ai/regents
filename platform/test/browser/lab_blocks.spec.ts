import {expect, test, type Locator, type Page} from "./support/offline"

// The product map in the Overview hero. The suite's browser draws no GPU picture,
// so these run on the still picture the server draws; the names and lines are
// page elements above whichever picture shows, so they answer the same over either.

async function openMap(page: Page) {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const map = page.getByRole("group", {name: "Product map"})
  await expect(map).toHaveAttribute("data-lab-blocks-motion", "rest")
  await map.locator(".lab-blocks__stage").scrollIntoViewIfNeeded()
  return map
}

type Line = {line: string; sentence: string; index: string; free: number; press: {x: number; y: number}}

// How much of each line, along the band that takes its press (its first line), a finger lands on that line and
// nothing else, and the middle of its longest such stretch.
function measureLines(map: Locator): Promise<Line[]> {
  return map.evaluate(root => {
    return [...root.querySelectorAll<SVGGElement>("[data-link]")].map(line => {
      const hit = line.querySelector<SVGLineElement>("line")!
      const total = hit.getTotalLength()
      const screen = hit.getScreenCTM()!
      const at = (step: number) => {
        const {x, y} = hit.getPointAtLength((total * step) / 300).matrixTransform(screen)
        return {x, y}
      }
      let mine = 0
      let run = {from: 0, steps: 0}
      let best = run
      let previous = at(0)
      for (let step = 1; step <= 300; step++) {
        const point = at(step)
        const middle = {x: (point.x + previous.x) / 2, y: (point.y + previous.y) / 2}
        if (document.elementFromPoint(middle.x, middle.y)?.closest("[data-link]") === line) {
          mine += Math.hypot(point.x - previous.x, point.y - previous.y)
          run = run.steps && run.from + run.steps === step ? {...run, steps: run.steps + 1} : {from: step, steps: 1}
          if (run.steps > best.steps) best = run
        }
        previous = point
      }
      const [pair, sentence] = line.getAttribute("aria-label")!.split(": ")
      return {line: pair!, sentence: sentence!, index: line.dataset.link!, free: Math.round(mine), press: at(best.from - 1 + best.steps / 2)}
    })
  })
}

test("a line reached from the keyboard says how its two products work together", async ({page}) => {
  const map = await openMap(page)
  const invitation = map.locator('[data-say=""]')
  await expect(invitation).toHaveAttribute("data-shown", "")

  // The lines come straight after the places.
  await map.getByRole("link", {name: /^Sign-in with Agent/}).focus()
  await page.keyboard.press("Tab")
  const line = map.locator("[data-link]").first()
  await expect(line).toBeFocused()

  const [from, to, index, name] = await line.evaluate(element => [
    element.getAttribute("data-from")!,
    element.getAttribute("data-to")!,
    element.getAttribute("data-link")!,
    element.getAttribute("aria-label")!,
  ])
  expect(name.startsWith(`${from} and ${to}: `)).toBe(true)

  // Its sentence takes the caption's place, and its two ends stay lifted.
  const said = map.locator("[data-say][data-shown]")
  await expect(said).toHaveCount(1)
  await expect(said).toHaveAttribute("data-say", index)
  await expect(said).toContainText(name.slice(`${from} and ${to}: `.length))
  await expect(map).toHaveAttribute("data-lab-blocks-pick", "line")
  await expect(line).toHaveAttribute("data-picked", "")
  const lifted = map.locator(".lab-blocks__place[data-picked]")
  await expect(lifted).toHaveCount(2)
  expect((await lifted.evaluateAll(places => places.map(place => (place as HTMLElement).dataset.node))).sort()).toEqual(
    [from, to].sort(),
  )

  // The next line follows.
  await page.keyboard.press("Tab")
  await expect(map.locator("[data-link]").nth(1)).toBeFocused()

  // Leaving the map puts the invitation back.
  await page.getByRole("heading", {level: 1}).focus()
  await expect(invitation).toHaveAttribute("data-shown", "")
  await expect(map).not.toHaveAttribute("data-lab-blocks-pick")
  await expect(map.locator("[data-link][data-picked], .lab-blocks__place[data-picked]")).toHaveCount(0)
})

test("each product's block opens what its card opens", async ({page}) => {
  const map = await openMap(page)
  const cards = page.locator('ul[aria-label="Products"]')

  for (const name of ["Patchbay", "Autolaunch", "Techtree", "Keyfleet", "Protocol", "Cloak"]) {
    const place = map.locator(`.lab-blocks__place[data-node="${name}"]`)
    const href = await place.getAttribute("href")
    const card = cards.locator(`a[href="${href}"]`)
    await expect(card).toHaveCount(1)
    expect(await card.getAttribute("target")).toBe(await place.getAttribute("target"))
  }
  const patchbay = map.locator('.lab-blocks__place[data-node="Patchbay"]')
  await expect(patchbay).toHaveAttribute("href", "https://patchbay.help")
  await expect(patchbay).toHaveAttribute("target", "_blank")

  // A place is pressed by its name or its block; staking opens on this site.
  await map.locator('.lab-blocks__place[data-node="Protocol"] .lab-blocks__name').click()
  await expect(page).toHaveURL(/\/stake$/)
})

test("the map answers the same for a visitor who asked for less motion", async ({page}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  const map = await openMap(page)

  // Nothing waits to be drawn in.
  const waiting = await map.evaluate(root => ({
    unseen: [...root.querySelectorAll("[data-art-node], .lab-blocks__crown use, [data-art-link], .lab-blocks__name")].filter(
      el => getComputedStyle(el).opacity !== "1",
    ).length,
    moving: root.getAnimations({subtree: true}).length,
  }))
  expect(waiting).toEqual({unseen: 0, moving: 0})

  // A line under the mouse is picked.
  const lines = await measureLines(map)
  const pair = lines.find(line => line.line === "Keyfleet and Autolaunch")!
  const line = map.locator(`[data-link="${pair.index}"]`)
  await page.mouse.move(pair.press.x, pair.press.y)
  await expect(line).toHaveAttribute("data-picked", "")
  await expect(map.locator("[data-say][data-shown]")).toHaveAttribute("data-say", pair.index)

  // A block under the mouse lifts every line it has.
  await map.locator('.lab-blocks__place[data-node="Keyfleet"] .lab-blocks__block').hover()
  await expect(map).toHaveAttribute("data-lab-blocks-pick", "place")
  const keyfleetLines = map.locator('[data-link]:is([data-from="Keyfleet"], [data-to="Keyfleet"])')
  await expect(map.locator("[data-link][data-picked]")).toHaveCount(await keyfleetLines.count())

  // A pressed line keeps its sentence once the mouse has gone.
  await page.mouse.click(pair.press.x, pair.press.y)
  await page.mouse.move(1, 1)
  await expect(line).toBeFocused()
  await expect(line).toHaveAttribute("data-picked", "")
  await expect(map.locator("[data-say][data-shown]")).toHaveAttribute("data-say", pair.index)
})

for (const width of [320, 390, 1280]) {
  test(`the map fits a ${width}px screen with every name whole and every line easy to tap`, async ({page}) => {
    await page.setViewportSize({width, height: 900})
    const map = await openMap(page)

    // Every name on the stage, inside the hero, and clear of every other name.
    const names = await map.evaluate(root => {
      const stage = root.querySelector(".lab-blocks__stage")!.getBoundingClientRect()
      const hero = root.closest("header.regent-ops-heading")!.getBoundingClientRect()
      const boxes = [...root.querySelectorAll<HTMLElement>(".lab-blocks__name")].map(name => ({
        node: name.closest<HTMLElement>(".lab-blocks__place")!.dataset.node!,
        box: name.getBoundingClientRect(),
      }))
      const within = (box: DOMRect, frame: DOMRect) =>
        box.left >= frame.left - 0.5 && box.right <= frame.right + 0.5 && box.top >= frame.top - 0.5 && box.bottom <= frame.bottom + 0.5
      return {
        outside: boxes.filter(({box}) => !within(box, stage) || !within(box, hero)).map(name => name.node),
        overlaps: boxes.flatMap((a, i) =>
          boxes
            .slice(i + 1)
            .filter(
              b =>
                Math.min(a.box.right, b.box.right) > Math.max(a.box.left, b.box.left) &&
                Math.min(a.box.bottom, b.box.bottom) > Math.max(a.box.top, b.box.top),
            )
            .map(b => `${a.node} / ${b.node}`),
        ),
      }
    })
    expect(names).toEqual({outside: [], overlaps: []})

    const lines = await measureLines(map)
    expect(lines).toHaveLength(13)
    expect(lines.filter(line => line.free < 44).map(line => line.line)).toEqual([])

    // A press in the middle of each line's free stretch picks that line and says its own sentence.
    const said = map.locator("[data-say][data-shown]")
    for (const line of lines) {
      await page.mouse.click(line.press.x, line.press.y)
      await expect(said, line.line).toHaveAttribute("data-say", line.index)
      await expect(said, line.line).toContainText(line.sentence)
    }
    expect(lines.map(line => line.sentence)).toContain("Techtree sends all the USDC it earns to $REGENT stakers.")

    // Sign-in with Agent keeps the bottom right corner.
    const corner = await map.evaluate(root => {
      const stage = root.querySelector(".lab-blocks__stage")!.getBoundingClientRect()
      const block = root.querySelector('.lab-blocks__place[data-node="Sign-in with Agent"] .lab-blocks__block')!.getBoundingClientRect()
      return {
        right: block.left + block.width / 2 > stage.left + stage.width / 2,
        bottom: block.top + block.height / 2 > stage.top + stage.height / 2,
      }
    })
    expect(corner).toEqual({right: true, bottom: true})

    expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
    const scroller = page.locator("#app-shell-scroller")
    expect(await scroller.evaluate(element => element.scrollWidth - element.clientWidth)).toBe(0)
  })
}
