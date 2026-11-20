/**
 * The motion of a Patchbay list the server keeps current, such as the home
 * page's Recent list (`RegentsWeb.Patchbay.PostListLive`), as patchbay.help
 * has it (`MotionArrivals`).
 */
import {EASE_OUT, play, still} from "../hooks/motion/shared"
import type {Hook} from "../hook_composition"

// What the reader was reading before the server changed the list, by how far
// it was from the top of the screen: the field they were typing in; or, once
// they have scrolled past the list's start, each item still on the screen or
// below it, in order, and the end of the list. While the list starts on the
// screen nothing is kept, so the reader sees what arrives.
type Place = {typing: [HTMLElement, number]} | {items: [HTMLElement, number][]; end: number}
// The page scrolls by whole pixels and rows need not be whole pixels tall, so
// what a move could not make up, under a pixel, is `owed` to the next one
// while the reader stays where the last one left them, at `rest`.
type ArrivalsHook = {el: HTMLElement; seen: Set<string>; place?: Place; owed: number; rest?: number}

// The items of a list the server keeps current, each with an id: the
// element's children, or those `data-arrivals` names.
const items = (root: HTMLElement) =>
  [...root.querySelectorAll<HTMLElement>(root.dataset.arrivals ?? ":scope > *")]

const top = (el: Element) => el.getBoundingClientRect().top

function place(root: HTMLElement): Place | undefined {
  const focused = document.activeElement
  if (
    focused instanceof HTMLElement && root.contains(focused) && focused.matches("input, textarea, select") &&
    top(focused) >= 0 && top(focused) < innerHeight
  ) {
    return {typing: [focused, top(focused)]}
  }
  // A list scrolled to its start sits at the top of the screen to within a
  // pixel, as rows need not stop on whole pixels.
  const box = root.getBoundingClientRect()
  if (box.top >= 1) return undefined
  return {
    items: items(root)
      .filter(item => item.getBoundingClientRect().bottom > 0)
      .map(item => [item, top(item)]),
    end: box.bottom,
  }
}

// How far what the reader was reading moved: the field they are typing in;
// otherwise the first item they could see that is still in the list, or else
// everything after the list. What arrives above the screen, or changes size
// there, moves it; what arrives lower down does not.
function moved(root: HTMLElement, was: Place) {
  if ("typing" in was) return was.typing[0].isConnected ? top(was.typing[0]) - was.typing[1] : 0
  const kept = was.items.find(([item]) => root.contains(item))
  return kept ? top(kept[0]) - kept[1] : root.getBoundingClientRect().bottom - was.end
}

// Several items that arrive together step in from the top: the first few a
// little apart, each gap shorter than the last, and the rest with the fifth,
// so even a long page of them is in place within 300 ms.
const STEPS = [0, 40, 72, 98, 120]
const stepIn = (_item: unknown, i = 0) => STEPS[Math.min(i, STEPS.length - 1)]

/**
 * A list that others add to and change while the reader watches, such as new
 * posts or replies. What arrives settles in where it lands, rising a few
 * pixels as it fades in; nothing around it moves, so the page shifts only by
 * its height. In a list marked `data-glow`, what arrives also glows once in
 * the tint its `::before` holds (`[data-arrived]`, in Patchbay's motion.css),
 * with less motion asked for too, as the glow does not move. A reader scrolled
 * past the list's start, or typing in a field in it, keeps what they were
 * reading where it was on the screen whatever arrives or changes size above
 * it, as a browser that anchors its scrolling does, in every browser. What was
 * there when the list was drawn stays still, and so does an item drawn again.
 */
export const MotionArrivals: Hook = {
  mounted(this: ArrivalsHook) {
    this.seen = new Set(items(this.el).map(item => item.id))
  },

  beforeUpdate(this: ArrivalsHook) {
    this.place = place(this.el)
    if (scrollY !== this.rest) this.owed = 0
  },

  updated(this: ArrivalsHook) {
    const shift = this.place ? moved(this.el, this.place) + this.owed : 0
    const from = scrollY
    if (shift !== 0) scrollBy({top: shift, behavior: "instant"})
    const left = shift - (scrollY - from)
    this.owed = Math.abs(left) < 1 ? left : 0
    this.rest = scrollY

    const now = items(this.el)
    const arrived = now.filter(item => !this.seen.has(item.id))
    this.seen = new Set(now.map(item => item.id))
    if (arrived.length === 0) return
    if (this.el.dataset.glow !== undefined) for (const item of arrived) glow(item)
    if (!still(this.el)) play(arrived, {y: {from: 6}, opacity: {from: 0}, duration: 180, delay: stepIn, ease: EASE_OUT})
  },
}

// The glow is the stylesheet's own animation on the item's `::before`, started
// by the mark and taken off when it ends, so the item is left exactly as the
// server drew it.
function glow(item: HTMLElement) {
  const done = (event: AnimationEvent) => {
    if (event.target !== item || event.pseudoElement !== "::before") return
    item.removeEventListener("animationend", done)
    item.removeEventListener("animationcancel", done)
    delete item.dataset.arrived
  }
  item.addEventListener("animationend", done)
  item.addEventListener("animationcancel", done)
  item.dataset.arrived = ""
}
