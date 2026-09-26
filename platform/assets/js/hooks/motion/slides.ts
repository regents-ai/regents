/**
 * Panels that open over the page: the phone menu slides out as a drawer, a
 * dialog rises as a sheet and a header menu pops under its button. The page
 * opens and closes them itself; this only moves a panel from where it starts
 * to where it rests, then hands it back to its stylesheet. Closing is
 * immediate.
 *
 * Moves in percent name both ends, so they stay a share of the panel's own
 * size instead of being converted to pixels.
 */
import {animate, spring, utils, type JSAnimation} from "animejs"
import {BASE, EASE_OUT, SLOW} from "./shared"

const tidy = (animation: JSAnimation) => utils.cleanInlineStyles(animation)

// The phone menu sits against the left edge, so its drawer comes from there.
export const drawer = (el: Element) =>
  animate(el, {x: ["-100%", "0%"], ease: spring({bounce: 0.3, duration: 380}), onComplete: tidy})

export const sheet = (el: Element) =>
  animate(el, {y: ["100%", "0%"], ease: spring({bounce: 0.35, duration: 400}), onComplete: tidy})

export const menu = (el: Element) =>
  animate(el, {
    y: {from: -6},
    scale: {from: 0.9},
    opacity: {from: 0},
    duration: SLOW,
    ease: "outBack(2.2)",
    onComplete: tidy,
  })

export const backdrop = (el: Element) =>
  animate(el, {opacity: {from: 0}, duration: BASE, ease: EASE_OUT, onComplete: tidy})
