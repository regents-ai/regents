/**
 * The Atlas blocks' layout, as pure sums: squarified treemaps (Bruls,
 * Huizing and van Wijk) that hold still under new counts. Tiles keep the
 * order they were first seen in, busiest first, with newcomers after them,
 * and the rows a layout was cut into are kept while they still give tiles
 * of a fair shape, so new counts grow and shrink tiles where they stand
 * rather than move them. Nested tiles sit inside their parent below a band
 * that names it, and fade in as the parent grows to fill the stage.
 */

export type Rect = {x: number; y: number; w: number; h: number}

/** One cut of a layout: how many tiles it holds, and whether it stands as a column down the left of what is left (or a row along its top). */
export type Cut = {readonly count: number; readonly column: boolean}

/** A kept layout's worst tile may be this much less square than a fresh layout's worst. */
export const KEEP = 1.5

/** The band naming a tile above its children, and the room around them, in CSS pixels once the tile fills the stage. */
export const HEAD = 24
export const PAD = 4

/** A tile's children start to show at this share of the zoom that fills the stage with it, and show fully at the second. */
export const SHOW_FROM = 0.55
export const SHOW_AT = 0.85

/** The most room between neighbouring tiles, and the roundest a tile's corners get, in CSS pixels on screen. */
export const GAP = 4
export const RADIUS = 8

/** The room a tile whose shorter side is `side` CSS pixels on screen keeps from its neighbours: less for a small tile, so it never vanishes into its gaps. */
export const gutter = (side: number) => Math.min(GAP, Math.max(0, side) * 0.15)

/** How round the corners of a tile whose shorter side is `side` are: at most a fifth of what is left of it, so a small tile stays a block and never a blob. */
export const corner = (side: number) => Math.min(RADIUS, Math.max(0, side - gutter(side)) * 0.2)

// How unlike a square a row of areas summing to `sum`, from `min` to `max`,
// is at its worst once laid along a side of length `side`.
const worst = (sum: number, min: number, max: number, side: number) => {
  const squared = side * side
  return Math.max((squared * max) / (sum * sum), (sum * sum) / (squared * min))
}

/** A fresh squarified layout's cuts of `areas`, in order, which together fill `rect`. */
export function cut(areas: readonly number[], rect: Rect): Cut[] {
  const cuts: Cut[] = []
  let {x, y, w, h} = rect
  let index = 0
  while (index < areas.length) {
    const column = w >= h
    const side = Math.min(w, h)
    if (side <= 0) {
      cuts.push({count: areas.length - index, column})
      break
    }
    let [sum, min, max, count] = [0, Infinity, 0, 0]
    while (index + count < areas.length) {
      const area = areas[index + count]
      // A tile with no area rides along in the row it falls in.
      if (area > 0) {
        const [nextSum, nextMin, nextMax] = [sum + area, Math.min(min, area), Math.max(max, area)]
        if (sum > 0 && worst(nextSum, nextMin, nextMax, side) > worst(sum, min, max, side)) break
        ;[sum, min, max] = [nextSum, nextMin, nextMax]
      }
      count += 1
    }
    cuts.push({count, column})
    if (column) {
      const across = sum / h
      x += across
      w = Math.max(0, w - across)
    } else {
      const down = sum / w
      y += down
      h = Math.max(0, h - down)
    }
    index += count
  }
  return cuts
}

/**
 * Lays `areas` out in `rect` along `cuts`, writing each tile's rect into
 * `out` in order. Tiles past the cuts given are laid out in a fresh layout of
 * what is left. Returns the cuts used.
 */
