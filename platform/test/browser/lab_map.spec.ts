import {expect, test, type Page} from "./support/offline"

// The map in the Overview hero. The suite's browser draws no GPU picture, so these
// run on the map the server draws, which is the whole of it: the glow behind it
// only ever adds to what is already there.

async function openMap(page: Page) {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const map = page.getByRole("group", {name: "Product map"})
  await expect(map).toHaveAttribute("data-lab-map-motion", "rest")
  return map
}

test("a line reached from the keyboard says how its two products work together", async ({page}) => {
  const map = await openMap(page)
  const invitation = map.locator('.lab-map__say[data-say=""]')
  await expect(invitation).toHaveAttribute("data-shown", "")

  // The lines come straight after the dots.
  await map.getByRole("link", {name: /^Sign-in with Agent/}).focus()
  await page.keyboard.press("Tab")
  const line = map.locator(".lab-map__link").first()
  await expect(line).toBeFocused()

  const [from, to, index, name] = await line.evaluate(element => [
    element.getAttribute("data-from")!,
    element.getAttribute("data-to")!,
    element.getAttribute("data-link")!,
    element.getAttribute("aria-label")!,
  ])
  expect(name.startsWith(`${from} and ${to}: `)).toBe(true)

  // Its sentence takes the caption's place, and its two ends stay lifted.
  const said = map.locator(".lab-map__say[data-shown]")
  await expect(said).toHaveCount(1)
  await expect(said).toHaveAttribute("data-say", index)
  await expect(said).toContainText(name.slice(`${from} and ${to}: `.length))
  await expect(invitation).not.toHaveAttribute("data-shown", "")
  await expect(map).toHaveAttribute("data-lab-map-pick", "line")
  await expect(line).toHaveAttribute("data-picked", "")
  const lifted = map.locator(".lab-map__node[data-picked]")
  await expect(lifted).toHaveCount(2)
  expect((await lifted.evaluateAll(nodes => nodes.map(node => (node as HTMLElement).dataset.node))).sort()).toEqual(
    [from, to].sort(),
  )

  // Leaving the map puts the invitation back.
  await page.getByRole("heading", {level: 1}).focus()
  await expect(invitation).toHaveAttribute("data-shown", "")
  await expect(map).not.toHaveAttribute("data-lab-map-pick")
  await expect(map.locator("[data-picked]")).toHaveCount(0)
})

test("each product's dot opens what its card opens", async ({page}) => {
  const map = await openMap(page)
  const cards = page.locator('ul[aria-label="Products"]')

  for (const name of ["Patchbay", "Autolaunch", "Techtree", "Keyfleet", "Protocol", "Cloak"]) {
    const dot = map.locator(`.lab-map__node[data-node="${name}"]`)
    const href = await dot.getAttribute("href")
    const target = await dot.getAttribute("target")
    const card = cards.locator(`a[href="${href}"]`)
    await expect(card).toHaveCount(1)
    expect(await card.getAttribute("target")).toBe(target)
  }
  await expect(map.locator('.lab-map__node[data-node="Patchbay"]')).toHaveAttribute("href", "https://patchbay.help")
  await expect(map.locator('.lab-map__node[data-node="Patchbay"]')).toHaveAttribute("target", "_blank")

  // A dot is pressed by its name or its dot; staking opens on this site.
  await map.locator('.lab-map__node[data-node="Protocol"] .lab-map__name').click()
  await expect(page).toHaveURL(/\/stake$/)
})

