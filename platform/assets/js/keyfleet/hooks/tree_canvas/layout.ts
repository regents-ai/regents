/**
 * Where every card of a tree canvas stands, in slices, with nothing drawn:
 * the canvas hook draws what this answers.
 *
 * Every arrangement is a tree read left to right: an item stands after the
 * items it came from and before the ones made from it. A loop of links is
 * cut where the oldest item in it is reached again; that link is still
 * drawn, marked as running back.
 *
 * - `time`: a column for each hour or day, oldest on the left. In a column
 *   the tree runs left to right in its own sub-columns.
 * - `author` and `activity`: a band for each Key, or for how recently the
 *   items changed (most recent at the top). Across the bands the tree runs
 *   left to right by how many links lead to an item.
 *
 * In a column, each card stands as near as it can to the mean height of the
 * cards it came from, and never on another.
 */

export type Arrange = "time" | "author" | "activity"
export type Every = "hour" | "day"

export type TreeItem = {
  readonly id: string
  /** When it was made and when it last changed, in ms since 1970. */
  readonly created: number
  readonly changed: number
  /** Who made it, as its slice is headed: "Key 12". */
  readonly author: string
}

/** A link from the item something came from to the item made from it. */
export type TreeLink = {
  readonly id: string
  readonly from: string
  readonly to: string
  readonly type: string
}

export type Clock = {
  /** The start of the hour or day `at` falls in. */
  start(at: number, every: Every): number
  /** A time slice's heading. */
  label(start: number, every: Every): string
}

export type Placed = {readonly id: string; readonly x: number; readonly y: number; readonly slice: number}

export type Slice = {
  readonly key: string
  readonly label: string
  /** The band the slice covers, heading included. */
  readonly x: number
  readonly y: number
  readonly width: number
  readonly height: number
}

export type Path = {
  readonly id: string
  readonly from: string
  readonly to: string
  readonly type: string
  /** A link that closes a loop. */
  readonly back: boolean
  /** Start, two handles and end of its curve. */
  readonly points: readonly [number, number, number, number, number, number, number, number]
}

export type Layout = {
  readonly cards: ReadonlyMap<string, Placed>
  readonly slices: readonly Slice[]
  readonly paths: readonly Path[]
  /** Every card in reading order: slice by slice, column by column, top to bottom. */
  readonly order: readonly string[]
  readonly bounds: {readonly left: number; readonly top: number; readonly right: number; readonly bottom: number}
}

export const CARD = {width: 240, height: 104}
const COLUMN_GAP = 64
const ROW_GAP = 16
const SLICE_GAP = 96
/** The room at the top of each slice for its heading. */
export const HEADING = 48

const HOUR = 60 * 60 * 1000
const DAY = 24 * HOUR

// How recently items changed, most recent first.
const recency: readonly [number, string][] = [
  [HOUR, "Past hour"],
  [DAY, "Past day"],
  [7 * DAY, "Past week"],
  [30 * DAY, "Past month"],
  [Infinity, "Older"],
]

const byAge = (a: TreeItem, b: TreeItem) => a.created - b.created || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)

/**
 * The links that close a loop, and every item in an order where each comes
 * after all it came from by the other links. Items are walked oldest first,
 * so the link cut from a loop is the one back to its oldest item.
 */
function cut(items: readonly TreeItem[], links: readonly TreeLink[]) {
  const out = new Map<string, number[]>()
  links.forEach((link, index) => out.set(link.from, [...(out.get(link.from) ?? []), index]))
  const state = new Map<string, 1 | 2>()
  const back = new Set<number>()
  const finished: string[] = []
  for (const root of [...items].sort(byAge)) {
    if (state.has(root.id)) continue
    // An explicit stack, so a long chain never runs out of call depth.
    const stack: [string, number][] = [[root.id, 0]]
    state.set(root.id, 1)
    while (stack.length) {
      const top = stack[stack.length - 1]
      const next = out.get(top[0])?.[top[1]]
      if (next === undefined) {
        stack.pop()
        state.set(top[0], 2)
        finished.push(top[0])
        continue
      }
      top[1] += 1
      const to = links[next].to
      if (state.get(to) === 1) back.add(next)
      else if (!state.has(to)) {
        state.set(to, 1)
        stack.push([to, 0])
      }
    }
  }
  return {back, sorted: finished.reverse()}
}