export function place(areas: readonly number[], rect: Rect, cuts: readonly Cut[], out: Rect[]): Cut[] {
  const used: Cut[] = []
  let {x, y, w, h} = rect
  let index = 0
  for (const each of cuts) {
    if (index >= areas.length) break
    const count = Math.min(each.count, areas.length - index)
    let sum = 0
    for (let at = index; at < index + count; at++) sum += areas[at]
    if (each.column) {
      const across = h > 0 ? sum / h : 0
      let top = y
      for (let at = index; at < index + count; at++) {
        const down = across > 0 ? areas[at] / across : 0
        out[at] = {x, y: top, w: across, h: down}
        top += down
      }
      x += across
      w = Math.max(0, w - across)
    } else {
      const down = w > 0 ? sum / w : 0
      let left = x
      for (let at = index; at < index + count; at++) {
        const across = down > 0 ? areas[at] / down : 0
        out[at] = {x: left, y, w: across, h: down}
        left += across
      }
      y += down
      h = Math.max(0, h - down)
    }
    used.push({count, column: each.column})
    index += count
  }
  if (index < areas.length) {
    const rest = areas.slice(index)
    const left = {x, y, w, h}
    const tail: Rect[] = []
    const fresh = place(rest, left, cut(rest, left), tail)
    tail.forEach((tile, at) => (out[index + at] = tile))
    used.push(...fresh)
  }
  return used
}

/** How unlike a square the least square tile with any area is: 1 for squares. */
export function aspect(rects: readonly Rect[]): number {
  let most = 1
  for (const {w, h} of rects) {
    if (w > 0 && h > 0) most = Math.max(most, w / h, h / w)
  }
  return most
}

/**
 * Tiles for `weights`, in order, filling `rect`: the cuts of `kept` while
 * their worst tile stays within `KEEP` of a fresh layout's worst, else a
 * fresh layout. Returns the tiles and the cuts to keep for next time.
 */
export function squarify(
  weights: readonly number[],
  rect: Rect,
  kept?: readonly Cut[],
): {rects: Rect[]; cuts: Cut[]} {
  let total = 0
  for (const weight of weights) total += Math.max(0, weight)
  const room = rect.w * rect.h
  const areas = weights.map(weight => (total > 0 ? (Math.max(0, weight) / total) * room : 0))
  const fresh: Rect[] = []
  const cuts = place(areas, rect, cut(areas, rect), fresh)
  if (kept && kept.length > 0) {
    const held: Rect[] = []
    const heldCuts = place(areas, rect, kept, held)
    if (aspect(held) <= KEEP * aspect(fresh)) return {rects: held, cuts: heldCuts}
  }
  return {rects: fresh, cuts}
}

/**
 * The order tiles keep: those already shown where they were, then any new
 * ones, the most work first. Ones gone are left out.
 */
export function ordered(shown: readonly string[], weights: ReadonlyMap<string, number>): string[] {
  const kept = shown.filter(id => weights.has(id))
  const known = new Set(kept)
  const fresh = [...weights.keys()]
    .filter(id => !known.has(id))
    .sort((a, b) => weights.get(b)! - weights.get(a)! || (a < b ? -1 : a > b ? 1 : 0))
  return kept.concat(fresh)
}

/** The zoom at which a tile fills a stage `width` by `height`. */
export const fills = (rect: Rect, width: number, height: number) =>
  Math.min(width / Math.max(rect.w, 1e-9), height / Math.max(rect.h, 1e-9))

/** Where a tile that fills the stage at zoom `fill` lays its children: below its band, inside its room. */
export function inner(rect: Rect, fill: number): Rect {
  const pad = PAD / fill
  const head = HEAD / fill
  return {
    x: rect.x + pad,
    y: rect.y + head,
    w: Math.max(0, rect.w - 2 * pad),
    h: Math.max(0, rect.h - head - pad),
  }
}

/** How fully a tile that fills the stage at zoom `fill` shows its children at zoom `zoom`, 0..1. */
export function shown(zoom: number, fill: number): number {
  const t = Math.min(1, Math.max(0, (zoom / fill - SHOW_FROM) / (SHOW_AT - SHOW_FROM)))
  return t * t * (3 - 2 * t)
}

/** How recent `last` is within a window from `from` up to `until` (its end, or now in the window holding now), 0 the oldest and 1 the newest. */
export function recency(last: number, from: number, until: number): number {
  if (until <= from) return 1
  return Math.min(1, Math.max(0, (last - from) / (until - from)))
}

/** Each rect between two layouts at `t` of the way, 0..1, into `out`. */
export function between(from: Rect, to: Rect, t: number, out: Rect): Rect {
  out.x = from.x + (to.x - from.x) * t
  out.y = from.y + (to.y - from.y) * t
  out.w = from.w + (to.w - from.w) * t
  out.h = from.h + (to.h - from.h) * t
  return out
}
