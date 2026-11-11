import {animate, createScope, createTimer, utils, type Scope, type Timer} from "animejs"

import {createCanvasIsland, type CanvasIslandController, type LoadRenderer} from "../canvas_island"
import {REST, calmAround, type Cell, type Panel} from "../datascape/field"
import type {DatascapeRenderer} from "../datascape/renderer"
import {play, still} from "./motion/shared"

/** How long a panel takes to open, and to put together what it shows, in milliseconds. */
const OPENING = 750
const ASSEMBLY = 2400
/** How white a panel is as it opens, from 0 to 1. */
const FLASH = 0.55
/** How far a panel's opening may be held back, so a cell's panels do not all open at once, in milliseconds. */
const STAGGER = 500
/** The first picture fills outward from its middle over this long, in milliseconds. */
const FIRST_WAVE = 900
/** How fast a tube is drawn, in world units a second. */
const TUBE_SPEED = 1300
/** How long a panel takes to grow under the pointer and to settle back, in milliseconds. */
const REACTION = 350
/** Half the width, in world units, from which a panel opens with a bounce, a flash and sparks; smaller ones just appear. */
const LARGE = 8
/** Sparks thrown as a panel opens, and when it is pressed. */
const OPENING_SPARKS = 3
const PRESS_SPARKS = 14
/** How far past an open glass panel's edges, in CSS pixels, the pointer must go before the picture flies. */
export const LEAVING = 28
/** How long after a press opens the glass panel steering leaves it open, in milliseconds. */
export const GRACE = 2000
/** How long a glass panel squashes, how long it takes to go in all, and how long to open, in milliseconds. */
const SQUASH = 110
const SHRINK = 400
const GROW = 550
/** How much wider and flatter a glass panel squashes before it shrinks. */
const WIDER = 1.06
const FLATTER = 0.9

/** A glass panel's scale on each axis and its opacity, as drawn right now. */
const poseOf = (el: HTMLElement) => {
  const style = getComputedStyle(el)
  const matrix = new DOMMatrixReadOnly(style.transform)
  return {scaleX: matrix.a, scaleY: matrix.d, opacity: Number(style.opacity)}
}

/**
 * The pose the stylesheet gives a glass panel, measured the first time a move asks:
 * Anime.js asks while it builds the move, after `play()` has undone the last one, so
 * no inline style is left to hide it.
 */
const restingPose = (el: HTMLElement) => {
  let pose: ReturnType<typeof poseOf> | undefined
  return () => (pose ??= poseOf(el))
}

type DatascapeHook = {
  el: HTMLElement
  island?: CanvasIslandController
  scope?: Scope
}

/**
 * The datascape at /animations/datascape: an endless dark plane of panels,
 * tubes and specks in three layers of depth, flown over by moving the pointer
 * towards an edge of the picture, or holding a finger there.
 *
 * The picture always moves, so it draws every frame while it is on screen. A
 * visitor who asked for less motion, or whose browser cannot draw it, keeps
 * the still picture the server rendered.
 *
 * The field decides what is near enough to show and what the pointer rests on;
 * Anime.js brings each panel in, draws each tube, and grows the panel under
 * the pointer. It only ever changes numbers on the field's panels and tubes,
 * which the renderer reads when it draws.
 *
 * A root may hold a glass panel (`[data-datascape-glass]`) centred over the
 * picture. It starts away; pressing a panel in the picture opens it, and focus
 * moving into it opens it at once and holds it open. Once it has been open for
 * `GRACE` after the last press, and focus is elsewhere, steering squashes it and
 * sends it away again, until the next press. While it is open the pointer steers
 * nothing round it. The root's `data-datascape-glass-state` says `away` or
 * `open`, and the stylesheet holds both poses and decides when there is no
 * picture to press, so the panel simply stays: each move starts from wherever the
 * panel is and hands it back to the stylesheet when it ends.
 */
