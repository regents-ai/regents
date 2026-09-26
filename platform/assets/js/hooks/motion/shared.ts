/**
 * What all of Regents' motion shares: the design system's timings and curves,
 * the two questions asked before anything moves, and how every move starts.
 */
import {animate, cubicBezier, utils, type AnimationParams, type JSAnimation} from "animejs"

export const BASE = 200
export const SLOW = 280

export const EASE_OUT = cubicBezier(0.23, 1, 0.32, 1)

// The reader asked for less motion in their system settings.
export const still = () => matchMedia("(prefers-reduced-motion: reduce)").matches

// A click from Enter or Space reports no pointer presses. Keyboard-driven UI
// answers at once rather than animating.
export const byPointer = (event: MouseEvent) => event.detail > 0

// Menus and dialogs open without a click of their own: a hover opens the
// $REGENT menu and a finished transaction opens its receipt. They move only
// when the reader was last using a mouse or a finger.
let pointer = false

export const lastInputByPointer = () => pointer

export function watchInput(doc: Document) {
  const byHand = () => { pointer = true }
  doc.addEventListener("pointerdown", byHand, true)
  doc.addEventListener("pointermove", byHand, true)
  doc.addEventListener("keydown", () => { pointer = false }, true)
}

// Anime.js hands an element back to its stylesheet by restoring the inline
// style it found when the animation began. One begun over another's
// half-way frame would end on that frame, so each run first puts its
// elements back as they were before the last run on them began. Every run
// then starts from rest, and ends there with no inline style left behind.
// A finished run is forgotten, so nothing later puts back its old snapshot.
const playing = new WeakMap<Element, JSAnimation>()

export function play(targets: Element | Element[], params: AnimationParams) {
  const els = [targets].flat()
  for (const el of els) playing.get(el)?.revert()
  const animation = animate(els, {
    ...params,
    onComplete: done => {
      utils.cleanInlineStyles(done)
      for (const el of els) if (playing.get(el) === done) playing.delete(el)
    },
  })
  for (const el of els) playing.set(el, animation)
  return animation
}
