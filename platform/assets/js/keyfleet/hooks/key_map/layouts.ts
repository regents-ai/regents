import {axialToOffset, mod, offsetToAxial, type Cell} from "./lattice"

/**
 * Where every key of a fleet sits, and the finite map that repeats in every
 * direction around the keys shown so far.
 *
 * A layout is a fixed function from key number to axial cell, so a key never
 * moves when later keys sell; only the repeating map's extent grows.
 */

export type LayoutKind = "fibonacci" | "classic" | "accelerant" | "regents_club"

type Seats = {q: Int32Array; r: Int32Array; level: Uint16Array}

export type KeyMapGrid = {
  /** The two axial translations under which the map repeats. */
  periodA: Cell
  periodB: Cell
  /** A key number above 0, a level heading as `-level`, or 0 for an empty cell. */
  valueAt(q: number, r: number): number
  /** The key's cell in the home copy. */
  home(key: number): Cell
  /** The key's Fibonacci level, or 0 for fleets without levels. */
  levelOf(key: number): number
}

// Empty cells kept around the shown keys, so neighbouring copies stay apart.
const gutter = 2
// Level 8's 55 keys make one 28 + 27 band; every later level repeats it.
const wideRow = 28
const narrowRow = 27
const snakeWidth = 5
const classicSupply = 1_024
const accelerantSupply = 2_000
const clubSupply = 1_998

/** How many keys a fleet can ever have; the Fibonacci fleets' levels keep opening, so they have no limit. */
export const maxSupply: Record<LayoutKind, number | null> = {
  fibonacci: null,
  classic: classicSupply,
  accelerant: accelerantSupply,
  regents_club: clubSupply,
}

/** Whether a fleet's keys are given, one per Regents Club Pass, rather than sold. */
export const given = (layout: LayoutKind) => layout === "regents_club"

/** How many keys a Fibonacci level has: 2, 3, 5, 8 and on, without end. */
export function fibonacciLevelSupply(level: number) {
  let [previous, current] = [1, 2]
  for (let index = 1; index < level; index++) [previous, current] = [current, previous + current]
  return current
}

/** The Fibonacci level a key belongs to. */
export function fibonacciLevelOf(key: number) {
  let level = 1
  let last = fibonacciLevelSupply(1)
  while (key > last) {
    level += 1
    last += fibonacciLevelSupply(level)
  }
  return level
}

/** The first key of a Fibonacci level. */
export function levelStart(level: number) {
  let start = 1
  for (let earlier = 1; earlier < level; earlier++) start += fibonacciLevelSupply(earlier)
  return start
}

/** The last key of a Fibonacci level. */
export const levelEnd = (level: number) => levelStart(level + 1) - 1

function seatTable(count: number, place: (push: (col: number, row: number, level: number) => void) => void): Seats {
  const seats = {q: new Int32Array(count), r: new Int32Array(count), level: new Uint16Array(count)}
  let index = 0
  place((col, row, level) => {
    const [q, r] = offsetToAxial(col, row)
    seats.q[index] = q
    seats.r[index] = r
    seats.level[index] = level
    index += 1
  })
  return seats
}

// Levels 1–7 are one centred row each; later levels are 28/27 bands. A row
// centres exactly only when its length suits its row's parity, so the rest sit
// half a cell off. One tie-break per level keeps a level's rows interlocking,
// and alternating it between levels keeps the stack from leaning. One blank
// row separates levels and holds the level's heading. The levels never end,
// so the seats go as far as the level holding key `count`.
const fibonacciSeats = (count: number) => {
  const levels = fibonacciLevelOf(Math.max(count, 1))
  return seatTable(levelEnd(levels), push => {
    let row = 0
    for (let level = 1; level <= levels; level++) {
      const supply = fibonacciLevelSupply(level)
      const lean = level % 2 === 0 ? Math.floor : Math.ceil
      let left = supply
      let wide = true
      while (left > 0) {
        const length = level < 8 ? left : Math.min(left, wide ? wideRow : narrowRow)
        const exact = -mod(row, 2) / 2 - (length - 1) / 2
        const start = Number.isInteger(exact) ? exact : lean(exact)
        for (let k = 0; k < length; k++) push(start + k, row, level)
        left -= length
        wide = !wide
        row += 1
      }
      row += 1
    }
  })
}

