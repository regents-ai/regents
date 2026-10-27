import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The page's Pair New Agent button points to the agents to choose from in the
// side panel: focus lands on the first of them (or the one already chosen),
// their box glides into view and is marked for a moment while the agents
// settle in turn, on every press.
const choices = "#shell-pairing .rg-account__choices"

async function signIn(page: Page, path: string) {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()
  await page.goto(path)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
}

async function openAccount(page: Page) {
  await signIn(page, "/account")
  await expect(page.locator("#account-agents")).toBeVisible()
}

const pairNewAgent = (page: Page) =>
  page.locator("#account-agents").getByRole("button", {name: "Pair New Agent"})

// The first agent to choose, which a screen reader hears inside the box's question.
const firstChoice = (page: Page) =>
  page.getByRole("group", {name: "Choose the agent to pair"}).getByRole("radio").first()

// The box is inside the panel's visible part and inside the window.
const inView = (page: Page) =>
  page.evaluate(selector => {
    const box = document.querySelector(selector)!.getBoundingClientRect()
    const panel = document.querySelector("#shell-aside")!.getBoundingClientRect()
    return box.top >= panel.top && box.bottom <= panel.bottom && box.bottom <= window.innerHeight
  }, choices)

// Once a glide has ended, the box is in view.
async function expectInView(page: Page) {
  await expect.poll(() => inView(page)).toBe(true)
}

// How strongly the box is marked: its mark's opacity, 0 when unmarked.
const mark = (page: Page) => page.locator(choices).evaluate(box => Number(getComputedStyle(box, "::after").opacity))

// What every frame drawn shows, from just before a press: the panel's scroll,
// the mark, and how far the first and last agents are from their own size (0
// at rest).
type Frame = {scroll: number; mark: number; first: number; last: number}
type Recorder = {recording: Frame[]}
const frames = 130

