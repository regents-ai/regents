/**
 * Motion for things the server decides: a list that changes and a figure that
 * moves. The page renders every result first; these only animate from the old
 * picture to the new one.
 */
import {
  animate,
  createLayout,
  createScope,
  spring,
  splitText,
  stagger,
  type AnimationParams,
  type AutoLayout,
  type LayoutAnimationParams,
  type Scope,
  type TextSplitter,
} from "animejs"
import {BASE, SLOW, still} from "./shared"
import type {Hook} from "../../hook_composition"

// How a list moves when the server adds, reorders or drops its items. Each is
// built fresh per change because a stagger remembers the items it measured.
const LAYOUTS: Record<string, () => LayoutAnimationParams> = {
  bounce: () => ({
    ease: spring({bounce: 0.35, duration: 420}),
    enterFrom: {opacity: 0, transform: "translateY(-12px)"},
    leaveTo: {opacity: 0, transform: "scale(.9)", ease: "in(3)", duration: BASE},
  }),
}

type ListHook = {el: HTMLElement; scope?: Scope; layout?: AutoLayout}

/**
 * A list the server owns. It renders `data-layout-id` on the list and on
 * every item, names the items in `data-children` and the version in
 * `data-variant`.
 */
export const MotionList: Hook = {
  mounted(this: ListHook) {
    const scope = createScope({root: this.el})

    this.scope = scope.add(() => {
      const layout = createLayout(this.el, {children: this.el.dataset.children})
      scope.add("record", () => layout.record())
      scope.add("move", () => layout.animate(LAYOUTS[this.el.dataset.variant ?? ""]()))
    })
  },

  beforeUpdate(this: ListHook) {
    this.scope?.methods.record()
  },

  updated(this: ListHook) {
    if (!still()) this.scope?.methods.move()
  },

  destroyed(this: ListHook) {
    this.scope?.revert()
  },
}

// How the digits that changed arrive. `clip` masks each digit in its own
// slot, so a digit rolling in is hidden until it reaches the slot.
const ROLLS: Record<string, (up: boolean) => AnimationParams> = {
  roll: up => ({y: [up ? "100%" : "-100%", "0%"], duration: SLOW, ease: "outBack(1.4)"}),
}

const worth = (text: string) => Number(text.replace(/\D/g, ""))

// The figures inside a part of the page, each written by `TokenDisplay`.
const figures = (root: HTMLElement) => [...root.querySelectorAll<HTMLElement>("[data-count]")]

type CountHook = {
  el: HTMLElement
  scope?: Scope
  before?: string[]
  splits: Set<TextSplitter>
}

/**
 * Figures the server changes, such as a wallet's balances after a
 * transaction. Only the digits that changed move, the ones nearest the end
 * first, like a counter turning over. The digits are split into pieces for
 * the move and joined back as soon as it ends, so the page always patches the
 * plain figure it rendered.
 */
export const MotionCount: Hook = {
  mounted(this: CountHook) {
    const scope = createScope({root: this.el})
    this.splits = new Set()

    this.scope = scope.add(() => {
      scope.add("roll", (split: TextSplitter, digits: HTMLElement[], up: boolean) => {
        animate(digits, {
          ...ROLLS[this.el.dataset.variant ?? ""](up),
          delay: stagger(45, {from: "last"}),
          onComplete: () => join(this, split),
        })
      })
    })
  },

  beforeUpdate(this: CountHook) {
    for (const split of this.splits) join(this, split)
    this.before = figures(this.el).map(figure => figure.textContent ?? "")
  },

  updated(this: CountHook) {
    const before = this.before ?? []
    const after = figures(this.el)
    if (still() || after.length !== before.length) return

    after.forEach((figure, index) => {
      const was = before[index]
      const now = figure.textContent ?? ""
      if (was === now) return

      const split = splitText(figure, {words: false, chars: {wrap: "clip"}})
      const digits = split.chars.filter((_char, i) => was.at(i - now.length) !== now[i])
      this.splits.add(split)
      this.scope?.methods.roll(split, digits, worth(now) > worth(was))
    })
  },

  destroyed(this: CountHook) {
    for (const split of this.splits) join(this, split)
    this.scope?.revert()
  },
}

// Put the plain figure back, but only for a split that is still on the page:
// an older one would write its stale figure over the new one.
function join(hook: CountHook, split: TextSplitter) {
  if (!hook.splits.delete(split)) return
  split.revert()
}
