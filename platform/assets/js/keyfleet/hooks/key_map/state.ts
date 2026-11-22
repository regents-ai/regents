import {axialToOffset, hexDistance, offsetToAxial, type Cell} from "./lattice"
import {fibonacciLevelOf, levelEnd, type KeyMapGrid} from "./layouts"

/** The server's reply to `keymap_ready`. */
export type KeyMapSnapshot = {
  minted: number
  /** How many keys the fleet can ever have, or null for a fleet whose levels keep opening. */
  max_supply: number | null
  /** Whether the fleet's keys are given, one per Regents Club Pass, so none is ever on sale. */
  given: boolean
  /**
   * Base64 bitsets, as long as the highest key marked needs; bit `id − 1` sits
   * in byte `(id − 1) >> 3`, least significant bit first.
   */
  mine: string
  agent: string
}

/** Keys whose marks changed: `[token_id, flags]`, bit 0 yours and bit 1 has an agent. */
export type KeyMapPatch = {
  minted: number
  keys: [number, number][]
}

/** The server's reply to `find_keys`: the keys found, as a bitset like `mine`, and words saying so. */
export type KeyMapFound = {
  keys: string
  words: string
}

/** The server's reply to `keymap_pictures`: where each key's card close-up is shown. */
export type KeyMapPictures = {
  pictures: [number, string][]
}

export type KeyMapState = {
  minted: number
  maxSupply: number | null
  given: boolean
  mine: Uint8Array
  agent: Uint8Array
}

export type Direction = "left" | "right" | "up" | "down"

/** A base64 bitset's bytes. */
export const decodeBits = (base64: string) => Uint8Array.from(atob(base64), character => character.charCodeAt(0))

export const decodeSnapshot = (snapshot: KeyMapSnapshot): KeyMapState => ({
  minted: snapshot.minted,
  maxSupply: snapshot.max_supply,
  given: snapshot.given,
  mine: decodeBits(snapshot.mine),
  agent: decodeBits(snapshot.agent),
})

export const hasBit = (bits: Uint8Array, key: number) => ((bits[(key - 1) >> 3] >> ((key - 1) & 7)) & 1) === 1

const setBit = (bits: Uint8Array, key: number, on: boolean) => {
  const mask = 1 << ((key - 1) & 7)
  bits[(key - 1) >> 3] = on ? bits[(key - 1) >> 3] | mask : bits[(key - 1) >> 3] & ~mask
}

// A copy of `bits` at least `bytes` long; a key past the end has no mark.
const widened = (bits: Uint8Array, bytes: number) => {
  const copy = new Uint8Array(Math.max(bits.length, bytes))
  copy.set(bits)
  return copy
}

/** The state after a patch; the state given is left as it was. */
export function applyPatch(state: KeyMapState, patch: KeyMapPatch): KeyMapState {
  const bytes = patch.keys.reduce((most, [key]) => Math.max(most, (key + 7) >> 3), 0)
  const mine = widened(state.mine, bytes)
  const agent = widened(state.agent, bytes)
  for (const [key, flags] of patch.keys) {
    setBit(mine, key, (flags & 1) === 1)
    setBit(agent, key, (flags & 2) === 2)
  }
  return {...state, minted: patch.minted, mine, agent}
}

/** The key on sale, or 0 once the fleet is sold out and for a fleet whose keys are given. */
export const nextKey = (state: KeyMapState) =>
  !state.given && (state.maxSupply === null || state.minted < state.maxSupply) ? state.minted + 1 : 0

/** The last key that can be chosen: the next key, or the last key minted when none is on sale. */
export const lastChoosable = (state: KeyMapState) => Math.max(state.minted, nextKey(state))

/**
 * How many keys the map draws, the one place that decides it. A fleet whose
 * levels keep opening is drawn to the end of the level on sale: every level
 * reached, and no level after it. A fleet with a size is drawn whole.
 */
export const drawnKeys = (state: KeyMapState) =>
  state.maxSupply === null ? levelEnd(fibonacciLevelOf(state.minted + 1)) : state.maxSupply

/** The level of the key on sale, or 0 once the fleet is sold out or for a fleet without levels. */
export const onSaleLevel = (grid: KeyMapGrid, state: KeyMapState) => {
  const next = nextKey(state)
  return next ? grid.levelOf(next) : 0
}

/** How a level stands: sold out, or on sale now. No level after the one on sale is drawn. */
export type LevelSale = "sold-out" | "on-sale"

/** Where a level stands against the level on sale. */
export const levelSale = (onSale: number, level: number): LevelSale => (level === onSale ? "on-sale" : "sold-out")

