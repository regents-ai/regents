/**
 * Where the particle field's grains live: every shape as one home for each
 * grain, worked out from geometry alone, with no page and no GPU, so it is the
 * same anywhere. How many grains there are follows the canvas (`grainsFor`).
 *
 * A shape is drawn in units one tall and `aspect` wide, centred on 0, with y
 * growing downwards as on the page. Each home says where its grain sits when the
 * value is 0 and when it is 1, over which stretch of the value it travels
 * between the two, over which stretch it lights, the tone of its light, which
 * way the surface under it faces, and its flags. A value change only moves
 * grains between their two places and lights them; it never asks for new homes.
 *
 * Grains lie on the surface of a solid seen from above: each part is a flat
 * shape whose edge rounds over (its bevel), and a grain is as likely anywhere on
 * that surface. Seen from above the rounded edge is foreshortened, so grains
 * crowd towards the silhouette as they would on a real rounded object, and that
 * crowding is the bright rim.
 *
 * Laying a shape out takes longer than a frame, so it is done in steps: each
 * `yield` is a place the work can stop until the next frame (`Steps`), and
 * `finish` does them all at once. A shape does not depend on the value; the
 * order its grains fly in does, and `inFlightOrder` works it out afresh.
 */

/** The most grains a field draws: a canvas of about 115,000 device pixels has them all, so the lab's always does. */
export const MAX_GRAINS = 80_000
/** Grains for each device pixel of the canvas, so a small field is as fine as a large one. */
export const GRAINS_PER_PIXEL = 0.7
/** Floats in one home: three vec4f, as the shaders read them. */
export const HOME_FLOATS = 12
/** A track grain the knob hides when it passes over it. */
export const BEHIND_KNOB = 1
/** A grain that turns round the centre with the clock, as a spinner's arc. */
export const TURNS = 2
/** How many grains a canvas of this many device pixels draws: the same rule for every field. */
export const grainsFor = ([width, height]: readonly [number, number]) =>
  Math.max(1, Math.min(MAX_GRAINS, Math.round(width * height * GRAINS_PER_PIXEL)))

/**
 * Grains that fly together as one column, top to bottom: a little fewer than
 * there are columns, so 80,000 grains make 320 columns of 250.
 */
export const columnOf = (grains: number) => Math.max(1, Math.round(Math.sqrt(grains / 1.28)))
/** How finely the flight order tells places apart across the whole shape, and down one column. */
export const ACROSS_STEPS = 4096
export const DOWN_STEPS = 64

/** A stretch of the value: below `from` nothing has happened, past `to` all of it. */
type Stretch = readonly [from: number, to: number]

const NEVER: Stretch = [2, 3]
const ALWAYS: Stretch = [-2, -1]
const WHOLE: Stretch = [0, 1]
/** How much of the value one grain takes to light, so a lit edge is soft, not stepped. */
const LIT_EDGE = 0.04
/**
 * The steepest surface counted at its true slope. A silhouette seen exactly edge
 * on would take every grain there is; past this it takes no more than five times
 * its share.
 */
const STEEPEST = 0.2
/** Cells across a part's longer side when it is drawn to be sampled. */
const CELLS = 400

/** Work done a few pieces at a time: the page runs one piece after another until its time for the frame is up. */
export type Steps<T> = Generator<void, T, void>

/** Every step at once, for work that cannot wait. */
export function finish<T>(steps: Steps<T>): T {
  for (;;) {
    const step = steps.next()
    if (step.done) return step.value
  }
}

/** Where one part's knob is, in units, when the value is 0 and when it is 1. */
export type Knob = {x0: number; y0: number; x1: number; y1: number; r: number}

export type Shape = {
  /** One home of HOME_FLOATS floats for each grain, as they were laid; `inFlightOrder` puts them in flying order. */
  homes: Float32Array<ArrayBuffer>
  /** The ball that hides the track behind it, for a switch or a slider. */
  knob: Knob | undefined
  /** Part of it turns by itself, so the picture never rests while it shows. */
  turns: boolean
  /** How much of the box it covers, in square units, so grains on a small shape can be fainter. */
  area: number
}

