import type {HolographicCardRenderer} from "../../vendor/regent_ui/holographic_card.mjs"
import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
  type MediaQuery,
} from "../canvas_island"

export type HolographicCardOptions = CanvasIslandOptions<HolographicCardRenderer> & {
  pointerQuery?: () => MediaQuery
}

const browserLoadCard: LoadRenderer<HolographicCardRenderer> = (canvas, size, onDeviceLost) =>
  import("../../vendor/regent_ui/holographic_card.mjs").then(({createHolographicCardRenderer}) =>
    createHolographicCardRenderer(canvas, size, onDeviceLost),
  )

/**
 * The shared holographic card, mounted the way the hero's crown is: the foil is
 * drawn on the island's canvas and the card itself turns with the pointer.
 *
 * The turn is the renderer's eased tilt written back to the card as CSS custom
 * properties, so the text on the face stays real DOM text and moves with the
 * foil beneath it. A picture that moves is never drawn for a visitor who asked
 * for less of it, and a pointer that cannot hover never lights the foil.
 */
export const createHolographicCardController = (
  root: HTMLElement,
  options: HolographicCardOptions = {},
): CanvasIslandController => {
  const pointerQuery = options.pointerQuery ?? (() => window.matchMedia("(pointer: fine)"))

  return createCanvasIsland(root, options, {
    canvasSelector: "[data-holo-canvas]",
    readyFlag: "holoReady",
    browserLoad: browserLoadCard,
    motionSensitive: true,
    interact({root: card, renderer, nudge, onReady}) {
      // Every frame the island draws is followed by the tilt the renderer settled
      // on, so the card keeps turning for exactly as long as the foil eases.
      onReady(() => {
        const current = renderer()
        if (!current) return
        const draw = current.present.bind(current)
        current.present = () => {
          draw()
          const [x, y] = current.tilt()
          card.style.setProperty("--rg-holo-tilt-x", `${x}rad`)
          card.style.setProperty("--rg-holo-tilt-y", `${y}rad`)
        }
      })
      const onPointerMove = (event: PointerEvent) => {
        if (event.isPrimary === false) return
        const {left, top, width, height} = card.getBoundingClientRect()
        renderer()?.point((event.clientX - left) / width, (event.clientY - top) / height)
        nudge()
      }
      const onPointerLeave = () => {
        renderer()?.rest()
        nudge()
      }

      const fine = pointerQuery().matches
      if (fine) {
        card.addEventListener("pointermove", onPointerMove, {passive: true})
        card.addEventListener("pointerleave", onPointerLeave, {passive: true})
      }

      return () => {
        if (fine) {
          card.removeEventListener("pointermove", onPointerMove)
          card.removeEventListener("pointerleave", onPointerLeave)
        }
        card.style.removeProperty("--rg-holo-tilt-x")
        card.style.removeProperty("--rg-holo-tilt-y")
      }
    },
  })
}

type HolographicCardHook = {
  el: HTMLElement
  controller?: CanvasIslandController
}

export const HolographicCard = {
  mounted(this: HolographicCardHook) {
    this.controller = createHolographicCardController(this.el)
    this.controller.mount()
  },
  disconnected(this: HolographicCardHook) {
    this.controller?.pause()
  },
  reconnected(this: HolographicCardHook) {
    this.controller?.resume()
  },
  destroyed(this: HolographicCardHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
