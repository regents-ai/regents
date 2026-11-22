import {createCamera} from "../../camera"
import {axialToPixel, nearestCopy, pixelToAxial, SQRT3, type Cell, type Point} from "./lattice"
import {buildMap, levelStart, type KeyMapGrid, type LayoutKind} from "./layouts"
import {
  applyPatch,
  decodeBits,
  decodeSnapshot,
  describeKey,
  drawnKeys,
  keyMarks,
  keyNear,
  lastChoosable,
  levelHeading,
  levelSale,
  nextHeldKey,
  nextKey,
  nextMarkedKey,
  onSaleLevel,
  startKey,
  step,
  type Direction,
  type KeyMapPatch,
  type KeyMapSnapshot,
  type KeyMapState,
} from "./state"
import {createPictures} from "./pictures"
import {createTiles} from "./tiles"

export type KeyMapStage = {
  /** Every key's marks. The key the page has chosen is read from `data-selected`. */
  load(snapshot: KeyMapSnapshot): void
  /** Marks for the keys that changed; ignored until the first load. */
  patch(patch: KeyMapPatch): void
  /** The key the page has chosen, or none. */
  select(key: number | null): void
  focusNext(): void
  /** The keyboard cursor moves to your next key, coming back round to the first. */
  focusMine(): void
  focusLevel(level: number): void
  /**
   * Marks the keys a search found, as the base64 bitset the page sent, and
   * moves the keyboard cursor to the first of them; the same search again
   * moves it to the next.
   */
  find(keys: string): void
  destroy(): void
}

export type KeyMapStageOptions = {
  layout: LayoutKind
  /** A key was chosen by click, tap or Enter. */
  select(key: number): void
  /**
   * Asks the page where the card close-ups of `keys`, a hundred at most, are
   * shown; `done` takes `[key, address]` for each key that has one.
   */
  pictures(keys: number[], done: (pictures: [number, string][]) => void): void
}

// How many keys' close-ups one ask names, and how long the map waits for the
// view to settle before asking, in milliseconds.
const picturesAsked = 100
const picturesWait = 150

// The map lays out, and asks for the close-ups of, at least a fifth more keys
// than the view and its cell of margin hold, so the keys just past each edge
// are ready: the fewest whole columns and rows past each side that reach it.
const moreKeys = 1.2

// The columns and rows to add past each side of `cols` by `rows` cells.
export function around(cols: number, rows: number): [number, number] {
  const [most, mostDown] = [Math.ceil(cols / 10), Math.ceil(rows / 10)]
  let best: [number, number] = [most, mostDown]
  for (let across = 0; across <= most; across++) {
    for (let down = 0; down <= mostDown; down++) {
      const more = (cols + 2 * across) * (rows + 2 * down)
      const fewest = (cols + 2 * best[0]) * (rows + 2 * best[1])
      if (more >= moreKeys * cols * rows && more < fewest) best = [across, down]
    }
  }
  return best
}

const recentreDistance = 100_000

const arrows: Record<string, Direction> = {
  ArrowLeft: "left",
  ArrowRight: "right",
  ArrowUp: "up",
  ArrowDown: "down",
}

/**
 * The key map inside its stage element: a pool of hex tiles on one layer that
 * the camera moves, repeating the fleet's map in every direction.
 */
