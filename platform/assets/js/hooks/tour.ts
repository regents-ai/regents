/**
 * A guided tour of a page (`RegentsWeb.Components.Tour`).
 *
 * The server draws the tour's steps and its layer into templates; this hook
 * copies the layer to the end of the document's body, outside the live page,
 * so nothing the page redraws or moves carries it off. The layer covers the
 * screen and takes no presses; only its card does, and the card keeps off
 * every wallet step and notice first, then off the part it points at. Every
 * button on the page, every wallet button above all, stays in reach while the
 * tour shows, and nothing here waits on, stops or changes a press on the page.
 *
 * The dimming is four boxes round a hole, and the ring four lines at the
 * hole's edge, placed by transform alone (tour/place.ts). Anime.js carries the
 * hole from one part to the next, fades the dimming in and drops the card in,
 * as a tip arrives; a step chosen from the keyboard, a tour a key started and
 * less motion asked for are simply there. The light round the ring is a vgpu
 * picture inside the shared canvas island (tour/renderer.ts), drawn only while
 * the tour shows and only when the ring moves; without WebGPU, or with less
 * motion, the ring is the page's own lines alone.
 *
 * The tour plays by itself once in a browser, as the page goes live, never
 * over an open window, and as soon as the last one closes. Finishing or
 * skipping it marks it seen; a browser that keeps nothing shows it again on
 * its next visit.
 * While it shows, the tour's element says so to the page round it with
 * `tour:opened` and `tour:closed`, which bubble, so a page that hides parts
 * of itself can keep them in sight.
 */
import {animate, createScope, type JSAnimation, type Scope} from "animejs"

import {createCanvasIsland} from "../canvas_island"
import {watchTheme} from "../theme"
import {cardSpot, grow, holeAround, mixBox, mixSpot, noHole, pieces, underFoot, type Box, type Spot} from "../tour/place"
import type {TourPicture, TourRenderer} from "../tour/renderer"
import {BASE, EASE_IN_OUT, EASE_OUT, FAST, SLOW, byPointer, fadeIn, lastInputByPointer, play, rest, still} from "./motion/shared"
import {colourReader} from "./theme_switch"

type Step = {target?: string; title: string; text: string}
type Run = {steps: Step[]; at: number; opener: Element | null}
type Frame = {hole: Box; card: Spot}

// A phone docks the card along the foot of the screen (components/tour.css).
const PHONE = "(max-width: 47.99rem)"

// What the card keeps off wherever there is room, so it stays in reach: every
// wallet step, the toasts and the page's notices.
const KEEP_CLEAR = "[data-onchain-step], [data-tour-clear], [data-toast], #flash-region > *"

// How far beyond its part a ring starts as a tour opens, before it closes in.
const OPENING = 24

/** The part a step points at, if it is on the page and drawn. */
function partFor(step: Step) {
  const part = step.target ? document.querySelector(step.target) : null
  return part && part.getClientRects().length > 0 ? part : null
}

/** A part's box on the screen. A heading is ringed round its words, not its whole line. */
function boxOf(part: Element): Box {
  let rect = part.getBoundingClientRect()
  if (/^H[1-6]$/.test(part.tagName)) {
    const words = document.createRange()
    words.selectNodeContents(part)
    rect = words.getBoundingClientRect()
  }
  return {x: rect.left, y: rect.top, w: rect.width, h: rect.height}
}

const windowOpen = () => document.querySelector("dialog[open]") !== null

function stepsOf(root: HTMLElement): Step[] {
  const list = root.querySelector<HTMLTemplateElement>("template[data-tour-steps]")!
  return [...list.content.querySelectorAll<HTMLElement>("[data-step]")].map(({dataset}) => ({
    target: dataset.target,
    title: dataset.title!,
    text: dataset.text!,
  }))
}

export type TourController = {destroy(): void}

