import type {EasingParam} from "animejs"
import {LAYOUTS} from "./motion/moments"
import {play, rest, still} from "./motion/shared"

// Where a box was: its place in the list as drawn, glide included, and as laid
// out, and how far it had faded in.
type Place = {drawn: number; laid: number; seen: number}
type SentHook = {el: HTMLElement; shown?: boolean; places?: Map<string, Place>; rejoining?: boolean}

const places = (list: HTMLElement) => {
  const top = list.getBoundingClientRect().top
  return new Map(
    [...list.querySelectorAll<HTMLElement>("li[id]")].map(box => [
      box.id,
      {
        drawn: box.getBoundingClientRect().top - top,
        laid: box.offsetTop - list.offsetTop,
        seen: Number(getComputedStyle(box).opacity),
      },
    ]),
  )
}

const same = (before: Map<string, Place>, after: Map<string, Place>) =>
  [...before.keys()].join() === [...after.keys()].join() &&
  [...after].every(([id, place]) => before.get(id)?.laid === place.laid)

/**
 * The transactions a wallet button sent (`SubmittedTransactions.list`), moving
 * with the site's list spring (`LAYOUTS`, named in `data-variant`). The list's
 * first box arrives with the list, fading in; after that a new box fades in
 * where it lands while the boxes that stay glide to their new places.
 *
 * The server sends this list again each time it reads Base, several times a
 * second, which wipes any style written once on the boxes, so this is not
 * `MotionList`: only the glide and the fade are written, on every frame, and
 * only when a box arrived, left or moved. A copy of the list that changes
 * nothing leaves a glide under way to finish. Nothing moves on load, when the
 * page reconnects, or for a reader who asked for less motion.
 */
export const SentList = {
  beforeUpdate(this: SentHook) {
    this.shown = !this.el.hidden
    this.places = places(this.el)
  },

  updated(this: SentHook) {
    const before = this.places ?? new Map<string, Place>()
    if (this.rejoining || still(this.el)) return
    const ease = LAYOUTS[this.el.dataset.variant ?? ""]().ease as EasingParam

    if (!this.shown) {
      if (!this.el.hidden) play(this.el, {opacity: {from: 0}, ease})
      return
    }
    if (same(before, places(this.el))) return

    const boxes = [...this.el.querySelectorAll<HTMLElement>("li[id]")]
    rest(boxes)
    const after = places(this.el)
    for (const box of boxes) {
      const was = before.get(box.id)
      if (!was) {
        play(box, {opacity: {from: 0}, ease})
        continue
      }
      // A box still gliding or fading in carries on from where it was drawn.
      const glide = was.drawn - after.get(box.id)!.drawn
      const moving = Math.abs(glide) >= 1
      const fading = was.seen < 1
      if (moving || fading) {
        play(box, {...(moving && {y: {from: glide}}), ...(fading && {opacity: {from: was.seen}}), ease})
      }
    }
  },

  disconnected(this: SentHook) {
    this.rejoining = true
  },

  reconnected(this: SentHook) {
    this.rejoining = false
  },
}