export function createKeyMapStage(root: HTMLElement, options: KeyMapStageOptions): KeyMapStage {
  const layer = document.createElement("div")
  layer.className = "km-layer"
  layer.setAttribute("aria-hidden", "true")
  const status = document.createElement("p")
  status.className = "visually-hidden"
  status.setAttribute("aria-live", "polite")
  root.replaceChildren(layer, status)

  const motion = window.matchMedia("(prefers-reduced-motion: reduce)")
  let grid: KeyMapGrid | null = null
  let state: KeyMapState | null = null
  let selected = 0
  let cursor: Cell | null = null
  // The keys the last search found, as sent and as bits.
  let sought = ""
  let found = new Uint8Array()
  // Where each key's card close-up is shown, the keys asked about since the
  // last load, and the keys waiting to be asked about.
  const pictures = new Map<number, string>()
  const asked = new Set<number>()
  let wanted: number[] = []
  let asking = 0
  // Circumradius of a cell and the stage's size, in CSS pixels.
  let size = 0
  let width = 0
  let height = 0
  let placedAt = ""
  // Loads the close-ups a few at a time, nearest where the view is heading first.
  const loads = createPictures()

  const cursorKey = () => (cursor && grid ? grid.valueAt(...cursor) : 0)

  const choosable = (key: number) => key >= 1 && key <= lastChoosable(state!)

  const tiles = createTiles(layer, {
    marks: key => keyMarks(state!, key, selected, cursorKey(), found),
    caption: key => (key === nextKey(state!) ? "Next" : ""),
    picture: key => pictures.get(key) ?? "",
    sale: level => levelSale(onSaleLevel(grid!, state!), level),
    heading: level => levelHeading(level, levelSale(onSaleLevel(grid!, state!), level)),
  }, loads)

  // Asks where the close-ups of `keys` are shown, a hundred at a time, then
  // runs `then`. A key with no close-up is forgotten, so one whose card was
  // drawn again is not left with its old picture.
  const ask = (keys: number[], then: () => void) => {
    for (let from = 0; from < keys.length; from += picturesAsked) {
      const batch = keys.slice(from, from + picturesAsked)
      options.pictures(batch, found => {
        batch.forEach(key => pictures.delete(key))
        found.forEach(([key, address]) => pictures.set(key, address))
        tiles.refresh()
        then()
      })
    }
  }

  // Asks for the close-ups of the sold keys in view not asked about yet, once
  // the view has stayed put for a moment.
  const seek = () => {
    for (const key of tiles.keys()) {
      if (key > state!.minted || asked.has(key)) continue
      asked.add(key)
      wanted.push(key)
    }
    if (!wanted.length || asking) return
    asking = window.setTimeout(() => {
      asking = 0
      const keys = wanted
      wanted = []
      ask(keys, () => {})
    }, picturesWait)
  }

  // Starts on the close-ups of the sold keys in a view centred on world point
  // (x, y) as soon as the map sets off there, so they are on their way before
  // it lands. Each key loads once, at its copy nearest that point.
  const land = (x: number, y: number) => {
    const [colPitch, rowPitch] = [SQRT3 * size, 1.5 * size]
    const [left, top, right, bottom] = [x - width / 2, y - height / 2, x + width / 2, y + height / 2]
    const landing = new Map<number, Point>()
    for (let r = Math.floor(top / rowPitch); r <= Math.ceil(bottom / rowPitch); r++) {
      for (let q = Math.floor(left / colPitch - r / 2); q <= Math.ceil(right / colPitch - r / 2); q++) {
        const key = grid!.valueAt(q, r)
        if (key > 0 && key <= state!.minted && !landing.has(key)) landing.set(key, axialToPixel(q, r, size))
      }
    }
    const preload = () => {
      const ahead: [string, number, number][] = []
      landing.forEach(([kx, ky], key) => pictures.has(key) && ahead.push([pictures.get(key)!, kx, ky]))
      loads.ahead(ahead)
    }
    const unasked = [...landing.keys()].filter(key => !asked.has(key))
    unasked.forEach(key => asked.add(key))
    loads.focus(x, y)
    preload()
    if (unasked.length) ask(unasked, preload)
  }

  const periods = (): [Point, Point] => [axialToPixel(...grid!.periodA, size), axialToPixel(...grid!.periodB, size)]

  // Brings the camera back near the origin by whole copies of the map once it
  // has travelled far, so positions stay precise in the browser's 32-bit
  // transforms (0.01 px at this distance). The picture is unchanged, but every
  // tile is placed afresh, so it happens only every 100,000 px or so.
  const recentre = () => {
    if (Math.hypot(camera.x, camera.y) < recentreDistance) return
    const [a, b] = periods()
    const det = a[0] * b[1] - a[1] * b[0]
    const i = Math.round((camera.x * b[1] - camera.y * b[0]) / det)
    const j = Math.round((a[0] * camera.y - a[1] * camera.x) / det)
    if (i === 0 && j === 0) return
    camera.shift(-(i * a[0] + j * b[0]), -(i * a[1] + j * b[1]))
    loads.shift(-(i * a[0] + j * b[0]), -(i * a[1] + j * b[1]))
    if (cursor) cursor = [cursor[0] - i * grid!.periodA[0] - j * grid!.periodB[0], cursor[1] - i * grid!.periodA[1] - j * grid!.periodB[1]]
    placedAt = ""
  }

  const render = () => {
    if (!grid) return
    recentre()
    layer.style.transform = `translate3d(${width / 2 - camera.x}px, ${height / 2 - camera.y}px, 0)`
    loads.focus(...camera.heading())
    const cell = `${Math.floor(camera.x / (SQRT3 * size))},${Math.floor(camera.y / (1.5 * size))}`
    if (cell === placedAt) return
    placedAt = cell
    const [colPitch, rowPitch] = [SQRT3 * size, 1.5 * size]
    const [across, down] = around(width / colPitch + 3, height / rowPitch + 3)
    const [halfWidth, halfHeight] = [width / 2 + across * colPitch, height / 2 + down * rowPitch]
    tiles.place(grid, size, camera.x - halfWidth, camera.y - halfHeight, camera.x + halfWidth, camera.y + halfHeight)
    seek()
  }

  const camera = createCamera(root, {
    onFrame: render,
    onTap: (clientX, clientY) => {
      if (!grid) return
      const rect = root.getBoundingClientRect()
      const x = clientX - rect.left - root.clientLeft - width / 2 + camera.x
      const y = clientY - rect.top - root.clientTop - height / 2 + camera.y
      const value = grid.valueAt(...pixelToAxial(x, y, size))
      if (choosable(value)) choose(value)
    },
    reducedMotion: () => motion.matches,
  })

  const choose = (key: number) => {
    selected = key
    tiles.refresh()
    options.select(key)
  }

  const centreCell = () => pixelToAxial(camera.x, camera.y, size)

  // The copy of a key nearest the middle of the view.
  const nearestCell = (key: number) => {
    const [a, b] = periods()
    const [x, y] = nearestCopy(axialToPixel(...grid!.home(key), size), [camera.x, camera.y], a, b)
    return pixelToAxial(x, y, size)
  }

  // Moves the keyboard cursor, reads the key out and keeps it in view.
  const moveCursor = (cell: Cell, centre: boolean) => {
    cursor = cell
    tiles.refresh()
    status.textContent = describeKey(grid!, state!, cursorKey())
    bringIntoView(cell, centre)
  }

  const bringIntoView = (cell: Cell, centre: boolean) => {
    const [x, y] = axialToPixel(...cell, size)
    const margin = SQRT3 * size
    const hidden = Math.abs(x - camera.x) > width / 2 - margin || Math.abs(y - camera.y) > height / 2 - margin
    if (!centre && !hidden) return
    land(x, y)
    camera.glideTo(x, y)
  }

  // The cursor goes to a key shown on the map, in the view's middle.
  const focusKey = (key: number) => {
    if (grid && state && key >= 1 && key <= drawnKeys(state)) moveCursor(nearestCell(key), true)
  }

  // Draws `next`. The view stays on the keys it was showing: the camera is
  // held as an offset from the key nearest the middle, then restored from
  // that key's home cell. The first drawing opens on the chosen key, or else
  // the next key.
  const show = (next: KeyMapState) => {
    const anchor = grid && keyNear(grid, centreCell())
    const kept = anchor && grid!.valueAt(...anchor) <= drawnKeys(next) ? anchor : null
    const cursorWas = cursorKey()
    const key = kept ? grid!.valueAt(...kept) : selected || startKey(next)
    const [fromX, fromY] = kept ? axialToPixel(...kept, size) : [camera.x, camera.y]
    grid = buildMap(options.layout, drawnKeys(next))
    state = next
    tiles.clear()
    placedAt = ""
    const [x, y] = axialToPixel(...grid.home(key), size)
    if (kept) camera.shift(x - fromX, y - fromY)
    else camera.jumpTo(x, y)
    cursor = cursorWas && cursorWas <= drawnKeys(next) ? nearestCell(cursorWas) : null
    if (!cursor) status.textContent = ""
    render()
  }

  // Shortcuts with Alt, Control or Command belong to the browser. Space never
  // scrolls the page while the map has focus; like Enter, it chooses the key
  // under the cursor when there is one.
  const keydown = (event: KeyboardEvent) => {
    if (!grid || !state || event.altKey || event.ctrlKey || event.metaKey) return
    const direction = arrows[event.key]
    if (direction) {
      event.preventDefault()
      const cell = cursor ? step(grid, cursor, direction) : keyNear(grid, centreCell())
      if (cell) moveCursor(cell, false)
    } else if (event.key === "Home") {
      event.preventDefault()
      moveCursor(nearestCell(startKey(state)), true)
    } else if (event.key === "Enter" || event.key === " ") {
      if (cursor || event.key === " ") event.preventDefault()
      if (cursor && choosable(cursorKey())) choose(cursorKey())
    } else if (event.key === "Escape" && cursor) {
      cursor = null
      status.textContent = ""
      tiles.refresh()
    }
  }

  const measure = () => {
    const cell = parseFloat(getComputedStyle(root).getPropertyValue("--km-cell"))
    const nextSize = cell / SQRT3
    if (size && nextSize !== size) {
      camera.scale(nextSize / size)
      tiles.clear()
    }
    size = nextSize
    width = root.clientWidth
    height = root.clientHeight
    placedAt = ""
    render()
  }

  const resize = new ResizeObserver(measure)
  resize.observe(root)
  root.addEventListener("keydown", keydown)
  measure()

  return {
    load(snapshot) {
      // The page, not the map, keeps the chosen key.
      selected = Number(root.dataset.selected) || 0
      // Every key in view is asked about afresh; the close-ups already drawn
      // stay until the answers come.
      asked.clear()
      wanted = []
      show(decodeSnapshot(snapshot))
      root.classList.add("key-map--ready")
    },

    patch(patch) {
      if (!state) return
      const next = applyPatch(state, patch)
      // A key that changed may have its card now, so it is asked about again.
      patch.keys.forEach(([key]) => asked.delete(key))
      if (drawnKeys(next) !== drawnKeys(state)) return show(next)
      state = next
      tiles.refresh()
      seek()
    },

    select(key) {
      selected = key ?? 0
      if (!grid || !state) return
      tiles.refresh()
      if (choosable(selected)) bringIntoView(nearestCell(selected), false)
    },

    focusNext() {
      if (state) focusKey(nextKey(state))
    },

    focusMine() {
      if (!state) return
      const key = nextHeldKey(state, cursorKey())
      if (key) focusKey(key)
      else status.textContent = "You don’t hold any Keys in this fleet."
    },

    focusLevel(level) {
      focusKey(levelStart(level))
    },

    find(keys) {
      if (!state) return
      const after = keys === sought ? cursorKey() : 0
      sought = keys
      found = decodeBits(keys)
      tiles.refresh()
      const key = nextMarkedKey(state, found, after)
      if (key) focusKey(key)
    },

    destroy() {
      window.clearTimeout(asking)
      loads.destroy()
      camera.destroy()
      resize.disconnect()
      root.removeEventListener("keydown", keydown)
    },
  }
}
