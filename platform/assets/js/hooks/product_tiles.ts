import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
  type MediaQuery,
} from "../canvas_island"
import {channels, type TileLook} from "../product_tiles/look"
import type {Box, ProductTilesRenderer, TileRow} from "../product_tiles/renderer"

export type ProductTilesOptions = CanvasIslandOptions<ProductTilesRenderer> & {
  pointerQuery?: () => MediaQuery
}

const TILE = "[data-product-tile]"

/** A tile's colours, as its product's rule in the stylesheet sets them. */
const lookOf = (tile: HTMLElement): TileLook => {
  const style = getComputedStyle(tile)
  const color = (name: string) => channels(style.getPropertyValue(name))
  return {
    deep: color("--tile-deep"),
    mid: color("--tile-mid"),
    light: color("--tile-light"),
    sheen: color("--tile-sheen"),
    ink: color("--tile-ink"),
  }
}

/** The shared press scales a tile's paint about its middle; between presses it is 1. */
const pressOf = (tile: HTMLElement) => Number(tile.style.getPropertyValue("--rg-press-scale") || 1)

/**
 * A box as fractions of the canvas box, scaled about its own middle. Both are
 * measured on screen, so a transform round the whole row (the glass panel
 * growing in) moves them together and the fractions stay true.
 */
const within = (box: DOMRect, canvas: DOMRect, scale: number): Box => {
  const middleX = box.left + box.width / 2 - canvas.left
  const middleY = box.top + box.height / 2 - canvas.top
  const halfWidth = (box.width * scale) / 2
  const halfHeight = (box.height * scale) / 2
  return [
    (middleX - halfWidth) / canvas.width,
    (middleY - halfHeight) / canvas.height,
    (middleX + halfWidth) / canvas.width,
    (middleY + halfHeight) / canvas.height,
  ]
}

const rowOf = (root: HTMLElement, canvas: HTMLCanvasElement): TileRow => {
  const tiles = [...root.querySelectorAll<HTMLElement>(TILE)]
  return {
    looks: tiles.map(lookOf),
    measure() {
      const frame = canvas.getBoundingClientRect()
      return tiles.map(tile => within(tile.getBoundingClientRect(), frame, pressOf(tile)))
    },
    width: () => canvas.clientWidth,
  }
}

const browserLoadTiles =
  (root: HTMLElement): LoadRenderer<ProductTilesRenderer> =>
  async (canvas, size, onDeviceLost) => {
    const {createProductTilesRenderer} = await import("../product_tiles/renderer")
    return createProductTilesRenderer(canvas, size, onDeviceLost, rowOf(root, canvas))
  }

/**
 * The product row's tiles, each in its own product's colours, drawn as one flow on
 * one canvas behind the whole row. The flow moves by itself, so it is never drawn
 * for a visitor who asked for less motion; the stylesheet's still gradient stays.
 * A pointer that can hover lights the tile under it.
 */
export const createProductTilesController = (
  root: HTMLElement,
  options: ProductTilesOptions = {},
): CanvasIslandController => {
  const pointerQuery = options.pointerQuery ?? (() => window.matchMedia("(pointer: fine)"))

  return createCanvasIsland(root, options, {
    canvasSelector: "[data-product-tiles-canvas]",
    readyFlag: "productTilesReady",
    browserLoad: browserLoadTiles(root),
    motionSensitive: true,
    continuous: true,
    interact({root: row, canvas, renderer}) {
      if (!pointerQuery().matches) return () => {}
      const tiles = [...row.querySelectorAll<HTMLElement>(TILE)]

      const onPointerMove = (event: PointerEvent) => {
        if (!event.isPrimary) return
        const over = (event.target as Element).closest<HTMLElement>(TILE)
        const tile = over ? tiles.indexOf(over) : -1
        if (tile < 0) {
          renderer()?.rest()
          return
        }
        const {left, top, width, height} = canvas().getBoundingClientRect()
        renderer()?.point(tile, [(event.clientX - left) / width, (event.clientY - top) / height])
      }
      const onPointerLeave = () => renderer()?.rest()

      row.addEventListener("pointermove", onPointerMove, {passive: true})
      row.addEventListener("pointerleave", onPointerLeave, {passive: true})
      return () => {
        row.removeEventListener("pointermove", onPointerMove)
        row.removeEventListener("pointerleave", onPointerLeave)
      }
    },
  })
}

type ProductTilesHook = {
  el: HTMLElement
  controller?: CanvasIslandController
  glass?: MutationObserver
  connected?: boolean
  follow?: () => void
}

/**
 * The row lives on the home page's glass panel, which goes away (shrunk and
 * clear) while the visitor flies the picture behind it. The Datascape hook round
 * the panel says which on its root, and it mounts first, as LiveView mounts hooks
 * in page order. The flow draws only while the panel can be seen and the page is
 * connected.
 */
export const ProductTiles = {
  mounted(this: ProductTilesHook) {
    const controller = createProductTilesController(this.el)
    const home = this.el.closest<HTMLElement>("[data-datascape-glass-state]")
    this.controller = controller
    this.connected = true
    this.follow = () => {
      const away =
        home?.dataset.datascapeGlassState === "away" && home.dataset.datascapeReady !== "false"
      if (this.connected && !away) controller.resume()
      else controller.pause()
    }
    if (home) {
      this.glass = new MutationObserver(this.follow)
      this.glass.observe(home, {attributeFilter: ["data-datascape-glass-state", "data-datascape-ready"]})
    }
    controller.mount()
    this.follow()
  },
  disconnected(this: ProductTilesHook) {
    this.connected = false
    this.follow?.()
  },
  reconnected(this: ProductTilesHook) {
    this.connected = true
    this.follow?.()
  },
  destroyed(this: ProductTilesHook) {
    this.glass?.disconnect()
    this.controller?.destroy()
    this.controller = undefined
  },
}
