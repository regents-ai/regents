import type {Hook} from "../hook_composition"
import {still} from "./motion/shared"

interface FigureFlashHook {
  el: HTMLElement
  before?: string[]
}

// The figures inside, each marked `data-count` (the same ones MotionCount rolls).
const figures = (root: HTMLElement) => [...root.querySelectorAll<HTMLElement>("[data-count]")]

/**
 * A figure the server changes gives a small flash behind it as it turns over,
 * so the eye finds what a landed transaction moved. The flash is the opacity of
 * the `[data-flash]` element's own `::after`; the page's figures are untouched.
 */
export const FigureFlash: Hook = {
  beforeUpdate(this: FigureFlashHook) {
    this.before = figures(this.el).map(figure => figure.textContent ?? "")
  },

  updated(this: FigureFlashHook) {
    const before = this.before ?? []
    const after = figures(this.el)
    if (still(this.el) || after.length !== before.length) return

    after.forEach((figure, index) => {
      if (before[index] === (figure.textContent ?? "")) return
      figure.closest<HTMLElement>("[data-flash]")?.animate(
        [{opacity: 0}, {opacity: 1, offset: 0.25}, {opacity: 0}],
        {duration: 900, easing: "ease-out", pseudoElement: "::after"},
      )
    })
  },
}