// Rows of five in a snake, so every key is a neighbour of the one before it:
// Accelerant's 2,000 and the Regents Club's 1,998.
const snakeSeats = (supply: number) => () =>
  seatTable(supply, push => {
    for (let index = 0; index < supply; index++) {
      const row = Math.floor(index / snakeWidth)
      const k = index % snakeWidth
      push(row % 2 === 0 ? k : snakeWidth - 1 - k, row, 0)
    }
  })

// Axial rhombus shells: shell k is the far edge of a (k+1)×(k+1) rhombus, so
// the fleet closes at exactly 32 × 32 = 1,024.
const classicSeats = (): Seats => {
  const count = classicSupply
  const seats = {q: new Int32Array(count), r: new Int32Array(count), level: new Uint16Array(count)}
  for (let key = 1; key <= count; key++) {
    const shell = classicShell(key)
    const i = key - 1 - shell * shell
    seats.q[key - 1] = i <= shell ? shell : 2 * shell - i
    seats.r[key - 1] = i <= shell ? i : shell
  }
  return seats
}

const classicShell = (key: number) => Math.ceil(Math.sqrt(key)) - 1

const seatBuilders: Record<LayoutKind, (count: number) => Seats> = {
  fibonacci: fibonacciSeats,
  classic: classicSeats,
  accelerant: snakeSeats(accelerantSupply),
  regents_club: snakeSeats(clubSupply),
}

const seatCache = new Map<LayoutKind, Seats>()

// A key's seat never changes, so seats built for more keys serve fewer; a
// Fibonacci fleet's seats are built again only once a new level is shown.
const seatsFor = (kind: LayoutKind, shown: number) => {
  const cached = seatCache.get(kind)
  if (cached && cached.q.length >= shown) return cached
  const built = seatBuilders[kind](shown)
  seatCache.set(kind, built)
  return built
}

/** The finite map of the first `shown` keys of a fleet, repeating in both directions. */
export function buildMap(kind: LayoutKind, shown: number): KeyMapGrid {
  const seats = seatsFor(kind, shown)
  return {
    ...(kind === "classic" ? rhombusMap(seats, shown) : rowMap(seats, shown)),
    home: key => [seats.q[key - 1], seats.r[key - 1]],
    levelOf: key => seats.level[key - 1],
  }
}

type Repeat = Pick<KeyMapGrid, "periodA" | "periodB" | "valueAt">

function rhombusMap(seats: Seats, shown: number): Repeat {
  const period = classicShell(shown) + 1 + gutter
  const grid = new Int32Array(period * period)
  for (let key = 1; key <= shown; key++) grid[seats.r[key - 1] * period + seats.q[key - 1]] = key
  return {
    periodA: [period, 0],
    periodB: [0, period],
    valueAt: (q, r) => grid[mod(r, period) * period + mod(q, period)],
  }
}

// Row layouts repeat every W columns and every H rows. H is even, so a copy
// keeps each row's parity and every copy is a pure translation on screen.
function rowMap(seats: Seats, shown: number): Repeat {
  let minCol = Infinity
  let maxCol = -Infinity
  let maxRow = 0
  for (let index = 0; index < shown; index++) {
    const [col, row] = axialToOffset(seats.q[index], seats.r[index])
    if (col < minCol) minCol = col
    if (col > maxCol) maxCol = col
    if (row > maxRow) maxRow = row
  }
  const width = maxCol - minCol + 1 + gutter
  const height = (maxRow + 1 + gutter + 1) & ~1
  const grid = new Int32Array(width * height)
  const put = (col: number, row: number, value: number) => {
    grid[mod(row, height) * width + mod(col - minCol, width)] = value
  }

  let previousLevel = 0
  for (let index = 0; index < shown; index++) {
    const [col, row] = axialToOffset(seats.q[index], seats.r[index])
    put(col, row, index + 1)
    const level = seats.level[index]
    // A level's first key is the left end of its first row; its heading sits
    // in the blank row above.
    if (level !== previousLevel) put(col, row - 1, -level)
    previousLevel = level
  }

  return {
    periodA: [width, 0],
    periodB: [-height / 2, height],
    valueAt: (q, r) => grid[mod(r, height) * width + mod(q + Math.floor(r / 2) - minCol, width)],
  }
}
