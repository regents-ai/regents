/**
 * Motion for things the server decides: a list that changes, such as a stack
 * of notes, a figure that moves, and work that is done. The page renders
 * every result first; these islands only animate from the old picture to the
 * new one.
 */
import {
  animate,
  createDrawable,
  createLayout,
  createScope,
  spring,
  splitText,
  stagger,
  type AnimationParams,
  type LayoutAnimationParams,
  type Scope,
  type TextSplitter,
} from "animejs"
import {BASE, CLIPPED_CHAR, EASE_OUT, SLOW, play, still, watched} from "./shared"
import {deny} from "./press"
import type {Hook} from "../../../hook_composition"

// How a list moves when the server adds, reorders or drops its items: `bounce`
// for lists and `pop` for notes that come and go. A new item only fades in
// where it lands: a slide or a scale in its entrance stays written on it as
// `translate: none` once it settles. Each is built fresh per change because a
// stagger remembers the items it measured.
export const LAYOUTS: Record<string, () => LayoutAnimationParams> = {
  bounce: () => ({
    ease: spring({bounce: 0.35, duration: 420}),
    enterFrom: {opacity: 0},
    leaveTo: {opacity: 0, transform: "scale(.9)", ease: "in(3)", duration: BASE},
  }),
  pop: () => ({
    ease: spring({bounce: 0.45, duration: 360}),
    enterFrom: {opacity: 0},
    leaveTo: {opacity: 0, transform: "scale(.8)", ease: "in(3)", duration: BASE},
  }),
}

// How a list the server draws again whole stood before a change: its items in
// order, and the place in the record each element inside it held, which the
// redraw takes off.
type Drawn = {order: string; ids: [HTMLElement, string][]}

type ListHook = {el: HTMLElement; scope?: Scope; mine?: Set<string>; drawn?: Drawn}

// The reader's own items in a list, each marked `data-own`, by id.
const own = (list: HTMLElement) => new Set([...list.querySelectorAll<HTMLElement>("[data-own]")].map(item => item.id))

const order = (list: HTMLElement) => [...list.querySelectorAll(list.dataset.children!)].map(item => item.id).join(" ")

const drawn = (list: HTMLElement): Drawn => ({
  order: order(list),
  ids: [...list.querySelectorAll<HTMLElement>("[data-layout-id]")].map(el => [el, el.dataset.layoutId!]),
})

/**
 * A list the server owns, built from a table of versions. It renders
 * `data-layout-id` on the list and on every item, names the items in
 * `data-children` and the version in `data-variant`. An item that is leaving
 * is hidden for a moment before the server drops it, so it can fade out while
 * its neighbours close the gap. A change that brings the reader's own item,
 * marked `data-own`, such as a message they just sent, answers them at once:
 * it is simply there. A list the server may draw again whole, such as a
 * gallery the page redraws whenever it changes or a thread whose connection
 * comes back, is marked `data-redrawn`: it moves only when its items come, go
 * or change places, and what is inside each item stays as it is while they
 * move. A list still moving when the window changes size is at its new place
 * at once.
 */
export const listHook = (layouts: Record<string, () => LayoutAnimationParams>): Hook => ({
  mounted(this: ListHook) {
    const scope = createScope({root: this.el})

    this.scope = scope.add(() => {
      const layout = createLayout(this.el, {children: this.el.dataset.children})
      scope.add("record", () => layout.record())
      scope.add("move", () => layout.animate(layouts[this.el.dataset.variant ?? ""]()))

      // While the list moves, every element in it is held at the size it had
      // in the window the move began in. A window that changes size, as a
      // phone turns or the page zooms, lands the move at once, so the first
      // frame drawn at the new size has each button at its new size.
      const land = () => {
        if (layout.timeline?.completed === false) layout.timeline.complete()
      }
      window.addEventListener("resize", land)
      return () => window.removeEventListener("resize", land)
    })
  },

  beforeUpdate(this: ListHook) {
    this.scope?.methods.record()
    this.mine = own(this.el)
    this.drawn = this.el.dataset.redrawn === undefined ? undefined : drawn(this.el)
  },

  updated(this: ListHook) {
    const {mine, drawn} = this
    if (drawn) for (const [el, id] of drawn.ids) el.dataset.layoutId ??= id
    if (still(this.el) || [...own(this.el)].some(id => !mine!.has(id)) || drawn?.order === order(this.el)) return
    this.scope?.methods.move()
  },

  destroyed(this: ListHook) {
    this.scope?.revert()
  },
})

export const MotionList = listHook(LAYOUTS)

// How the digits that changed arrive. `clip` masks each digit in its own
// slot, so a digit rolling in is hidden until it reaches the slot.
export type Roll = {clip: boolean; move: (up: boolean) => AnimationParams}

export const ROLLS: Record<string, Roll> = {
  roll: {clip: true, move: up => ({y: [up ? "100%" : "-100%", "0%"], duration: SLOW, ease: "outBack(1.4)"})},
  // A balance that changed while the reader watches: the new digits flash in.
  flash: {clip: false, move: () => ({opacity: [0, 1, 0.35, 1], scale: [1.35, 1], duration: SLOW * 3, ease: "outQuad"})},
}

// What a figure is worth, decimals included, so 1.75 to 2 rolls up.
const worth = (text: string) => Number(text.replace(/[^\d.]/g, ""))

// A figure's characters as the split makes them, which leaves out spaces, so
// a figure with a unit such as "12.5 USDC" lines up digit for digit.
const glyphs = (figure: HTMLElement) => (figure.textContent ?? "").replace(/\s/g, "")

