/**
 * What all of Regents' motion shares: the design system's timings and curves,
 * and the two questions asked before anything moves.
 */
import {cubicBezier} from "animejs"

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
