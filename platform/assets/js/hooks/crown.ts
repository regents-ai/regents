import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
  type MediaQuery,
} from "../canvas_island"
import type {CrownRenderer} from "../crown"

export type CrownOptions = CanvasIslandOptions<CrownRenderer> & {
  pointerQuery?: () => MediaQuery
  viewportHeight?: () => number
}

export type CrownController = CanvasIslandController & {
  /** Reads the crown's look again and hands it to the crown already on screen. */
  restyle(): void
}

/** The look the markup names in `data-crown-look`, from this site's own looks. */
const lookFor = async (root: HTMLElement) => {
  const {crownLook} = await import("../crown_looks")
  return crownLook(root.dataset.crownLook!)
}

const browserLoadCrown =
  (root: HTMLElement): LoadRenderer<CrownRenderer> =>
  async (canvas, size, onDeviceLost) => {
    const [{createCrownRenderer}, look] = await Promise.all([import("../crown"), lookFor(root)])
    return createCrownRenderer(canvas, size, onDeviceLost, look)
  }

const clampUnit = (value: number): number => Math.min(1, Math.max(0, value))

/**
 * The glass crown: thirteen cubes and three beams, drawn on the island's canvas.
 *
 * The island is a layer behind the stage it decorates and takes no pointer
 * events itself, so the pointer is read from that stage: it turns the camera a
 * little and swings the beams. A touch is not a hover, so on a phone the crown
 * takes its aim from how far the stage has travelled up the screen. Without
 * WebGPU, or for a visitor who asked for less motion, none of this runs and the
 * still picture the server rendered stays.
 */
export const createCrownController = (
  root: HTMLElement,
  options: CrownOptions = {},
): CrownController => {
  const pointerQuery = options.pointerQuery ?? (() => window.matchMedia("(pointer: fine)"))
  const viewportHeight = options.viewportHeight ?? (() => window.innerHeight)
  let restyle = () => {}

  const island = createCanvasIsland(root, options, {
    canvasSelector: "[data-crown-canvas]",
    readyFlag: "crownReady",
    browserLoad: browserLoadCrown(root),
    motionSensitive: true,
    continuous: false,
    interact({root: layer, canvas, renderer, nudge, onReady}) {
      const stage = () => layer.parentElement!
      const onPointerMove = (event: PointerEvent) => {
        if (event.isPrimary === false) return
        const {left, top, width, height} = stage().getBoundingClientRect()
        renderer()?.aim((event.clientX - left) / width, (event.clientY - top) / height)
        nudge()
      }
      const onPointerLeave = () => {
        renderer()?.rest()
        nudge()
      }
      const onScroll = () => {
        const current = renderer()
        if (!current) return
        const {top, height} = canvas().getBoundingClientRect()
        const travel = viewportHeight() + height
        if (travel <= 0) return
        current.aim(0.5, clampUnit((viewportHeight() - top) / travel))
        nudge()
      }
      // A crown still on its way picks its look up when it lands, so only one
      // already drawn has anything to be handed.
      restyle = () => {
        if (!renderer()) return
        void lookFor(layer).then(look => {
          renderer()?.restyle(look)
          nudge()
        })
      }

      const fine = pointerQuery().matches
      if (fine) {
        stage().addEventListener("pointermove", onPointerMove, {passive: true})
        stage().addEventListener("pointerleave", onPointerLeave, {passive: true})
      } else {
        document.addEventListener("scroll", onScroll, {passive: true})
        // The visitor may arrive part-way down the page, so the first shot is
        // composed for where the stage already is.
        onReady(onScroll)
      }

      return () => {
        restyle = () => {}
        if (fine) {
          stage().removeEventListener("pointermove", onPointerMove)
          stage().removeEventListener("pointerleave", onPointerLeave)
        } else {
          document.removeEventListener("scroll", onScroll)
        }
      }
    },
  })

  return {...island, restyle: () => restyle()}
}

type CrownHook = {
  el: HTMLElement
  controller?: CrownController
}

export const Crown = {
  mounted(this: CrownHook) {
    this.controller = createCrownController(this.el)
    this.controller.mount()
  },
  // The server names the look; a new name restyles the crown already drawn.
  updated(this: CrownHook) {
    this.controller?.restyle()
  },
  disconnected(this: CrownHook) {
    this.controller?.pause()
  },
  reconnected(this: CrownHook) {
    this.controller?.resume()
  },
  destroyed(this: CrownHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
