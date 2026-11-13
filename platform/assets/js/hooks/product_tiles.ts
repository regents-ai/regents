import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
  type MediaQuery,
} from "../canvas_island"
import {channels, type TileLook} from "../product_tiles/look"
import type {Box, ProductTilesRenderer, TileRow} from "../product_tiles/renderer"
import {glassIsland} from "./glass_island"

export type ProductTilesOptions = CanvasIslandOptions<ProductTilesRenderer> & {
  pointerQuery?: () => MediaQuery
}

const TILE = "[data-product-tile]"

/** The row's colours, as the stylesheet sets them. */
const lookOf = (row: HTMLElement): TileLook => {
  const style = getComputedStyle(row)
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
    look: lookOf(root),
    count: tiles.length,
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
 * The product row's charcoal tiles, drawn as one flow on one canvas behind the
 * whole row; each tile's dot in its product's colour is the stylesheet's. The flow
 * moves by itself, so it is never drawn for a visitor who asked for less motion;
 * the stylesheet's still gradient stays.
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

/** The row lives on the home page's glass panel and draws only while that can be seen. */
export const ProductTiles = glassIsland(root => createProductTilesController(root))
