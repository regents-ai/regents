import {createScope, type Scope} from "animejs"
import {EASE_IN_OUT, SLOW, byPointer, play, still} from "./motion/shared"
import {TABS} from "./motion/reveals"

type PicksHook = {el: HTMLElement; scope?: Scope}

/**
 * A day's choice of papers on Daily Research. The page switches the paper
 * itself, at once, with LiveView commands; a pick made with a mouse or finger
 * then moves as the site's tabs do (`TABS`, named in `data-variant`): the
 * chosen pick's mark travels over from the last pick, as a tab's underline
 * does, and the paper glides in from that side. A pick from the keyboard, or
 * with less motion asked for, is simply there.
 */
export const PaperPicks = {
  mounted(this: PicksHook) {
    const scope = createScope({root: this.el})

    this.scope = scope.add(() => {
      const picks = () => [...this.el.querySelectorAll<HTMLElement>("[aria-pressed]")]
      const chosen = () => picks().find(pick => pick.getAttribute("aria-pressed") === "true")
      let shown = chosen()
      let pointer = false

      // The mark is drawn where it rests, inside the new pick, then sent back
      // to the old pick's place and brought home from there.
      scope.add("move", (from: HTMLElement, to: HTMLElement) => {
        const was = from.getBoundingClientRect()
        const now = to.getBoundingClientRect()
        const mark = to.querySelector(".paper-daily__pick-mark")
        if (mark) {
          const width = mark.getBoundingClientRect().width
          play(mark, {
            x: {from: was.left - now.left},
            y: {from: was.bottom - now.bottom},
            scaleX: {from: (width + was.width - now.width) / width},
            duration: SLOW,
            ease: EASE_IN_OUT,
          })
        }

        const step = picks().indexOf(to) > picks().indexOf(from) ? 1 : -1
        const paper = document.getElementById(to.getAttribute("aria-controls") ?? "")
        if (paper) play(paper, TABS[this.el.dataset.variant ?? ""].panel(step))
      })

      const onClick = (event: MouseEvent) => {
        if (event.target instanceof Element && event.target.closest("[aria-pressed]")) {
          pointer = byPointer(event)
        }
      }
      // The page's command runs after the press has reached the document, so
      // the switch is read from the picks once their `aria-pressed` changes.
      const watch = new MutationObserver(() => {
        const from = shown
        const to = chosen()
        const moved = pointer
        shown = to
        pointer = false
        if (from && to && from !== to && moved && !still(this.el)) scope.methods.move(from, to)
      })

      watch.observe(this.el, {subtree: true, attributes: true, attributeFilter: ["aria-pressed"]})
      this.el.addEventListener("click", onClick, true)
      return () => {
        watch.disconnect()
        this.el.removeEventListener("click", onClick, true)
      }
    })
  },

  destroyed(this: PicksHook) {
    this.scope?.revert()
  },
}
