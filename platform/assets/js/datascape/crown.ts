/**
 * The crown: the Regents mark made of the datascape's own panels. Each of its thirteen
 * squares is a panel taken out of the field, flown to its place in the mark and held there,
 * drawn over the field in the field's own look, and turned a few degrees towards the pointer
 * on a spring. Flying the field lets the squares go: each is put back into the world as a
 * panel, where it is on the page, and the flight carries it away. The crown forms again from
 * whatever panels are nearest once the field rests.
 *
 * Everything here is measured on the page, in CSS pixels from the picture's middle, as the
 * pointer is. The driver animates the numbers; the renderer draws them.
 */
import {HURRY, type Field, type Panel} from "./field"
import type {Quiet} from "./renderer"
import {CELL, KIND, LAYERS, type Colour, type Kind} from "./world"

/** The mark's squares, as a column and a row of its five by three grid. */
const SLOTS: readonly (readonly [number, number])[] = [
  [0, 0], [2, 0], [4, 0],
  [0, 1], [1, 1], [2, 1], [3, 1], [4, 1],
  [0, 2], [1, 2], [2, 2], [3, 2], [4, 2],
]
/** The mark in its own units: a square's side, the step from one square to the next, and the whole mark. */
const SIDE = 34
const STEP = 36
export const MARK_WIDTH = 4 * STEP + SIDE
export const MARK_HEIGHT = 2 * STEP + SIDE
/** Room kept clear round the mark when the field goes quiet round it, in CSS pixels. */
export const CROWN_ROOM = 24
/** The kinds of panel that fill a square edge to edge, so the mark reads as the mark. */
const FILLING: ReadonlySet<Kind> = new Set([KIND.mosaic, KIND.gradient, KIND.bars])
/** A panel must have grown at least this far to be seen leaving for the crown. */
const SHOWN = 0.3
/** Added to how far a panel out of sight is, so every panel in sight is taken before any other. */
const OUT_OF_SIGHT = 1e6
/** The nearest layer, where a square let go is put back into the world. */
const NEAREST = LAYERS.length - 1
/** How far the crown turns towards a pointer at the window's edge, in radians: across, then up and down. */
const YAW = (6 * Math.PI) / 180
const TILT = (4 * Math.PI) / 180
/** The spring the turn follows. */
const STIFFNESS = 120
const DAMPING = 18
/** A glitch on one square: how long it lasts, then the shortest and longest wait before the next, in seconds. */
export const GLITCH_TIME = 0.24
const GLITCH_WAIT: readonly [number, number] = [4.5, 10]
/** Longest step the crown takes, as the field does. */
const MAX_STEP = 1 / 20

export type Square = {
  /** Which of the mark's squares it is. */
  readonly slot: number
  /** Its place in the mark, from the mark's middle, in the mark's units. */
  readonly mx: number
  readonly my: number
  readonly kind: Kind
  readonly seed: number
  readonly a: Colour
  readonly b: Colour
  readonly entrance: number
  /** The panel it was taken from, hidden in the field while the square is out of it. */
  readonly source: Panel | null
  /** Where it set out from: its middle, then half its width and height. */
  readonly from: readonly [number, number, number, number]
  /** How far along its flight, from 0 where it set out to 1 in its place in the mark. */
  flown: number
  /** How lit and how solid it is: its layer's light and its own solidness where it set out, 1 in the mark. */
  light: number
  alpha: number
  grow: number
  flash: number
  assemble: number
  hover: number
  clock: number
}

