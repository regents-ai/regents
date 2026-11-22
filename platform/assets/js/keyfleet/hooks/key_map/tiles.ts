import {axialToPixel, SQRT3} from "./lattice"
import type {KeyMapGrid} from "./layouts"
import type {Pictures} from "./pictures"
import {grouped, levelTone, type LevelSale} from "./state"

export type TileFaces = {
  /** A tile's marks for `data-state`. */
  marks(key: number): string
  /** The small line under a key's number. */
  caption(key: number): string
  /** Where a key's card close-up is shown, or "" for a key drawn by its number. */
  picture(key: number): string
  /** How a level stands, for `data-level` on its keys, heading and outline. */
  sale(level: number): LevelSale
  /** A level heading's words. */
  heading(level: number): string
}

export type Tiles = {
  /**
   * Gives every key or level heading whose cell touches the world rectangle a
   * pooled element, and hides the rest of the pool.
   */
  place(grid: KeyMapGrid, size: number, left: number, top: number, right: number, bottom: number): void
  /** Rewrites the marks, captions and level outlines on every placed tile. */
  refresh(): void
  /** Frees every tile, so the next placement positions each one afresh. */
  clear(): void
  /** The keys placed now, each once however many copies of it are in view. */
  keys(): Set<number>
}

type Tile = {
  el: HTMLElement
  value: number
  level: number
  label: HTMLElement
  caption: HTMLElement
  // The key's card close-up, and where it is shown ("" for none). The tile is
  // marked `data-pic` only once the close-up has loaded, so a key keeps its
  // number until then, and for good when the close-up can't be loaded.
  picture: HTMLImageElement
  shown: string
  // Where the tile is drawn, in world pixels, so its close-up loads in turn by
  // how near it is to where the viewer is heading.
  x: number
  y: number
  // The outline along the tile's cell where its level ends, made the first
  // time the tile needs one.
  edge: SVGPathElement | null
}

// Cells stay within a few copies of the origin, so both coordinates fit in 21 bits.
const cellId = (q: number, r: number) => (r + 2 ** 20) * 2 ** 21 + (q + 2 ** 20)

const svg = "http://www.w3.org/2000/svg"

// The six neighbours across a cell's edges, clockwise from the upper right
// edge, which runs from the top corner.
const neighbours: readonly (readonly [number, number])[] = [
  [1, -1],
  [1, 0],
  [0, 1],
  [-1, 1],
  [-1, 0],
  [0, -1],
]

/** The edges of a key's cell, as bits in `neighbours` order, where its level ends. */
export function levelEdges(grid: KeyMapGrid, q: number, r: number, level: number) {
  let edges = 0
  neighbours.forEach(([dq, dr], index) => {
    const value = grid.valueAt(q + dq, r + dr)
    if (value <= 0 || grid.levelOf(value) !== level) edges |= 1 << index
  })
  return edges
}

// The path along a cell's edges in `edges`, around its centre, for a cell of
// circumradius `size`. It runs along the cell's own edges, halfway across the
// gap between tiles, so a level's outline joins up from tile to tile.
function edgePath(edges: number, size: number) {
  const corner = (index: number) => {
    const angle = (Math.PI / 3) * index - Math.PI / 2
    return `${(size * Math.cos(angle)).toFixed(2)} ${(size * Math.sin(angle)).toFixed(2)}`
  }
  let path = ""
  for (let index = 0; index < 6; index++) {
    if (edges & (1 << index)) path += `M${corner(index)}L${corner(index + 1)}`
  }
  return path
}

/**
 * The pool only grows to the most cells covered at once: the stage plus one
 * cell on every side, at most (w / cell + 5) × (h / (0.866 × cell) + 5)
 * elements, fewer where the map has gaps. The laptop stage (1,390 × 630 at
 * 96 px cells) needs at most 19 × 12 = 228 against a budget of 400, and the
 * phone stage (378 × 587 at 76 px) at most 9 × 13 = 117 against 160. A stage
 * wider than about 2,300 px would pass 400.
 */
