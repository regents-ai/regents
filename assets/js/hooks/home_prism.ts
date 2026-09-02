import type {PrismRenderer} from "../home_prism"
import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
  type MediaQuery,
} from "../canvas_island"

export type HomePrismOptions = CanvasIslandOptions<PrismRenderer> & {
  pointerQuery?: () => MediaQuery
  viewportHeight?: () => number
}

const browserLoadPrism: LoadRenderer<PrismRenderer> = (canvas, size, onDeviceLost) =>
  import("../home_prism").then(({createPrismRenderer}) =>
    createPrismRenderer(canvas, size, onDeviceLost),
  )

const clampUnit = (value: number): number => Math.min(1, Math.max(0, value))

export const createHomePrismController = (
  root: HTMLElement,
  options: HomePrismOptions = {},
): CanvasIslandController => {
  const pointerQuery = options.pointerQuery ?? (() => window.matchMedia("(pointer: fine)"))
  const viewportHeight = options.viewportHeight ?? (() => window.innerHeight)

  return createCanvasIsland(root, options, {
    canvasSelector: "[data-home-prism-canvas]",
    readyFlag: "prismReady",
    browserLoad: browserLoadPrism,
    motionSensitive: true,
    interact({root: island, canvas, renderer, nudge, onReady}) {
      // The island itself takes no pointer events, so hover is read from the hero it
      // decorates — the element the server renders it inside.
      const hero = () => island.parentElement!
      const onPointerMove = (event: PointerEvent) => {
        if (event.isPrimary === false) return
        const {left, top, width, height} = hero().getBoundingClientRect()
        renderer()?.aim((event.clientX - left) / width, (event.clientY - top) / height)
        nudge()
      }
      const onPointerLeave = () => {
        renderer()?.rest()
        nudge()
      }
      // A touch is not a hover, so the crown takes its aim from the reading position:
      // it turns through the shot as the hero travels up the screen.
      const onScroll = () => {
        const current = renderer()
        if (!current) return
        const {top, height} = canvas().getBoundingClientRect()
        const travel = viewportHeight() + height
        if (travel <= 0) return
        current.aim(0.5, clampUnit((viewportHeight() - top) / travel))
        nudge()
      }

      const fine = pointerQuery().matches
      if (fine) {
        hero().addEventListener("pointermove", onPointerMove, {passive: true})
        hero().addEventListener("pointerleave", onPointerLeave, {passive: true})
      } else {
        document.addEventListener("scroll", onScroll, {passive: true})
        // The visitor may arrive part-way down the page, so the first shot is
        // composed for where the hero already is.
        onReady(onScroll)
      }

      return () => {
        if (fine) {
          hero().removeEventListener("pointermove", onPointerMove)
          hero().removeEventListener("pointerleave", onPointerLeave)
        } else {
          document.removeEventListener("scroll", onScroll)
        }
      }
    },
  })
}

type HomePrismHook = {
  el: HTMLElement
  controller?: CanvasIslandController
}

export const HomePrism = {
  mounted(this: HomePrismHook) {
    this.controller = createHomePrismController(this.el)
    this.controller.mount()
  },
  disconnected(this: HomePrismHook) {
    this.controller?.pause()
  },
  reconnected(this: HomePrismHook) {
    this.controller?.resume()
  },
  destroyed(this: HomePrismHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