export type Crown = {
  /** The squares in the mark's order, or none while there is no crown. */
  readonly squares: Square[]
  /** Where the mark sits: its middle from the picture's middle, and CSS pixels in one of its units. */
  readonly place: {x: number; y: number; unit: number}
  /** How quiet the field is round the crown, from 0 to 1. */
  quiet: number
  /** Where the pointer is, as a share of half the window each way from the crown's middle, or null when it is away. */
  aim: readonly [number, number] | null
  /** How far the crown is turned: across, then up and down, in radians. */
  readonly turn: {yaw: number; pitch: number}
  /** The square glitching now, or -1, and how long ago its glitch began, in seconds. */
  readonly glitch: {square: number; age: number}
  /**
   * Takes a panel out of the field for each square, the nearest in sight first, and builds
   * the squares setting out from them, for a picture this many CSS pixels wide and tall
   * whose words and bar are quiet as `words` says.
   */
  take(width: number, height: number, words: Quiet): Square[]
  /**
   * Puts each square back into the world where it is drawn, on the nearest layer, and returns
   * the panels they became; one still waiting to set out just gives its panel back.
   */
  letGo(): Panel[]
  /** Takes the squares away and gives the field back the panels they came from. */
  clear(): void
  /** Where a square is drawn: its middle, then half its width and height. */
  rect(square: Square): [number, number, number, number]
  /** The square drawn under a point, measured from the picture's middle. */
  squareAt(x: number, y: number): Square | null
  /** Moves the turn and the glitches on by this many seconds. */
  advance(elapsed: number): void
}