/** A raster of the server's drawing, already fitted into the box: 1 where it is drawn. */
export type Picture = {
  mask: Uint8Array
  width: number
  height: number
  /** Units per cell. */
  cell: number
  /** The unit position of the first cell's top left corner. */
  left: number
  top: number
}

/** A seeded random stream (mulberry32), so a shape lands the same way every time. */
export function random(seed: number): () => number {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const seedOf = (name: string) => [...name].reduce((hash, char) => Math.imul(hash ^ char.charCodeAt(0), 16777619), 2166136261)

const clamp = (x: number, low: number, high: number) => Math.min(high, Math.max(low, x))

/** How far the value has come through a stretch, from 0 to 1. */
export const through = (value: number, [from, to]: Stretch) => clamp((value - from) / Math.max(to - from, 1e-5), 0, 1)

/** The stretch over which a grain at `s` along a fill lights: at value 0 none is lit, at 1 all are. */
const litFrom = (s: number): Stretch => {
  const from = clamp(s, 0, 1) * (1 - LIT_EDGE)
  return [from, from + LIT_EDGE]
}

type Distance = (x: number, y: number) => number

/**
 * A part drawn into cells: how far each cell's centre lies inside it, in units;
 * 0 outside. A part given as a distance keeps it, so its grains keep to its true
 * edge rather than to the steps of its cells.
 */
type Solid = {width: number; height: number; cell: number; left: number; top: number; depth: Float32Array; distance?: Distance}

/** A part given as a signed distance (negative inside), drawn into cells over its bounds. */
function* solidOf(distance: Distance, left: number, top: number, right: number, bottom: number): Steps<Solid> {
  const cell = Math.max(right - left, bottom - top) / CELLS
  // A cell of nothing all round, so every solid cell has neighbours to take a slope from.
  const x0 = left - 2 * cell
  const y0 = top - 2 * cell
  const width = Math.ceil((right - left) / cell) + 4
  const height = Math.ceil((bottom - top) / cell) + 4
  const depth = new Float32Array(width * height)
  for (let j = 0; j < height; j++) {
    const y = y0 + (j + 0.5) * cell
    for (let i = 0; i < width; i++) {
      const d = distance(x0 + (i + 0.5) * cell, y)
      if (d < 0) depth[j * width + i] = -d
    }
    if (j % 8 === 7) yield
  }
  return {width, height, cell, left: x0, top: y0, depth, distance}
}

/** Squared distance along one row or column to the nearest zero (Felzenszwalb and Huttenlocher). */
function squaredDistance1d(f: Float64Array, n: number, out: Float64Array, v: Int32Array, z: Float64Array) {
  let k = 0
  v[0] = 0
  z[0] = -Infinity
  z[1] = Infinity
  for (let q = 1; q < n; q++) {
    let s = (f[q]! + q * q - (f[v[k]!]! + v[k]! * v[k]!)) / (2 * q - 2 * v[k]!)
    while (s <= z[k]!) {
      k--
      s = (f[q]! + q * q - (f[v[k]!]! + v[k]! * v[k]!)) / (2 * q - 2 * v[k]!)
    }
    k++
    v[k] = q
    z[k] = s
    z[k + 1] = Infinity
  }
  k = 0
  for (let q = 0; q < n; q++) {
    while (z[k + 1]! < q) k++
    out[q] = (q - v[k]!) * (q - v[k]!) + f[v[k]!]!
  }
}

/** A drawn picture as a solid: each drawn cell's distance in from the drawing's edge. */
function* solidOfPicture(picture: Picture): Steps<Solid> {
  // Two empty cells all round, so the edge of the raster always counts as outside.
  const width = picture.width + 4
  const height = picture.height + 4
  const far = 1e20
  const field = new Float64Array(width * height)
  for (let j = 0; j < height; j++) {
    for (let i = 0; i < width; i++) {
      const pi = i - 2
      const pj = j - 2
      const drawn = pi >= 0 && pj >= 0 && pi < picture.width && pj < picture.height && picture.mask[pj * picture.width + pi] === 1
      field[j * width + i] = drawn ? far : 0
    }
  }
  yield
  const longest = Math.max(width, height)
  const f = new Float64Array(longest)
  const out = new Float64Array(longest)
  const v = new Int32Array(longest)
  const z = new Float64Array(longest + 1)
  for (let i = 0; i < width; i++) {
    for (let j = 0; j < height; j++) f[j] = field[j * width + i]!
    squaredDistance1d(f, height, out, v, z)
    for (let j = 0; j < height; j++) field[j * width + i] = out[j]!
    if (i % 32 === 31) yield
  }
  for (let j = 0; j < height; j++) {
    for (let i = 0; i < width; i++) f[i] = field[j * width + i]!
    squaredDistance1d(f, width, out, v, z)
    for (let i = 0; i < width; i++) field[j * width + i] = out[i]!
    if (j % 32 === 31) yield
  }
  const depth = new Float32Array(width * height)
  for (let c = 0; c < depth.length; c++) {
    // The nearest empty cell's centre is half a cell past the edge.
    if (field[c]! > 0) depth[c] = Math.max(Math.sqrt(field[c]!) - 0.5, 0.25) * picture.cell
  }
  return {width, height, cell: picture.cell, left: picture.left - 2 * picture.cell, top: picture.top - 2 * picture.cell, depth}
}

/** A solid's surface, ready to be sampled with each cell as likely as its share of the surface. */
type Surface = {solid: Solid; bevel: number; cells: Int32Array; running: Float64Array; area: number}

function* surfaceOf(solid: Solid, bevel: number): Steps<Surface> {
  let inside = 0
  for (let c = 0; c < solid.depth.length; c++) if (solid.depth[c]! > 0) inside++
  const cells = new Int32Array(inside)
  const running = new Float64Array(inside)
  let k = 0
  let sum = 0
  for (let c = 0; c < solid.depth.length; c++) {
    if (solid.depth[c]! <= 0) continue
    const tilt = 1 - Math.min(solid.depth[c]! / bevel, 1)
    sum += 1 / Math.max(Math.sqrt(1 - tilt * tilt), STEEPEST)
    cells[k] = c
    running[k] = sum
    k++
    if (k % 16384 === 0) yield
  }
  return {solid, bevel, cells, running, area: inside * solid.cell * solid.cell}
}

/** One point on a surface: where it is, and the sideways part of the way the surface faces there. */
type Point = {x: number; y: number; nx: number; ny: number}

function sample(surface: Surface, rand: () => number, point: Point) {
  const {solid, running, cells} = surface
  const pick = rand() * running[running.length - 1]!
  let low = 0
  let high = running.length - 1
  while (low < high) {
    const mid = (low + high) >> 1
    if (running[mid]! < pick) low = mid + 1
    else high = mid
  }
  const c = cells[low]!
  const i = c % solid.width
  const j = (c - i) / solid.width
  const d = solid.depth
  const gx = d[c + 1]! - d[c - 1]!
  const gy = d[c + solid.width]! - d[c - solid.width]!
  const slope = Math.hypot(gx, gy)
  // The surface faces out over the edge as much as it has rounded over.
  const tilt = 1 - Math.min(d[c]! / surface.bevel, 1)
  // The cell's centre is inside, so a point drawn again until it is inside soon is.
  do {
    point.x = solid.left + (i + rand()) * solid.cell
    point.y = solid.top + (j + rand()) * solid.cell
  } while (solid.distance && solid.distance(point.x, point.y) > 0)
  point.nx = slope > 0 ? (-gx / slope) * tilt : 0
  point.ny = slope > 0 ? (-gy / slope) * tilt : 0
}

type Home = {
  x0: number
  y0: number
  x1: number
  y1: number
  move: Stretch
  lit: Stretch
  tone: number
  flags: number
}

type Part = {
  surface: Surface
  /** How many grains it takes against the other parts: its surface, unless it says otherwise. */
  share?: number
  home(point: Point, rand: () => number): Home
}

const shareOf = (part: Part) => part.share ?? part.surface.running[part.surface.running.length - 1]! * part.surface.solid.cell ** 2

function* assemble(name: string, parts: readonly Part[], grains: number): Steps<Float32Array<ArrayBuffer>> {
  const rand = random(seedOf(name))
  const homes = new Float32Array(grains * HOME_FLOATS)
  const total = parts.reduce((sum, part) => sum + shareOf(part), 0)
  const point: Point = {x: 0, y: 0, nx: 0, ny: 0}
  let at = 0
  for (const [index, part] of parts.entries()) {
    const count = index === parts.length - 1 ? grains - at : Math.round((grains * shareOf(part)) / total)
    for (let k = 0; k < count; k++) {
      sample(part.surface, rand, point)
      const home = part.home(point, rand)
      const slot = (at + k) * HOME_FLOATS
      homes[slot] = home.x0
      homes[slot + 1] = home.y0
      homes[slot + 2] = home.x1
      homes[slot + 3] = home.y1
      homes[slot + 4] = point.nx
      homes[slot + 5] = point.ny
      homes[slot + 6] = home.move[0]
      homes[slot + 7] = home.move[1]
      homes[slot + 8] = home.lit[0]
      homes[slot + 9] = home.lit[1]
      homes[slot + 10] = home.tone
      homes[slot + 11] = home.flags
      if (k % 2048 === 2047) yield
    }
    at += count
  }
  return homes
}

/**
 * `order` (a run of grain numbers) sorted by `key`, coarsely: counted into
 * `steps` buckets between the run's least and greatest key, so it takes one
 * pass whatever the length. Grains in one bucket keep the order they came in.
 */
function sortRun(order: Uint32Array, key: Float32Array, steps: number, counts: Uint32Array, scratch: Uint32Array) {
  let low = Infinity
  let high = -Infinity
  for (let k = 0; k < order.length; k++) {
    low = Math.min(low, key[order[k]!]!)
    high = Math.max(high, key[order[k]!]!)
  }
  const per = (steps - 1) / Math.max(high - low, 1e-9)
  counts.fill(0)
  for (let k = 0; k < order.length; k++) counts[Math.floor((key[order[k]!]! - low) * per)]!++
  let sum = 0
  for (let b = 0; b < steps; b++) {
    const count = counts[b]!
    counts[b] = sum
    sum += count
  }
  for (let k = 0; k < order.length; k++) scratch[counts[Math.floor((key[order[k]!]! - low) * per)]!++] = order[k]!
  order.set(scratch.subarray(0, order.length))
}

/**
 * A shape's homes in the order its grains fly, where they sit at this value: in
 * columns from left to right, each run from top to bottom. A grain keeps its
 * number from shape to shape, so the top left of one shape flies to the top
 * left of the next, and the cloud moves across as one sheet instead of
 * crossing itself.
 */
export function* inFlightOrder(homes: Float32Array<ArrayBuffer>, value: number): Steps<Float32Array<ArrayBuffer>> {
  const grains = homes.length / HOME_FLOATS
  const column = columnOf(grains)
  const across = new Float32Array(grains)
  const down = new Float32Array(grains)
  for (let g = 0; g < grains; g++) {
    const at = g * HOME_FLOATS
    const m = clamp((value - homes[at + 6]!) / Math.max(homes[at + 7]! - homes[at + 6]!, 1e-5), 0, 1)
    across[g] = homes[at]! + (homes[at + 2]! - homes[at]!) * m
    down[g] = homes[at + 1]! + (homes[at + 3]! - homes[at + 1]!) * m
  }
  yield
  const order = new Uint32Array(grains)
  for (let g = 0; g < grains; g++) order[g] = g
  const scratch = new Uint32Array(grains)
  sortRun(order, across, ACROSS_STEPS, new Uint32Array(ACROSS_STEPS), scratch)
  yield
  const counts = new Uint32Array(DOWN_STEPS)
  for (let start = 0; start < grains; start += column) {
    sortRun(order.subarray(start, start + column), down, DOWN_STEPS, counts, scratch)
  }
  yield
  const ordered = new Float32Array(homes.length)
  for (let slot = 0; slot < grains; slot++) {
    const from = order[slot]! * HOME_FLOATS
    const to = slot * HOME_FLOATS
    for (let f = 0; f < HOME_FLOATS; f++) ordered[to + f] = homes[from + f]!
    if (slot % 4096 === 4095) yield
  }
  return ordered
}

const areaOf = (parts: readonly Part[]) => parts.reduce((sum, part) => sum + part.surface.area, 0)

// Signed distances, negative inside.
const circle =
  (r: number): Distance =>
  (x, y) =>
    Math.hypot(x, y) - r

/** A horizontal stadium round the segment from (a, 0) to (b, 0). */
const stadium =
  (a: number, b: number, r: number): Distance =>
  (x, y) =>
    Math.hypot(x - clamp(x, a, b), y) - r

const band =
  (radius: number, half: number): Distance =>
  (x, y) =>
    Math.abs(Math.hypot(x, y) - radius) - half

const roundedSquare = (x: number, y: number, half: number, corner: number) => {
  const qx = Math.abs(x) - half + corner
  const qy = Math.abs(y) - half + corner
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - corner
}

/** Clockwise turns from twelve o'clock, from 0 to 1. */
const turnOf = (x: number, y: number) => (Math.atan2(x, -y) / (2 * Math.PI) + 1) % 1

const still = (point: Point, lit: Stretch, tone: number, flags = 0): Home => ({
  x0: point.x,
  y0: point.y,
  x1: point.x,
  y1: point.y,
  move: WHOLE,
  lit,
  tone,
  flags,
})

/** A track with a ball that rolls along it, lighting the track behind it (switch and slider). */
function* rollingKnob(name: string, aspect: number, grains: number, track: number, knob: number, trackBevel: number): Steps<Shape> {
  const ends = aspect / 2 - 0.5
  const across = (x: number) => (x + ends) / (2 * ends)
  const parts: Part[] = [
    {
      surface: yield* surfaceOf(yield* solidOf(stadium(-ends, ends, track), -aspect / 2, -0.5, aspect / 2, 0.5), trackBevel),
      home: point => still(point, litFrom(across(point.x)), clamp(across(point.x), 0, 1), BEHIND_KNOB),
    },
    {
      surface: yield* surfaceOf(yield* solidOf(circle(knob), -knob, -knob, knob, knob), knob),
      home: point => ({x0: point.x - ends, y0: point.y, x1: point.x + ends, y1: point.y, move: WHOLE, lit: NEVER, tone: 0, flags: 0}),
    },
  ]
  return {homes: yield* assemble(name, parts, grains), knob: {x0: -ends, y0: 0, x1: ends, y1: 0, r: knob}, turns: false, area: areaOf(parts)}
}

const switchShape = (aspect: number, grains: number) => rollingKnob("switch", aspect, grains, 0.5, 0.39, 0.2)

const sliderShape = (aspect: number, grains: number) => rollingKnob("slider", aspect, grains, 0.1, 0.46, 0.1)

function* barShape(aspect: number, grains: number): Steps<Shape> {
  const ends = aspect / 2 - 0.5
  const parts: Part[] = [
    {
      surface: yield* surfaceOf(yield* solidOf(stadium(-ends, ends, 0.5), -aspect / 2, -0.5, aspect / 2, 0.5), 0.32),
      home: point => {
        const s = clamp((point.x + aspect / 2) / aspect, 0, 1)
        return still(point, litFrom(s), s)
      },
    },
  ]
  return {homes: yield* assemble("bar", parts, grains), knob: undefined, turns: false, area: areaOf(parts)}
}

function* ringShape(grains: number): Steps<Shape> {
  const parts: Part[] = [
    {
      surface: yield* surfaceOf(yield* solidOf(band(0.37, 0.1), -0.5, -0.5, 0.5, 0.5), 0.08),
      home: point => {
        const s = turnOf(point.x, point.y)
        return still(point, litFrom(s), s)
      },
    },
  ]
  return {homes: yield* assemble("ring", parts, grains), knob: undefined, turns: false, area: areaOf(parts)}
}

/** Three quarters of a ring with round ends, turning clockwise, brightest at its leading end. */
function* spinnerShape(grains: number): Steps<Shape> {
  const radius = 0.36
  const half = 0.085
  const span = 0.75
  const arc: Distance = (x, y) => {
    const turn = turnOf(x, y)
    if (turn <= span) return Math.abs(Math.hypot(x, y) - radius) - half
    const end = (t: number) => [Math.sin(2 * Math.PI * t) * radius, -Math.cos(2 * Math.PI * t) * radius] as const
    const [ax, ay] = end(0)
    const [bx, by] = end(span)
    return Math.min(Math.hypot(x - ax, y - ay), Math.hypot(x - bx, y - by)) - half
  }
  const parts: Part[] = [
    {
      surface: yield* surfaceOf(yield* solidOf(arc, -0.5, -0.5, 0.5, 0.5), half),
      home: point => still(point, ALWAYS, 1 - clamp(turnOf(point.x, point.y) / span, 0, 1), TURNS),
    },
  ]
  return {homes: yield* assemble("spinner", parts, grains), knob: undefined, turns: true, area: areaOf(parts)}
}

/** A pen's line through `points`: for any spot, how far it lies from the line and how far along it, from where the pen starts (0) to where it lifts (1). */
function penLine(points: readonly (readonly [number, number])[]) {
  const lengths = points.slice(1).map((p, k) => Math.hypot(p[0] - points[k]![0], p[1] - points[k]![1]))
  const total = lengths.reduce((sum, length) => sum + length, 0)
  return (x: number, y: number) => {
    let best = Infinity
    let along = 0
    let before = 0
    for (let k = 0; k < lengths.length; k++) {
      const length = lengths[k]!
      const [ax, ay] = points[k]!
      const [bx, by] = points[k + 1]!
      const t = clamp(((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / (length * length), 0, 1)
      const d = Math.hypot(x - (ax + (bx - ax) * t), y - (ay + (by - ay) * t))
      if (d < best) {
        best = d
        along = (before + t * length) / total
      }
      before += length
    }
    return {distance: best, along}
  }
}

/** A box, and a tick its grains fly in to draw as the value rises, from the pen's start to its lift. */
function* checkboxShape(grains: number): Steps<Shape> {
  const frameHalf = 0.055
  const tick = penLine([[-0.2, 0.01], [-0.06, 0.15], [0.22, -0.15]])
  const tickHalf = 0.07
  const frame = yield* surfaceOf(yield* solidOf((x, y) => Math.abs(roundedSquare(x, y, 0.36, 0.12)) - frameHalf, -0.5, -0.5, 0.5, 0.5), frameHalf)
  const resting: Point = {x: 0, y: 0, nx: 0, ny: 0}
  const parts: Part[] = [
    {
      surface: frame,
      home: point => still(point, [0.55, 0.95], clamp(point.x + 0.5, 0, 1)),
    },
    {
      surface: yield* surfaceOf(yield* solidOf((x, y) => tick(x, y).distance - tickHalf, -0.35, -0.3, 0.35, 0.3), tickHalf),
      home: (point, rand) => {
        // Unticked, the grain waits on the box; it flies in as the pen reaches its place.
        sample(frame, rand, resting)
        const s = tick(point.x, point.y).along
        const stretch: Stretch = [s * 0.7, s * 0.7 + 0.3]
        return {x0: resting.x, y0: resting.y, x1: point.x, y1: point.y, move: stretch, lit: stretch, tone: s, flags: 0}
      },
    },
  ]
  return {homes: yield* assemble("checkbox", parts, grains), knob: undefined, turns: false, area: areaOf(parts)}
}

/** Three rings in a row and one lit ball that rolls to the chosen one: 0, a half or 1. */
function* radioShape(aspect: number, grains: number): Steps<Shape> {
  const gap = aspect / 3
  const ring = yield* surfaceOf(yield* solidOf(band(0.34, 0.06), -0.5, -0.5, 0.5, 0.5), 0.06)
  const dot = 0.19
  const parts: Part[] = [-1, 0, 1].map(k => ({
    surface: ring,
    home: point => still({...point, x: point.x + k * gap}, NEVER, 0),
  }))
  parts.push({
    surface: yield* surfaceOf(yield* solidOf(circle(dot), -dot, -dot, dot, dot), dot),
    home: point => ({x0: point.x - gap, y0: point.y, x1: point.x + gap, y1: point.y, move: WHOLE, lit: ALWAYS, tone: 0.5, flags: 0}),
  })
  return {homes: yield* assemble("radio", parts, grains), knob: undefined, turns: false, area: areaOf(parts)}
}

/** A row of `count` balls; the first n light when the value is n of `count`. */
function* stepsShape(count: number, aspect: number, grains: number): Steps<Shape> {
  const gap = aspect / count
  const r = Math.min(0.3, gap * 0.3)
  const ball = yield* surfaceOf(yield* solidOf(circle(r), -r, -r, r, r), r)
  const parts: Part[] = Array.from({length: count}, (_, k) => ({
    surface: ball,
    home: (point: Point) =>
      still({...point, x: point.x + (k - (count - 1) / 2) * gap}, [(k + 0.55) / count, (k + 0.95) / count], k / Math.max(count - 1, 1)),
  }))
  return {homes: yield* assemble(`steps:${count}`, parts, grains), knob: undefined, turns: false, area: areaOf(parts)}
}

/**
 * The shape a control's name asks for, drawn to fill a box `aspect` wide and one
 * tall, in `grains` grains. A drawing the server put in the field is a picture;
 * see `pictureShape`.
 */
export function controlShape(name: string, aspect: number, grains: number): Steps<Shape> {
  const steps = /^steps:([2-8])$/.exec(name)
  if (steps) return stepsShape(Number(steps[1]), aspect, grains)
  switch (name) {
    case "switch":
      return switchShape(aspect, grains)
    case "slider":
      return sliderShape(aspect, grains)
    case "bar":
      return barShape(aspect, grains)
    case "ring":
      return ringShape(grains)
    case "spinner":
      return spinnerShape(grains)
    case "checkbox":
      return checkboxShape(grains)
    case "radio":
      return radioShape(aspect, grains)
    default:
      throw new Error(`The particle field has no shape called ${name}`)
  }
}

/**
 * A picture the server drew, as grains on its surface: a stroke becomes a tube
 * and a filled block a tile with rounded edges. The value lights it from left to right.
 */
export function* pictureShape(name: string, picture: Picture, grains: number): Steps<Shape> {
  const solid = yield* solidOfPicture(picture)
  let thickest = 0
  let leftmost = Infinity
  let rightmost = -Infinity
  for (let c = 0; c < solid.depth.length; c++) {
    if (solid.depth[c]! <= 0) continue
    thickest = Math.max(thickest, solid.depth[c]!)
    const x = solid.left + ((c % solid.width) + 0.5) * solid.cell
    leftmost = Math.min(leftmost, x)
    rightmost = Math.max(rightmost, x)
  }
  if (thickest === 0) throw new Error(`The drawing for ${name} is empty`)
  const span = Math.max(rightmost - leftmost, solid.cell)
  const parts: Part[] = [
    {
      surface: yield* surfaceOf(solid, thickest * 0.7),
      home: point => {
        const s = clamp((point.x - leftmost) / span, 0, 1)
        return still(point, litFrom(s), s)
      },
    },
  ]
  return {homes: yield* assemble(name, parts, grains), knob: undefined, turns: false, area: areaOf(parts)}
}