export function createTour(root: HTMLElement): TourController {
  const template = root.querySelector<HTMLTemplateElement>("template[data-tour-layer]")!
  const layer = template.content.firstElementChild!.cloneNode(true) as HTMLElement
  document.body.append(layer)

  const find = <T extends Element = HTMLElement>(selector: string) => layer.querySelector<T>(selector)!
  const stage = find("[data-tour-stage]")
  const shade = find(".tour__shade")
  const edge = find(".tour__edge")
  const shadePieces = [...shade.children] as HTMLElement[]
  const ringPieces = [...edge.children] as HTMLElement[]
  const spot = find(".tour__spot")
  const card = find(".tour__card")
  const canvas = find<HTMLCanvasElement>("[data-tour-canvas]")
  const dots = find(".tour__dots")
  const words = find(".tour__words")
  const title = find("[data-tour-title]")
  const text = find("[data-tour-text]")
  const say = find("[data-tour-say]")
  const back = find<HTMLButtonElement>("[data-tour-back]")
  const next = find<HTMLButtonElement>("[data-tour-next]")
  const skip = find<HTMLButtonElement>("[data-tour-skip]")
  const nextLabel = next.querySelector(".rg-button__label")!

  const steps = stepsOf(root)
  const key = root.dataset.tourKey!
  const phone = window.matchMedia(PHONE)
  const forced = window.matchMedia("(forced-colors: active)")
  const readColour = colourReader()

  let run: Run | undefined
  // What is on the screen now, and where the move to the next step set off from.
  let shown: Frame | undefined
  let from: Frame | undefined
  // How far the ring has moved from `from` to its part, from 0 to 1.
  const move = {t: 1}
  let moving: JSAnimation | undefined
  let colours: TourPicture["colours"] | undefined
  let draw = () => {}
  let windows: MutationObserver | undefined

  const seen = () => {
    try {
      return localStorage.getItem(key) === "seen"
    } catch {
      return false
    }
  }

  const markSeen = () => {
    try {
      localStorage.setItem(key, "seen")
    } catch {
      // A browser that keeps nothing plays the tour again on its next visit.
    }
  }

  const tell = (what: "opened" | "closed") => root.dispatchEvent(new CustomEvent(`tour:${what}`, {bubbles: true}))

  const view = () => ({w: layer.clientWidth, h: layer.clientHeight})
  const cardSize = () => ({w: spot.offsetWidth, h: spot.offsetHeight})

  // Where the hole and the card belong for the step on show, as the page stands now.
  const aim = (): Frame => {
    const size = view()
    const part = partFor(run!.steps[run!.at])
    const hole = part ? holeAround(boxOf(part)) : noHole(size)
    const clear = [...document.querySelectorAll(KEEP_CLEAR)]
      .filter(control => control.getClientRects().length > 0)
      .map(boxOf)
    return {hole, card: cardSpot(part ? hole : undefined, cardSize(), size, phone.matches, clear)}
  }

  const put = (piece: HTMLElement, box: Box) => {
    piece.style.transform = `translate(${box.x}px, ${box.y}px) scale(${box.w}, ${box.h})`
  }

  const render = () => {
    if (!run) return
    const to = aim()
    shown =
      from && move.t < 1 ? {hole: mixBox(from.hole, to.hole, move.t), card: mixSpot(from.card, to.card, move.t)} : to
    const {shade: boxes, ring} = pieces(shown.hole, view())
    boxes.forEach((box, i) => put(shadePieces[i], box))
    ring.forEach((box, i) => put(ringPieces[i], box))
    spot.style.transform = `translate(${Math.round(shown.card.x)}px, ${Math.round(shown.card.y)}px)`
    draw()
  }

  // The page is the first box round the tour that paints a solid background;
  // the ring's colour is its lines' own.
  const readColours = (): TourPicture["colours"] => {
    let page: TourPicture["colours"]["page"] | undefined
    for (let el: Element | null = root; el && !page; el = el.parentElement) {
      const found = readColour(getComputedStyle(el).backgroundColor)
      if (found?.opaque) page = found.rgb
    }
    return {page: page!, ring: readColour(getComputedStyle(ringPieces[0]).backgroundColor)!.rgb}
  }

  const picture = (): TourPicture => {
    colours ??= readColours()
    const hole = shown && shown.hole.w > 0 ? shown.hole : undefined
    return {width: canvas.clientWidth, height: canvas.clientHeight, hole, run: move.t, colours}
  }

  const island = createCanvasIsland<TourRenderer>(layer, {}, {
    canvasSelector: "[data-tour-canvas]",
    readyFlag: "tourReady",
    motionSensitive: true,
    // Drawn only when the ring moves or the screen changes; nothing moves between.
    continuous: false,
    browserLoad: async (surface, size, lost) => {
      const {createTourRenderer} = await import("../tour/renderer")
      return createTourRenderer(surface, size, lost)
    },
    interact: ({renderer, nudge, onReady}) => {
      draw = () => {
        const current = renderer()
        if (!current) return
        current.show(picture())
        nudge()
      }
      onReady(() => renderer()?.show(picture()))
      return () => {
        draw = () => {}
      }
    },
  })

  const scope: Scope = createScope({root: layer})
  scope.add(() => {
    // The ring and the card go from where they are to the step's part. A
    // tour opening has its ring close in on the first part as the dimming
    // fades in and the card drops in.
    scope.add("glide", (opening: boolean) => {
      moving?.cancel()
      moving = animate(move, {
        t: [0, 1],
        duration: SLOW,
        ease: opening ? EASE_OUT : EASE_IN_OUT,
        onUpdate: render,
      })
      if (opening) {
        fadeIn(shade)
        play(card, {y: {from: -6}, opacity: {from: 0}, duration: BASE, ease: EASE_OUT})
      } else {
        play(words, {opacity: {from: 0}, duration: FAST, ease: EASE_OUT})
      }
    })

    scope.add("leave", () => {
      stage.dataset.leaving = ""
      play([shade, edge, card], {opacity: {to: 0}, duration: FAST, ease: EASE_OUT}).then(() => {
        if (!run) hide()
      })
    })
  })

  const hide = () => {
    stage.hidden = true
    delete stage.dataset.leaving
    shown = undefined
    from = undefined
  }

  const resized = new ResizeObserver(() => render())
  const onKey = (event: KeyboardEvent) => {
    if (event.key !== "Escape" || event.defaultPrevented || !run || windowOpen()) return
    if (event.target instanceof Element && event.target.closest("input, textarea, select, [contenteditable]")) return
    finish(false)
  }

  const watch = () => {
    window.addEventListener("resize", render)
    document.addEventListener("scroll", render, {capture: true, passive: true})
    document.addEventListener("keydown", onKey)
  }

  const unwatch = () => {
    window.removeEventListener("resize", render)
    document.removeEventListener("scroll", render, {capture: true})
    document.removeEventListener("keydown", onKey)
    resized.disconnect()
  }

  // The card, the box the tour sits in and the part on show: a change in any
  // of their sizes can move the part or the card.
  const observe = (part: Element | null) => {
    resized.disconnect()
    resized.observe(spot)
    if (root.parentElement) resized.observe(root.parentElement)
    if (part) resized.observe(part)
  }

  // Shows step `at`, moving to it when `moves`.
  const go = (at: number, moves: boolean, opening = false) => {
    const current = run!
    current.at = at
    const step = current.steps[at]
    title.textContent = step.title
    text.textContent = step.text
    // Back is hidden on the first step; focus on it goes on to Next, not off the card.
    if (at === 0 && document.activeElement === back) next.focus({preventScroll: true, focusVisible: !lastInputByPointer()})
    back.hidden = at === 0
    nextLabel.textContent = at === current.steps.length - 1 ? "Done" : "Next"
    ;[...dots.children].forEach((dot, i) => dot.toggleAttribute("data-current", i === at))
    if (!opening) say.textContent = `${step.title}. ${step.text} Step ${at + 1} of ${current.steps.length}.`

    const part = partFor(step)
    part?.scrollIntoView({block: "nearest", inline: "nearest"})
    // A phone's card docks along the screen's foot: a part it would lie over
    // is brought up to the middle of the screen.
    if (part && phone.matches && underFoot(holeAround(boxOf(part)), cardSize(), view())) {
      part.scrollIntoView({block: "center", inline: "nearest"})
    }
    observe(part)

    moving?.cancel()
    move.t = 1
    if (moves && (opening || shown)) {
      const to = aim()
      from = opening ? {hole: part ? grow(to.hole, OPENING) : to.hole, card: to.card} : shown
      move.t = 0
      scope.methods.glide(opening)
    }
    render()
  }

  const start = (moves: boolean) => {
    stopWaiting()
    run = {steps: steps.filter(step => !step.target || partFor(step)), at: 0, opener: document.activeElement}
    tell("opened")
    rest([shade, edge, card])
    hide()
    stage.hidden = false
    dots.replaceChildren(...run.steps.map(() => document.createElement("li")))
    unwatch()
    watch()
    if (!still(layer) && !forced.matches) island.mount()
    go(0, moves, true)
    next.focus({preventScroll: true, focusVisible: !lastInputByPointer()})
  }

  const finish = (moves: boolean) => {
    if (!run) return
    markSeen()
    const {opener} = run
    run = undefined
    unwatch()
    island.destroy()
    moving?.cancel()
    if (layer.contains(document.activeElement)) {
      const home = opener instanceof HTMLElement && opener.isConnected && opener !== document.body ? opener : null
      home?.focus({focusVisible: !moves})
    }
    if (moves) scope.methods.leave()
    else hide()
    tell("closed")
  }

  const stopWaiting = () => {
    windows?.disconnect()
    windows = undefined
  }

  // Plays the tour by itself once, never over a window: one waiting on a
  // window starts as the last window closes.
  const consider = () => {
    if (run || seen()) return
    if (!windowOpen()) return start(lastInputByPointer() && !still(layer))
    if (windows) return
    windows = new MutationObserver(() => {
      if (windowOpen()) return
      stopWaiting()
      consider()
    })
    windows.observe(document.body, {subtree: true, childList: true, attributes: true, attributeFilter: ["open"]})
  }

  const events = new AbortController()
  const listen = {signal: events.signal}
  next.addEventListener(
    "click",
    event => {
      if (!run) return
      if (run.at === run.steps.length - 1) finish(byPointer(event) && !still(layer))
      else go(run.at + 1, byPointer(event) && !still(layer))
    },
    listen,
  )
  back.addEventListener("click", event => run && go(run.at - 1, byPointer(event) && !still(layer)), listen)
  skip.addEventListener("click", event => finish(byPointer(event) && !still(layer)), listen)
  const follow = watchTheme(() => {
    colours = undefined
    draw()
  })

  consider()

  return {
    destroy() {
      stopWaiting()
      unwatch()
      events.abort()
      follow()
      island.destroy()
      scope.revert()
      layer.remove()
    },
  }
}

type TourHook = {el: HTMLElement; tour?: TourController}

export const Tour = {
  mounted(this: TourHook) {
    this.tour = createTour(this.el)
  },
  destroyed(this: TourHook) {
    this.tour?.destroy()
    this.tour = undefined
  },
}
