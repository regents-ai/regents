/**
 * The datascape as it stands right now: where the camera is and how fast it is
 * going, the cells near enough to be drawn, and the sparks in the air.
 *
 * The camera is steered by where the pointer is across the picture: near the
 * middle it rests, and the nearer an edge the faster it flies that way. Cells are made as they come
 * into reach and dropped once they are well out of it; whoever watches the
 * field is told of each, so it can bring a cell's panels in.
 */
import {CELL, KIND, LAYERS, cellContents, type Colour, type PanelSeed, type TubeSeed} from "./world"

/** Fastest the camera ever flies, in world units a second. */
export const SPEED = 2200
/** A smaller picture flies slower: its longer side this many times a second, so panels still have time to open. */
const PACE = 1.4
/** How far ahead of the camera cells are brought in, in seconds of travel, so each is ready before it comes into sight. */
const LEAD = 0.45
/** How long the camera takes to answer the pointer, in seconds. */
const LAG = 0.55
/** The share of the picture round its middle where the pointer steers nothing, unless the field is told otherwise. */
export const REST = 0.1
/** The most of the picture a calm zone may take, so there is always room left to steer. */
const MOST_CALM = 0.9
/** How sharply speed rises towards an edge. */
const CURVE = 1.6
/** How far the picture leans into a turn, in radians, at full speed. */
const LEAN = (2.5 * Math.PI) / 180
/** How far the camera pulls back at full speed, as a share of the picture. */
const PULL = 0.22
/** How fast the camera drifts while nothing steers it, in world units a second. */
const DRIFT: readonly [number, number] = [12, 7]
/** Cells kept beyond the picture's edge, so a panel is ready before it shows. */
const MARGIN = 0.35
/** How much further out a cell must be before it is dropped, so one on the edge does not flicker. */
const KEEP = 0.9
/** How much larger a panel under the pointer grows. */
export const EXPANSION = 0.22
/** How much faster a panel under the pointer runs. */
const HURRY = 5
/** Longest step the field takes, so a tab coming back does not jump it. */
const MAX_STEP = 1 / 20

/** A panel in the picture, with the numbers its motion changes. */
export type Panel = PanelSeed & {
  readonly layer: number
  /** From 0, not there, to 1, there. It may pass 1 on the way in. */
  grow: number
  /** How white the panel is, from 0 to 1. */
  flash: number
  /** How much of what the panel shows has been put together, from 0 to 1. */
  assemble: number
  /** How far the panel has grown under the pointer, from 0 to 1. */
  hover: number
  /** The panel's own clock, in seconds. It runs faster under the pointer. */
  clock: number
  /** Whether the picture has shown where the panel is, and so whoever watches was told to open it. */
  seen: boolean
}

export type Tube = TubeSeed & {
  /** How much of the tube's length has been drawn, in world units. */
  drawn: number
  /** Whether the picture has shown the tube's cell, and so whoever watches was told to draw it. */
  seen: boolean
}

export type Cell = {
  readonly key: string
  readonly layer: number
  readonly column: number
  readonly row: number
  readonly panels: Panel[]
  readonly tube: Tube | null
}

export type Spark = {
  readonly x: number
  readonly y: number
  /** How far it flies in all, in world units. */
  readonly dx: number
  readonly dy: number
  readonly born: number
  readonly life: number
  readonly size: number
  readonly layer: number
  readonly colour: Colour
}

/** Whoever opens panels and draws tubes as they come into sight, lets cells go, and answers the pointer coming to rest on a panel. */
export type Watcher = {
  /** A panel has come into sight, this far from the picture's middle as a share of the picture. */
  open(panel: Panel, distance: number): void
  /** A tube's cell has come into sight, likewise. */
  draw(tube: Tube, distance: number): void
  leave(cell: Cell): void
  /** The panel now under the pointer, or null once it is over none. */
  rest(panel: Panel | null): void
  /** Told only when it changes: true while the pointer is outside the calm zone and steering, false once it is back inside or away. */
  steer(steering: boolean): void
}

export type Field = {
  readonly camera: {x: number; y: number; vx: number; vy: number; lean: number; zoom: number}
  readonly cells: Map<string, Cell>
  readonly sparks: Spark[]
  /** Seconds the field has run. */
  time: number
  /** Where the pointer is, measured from the picture's middle in CSS pixels, or null when it is away. */
  pointer: readonly [number, number] | null
  /** Where the pointer steers nothing, round the picture's middle: shares of half its width and of half its height. */
  calm: readonly [number, number]
  /** Moves the field on by this many seconds, for a picture this many CSS pixels wide and tall. */
  advance(elapsed: number, width: number, height: number): void
  /** The panel drawn under a point, measured from the picture's middle in CSS pixels. */
  panelAt(x: number, y: number): Panel | null
  /** Throws a few sparks out from a panel. */
  burst(panel: Panel, count: number): void
}

