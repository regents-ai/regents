import {axialToPixel, SQRT3} from "./lattice"
import {buildMap, given, maxSupply, type LayoutKind} from "./layouts"
import {
  drawnKeys,
  levelSale,
  levelTone,
  nextKey,
  onSaleLevel,
  startKey,
  type KeyMapState,
  type LevelSale,
} from "./state"

// A cell's circumradius and the view's size, in the drawing's own units: about
// twelve keys across, framed the way the map opens.
const size = 10
const width = 12 * SQRT3 * size
const height = width * 0.625
// Each hexagon is drawn a little inside its cell, leaving the map's gap.
const inset = 0.88
const corners = Array.from({length: 6}, (_, index) => {
  const angle = (Math.PI / 3) * index - Math.PI / 2
  return [Math.cos(angle) * size * inset, Math.sin(angle) * size * inset] as const
})

export type PreviewTile = {
  key: number
  /** The hexagon's corners, as SVG `points`. */
  points: string
  /** The level's tone and sale, for a fleet with levels. */
  tone?: number
  level?: LevelSale
  mark?: "next" | "unsold"
}

export type Preview = {viewBox: string; tiles: PreviewTile[]}

/**
 * A still picture of a fleet's map as it opens, once `minted` keys are sold:
 * the keys around the next key on sale (key 1 once sold out), in the map's own
 * layout, tones and marks.
 */
export function preview(layout: LayoutKind, minted: number): Preview {
  const state: KeyMapState = {
    minted,
    maxSupply: maxSupply[layout],
    given: given(layout),
    mine: new Uint8Array(0),
    agent: new Uint8Array(0),
  }
  const grid = buildMap(layout, drawnKeys(state))
  const next = nextKey(state)
  const onSale = onSaleLevel(grid, state)
  const [cx, cy] = axialToPixel(...grid.home(startKey(state)), size)
  const tiles: PreviewTile[] = []

  const rowFrom = Math.floor((cy - height / 2) / (1.5 * size)) - 1
  const rowTo = Math.ceil((cy + height / 2) / (1.5 * size)) + 1
  for (let r = rowFrom; r <= rowTo; r++) {
    const qFrom = Math.floor((cx - width / 2) / (SQRT3 * size) - r / 2) - 1
    const qTo = Math.ceil((cx + width / 2) / (SQRT3 * size) - r / 2) + 1
    for (let q = qFrom; q <= qTo; q++) {
      const key = grid.valueAt(q, r)
      if (key <= 0) continue
      const [x, y] = axialToPixel(q, r, size)
      const tile: PreviewTile = {key, points: corners.map(([dx, dy]) => `${x + dx},${y + dy}`).join(" ")}
      const level = grid.levelOf(key)
      if (level) {
        tile.tone = levelTone(level)
        tile.level = levelSale(onSale, level)
      }
      if (key === next) tile.mark = "next"
      else if (key > minted) tile.mark = "unsold"
      tiles.push(tile)
    }
  }

  return {viewBox: `${cx - width / 2} ${cy - height / 2} ${width} ${height}`, tiles}
}

const svg = "http://www.w3.org/2000/svg"

/** Draws `preview(layout, minted)` as an SVG, replacing everything inside `root`. */
export function drawPreview(root: Element, layout: LayoutKind, minted: number) {
  const {viewBox, tiles} = preview(layout, minted)
  const drawing = document.createElementNS(svg, "svg")
  drawing.setAttribute("viewBox", viewBox)
  drawing.setAttribute("preserveAspectRatio", "xMidYMid slice")
  for (const {points, tone, level, mark} of tiles) {
    const polygon = document.createElementNS(svg, "polygon")
    polygon.setAttribute("points", points)
    if (tone !== undefined) polygon.dataset.tone = String(tone)
    if (level) polygon.dataset.level = level
    if (mark) polygon.dataset.state = mark
    drawing.append(polygon)
  }
  root.replaceChildren(drawing)
}