export function createCrown(field: Field): Crown {
  const squares: Square[] = []
  const place = {x: 0, y: 0, unit: 0}
  const turn = {yaw: 0, pitch: 0}
  const speed = {yaw: 0, pitch: 0}
  const glitch = {square: -1, age: 0}
  // A run of numbers for the glitches only.
  let scatter = 0x2545f491
  const chance = () => {
    scatter = (Math.imul(scatter ^ (scatter >>> 15), 0x2c1b3c6d) + 0x6d2b79f5) >>> 0
    return scatter / 4294967296
  }
  const nextWait = () => GLITCH_WAIT[0] + chance() * (GLITCH_WAIT[1] - GLITCH_WAIT[0])
  let wait = nextWait()

  /** Whether a point is inside the mark's box and the room round it. */
  const overMark = (x: number, y: number) =>
    Math.abs(x - place.x) < (MARK_WIDTH / 2) * place.unit + CROWN_ROOM &&
    Math.abs(y - place.y) < (MARK_HEIGHT / 2) * place.unit + CROWN_ROOM

  const crown: Crown = {
    squares,
    place,
    quiet: 0,
    aim: null,
    turn,
    glitch,
    take(width, height, words) {
      const {camera} = field
      const cos = Math.cos(camera.lean)
      const sin = Math.sin(camera.lean)
      // Panels the field has faded out round the words, under the bar or round the crown are not in sight.
      const hushed = (x: number, y: number, free: number) =>
        free < 0.5 &&
        ((Math.abs(x - words.x) < words.halfWidth && Math.abs(y - words.y) < words.halfHeight) ||
          y < words.band - height / 2 ||
          (crown.quiet > 0.5 && overMark(x, y)))
      const found: {panel: Panel; at: [number, number, number, number]; far: number}[] = []
      for (const cell of field.cells.values()) {
        const scale = LAYERS[cell.layer]!.depth * camera.zoom
        for (const panel of cell.panels) {
          if (!FILLING.has(panel.kind) || panel.taken) continue
          const dx = (panel.x - camera.x) * scale
          const dy = (panel.y - camera.y) * scale
          const x = dx * cos - dy * sin
          const y = dx * sin + dy * cos
          const inSight = panel.grow >= SHOWN && Math.abs(x) < width / 2 && Math.abs(y) < height / 2 && !hushed(x, y, panel.free)
          const far = Math.hypot(x - place.x, y - place.y) + (inSight ? 0 : OUT_OF_SIGHT)
          found.push({panel, at: [x, y, panel.w * scale, panel.h * scale], far})
        }
      }
      found.sort((one, other) => one.far - other.far)
      // Each panel sets out for the square that lies the same way round the middle, so no two paths cross.
      const around = (x: number, y: number) => Math.atan2(y, x)
      const chosen = found
        .slice(0, SLOTS.length)
        .sort((one, other) => around(one.at[0] - place.x, one.at[1] - place.y) - around(other.at[0] - place.x, other.at[1] - place.y))
      const slots = SLOTS.map(([column, row], slot) => ({slot, mx: column * STEP + SIDE / 2 - MARK_WIDTH / 2, my: row * STEP + SIDE / 2 - MARK_HEIGHT / 2}))
        .sort((one, other) => around(one.mx, one.my) - around(other.mx, other.my))
      squares.length = 0
      for (const [index, {panel, at}] of chosen.entries()) {
        panel.taken = true
        const {slot, mx, my} = slots[index]!
        squares.push({
          slot,
          mx,
          my,
          kind: panel.kind,
          seed: panel.seed,
          a: panel.a,
          b: panel.b,
          entrance: panel.entrance,
          source: panel,
          from: at,
          flown: 0,
          light: LAYERS[panel.layer]!.light,
          alpha: panel.alpha,
          grow: panel.grow,
          flash: 0,
          assemble: panel.assemble,
          hover: 0,
          clock: panel.clock,
        })
      }
      squares.sort((one, other) => one.slot - other.slot)
      return squares
    },
    letGo() {
      const {camera} = field
      const scale = LAYERS[NEAREST]!.depth * camera.zoom
      const cos = Math.cos(-camera.lean)
      const sin = Math.sin(-camera.lean)
      const loose: Panel[] = []
      for (const square of squares) {
        // A square still waiting to set out was never anywhere but its panel's place.
        if (square.flown === 0 && square.source) {
          square.source.taken = false
          continue
        }
        const [x, y, halfWidth, halfHeight] = crown.rect(square)
        const worldX = camera.x + (x * cos - y * sin) / scale
        const worldY = camera.y + (x * sin + y * cos) / scale
        const cell = field.cells.get(`${NEAREST}:${Math.floor(worldX / CELL)}:${Math.floor(worldY / CELL)}`)
        if (!cell) continue
        const panel: Panel = {
          kind: square.kind,
          x: worldX,
          y: worldY,
          w: halfWidth / scale,
          h: halfHeight / scale,
          seed: square.seed,
          a: square.a,
          b: square.b,
          alpha: 1,
          entrance: square.entrance,
          words: [0, 0, 0, 0],
          layer: NEAREST,
          grow: square.grow,
          flash: square.flash,
          assemble: square.assemble,
          hover: 0,
          clock: square.clock,
          seen: true,
          taken: false,
          free: 1,
        }
        cell.panels.push(panel)
        loose.push(panel)
      }
      squares.length = 0
      glitch.square = -1
      return loose
    },
    clear() {
      for (const square of squares) {
        if (square.source) square.source.taken = false
      }
      squares.length = 0
      glitch.square = -1
    },
    rect(square) {
      const half = (SIDE / 2) * place.unit
      const to = [place.x + square.mx * place.unit, place.y + square.my * place.unit, half, half]
      const t = square.flown
      const [x, y, w, h] = square.from
      return [x + (to[0]! - x) * t, y + (to[1]! - y) * t, w + (to[2]! - w) * t, h + (to[3]! - h) * t]
    },
    squareAt(x, y) {
      for (let index = squares.length - 1; index >= 0; index--) {
        const square = squares[index]!
        if (square.grow < 0.5) continue
        const [middleX, middleY, halfWidth, halfHeight] = crown.rect(square)
        if (Math.abs(x - middleX) <= halfWidth && Math.abs(y - middleY) <= halfHeight) return square
      }
      return null
    },
    advance(elapsed) {
      const dt = Math.min(MAX_STEP, elapsed)
      // The turn follows the pointer on a spring: the crown faces it, a few degrees at most.
      const aimYaw = crown.aim ? -crown.aim[0] * YAW : 0
      const aimPitch = crown.aim ? crown.aim[1] * TILT : 0
      speed.yaw += (STIFFNESS * (aimYaw - turn.yaw) - DAMPING * speed.yaw) * dt
      speed.pitch += (STIFFNESS * (aimPitch - turn.pitch) - DAMPING * speed.pitch) * dt
      turn.yaw += speed.yaw * dt
      turn.pitch += speed.pitch * dt
      for (const square of squares) square.clock += dt * (1 + square.hover * HURRY)
      // Now and then one square glitches for a moment.
      glitch.age += dt
      if (glitch.square >= 0 && glitch.age >= GLITCH_TIME) glitch.square = -1
      wait -= dt
      if (wait <= 0 && squares.length > 0) {
        glitch.square = Math.floor(chance() * squares.length)
        glitch.age = 0
        wait = GLITCH_TIME + nextWait()
      }
    },
  }
  return crown
}