async function startRecording(page: Page) {
  await page.evaluate(
    ([selector, frames]) => {
      const recorder = window as unknown as Recorder
      const settling = (label: Element | undefined) => {
        const transform = label ? getComputedStyle(label).transform : "none"
        return transform === "none" ? 0 : 1 - new DOMMatrixReadOnly(transform).a
      }
      recorder.recording = []
      const tick = () => {
        const box = document.querySelector(selector)
        const labels = [...(box?.querySelectorAll(".rg-account__choice") ?? [])]
        recorder.recording.push({
          scroll: document.querySelector("#shell-aside")?.scrollTop ?? 0,
          mark: box ? Number(getComputedStyle(box, "::after").opacity) : 0,
          first: settling(labels.at(0)),
          last: settling(labels.at(-1)),
        })
        if (recorder.recording.length < frames) requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
    },
    [choices, frames] as const,
  )
}

async function recording(page: Page) {
  await page.waitForFunction(frames => (window as unknown as Recorder).recording.length >= frames, frames)
  return page.evaluate(() => (window as unknown as Recorder).recording)
}

// A glide passes through several places on its way; a jump passes through none.
const between = (values: number[]) => {
  const [from, to] = [values[0], values.at(-1)!]
  return new Set(values.filter(value => value > Math.min(from, to) && value < Math.max(from, to))).size
}

async function scrollPanelToTop(page: Page) {
  await page.locator("#shell-aside").evaluate(panel => (panel.scrollTop = 0))
}

// A short window, so the agents' box starts below the panel's visible part.
for (const width of [1280, 390, 320]) {
  test(`Pair New Agent points to the agents to choose from at ${width}`, async ({page}) => {
    await page.setViewportSize({width, height: 360})
    await openAccount(page)

    if (width === 1280) {
      // On a computer the panel opens beside the page first.
      await page.locator("#shell-aside-button").click()
      await expect(page.locator("#shell-aside")).toBeVisible()
    } else {
      // On a phone the panel covers the page, so it is shut until the press opens it.
      await expect(page.locator("#shell-aside")).toBeHidden()
    }

    await startRecording(page)
    await pairNewAgent(page).click()
    await expect(page.locator("#shell-aside")).toBeVisible()
    await expect(firstChoice(page)).toBeFocused()
    const seen = await recording(page)
    // The box glides into view rather than jumping there.
    expect(between(seen.map(frame => frame.scroll))).toBeGreaterThanOrEqual(3)
    expect(seen.at(-1)!.scroll).toBeGreaterThan(40)
    await expectInView(page)
    // Marked at once, then the mark fades.
    expect(seen.find(frame => frame.mark > 0)?.mark).toBe(1)
    expect(seen.some(frame => frame.mark > 0.05 && frame.mark < 0.95)).toBe(true)
    // The agents settle in turn, the last after the first.
    expect(seen.some(frame => frame.last > frame.first + 0.02)).toBe(true)
    await expect.poll(() => mark(page)).toBe(0)
    // The agents end at rest, with nothing left written on them.
    await expect(page.locator(`${choices} .rg-account__choice[style]`)).toHaveCount(0)

    // A second press, after the panel was scrolled away from the agents, points
    // again. On a phone the panel is shut first, since it covers the button.
    if (width !== 1280) {
      await page.locator("#shell-aside-button").click()
      await expect(page.locator("#shell-aside")).toBeHidden()
    }
    await scrollPanelToTop(page)
    await pairNewAgent(page).click()
    expect(await mark(page)).toBe(1)
    await expect(firstChoice(page)).toBeFocused()
    await expectInView(page)
  })
}

test("a press while the last one still plays starts it over", async ({page}) => {
  await page.setViewportSize({width: 1280, height: 360})
  await openAccount(page)

  // The panel is shut, as it is by default: the press opens it beside the page.
  await startRecording(page)
  await pairNewAgent(page).click()
  await page.waitForTimeout(150)
  await pairNewAgent(page).click()
  await expect(firstChoice(page)).toBeFocused()
  const seen = await recording(page)

  // The first agent had all but settled when the second press sent it back
  // towards where it starts.
  const settled = seen.findIndex(frame => frame.mark === 1 && frame.first < 0.03)
  expect(settled).toBeGreaterThanOrEqual(0)
  expect(seen.slice(settled + 1).some((frame, i) => frame.first > seen[settled + i].first + 0.02)).toBe(true)
  await expectInView(page)
  await expect.poll(() => mark(page)).toBe(0)
  await expect(page.locator(`${choices} .rg-account__choice[style]`)).toHaveCount(0)
})

// The start page's Pair New Agent is a link to the account page, which draws
// the panel again when it arrives; the pointing happens in that new panel.
for (const width of [1280, 390]) {
  test(`Pair New Agent on the start page points to the agents after the account page arrives at ${width}`, async ({page}) => {
    await page.setViewportSize({width, height: 360})
    await signIn(page, "/start")

    await page.locator("#agent-start-page").getByRole("link", {name: "Pair New Agent"}).click()
    await page.waitForURL("**/account")
    await expect(page.locator("#shell-aside")).toBeVisible()
    await expect(firstChoice(page)).toBeFocused()
    await expect.poll(() => mark(page)).toBe(1)
    await expect.poll(() => page.locator("#shell-aside").evaluate(panel => panel.scrollTop)).toBeGreaterThan(40)
    await expectInView(page)
  })
}

// Pressed from the keyboard or with less motion asked for, nothing moves: the
// box is in view on the first frame, its mark goes without fading and the
// agents stay still.
function expectStill(seen: Frame[]) {
  expect(between(seen.map(frame => frame.scroll))).toBe(0)
  expect(seen.find(frame => frame.mark > 0)?.mark).toBe(1)
  expect(seen.every(frame => frame.mark === 0 || frame.mark === 1)).toBe(true)
  expect(seen.every(frame => frame.first === 0 && frame.last === 0)).toBe(true)
}

test("from the keyboard, focus lands on the first agent at once, and Escape goes back", async ({page}) => {
  await page.setViewportSize({width: 1280, height: 360})
  await openAccount(page)
  await page.locator("#shell-aside-button").click()

  await pairNewAgent(page).focus()
  await startRecording(page)
  await page.keyboard.press("Enter")
  await expect(firstChoice(page)).toBeFocused()
  expect(await inView(page)).toBe(true)
  const seen = await recording(page)
  expectStill(seen)
  expect(seen.at(-1)!.mark).toBe(0)

  await page.keyboard.press("Escape")
  await expect(page.locator("#shell-aside")).toBeHidden()
  await expect(page.locator("#shell-aside-button")).toBeFocused()
})

test("with less motion asked for, the agents' box is simply there and marked", async ({page}) => {
  await page.emulateMedia({reducedMotion: "reduce"})
  await page.setViewportSize({width: 390, height: 360})
  await openAccount(page)

  await startRecording(page)
  await pairNewAgent(page).click()
  await expect(firstChoice(page)).toBeFocused()
  expect(await inView(page)).toBe(true)
  const seen = await recording(page)
  expectStill(seen)
  expect(seen.at(-1)!.mark).toBe(0)

  // Escape closes the covering panel and goes back to its button.
  await page.keyboard.press("Escape")
  await expect(page.locator("#shell-aside")).toBeHidden()
  await expect(page.locator("#shell-aside-button")).toBeFocused()
})

// Pairing as a person does it: choosing their agent in the side panel's box.
const pairingBox = (page: Page) => page.locator("#shell-pairing")
const message = (page: Page) => page.locator("#shell-pairing-box pre")

// A person presses the agent's picture: the radio's label, whose name only
// screen readers hear.
async function choose(page: Page, agent: string) {
  const radio = pairingBox(page).getByRole("radio", {name: agent, exact: true})
  await radio.locator("xpath=ancestor::label").click()
  await expect(radio).toBeChecked()
}

async function openPairing(page: Page) {
  await page.setViewportSize({width: 1280, height: 900})
  await openAccount(page)
  await page.locator("#shell-aside-button").click()
  await pairNewAgent(page).click()
}

test("each agent keeps its own code until a new one is asked for", async ({page}) => {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  await openPairing(page)
  await expect(message(page)).toHaveCount(0)

  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  const first = await message(page).innerText()

  await choose(page, "Hermes")
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)

  // Coming back shows the same code, so a message already pasted still works.
  await choose(page, "Dots")
  await expect(message(page)).toHaveText(first)

  await pairingBox(page).getByRole("button", {name: "Make a new code"}).click()
  await expect(message(page)).not.toHaveText(first)
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  expect(errors).toEqual([])
})

// A reconnecting page sends the pairing form back with no agent picked, and a
// submit can come before a choice. Neither may crash the side panel (Sentinel,
// 23 Oct 2026, from Patchbay's error mail; ash-template 13379ab).
test("the pairing form with nothing chosen leaves the box as it is", async ({page}) => {
  const crashes: string[] = []
  page.on("websocket", socket =>
    socket.on("framereceived", frame => {
      if (String(frame.payload).includes('"phx_error"')) crashes.push(String(frame.payload).slice(0, 120))
    }),
  )
  await openPairing(page)
  const form = page.locator("form#shell-pairing-box")
  await expect(form.getByRole("radio", {checked: true})).toHaveCount(0)

  await form.getByRole("radio").first().dispatchEvent("input")
  await form.evaluate(element => (element as HTMLFormElement).requestSubmit())

  // The box still answers: choosing an agent shows its code.
  await choose(page, "Dots")
  await expect(message(page)).toContainText(/Pairing code:\s*\S{12,}/)
  expect(crashes).toEqual([])
})