test("the map answers the same for a visitor who asked for less motion", async ({page}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  const map = await openMap(page)

  // Nothing waits to be drawn in.
  expect(await map.locator(".lab-map__line").first().evaluate(line => getComputedStyle(line).strokeDashoffset)).toBe(
    "0px",
  )

  const line = map.getByRole("img", {name: /^Keyfleet and Autolaunch: /})
  await line.hover()
  await expect(line).toHaveAttribute("data-picked", "")
  await expect(map.locator(".lab-map__say[data-shown]")).toHaveAttribute(
    "data-say",
    (await line.getAttribute("data-link"))!,
  )

  // A dot under the mouse lifts every line it has.
  await map.locator('.lab-map__node[data-node="Keyfleet"] .lab-map__dot').hover()
  await expect(map).toHaveAttribute("data-lab-map-pick", "dot")
  const keyfleetLines = map.locator('.lab-map__link:is([data-from="Keyfleet"], [data-to="Keyfleet"])')
  await expect(map.locator(".lab-map__link[data-picked]")).toHaveCount(await keyfleetLines.count())

  // A pressed line keeps its sentence once the mouse has gone.
  await line.click()
  await page.mouse.move(1, 1)
  await expect(line).toBeFocused()
  await expect(line).toHaveAttribute("data-picked", "")
})

for (const width of [320, 390, 1280]) {
  test(`the map fits a ${width}px screen with every name whole and every line easy to tap`, async ({page}) => {
    await page.setViewportSize({width, height: 900})
    const map = await openMap(page)
    await map.locator(".lab-map__stage").scrollIntoViewIfNeeded()

    const fit = await map.evaluate(root => {
      const stage = root.querySelector(".lab-map__stage")!.getBoundingClientRect()
      const outside = [...root.querySelectorAll<HTMLElement>(".lab-map__node")]
        .filter(node => {
          const box = node.getBoundingClientRect()
          return box.left < stage.left || box.right > stage.right || box.top < stage.top || box.bottom > stage.bottom
        })
        .map(node => node.dataset.node)

      // How much of each line, along its middle, a finger lands on that line and nothing
      // else, and the middle of its longest such stretch.
      const lines = [...root.querySelectorAll<SVGGElement>(".lab-map__link")].map(line => {
        const hit = line.querySelector<SVGLineElement>(".lab-map__hit")!
        const [x1, y1, x2, y2] = [hit.x1, hit.y1, hit.x2, hit.y2].map(end => end.baseVal.value)
        const length = Math.hypot(x2 - x1, y2 - y1)
        const at = (step: number) => ({x: stage.left + x1 + ((x2 - x1) * step) / 200, y: stage.top + y1 + ((y2 - y1) * step) / 200})
        let mine = 0
        let run = {from: 0, steps: 0}
        let best = run
        for (let step = 0; step <= 200; step++) {
          const {x, y} = at(step)
          if (document.elementFromPoint(x, y)?.closest(".lab-map__link") === line) {
            mine += length / 200
            run = run.steps && run.from + run.steps === step ? {...run, steps: run.steps + 1} : {from: step, steps: 1}
            if (run.steps > best.steps) best = run
          }
        }
        return {
          line: line.getAttribute("aria-label")!.split(":")[0],
          index: line.dataset.link!,
          free: Math.round(mine),
          press: at(best.from + (best.steps - 1) / 2),
        }
      })
      return {outside, short: lines.filter(line => line.free < 44).map(line => line.line), lines}
    })
    expect({outside: fit.outside, short: fit.short}).toEqual({outside: [], short: []})

    // A press in the middle of each line's free stretch picks that line and no other.
    const said = map.locator(".lab-map__say[data-shown]")
    for (const line of fit.lines) {
      await page.mouse.click(line.press.x, line.press.y)
      await expect(said, line.line).toHaveAttribute("data-say", line.index)
    }

    // The sign-in dot keeps the bottom right corner.
    const corner = await map.evaluate(root => {
      const stage = root.querySelector(".lab-map__stage")!.getBoundingClientRect()
      const dot = root.querySelector('.lab-map__node--quiet .lab-map__dot')!.getBoundingClientRect()
      return {right: dot.left + dot.width / 2 > stage.left + stage.width / 2, bottom: dot.top + dot.height / 2 > stage.top + stage.height / 2}
    })
    expect(corner).toEqual({right: true, bottom: true})

    expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0)
    const scroller = page.locator("#app-shell-scroller")
    expect(await scroller.evaluate(element => element.scrollWidth - element.clientWidth)).toBe(0)
  })
}