// The figures inside a part of the page, each marked `data-count`.
const figures = (root: HTMLElement) => [...root.querySelectorAll<HTMLElement>("[data-count]")]

type CountHook = {el: HTMLElement; scope?: Scope; before?: string[]; splits: Set<TextSplitter>}

// Put the plain figure back, but only for a split that is still on the page:
// an older one would write its stale figure over the new one.
function join(hook: CountHook, split: TextSplitter) {
  if (!hook.splits.delete(split)) return
  split.revert()
}

/**
 * Figures the server changes, built from a table of versions. A figure may
 * carry a unit, such as "12.5 USDC". Only the characters that changed move,
 * the ones nearest the end first, like a counter turning over. The figure is
 * split into pieces for the move and joined back as soon as it ends, so the
 * page always patches the plain figure it rendered.
 */
export const countHook = (rolls: Record<string, Roll>): Hook => ({
  mounted(this: CountHook) {
    const scope = createScope({root: this.el})
    this.splits = new Set()

    this.scope = scope.add(() => {
      scope.add("roll", (split: TextSplitter, digits: HTMLElement[], up: boolean) => {
        animate(digits, {
          ...rolls[this.el.dataset.variant ?? ""].move(up),
          delay: stagger(45, {from: "last"}),
          onComplete: () => join(this, split),
        })
      })
    })
  },

  beforeUpdate(this: CountHook) {
    for (const split of this.splits) join(this, split)
    this.before = figures(this.el).map(glyphs)
  },

  updated(this: CountHook) {
    const before = this.before ?? []
    const after = figures(this.el)
    if (still(this.el) || after.length !== before.length) return

    const {clip} = rolls[this.el.dataset.variant ?? ""]
    after.forEach((figure, index) => {
      const was = before[index]
      const now = glyphs(figure)
      if (was === now) return

      const split = splitText(figure, {words: false, chars: clip ? CLIPPED_CHAR : true})
      const digits = split.chars.filter((_char, i) => was.at(i - now.length) !== now[i])
      this.splits.add(split)
      this.scope?.methods.roll(split, digits, worth(now) > worth(was))
    })
  },

  destroyed(this: CountHook) {
    for (const split of this.splits) join(this, split)
    this.scope?.revert()
  },
})

export const MotionCount = countHook(ROLLS)

type RefusalHook = {el: HTMLElement; scope?: Scope; said?: string}

/**
 * A message a live page shows when it refuses something. It shakes once when
 * it appears and again whenever it says something new, while `data-refused`
 * is on it. A shake still playing when the message goes stops with it.
 */
export const MotionRefusal: Hook = {
  mounted(this: RefusalHook) {
    const scope = createScope({root: this.el})
    this.said = this.el.textContent ?? ""

    this.scope = scope.add(() => {
      scope.add("shake", () => {
        if (this.el.dataset.refused !== undefined) deny(this.el)
      })
      scope.methods.shake()
    })
  },

  updated(this: RefusalHook) {
    const said = this.el.textContent ?? ""
    if (said !== this.said) this.scope?.methods.shake()
    this.said = said
  },

  destroyed(this: RefusalHook) {
    this.scope?.revert()
  },
}

/**
 * A done step's tick drawing in: only its stroke changes, from the start of
 * the line to its end, so nothing around it moves.
 */
export function drawTick(tick: SVGGeometryElement, delay = 0) {
  const [line] = createDrawable(tick)
  return animate(line, {draw: ["0 0", "0 1"], delay, duration: SLOW, ease: EASE_OUT})
}

/**
 * Words or a mark landing like a stamp on work just done: it drops onto the
 * page, turning straight as it lands. It only grows, turns and fades in, so
 * nothing around it moves. It starts at well over twice its size, so a
 * button it passes over must sit on top of it (as Approve and Buy do in the
 * Buy Key window), and every press still reaches the button.
 */
export const stamp = (el: Element) =>
  play(el, {scale: {from: 2.4}, rotate: {from: -24}, opacity: {from: 0}, duration: 240, ease: "in(3)"})

type TickHook = {el: HTMLElement; scope?: Scope; done?: boolean}

const done = (el: HTMLElement) => el.dataset.done !== undefined

/**
 * A step's mark, which shows a tick while `data-done` is on it. The tick
 * draws in when the step is done while the reader watches; a step already
 * done when the page opens, or when its connection comes back, shows it drawn.
 */
export const MotionTick: Hook = {
  mounted(this: TickHook) {
    const scope = createScope({root: this.el})
    this.done = done(this.el)

    this.scope = scope.add(() => {
      scope.add("draw", () => drawTick(this.el.querySelector<SVGGeometryElement>("svg path")!))
    })
  },

  updated(this: TickHook) {
    const now = done(this.el)
    if (now && !this.done && watched(this.el) && !still(this.el)) this.scope?.methods.draw()
    this.done = now
  },

  destroyed(this: TickHook) {
    this.scope?.revert()
  },
}

type StampHook = {el: HTMLElement; scope?: Scope}

/**
 * Words that land like a stamp when the work they announce is done while the
 * reader watches, such as "You’re in" once a Key bought here lands. On a page
 * that opens on the result they are simply there.
 */
export const MotionStamp: Hook = {
  mounted(this: StampHook) {
    const scope = createScope({root: this.el})

    this.scope = scope.add(() => {
      if (watched(this.el) && !still(this.el)) stamp(this.el)
    })
  },

  destroyed(this: StampHook) {
    this.scope?.revert()
  },
}
