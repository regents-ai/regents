/**
 * The motion of a Patchbay thread others reply to and like while the reader
 * watches (`RegentsWeb.Patchbay.ThreadLive`), as patchbay.help has it
 * (`MotionThread`): its replies settle in (`MotionArrivals`) and its counts
 * roll. A thread's figures come and go as it changes, such as a reply's first
 * like, so each figure is matched to itself rather than to its place, and the
 * figures `data-figures` names roll beside those marked `data-count`.
 */
import {animate, createScope, splitText, stagger, type Scope, type TextSplitter} from "animejs"
import {CLIPPED_CHAR, still} from "../hooks/motion/shared"
import {ROLLS} from "../hooks/motion/moments"
import {composeHooks, type Hook} from "../hook_composition"
import {MotionArrivals} from "./motion_arrivals"

// What a figure is worth, decimals included, so 1.75 to 2 rolls up.
const worth = (text: string) => Number(text.replace(/[^\d.]/g, ""))

// A figure's characters as the split makes them, which leaves out spaces.
const glyphs = (figure: HTMLElement) => (figure.textContent ?? "").replace(/\s/g, "")

// The figures inside the thread, each marked `data-count`, or those
// `data-figures` names.
const figures = (root: HTMLElement) =>
  [...root.querySelectorAll<HTMLElement>(root.dataset.figures ?? "[data-count]")]

type CountHook = {el: HTMLElement; scope?: Scope; before?: Map<HTMLElement, string>; splits: Set<TextSplitter>}

// Put the plain figure back, but only for a split that is still on the page:
// an older one would write its stale figure over the new one.
function join(hook: CountHook, split: TextSplitter) {
  if (!hook.splits.delete(split)) return
  split.revert()
}

// Only the characters that changed move, the ones nearest the end first. A
// figure the change brings is simply there, and the figures that were already
// there still roll. Each figure is joined back as soon as its move ends, so
// the page always patches the plain figure it rendered.
const MotionThreadCount: Hook = {
  mounted(this: CountHook) {
    const scope = createScope({root: this.el})
    this.splits = new Set()

    this.scope = scope.add(() => {
      scope.add("roll", (split: TextSplitter, digits: HTMLElement[], up: boolean) => {
        animate(digits, {
          ...ROLLS[this.el.dataset.variant ?? ""].move(up),
          delay: stagger(45, {from: "last"}),
          onComplete: () => join(this, split),
        })
      })
    })
  },

  beforeUpdate(this: CountHook) {
    for (const split of this.splits) join(this, split)
    this.before = new Map(figures(this.el).map(figure => [figure, glyphs(figure)]))
  },

  updated(this: CountHook) {
    if (still(this.el)) return

    const {clip} = ROLLS[this.el.dataset.variant ?? ""]
    for (const figure of figures(this.el)) {
      const was = this.before?.get(figure)
      const now = glyphs(figure)
      if (was === undefined || was === now) continue

      const split = splitText(figure, {words: false, chars: clip ? CLIPPED_CHAR : true})
      const digits = split.chars.filter((_char, i) => was.at(i - now.length) !== now[i])
      this.splits.add(split)
      this.scope?.methods.roll(split, digits, worth(now) > worth(was))
    }
  },

  destroyed(this: CountHook) {
    for (const split of this.splits) join(this, split)
    this.scope?.revert()
  },
}

export const MotionThread = composeHooks(MotionArrivals, MotionThreadCount)
