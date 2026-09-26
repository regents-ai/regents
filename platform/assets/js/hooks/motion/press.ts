/**
 * The answer to a mouse or finger press. The button still does its job the
 * instant it is pressed, wallet buttons included; the squish only plays
 * alongside it. It ends where it began, then hands the element back to its
 * stylesheet, so a hover style that moves it still can. One pressed again
 * mid-move starts over from wherever it is.
 */
import {animate, utils, type JSAnimation} from "animejs"

export const squish = (el: Element) =>
  animate(el, {
    scale: [{to: 0.9, duration: 90, ease: "out(3)"}, {to: 1, duration: 360, ease: "outBack(3)"}],
    onComplete: (animation: JSAnimation) => utils.cleanInlineStyles(animation),
  })