/** Each item's place along the tree among `within`: 0 for one nothing in `within` leads to. */
function depths(sorted: readonly string[], parents: ReadonlyMap<string, readonly string[]>, within: (id: string) => boolean) {
  const depth = new Map<string, number>()
  for (const id of sorted) {
    if (!within(id)) continue
    let d = 0
    for (const parent of parents.get(id) ?? []) {
      if (within(parent)) d = Math.max(d, (depth.get(parent) ?? 0) + 1)
    }
    depth.set(id, d)
  }
  return depth
}

function slicesOf(items: readonly TreeItem[], arrange: Arrange, every: Every, now: number, clock: Clock) {
  const groups = new Map<string, {label: string; rank: number | string; items: TreeItem[]}>()
  for (const item of items) {
    let key: string
    let label: string
    let rank: number | string
    if (arrange === "time") {
      const start = clock.start(item.created, every)
      key = String(start)
      label = clock.label(start, every)
      rank = start
    } else if (arrange === "author") {
      key = label = rank = item.author
    } else {
      const index = recency.findIndex(([within]) => now - item.changed < within)
      key = label = recency[index][1]
      rank = index
    }
    const group = groups.get(key) ?? {label, rank, items: []}
    group.items.push(item)
    groups.set(key, group)
  }
  return [...groups.entries()]
    .sort(([, a], [, b]) =>
      typeof a.rank === "number" && typeof b.rank === "number"
        ? a.rank - b.rank
        : String(a.rank).localeCompare(String(b.rank), "en", {numeric: true}),
    )
    .map(([key, group]) => ({key, label: group.label, items: group.items}))
}

/**
 * Stacks one column's items from `top`, each as near as it can to the mean
 * height of the placed items it came from, the oldest first where they tie;
 * answers where the column ends.
 */
function stack(
  column: readonly TreeItem[],
  x: number,
  top: number,
  slice: number,
  parents: ReadonlyMap<string, readonly string[]>,
  placed: Map<string, Placed>,
) {
  const wanted = (item: TreeItem) => {
    const ys = (parents.get(item.id) ?? []).flatMap(id => (placed.has(id) ? [placed.get(id)!.y] : []))
    return ys.length ? ys.reduce((sum, y) => sum + y, 0) / ys.length : Infinity
  }
  const order = column.map(item => ({item, wanted: wanted(item)}))
  order.sort((a, b) => a.wanted - b.wanted || byAge(a.item, b.item))
  let free = top
  for (const {item, wanted} of order) {
    const y = Math.round(Math.max(free, Number.isFinite(wanted) ? wanted : free))
    placed.set(item.id, {id: item.id, x, y, slice})
    free = y + CARD.height + ROW_GAP
  }
  return free - ROW_GAP
}

const pitch = CARD.width + COLUMN_GAP

/**
 * The curve of a link between two cards, by their top left corners: from the
 * right of the one it leaves to the left of the one it reaches, or the other
 * way round when it runs back.
 */
export function curve(from: {x: number; y: number}, to: {x: number; y: number}): Path["points"] {
  const y1 = from.y + CARD.height / 2
  const y2 = to.y + CARD.height / 2
  if (Math.abs(to.x - from.x) < CARD.width / 2) {
    // Two cards of one column: the link bows out to the right.
    const x = from.x + CARD.width
    const bow = x + Math.min(COLUMN_GAP / 2 + Math.abs(y2 - y1) / 8, COLUMN_GAP)
    return [x, y1, bow, y1, bow, y2, x, y2]
  }
  const forward = to.x > from.x
  const x1 = forward ? from.x + CARD.width : from.x
  const x2 = forward ? to.x : to.x + CARD.width
  const bend = Math.max(COLUMN_GAP / 2, Math.abs(x2 - x1) / 2) * (forward ? 1 : -1)
  return [x1, y1, x1 + bend, y1, x2 - bend, y2, x2, y2]
}