export function createTiles(layer: HTMLElement, faces: TileFaces, pictures: Pictures): Tiles {
  let placed = new Map<number, Tile>()
  const spare: Tile[] = []
  // Edge paths by edge bits, for the cell size they were drawn at.
  let paths = new Map<number, string>()
  let pathSize = 0

  // Draws the outline along `edges` around the tile, in a drawing inside the
  // tile itself, so the outline moves with the tile and moving the map never
  // redraws it. A tile inside its level, or on a map without levels, draws
  // none.
  const outline = (tile: Tile, edges: number, size: number) => {
    if (!edges) {
      tile.edge?.removeAttribute("d")
      return
    }
    if (size !== pathSize) {
      paths = new Map()
      pathSize = size
    }
    let path = paths.get(edges)
    if (path === undefined) {
      path = edgePath(edges, size)
      paths.set(edges, path)
    }
    if (!tile.edge) {
      const frame = document.createElementNS(svg, "svg")
      frame.setAttribute("class", "km-edges")
      tile.edge = document.createElementNS(svg, "path")
      tile.edge.setAttribute("class", "km-edge")
      frame.append(tile.edge)
      tile.el.prepend(frame)
    }
    tile.edge.setAttribute("d", path)
    tile.edge.dataset.level = faces.sale(tile.level)
  }

  const make = (): Tile => {
    const el = document.createElement("div")
    const frame = document.createElement("i")
    frame.className = "km-pic"
    const picture = document.createElement("img")
    picture.alt = ""
    picture.decoding = "async"
    picture.draggable = false
    frame.append(picture)
    const label = document.createElement("span")
    const caption = document.createElement("span")
    el.append(frame, label, caption)
    layer.append(el)
    const tile: Tile = {el, value: 0, level: 0, label, caption, picture, shown: "", x: 0, y: 0, edge: null}
    // A close-up asked for before the tile moved on to another key is ignored.
    picture.addEventListener("load", () => {
      if (tile.shown && picture.src === tile.shown) el.dataset.pic = ""
    })
    return tile
  }

  const show = (tile: Tile, address: string) => {
    if (tile.shown === address) return
    tile.shown = address
    delete tile.el.dataset.pic
    if (address) pictures.want(tile.picture, address, tile.x, tile.y)
    else {
      pictures.drop(tile.picture)
      tile.picture.removeAttribute("src")
    }
  }

  // A hidden tile gives up a close-up still to come, and asks again when shown.
  const free = (tile: Tile) => {
    tile.el.hidden = true
    if (!("pic" in tile.el.dataset)) show(tile, "")
    tile.edge?.removeAttribute("d")
    spare.push(tile)
  }

  const face = (tile: Tile) => {
    const {el} = tile
    if (tile.level) {
      const sale = faces.sale(tile.level)
      if (el.dataset.level !== sale) el.dataset.level = sale
      if (tile.edge && tile.edge.dataset.level !== sale) tile.edge.dataset.level = sale
    }
    if (tile.value <= 0) {
      const heading = faces.heading(tile.level)
      if (tile.label.textContent !== heading) tile.label.textContent = heading
      show(tile, "")
      return
    }
    show(tile, faces.picture(tile.value))
    const marks = faces.marks(tile.value)
    const caption = faces.caption(tile.value)
    if (el.dataset.state !== marks) el.dataset.state = marks
    if (tile.caption.textContent !== caption) tile.caption.textContent = caption
  }

  const paint = (tile: Tile, value: number, grid: KeyMapGrid) => {
    const {el} = tile
    el.hidden = false
    if (tile.value !== value) {
      tile.value = value
      tile.level = value > 0 ? grid.levelOf(value) : -value
      el.className = value > 0 ? "km-tile" : "km-level"
      if (value > 0) {
        el.dataset.key = String(value)
        tile.label.textContent = grouped(value)
      } else {
        delete el.dataset.key
        delete el.dataset.state
      }
      if (value > 0 && tile.level) el.dataset.tone = String(levelTone(tile.level))
      else delete el.dataset.tone
      if (!tile.level) delete el.dataset.level
      tile.caption.textContent = ""
    }
    face(tile)
  }

  return {
    place(grid, size, left, top, right, bottom) {
      const rowPitch = 1.5 * size
      const colPitch = SQRT3 * size
      const next = new Map<number, Tile>()
      const needed: number[] = []
      // One cell of margin: the layout is redone whenever the camera crosses a
      // cell, so the view never moves more than a cell past what is placed.
      for (let r = Math.floor(top / rowPitch) - 1; r <= Math.ceil(bottom / rowPitch) + 1; r++) {
        for (let q = Math.floor(left / colPitch - r / 2) - 1; q <= Math.ceil(right / colPitch - r / 2) + 1; q++) {
          const value = grid.valueAt(q, r)
          if (!value) continue
          const id = cellId(q, r)
          const tile = placed.get(id)
          if (tile) {
            placed.delete(id)
            next.set(id, tile)
          } else needed.push(q, r, value)
        }
      }
      placed.forEach(free)
      for (let index = 0; index < needed.length; index += 3) {
        const [q, r, value] = [needed[index], needed[index + 1], needed[index + 2]]
        const tile = spare.pop() ?? make()
        const [x, y] = axialToPixel(q, r, size)
        tile.x = x
        tile.y = y
        paint(tile, value, grid)
        tile.el.style.transform = `translate3d(${x}px, ${y}px, 0)`
        outline(tile, value > 0 && tile.level ? levelEdges(grid, q, r, tile.level) : 0, size)
        next.set(cellId(q, r), tile)
      }
      placed = next
    },

    refresh() {
      placed.forEach(face)
    },

    clear() {
      placed.forEach(free)
      placed = new Map()
    },

    keys() {
      const keys = new Set<number>()
      placed.forEach(tile => tile.value > 0 && keys.add(tile.value))
      return keys
    },
  }
}