export const Datascape = {
  mounted(this: DatascapeHook) {
    const root = this.el
    const canvas = root.querySelector<HTMLCanvasElement>("[data-datascape-canvas]")!
    let scape: DatascapeRenderer | undefined
    let rested: Panel | null = null

    const scope = createScope({root})
    this.scope = scope
    /** Opens a cell's panels and draws its tube. */
    scope.add("arrive", (cell: Cell) => {
      // Everything in the first picture arrives before the field's clock has moved.
      const wait = scape!.field.time === 0 ? cell.distance * FIRST_WAVE : 0
      for (const panel of cell.panels) {
        const large = panel.w > LARGE
        animate(panel, {
          grow: {to: 1, duration: large ? OPENING : OPENING / 2, ease: large ? "outBack(1.6)" : "outExpo"},
          flash: {from: large ? FLASH : 0, to: 0, duration: OPENING, ease: "outQuad"},
          assemble: {to: 1, duration: ASSEMBLY, ease: "outCubic"},
          delay: wait + panel.seed * STAGGER,
          onBegin: () => {
            if (large) scape?.field.burst(panel, OPENING_SPARKS)
          },
        })
      }
      const tube = cell.tube
      if (!tube) return
      animate(tube, {
        drawn: tube.length,
        duration: (tube.length / TUBE_SPEED) * 1000,
        delay: wait + tube.seed * STAGGER,
        ease: "inOutQuad",
      })
    })
    /** Stops whatever is still moving in a cell that has gone. */
    scope.add("leave", (cell: Cell) => {
      utils.remove(cell.panels)
      if (cell.tube) utils.remove(cell.tube)
    })
    /** Grows the panel the pointer came to rest on, and lets the one it left settle back. */
    scope.add("rest", (panel: Panel | null) => {
      if (rested) animate(rested, {hover: 0, duration: REACTION, ease: "outExpo"})
      if (panel) animate(panel, {hover: 1, duration: REACTION, ease: "outExpo"})
      rested = panel
      canvas.style.cursor = panel ? "pointer" : ""
    })
    /** A pressed panel flashes, throws sparks and puts itself together again. */
    scope.add("press", (panel: Panel) => {
      animate(panel, {
        flash: {from: 0.85, to: 0, duration: OPENING, ease: "outQuad"},
        assemble: {from: 0, to: 1, duration: ASSEMBLY / 2, ease: "outCubic"},
      })
      scape?.field.burst(panel, PRESS_SPARKS)
    })
    /** The glass panel squashes a little, then shrinks and fades to the stylesheet's away pose. */
    scope.add("compress", (el: HTMLElement) => {
      const from = poseOf(el)
      const rest = restingPose(el)
      play(el, {
        scaleX: [
          {from: from.scaleX, to: from.scaleX * WIDER, duration: SQUASH, ease: "outQuad"},
          {to: () => rest().scaleX, duration: SHRINK - SQUASH, ease: "inOutCubic"},
        ],
        scaleY: [
          {from: from.scaleY, to: from.scaleY * FLATTER, duration: SQUASH, ease: "outQuad"},
          {to: () => rest().scaleY, duration: SHRINK - SQUASH, ease: "inOutCubic"},
        ],
        opacity: {from: from.opacity, to: () => rest().opacity, duration: SHRINK, ease: "outQuad"},
      })
    })
    /** The glass panel grows back to the stylesheet's open pose, just past it and back, or is simply there when asked to be at once. */
    scope.add("expand", (el: HTMLElement, atOnce: boolean) => {
      const from = poseOf(el)
      const rest = restingPose(el)
      play(el, {
        scaleX: {from: from.scaleX, to: () => rest().scaleX},
        scaleY: {from: from.scaleY, to: () => rest().scaleY},
        opacity: {from: from.opacity, to: () => rest().opacity, ease: "outQuad"},
        duration: atOnce ? 0 : GROW,
        ease: "outBack",
      })
    })

    const glass = root.querySelector<HTMLElement>("[data-datascape-glass]")
    /** What the field last said about the pointer steering, whether focus is in the glass, whether a press still holds it open, and whether it is open. */
    let steering = false
    let focused = false
    let held = false
    let open = false
    if (glass) root.dataset.datascapeGlassState = "away"

    /** The field's calm zone: round the glass while it is open, the field's own while it is away. */
    const calm = () => {
      if (!scape || !glass) return
      scape.field.calm = open
        ? calmAround([glass.offsetWidth, glass.offsetHeight], LEAVING, [canvas.clientWidth, canvas.clientHeight])
        : [REST, REST]
    }
    /** Opens the glass or sends it away, with its move, or at once for the keyboard and for less motion. */
    const show = (next: boolean, atOnce = false) => {
      open = next
      root.dataset.datascapeGlassState = open ? "open" : "away"
      calm()
      scope.methods[open ? "expand" : "compress"]!(glass, atOnce || still(glass!))
    }
    /** An open glass goes away once the pointer steers, no press holds it and focus is elsewhere. */
    const settle = () => {
      if (open && steering && !held && !focused) show(false)
    }
    /** A press holds the glass open for a while, starting again with each press. */
    let hold: Timer | undefined
    scope.add("hold", () => {
      hold?.revert()
      held = true
      hold = createTimer({
        duration: GRACE,
        onComplete: () => {
          held = false
          settle()
        },
      })
    })
    /** A press on a panel in the picture opens the glass. */
    const summon = () => {
      if (!glass) return
      scope.methods.hold!()
      if (!open) show(true)
    }

    const load: LoadRenderer<DatascapeRenderer> = async (canvas, size, onDeviceLost) => {
      const {createDatascapeRenderer} = await import("../datascape/renderer")
      return createDatascapeRenderer(canvas, size, onDeviceLost, {
        arrive: cell => scope.methods.arrive!(cell),
        leave: cell => scope.methods.leave!(cell),
        rest: panel => scope.methods.rest!(panel),
        steer: next => {
          steering = next
          settle()
        },
      })
    }

    /** Where a pointer is, measured from the picture's middle in CSS pixels. */
    const pointOf = (event: MouseEvent): [number, number] => {
      const box = canvas.getBoundingClientRect()
      return [event.clientX - box.left - box.width / 2, event.clientY - box.top - box.height / 2]
    }
    const onPointerMove = (event: PointerEvent) => {
      // A finger steers only while it is held down; a mouse steers wherever it is.
      if (!scape || (event.pointerType !== "mouse" && event.buttons === 0)) return
      scape.field.pointer = pointOf(event)
    }
    const onPointerDown = (event: PointerEvent) => {
      if (!scape) return
      scape.field.pointer = pointOf(event)
      // A finger that slides off the picture keeps steering until it lifts.
      if (event.pointerType !== "mouse") canvas.setPointerCapture(event.pointerId)
    }
    const onPointerAway = (event: PointerEvent) => {
      if (!scape || (event.type === "pointerup" && event.pointerType === "mouse")) return
      scape.field.pointer = null
    }
    const onClick = (event: MouseEvent) => {
      const panel = scape?.field.panelAt(...pointOf(event))
      if (!panel) return
      scope.methods.press!(panel)
      summon()
    }
    const onFocusIn = () => {
      focused = true
      if (!open) show(true, true)
    }
    const onFocusOut = (event: FocusEvent) => {
      focused = glass!.contains(event.relatedTarget as Node | null)
      settle()
    }
    // The glass is measured by its layout size, which a running move does not change.
    const resized = new ResizeObserver(calm)
    // A picture that stops drawing, as when the visitor asks for less motion, steers nothing.
    const stopped = new MutationObserver(() => {
      if (root.dataset.datascapeReady !== "true") steering = false
    })

    this.island = createCanvasIsland<DatascapeRenderer>(root, {}, {
      canvasSelector: "[data-datascape-canvas]",
      readyFlag: "datascapeReady",
      browserLoad: load,
      motionSensitive: true,
      continuous: true,
      interact(island) {
        island.onReady(() => {
          // A renderer that lands, the first or one after a lost device, brings a field of its own.
          scape = island.renderer()!
          rested = null
          steering = false
          calm()
        })
        if (glass) {
          resized.observe(root)
          resized.observe(glass)
          stopped.observe(root, {attributes: true, attributeFilter: ["data-datascape-ready"]})
          glass.addEventListener("focusin", onFocusIn)
          glass.addEventListener("focusout", onFocusOut)
        }
        canvas.addEventListener("pointermove", onPointerMove)
        canvas.addEventListener("pointerdown", onPointerDown)
        canvas.addEventListener("pointerup", onPointerAway)
        canvas.addEventListener("pointercancel", onPointerAway)
        canvas.addEventListener("pointerleave", onPointerAway)
        canvas.addEventListener("click", onClick)
        return () => {
          scape = undefined
          rested = null
          canvas.style.cursor = ""
          canvas.removeEventListener("pointermove", onPointerMove)
          canvas.removeEventListener("pointerdown", onPointerDown)
          canvas.removeEventListener("pointerup", onPointerAway)
          canvas.removeEventListener("pointercancel", onPointerAway)
          canvas.removeEventListener("pointerleave", onPointerAway)
          canvas.removeEventListener("click", onClick)
          resized.disconnect()
          stopped.disconnect()
          glass?.removeEventListener("focusin", onFocusIn)
          glass?.removeEventListener("focusout", onFocusOut)
          // A picture that has stopped steers nothing.
          steering = false
        }
      },
    })
    this.island.mount()
  },
  disconnected(this: DatascapeHook) {
    this.island?.pause()
  },
  reconnected(this: DatascapeHook) {
    this.island?.resume()
  },
  destroyed(this: DatascapeHook) {
    this.island?.destroy()
    this.scope?.revert()
  },
}