/** How many tones the levels step through; neighbouring levels always differ. */
export const levelTones = 4

/** A level's tone, from 0: level 1 takes the first and the tones repeat in order. */
export const levelTone = (level: number) => (level - 1) % levelTones

/** A level heading's words. */
export const levelHeading = (level: number, sale: LevelSale) =>
  sale === "sold-out" ? `Level ${level} · sold out` : `Level ${level} · on sale now`

/** Where the map opens and where Home goes: the next key, or key 1 once sold out. */
export const startKey = (state: KeyMapState) => nextKey(state) || 1

/**
 * The first key after `after` marked in `bits`, coming back round to key 1
 * past the last key that can be chosen, or 0 when none is marked.
 */
export function nextMarkedKey(state: KeyMapState, bits: Uint8Array, after: number) {
  const shown = lastChoosable(state)
  for (let step = 1; step <= shown; step++) {
    const key = ((after + step - 1) % shown) + 1
    if (hasBit(bits, key)) return key
  }
  return 0
}

/** The first key after `after` that is yours, or 0 when you hold none. */
export const nextHeldKey = (state: KeyMapState, after: number) => nextMarkedKey(state, state.mine, after)

/** A key drawn but not minted, other than the next key, which can't be chosen yet. */
const unsold = (state: KeyMapState, key: number) => key > lastChoosable(state)

/** A tile's marks, for `data-state`; `found` is the keys the last search found. */
export function keyMarks(state: KeyMapState, key: number, selected: number, cursor: number, found: Uint8Array) {
  const marks: string[] = []
  if (key === nextKey(state)) marks.push("next")
  if (unsold(state, key)) marks.push("unsold")
  if (hasBit(found, key)) marks.push("found")
  if (hasBit(state.mine, key)) marks.push("mine")
  if (hasBit(state.agent, key)) marks.push("agent")
  if (key === selected) marks.push("selected")
  if (key === cursor) marks.push("cursor")
  return marks.join(" ")
}

// One formatter for every number the map shows: making one per number, as
// `toLocaleString` does, is most of the cost of drawing a key.
const grouping = new Intl.NumberFormat("en-US")

/** A number with its thousands grouped, as 17,769. */
export const grouped = (value: number) => grouping.format(value)

/** What the map reads out when the keyboard cursor lands on a key. */
export function describeKey(grid: KeyMapGrid, state: KeyMapState, key: number) {
  const level = grid.levelOf(key)
  const parts = [key === nextKey(state) ? `Next Key, ${grouped(key)}` : `Key ${grouped(key)}`]
  if (level) parts.push(`level ${level}`)
  if (hasBit(state.mine, key)) parts.push("yours")
  if (hasBit(state.agent, key)) parts.push("has an agent")
  if (unsold(state, key)) parts.push("not sold yet")
  return `${parts.join(", ")}.`
}

const isKey = (grid: KeyMapGrid, cell: Cell) => grid.valueAt(...cell) > 0

/**
 * The next key from `cell` in a direction, skipping empty cells. Left and right
 * follow the row; up and down keep the offset column. The map repeats, so the
 * walk always comes back round to a key.
 */
export function step(grid: KeyMapGrid, cell: Cell, direction: Direction): Cell {
  const horizontal = direction === "left" || direction === "right"
  const delta = direction === "left" || direction === "up" ? -1 : 1
  const [col, row] = axialToOffset(...cell)
  const limit = horizontal ? Math.abs(grid.periodA[0]) : 2 * Math.abs(grid.periodB[1])
  for (let distance = 1; distance <= limit; distance++) {
    const next = horizontal ? ([cell[0] + delta * distance, cell[1]] as const) : offsetToAxial(col, row + delta * distance)
    if (isKey(grid, next)) return next
  }
  return cell
}

/**
 * The key cell nearest `cell`, searching outward ring by ring, or null for a
 * map with no keys. Every cell is within one copy's span of a copy of each
 * key, so the search stops there.
 */
export function keyNear(grid: KeyMapGrid, cell: Cell): Cell | null {
  if (isKey(grid, cell)) return cell
  const span = hexDistance(...grid.periodA) + hexDistance(...grid.periodB)
  for (let radius = 1; radius <= span; radius++) {
    for (let dq = -radius; dq <= radius; dq++) {
      for (let dr = Math.max(-radius, -dq - radius); dr <= Math.min(radius, -dq + radius); dr++) {
        const candidate: Cell = [cell[0] + dq, cell[1] + dr]
        if (hexDistance(dq, dr) === radius && isKey(grid, candidate)) return candidate
      }
    }
  }
  return null
}