/** The fastest the camera flies over a picture this many CSS pixels wide and tall. */
export const topSpeed = (width: number, height: number) => Math.min(SPEED, PACE * Math.max(width, height))

/**
 * How fast the camera should go for a pointer this far from the middle on one axis, from -1 to 1,
 * when this share of that half of the picture is calm: nothing inside it, top speed at the edge.
 */
export const steerSpeed = (offset: number, top: number, calm = REST) => {
  const rest = Math.min(MOST_CALM, Math.max(0, calm))
  const reach = Math.max(0, (Math.abs(offset) - rest) / (1 - rest))
  return Math.sign(offset) * Math.min(1, reach) ** CURVE * top
}

/** The calm zone round a box this many CSS pixels wide and tall, centred in a picture this size, reaching this far past its edges. */
export const calmAround = (
  box: readonly [number, number],
  margin: number,
  picture: readonly [number, number],
): [number, number] => [(box[0] / 2 + margin) / (picture[0] / 2), (box[1] / 2 + margin) / (picture[1] / 2)]

/** A panel that answers the pointer: dust and labels are too small to. */
const answers = (panel: Panel) => panel.kind !== KIND.dust && panel.kind !== KIND.label

export function createField(watcher: Watcher): Field {
  const camera = {x: 0, y: 0, vx: 0, vy: 0, lean: 0, zoom: 1}
  const cells = new Map<string, Cell>()
  const sparks: Spark[] = []
  let resting: Panel | null = null
  let steering = false
  // A run of numbers for the sparks only; what the world holds never depends on it.
  let scatter = 0x9e3779b9
  const chance = () => {
    scatter = (Math.imul(scatter ^ (scatter >>> 15), 0x2c1b3c6d) + 0x6d2b79f5) >>> 0
    return scatter / 4294967296
  }

  /** Half of what a layer shows of the world, across and down. The picture leans, so its corners reach a little further than its sides. */
  const shown = (layer: number, width: number, height: number) => {
    const scale = LAYERS[layer]!.depth * camera.zoom
    return {scale, halfWidth: (width / 2 / scale) * 1.06, halfHeight: (height / 2 / scale) * 1.06}
  }

  const reach = (layer: number, width: number, height: number, margin: number) => {
    const view = shown(layer, width, height)
    const halfWidth = view.halfWidth + CELL * margin
    const halfHeight = view.halfHeight + CELL * margin
    // It reaches further the way the camera is going, by as far as it will fly in the lead time.
    const aheadX = camera.vx * LEAD
    const aheadY = camera.vy * LEAD
    return {
      left: Math.floor((camera.x + Math.min(0, aheadX) - halfWidth) / CELL),
      right: Math.floor((camera.x + Math.max(0, aheadX) + halfWidth) / CELL),
      top: Math.floor((camera.y + Math.min(0, aheadY) - halfHeight) / CELL),
      bottom: Math.floor((camera.y + Math.max(0, aheadY) + halfHeight) / CELL),
    }
  }

  const sync = (width: number, height: number) => {
    for (const [key, cell] of cells) {
      const kept = reach(cell.layer, width, height, MARGIN + KEEP)
      if (cell.column >= kept.left && cell.column <= kept.right && cell.row >= kept.top && cell.row <= kept.bottom) continue
      cells.delete(key)
      watcher.leave(cell)
    }
    for (let layer = 0; layer < LAYERS.length; layer++) {
      const near = reach(layer, width, height, MARGIN)
      for (let row = near.top; row <= near.bottom; row++) {
        for (let column = near.left; column <= near.right; column++) {
          const key = `${layer}:${column}:${row}`
          if (cells.has(key)) continue
          const contents = cellContents(layer, column, row)
          const cell: Cell = {
            key,
            layer,
            column,
            row,
            panels: contents.panels.map(seed => ({...seed, layer, grow: 0, flash: 0, assemble: 0, hover: 0, clock: seed.seed * 40, seen: false})),
            tube: contents.tube && {...contents.tube, drawn: 0, seen: false},
          }
          cells.set(key, cell)
        }
      }
    }
  }

  /** Tells whoever watches of each panel and tube the picture has just come to show, so it opens in sight and not before. */
  const sight = (width: number, height: number) => {
    const longest = Math.max(width, height)
    for (const cell of cells.values()) {
      const {scale, halfWidth, halfHeight} = shown(cell.layer, width, height)
      const shows = (x: number, y: number, w: number, h: number) =>
        Math.abs(x - camera.x) <= halfWidth + w && Math.abs(y - camera.y) <= halfHeight + h
      const distance = (x: number, y: number) => (Math.hypot(x - camera.x, y - camera.y) * scale) / longest
      for (const panel of cell.panels) {
        if (panel.seen || !shows(panel.x, panel.y, panel.w, panel.h)) continue
        panel.seen = true
        watcher.open(panel, distance(panel.x, panel.y))
      }
      const tube = cell.tube
      if (!tube || tube.seen) continue
      const [x, y] = [(cell.column + 0.5) * CELL, (cell.row + 0.5) * CELL]
      if (!shows(x, y, CELL / 2, CELL / 2)) continue
      tube.seen = true
      watcher.draw(tube, distance(x, y))
    }
  }

  const field: Field = {
    camera,
    cells,
    sparks,
    time: 0,
    pointer: null,
    calm: [REST, REST],
    advance(elapsed, width, height) {
      const dt = Math.min(MAX_STEP, elapsed)
      field.time += dt
      const top = topSpeed(width, height)
      const steered: readonly [number, number] | null = field.pointer && [
        steerSpeed(field.pointer[0] / (width / 2), top, field.calm[0]),
        steerSpeed(field.pointer[1] / (height / 2), top, field.calm[1]),
      ]
      const now = steered !== null && (steered[0] !== 0 || steered[1] !== 0)
      if (now !== steering) {
        steering = now
        watcher.steer(now)
      }
      const [aimX, aimY] = steered ?? DRIFT
      const answer = 1 - Math.exp((-dt * 3) / LAG)
      camera.vx += (aimX - camera.vx) * answer
      camera.vy += (aimY - camera.vy) * answer
      camera.x += camera.vx * dt
      camera.y += camera.vy * dt
      const pace = Math.min(1, Math.hypot(camera.vx, camera.vy) / top)
      camera.lean += ((-camera.vx / top) * LEAN - camera.lean) * answer
      camera.zoom += (1 - PULL * pace - camera.zoom) * answer
      sync(width, height)
      sight(width, height)
      for (const cell of cells.values()) {
        for (const panel of cell.panels) panel.clock += dt * (1 + panel.hover * HURRY)
      }
      // Sparks are added oldest first, so the spent ones gather at the front; one still waiting behind a
      // longer-lived spark is drawn at no size until its turn comes.
      let dead = 0
      while (dead < sparks.length && field.time - sparks[dead]!.born > sparks[dead]!.life) dead += 1
      if (dead > 0) sparks.splice(0, dead)
      // The world moves under a pointer that is holding still, so what it rests on is read again each step.
      const under = field.pointer ? field.panelAt(field.pointer[0], field.pointer[1]) : null
      if (under !== resting) {
        resting = under
        watcher.rest(under)
      }
    },
    panelAt(x, y) {
      const cos = Math.cos(-camera.lean)
      const sin = Math.sin(-camera.lean)
      const levelX = x * cos - y * sin
      const levelY = x * sin + y * cos
      // The nearest layer is drawn last, and within a layer the last cell and panel are on top.
      for (let layer = LAYERS.length - 1; layer >= 0; layer--) {
        const scale = LAYERS[layer]!.depth * camera.zoom
        const worldX = camera.x + levelX / scale
        const worldY = camera.y + levelY / scale
        let found: Panel | null = null
        for (const cell of cells.values()) {
          if (cell.layer !== layer) continue
          for (const panel of cell.panels) {
            if (!answers(panel) || panel.grow < 0.5) continue
            const size = 1 + panel.hover * EXPANSION
            if (Math.abs(worldX - panel.x) <= panel.w * size && Math.abs(worldY - panel.y) <= panel.h * size) found = panel
          }
        }
        if (found) return found
      }
      return null
    },
    burst(panel, count) {
      for (let index = 0; index < count; index++) {
        const turn = chance() * Math.PI * 2
        const far = (0.6 + chance() * 1.2) * Math.max(panel.w, panel.h) + 30
        sparks.push({
          x: panel.x + (chance() * 2 - 1) * panel.w,
          y: panel.y + (chance() * 2 - 1) * panel.h,
          dx: Math.cos(turn) * far,
          dy: Math.sin(turn) * far,
          born: field.time,
          life: 0.5 + chance() * 0.6,
          size: 1.5 + chance() * 3,
          layer: panel.layer,
          colour: chance() < 0.4 ? [1, 1, 1] : chance() < 0.5 ? panel.a : panel.b,
        })
      }
    },
  }
  return field
}
