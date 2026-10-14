import {createScope, type Scope} from "animejs"
import {EASE_IN_OUT, SLOW, lastInputByPointer, play, still} from "./motion/shared"

type ScrollCueHook = {el: HTMLElement; scope?: Scope; updateCue?: () => void}

export const ResearchScrollCue = {
  mounted(this: ScrollCueHook) {
    const scope = createScope({
      root: this.el,
      mediaQueries: {reduced: "(prefers-reduced-motion: reduce)"},
    })

    this.scope = scope.add(() => {
      const list = document.getElementById(this.el.dataset.scrollTarget ?? "")
      const chevron = this.el.querySelector("[data-scroll-chevron]")
      if (!list || !chevron) return

      const update = () => {
        this.el.hidden = list.scrollHeight - list.scrollTop <= list.clientHeight + 1
      }
      this.updateCue = update
      const resize = new ResizeObserver(update)
      list.addEventListener("scroll", update, {passive: true})
      resize.observe(list)
      update()

      if (!this.el.hidden && !still(this.el) && lastInputByPointer()) {
        play(chevron, {y: [0, 6, 0], duration: SLOW, ease: EASE_IN_OUT})
      }

      return () => {
        list.removeEventListener("scroll", update)
        resize.disconnect()
      }
    })
  },

  updated(this: ScrollCueHook) {
    this.updateCue?.()
  },

  destroyed(this: ScrollCueHook) {
    this.scope?.revert()
  },
}