/** Lays out `items` and the `links` between them in the arrangement asked for. */
export function layout(
  items: readonly TreeItem[],
  links: readonly TreeLink[],
  arrange: Arrange,
  every: Every,
  now: number,
  clock: Clock,
): Layout {
  const known = new Set(items.map(item => item.id))
  const drawn = links.filter(link => link.from !== link.to && known.has(link.from) && known.has(link.to))
  const {back, sorted} = cut(items, drawn)
  const parents = new Map<string, string[]>()
  drawn.forEach((link, index) => {
    if (!back.has(index)) parents.set(link.to, [...(parents.get(link.to) ?? []), link.from])
  })
  const slices = slicesOf(items, arrange, every, now, clock)
  const placed = new Map<string, Placed>()
  const bands: Slice[] = []

  if (arrange === "time") {
    let left = 0
    let bottom = 0
    const columns: {key: string; label: string; left: number; width: number}[] = []
    slices.forEach((slice, index) => {
      const ids = new Set(slice.items.map(item => item.id))
      const depth = depths(sorted, parents, id => ids.has(id))
      const deepest = Math.max(...depth.values())
      for (let d = 0; d <= deepest; d++) {
        const column = slice.items.filter(item => depth.get(item.id) === d)
        bottom = Math.max(bottom, stack(column, left + d * pitch, 0, index, parents, placed))
      }
      const width = (deepest + 1) * pitch - COLUMN_GAP
      columns.push({key: slice.key, label: slice.label, left, width})
      left += width + SLICE_GAP
    })
    for (const column of columns) {
      bands.push({
        key: column.key,
        label: column.label,
        x: column.left - SLICE_GAP / 4,
        y: -HEADING,
        width: column.width + SLICE_GAP / 2,
        height: bottom + HEADING + SLICE_GAP / 4,
      })
    }
  } else {
    const depth = depths(sorted, parents, () => true)
    const deepest = Math.max(0, ...depth.values())
    const width = (deepest + 1) * pitch - COLUMN_GAP
    let top = 0
    slices.forEach((slice, index) => {
      let bottom = top
      for (let d = 0; d <= deepest; d++) {
        const column = slice.items.filter(item => depth.get(item.id) === d)
        if (column.length) bottom = Math.max(bottom, stack(column, d * pitch, top, index, parents, placed))
      }
      bands.push({
        key: slice.key,
        label: slice.label,
        x: -SLICE_GAP / 4,
        y: top - HEADING,
        width: width + SLICE_GAP / 2,
        height: bottom - top + HEADING + SLICE_GAP / 4,
      })
      top = bottom + SLICE_GAP + HEADING
    })
  }

  const order = [...placed.values()]
    .sort((a, b) => a.slice - b.slice || a.x - b.x || a.y - b.y)
    .map(card => card.id)

  const paths = drawn.map((link, index) => ({
    id: link.id,
    from: link.from,
    to: link.to,
    type: link.type,
    back: back.has(index),
    points: curve(placed.get(link.from)!, placed.get(link.to)!),
  }))

  const bounds = bands.reduce(
    (box, band) => ({
      left: Math.min(box.left, band.x),
      top: Math.min(box.top, band.y),
      right: Math.max(box.right, band.x + band.width),
      bottom: Math.max(box.bottom, band.y + band.height),
    }),
    {left: 0, top: 0, right: 0, bottom: 0},
  )

  return {cards: placed, slices: bands, paths, order, bounds}
}

/**
 * Hours and days as the reader keeps them, in their own time zone: "Today",
 * "Yesterday", "12 Nov", with the year when it is not this one; an hour adds
 * its time, "Today, 14:00".
 */
export function localClock(now: number, locale?: string): Clock {
  const midnight = (at: number) => new Date(at).setHours(0, 0, 0, 0)
  const today = midnight(now)
  const thisYear = new Date(now).getFullYear()
  const time = new Intl.DateTimeFormat(locale, {timeStyle: "short"})
  const month = new Intl.DateTimeFormat("en-US", {month: "short"})
  const day = (start: number) => {
    const daysAgo = Math.round((today - midnight(start)) / DAY)
    if (daysAgo === 0) return "Today"
    if (daysAgo === 1) return "Yesterday"
    const date = new Date(start)
    const year = date.getFullYear() === thisYear ? "" : ` ${date.getFullYear()}`
    return `${date.getDate()} ${month.format(date)}${year}`
  }
  return {
    start: (at, every) => (every === "day" ? midnight(at) : new Date(at).setMinutes(0, 0, 0)),
    label: (start, every) => (every === "day" ? day(start) : `${day(start)}, ${time.format(start)}`),
  }
}
