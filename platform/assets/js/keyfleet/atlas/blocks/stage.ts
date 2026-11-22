/**
 * The Atlas as blocks: a treemap of the window shown. Each project is a block
 * as big as the work it holds in the window, tinted along the page's scale
 * by how recently it was worked on, with a dot on a block changed today.
 * Zooming into a block, or choosing it, opens it in place: it grows to fill
 * the stage while a block for each kind of work fades in inside it, then a
 * block for each thing, as big as its changes, the quieter ones gathered
 * into one more block, never bigger than a third of the things beside it,
 * that opens the same way, then the thing itself, its name a link to its
 * page. The path above the picture goes back up.
 *
 * Nothing the fleet did reaches the browser at once. The page answers for
 * the window's counts by project and kind (`atlas_blocks_fleet`), and for a
 * kind's things a hundred at a time (`atlas_blocks_things`), asked for only
 * as a kind or the rest of one grows toward filling the stage. When the
 * fleet's work is counted again the page says so (`changed`), and the counts
 * and the things on screen are read again in place.
 *
 * The blocks hold still: each keeps its place in the order it was first
 * seen, the busiest first, with newcomers after, and new counts ease every
 * block to its new size where it stands. The wheel and a pinch zoom about the
 * pointer and dragging moves. With the keyboard, the arrow keys move a ring
 * between neighbouring blocks, Enter opens the block ringed (and a thing's
 * page once it fills the stage), Escape goes back up and plus and minus zoom
 * about the ring. Choosing a thing in the strip beside the picture opens the
 * blocks down to it.
 *
 * The block pointed at, or ringed, stands out while the others quieten, and
 * a card beside it, never over it, says what it holds; the card's close
 * button or Escape puts it away until another block is chosen.
 *
 * The blocks are drawn on the GPU (`./renderer`) and only redrawn when
 * something moved; their names are the page's own, from a pool, shown only
 * where every word fits (measured, never cut short). Moves run under 300 ms
 * with anime.js, and at once after a key press or for a reader who asked for
 * less motion.
 */
import {animate, type JSAnimation} from "animejs"

import {createCamera} from "../../camera"
import {createCanvasIsland} from "../../canvas_island"
import {EASE_OUT, SLOW, byPointer, lastInputByPointer, still} from "../../hooks/motion/shared"
import {watchTheme} from "../../../theme"
import {tone} from "../../theme_tone"
import {HEAD, SHOW_FROM, between, fills, inner, ordered, recency, shown, squarify, type Cut, type Rect} from "./layout"
import {MAX_TILES, TILE_FLOATS, type BlocksRenderer} from "./renderer"

/** Asks the page, and hears its answer when it gives one. */
export type Ask = <Reply>(event: string, payload: object, reply?: (reply: Reply) => void) => void

export type BlocksStage = {
  /** The page drew the picture's element again: its projects, window or kind may have changed. */
  update(): void
  /** The fleet's work was counted again: the counts and the things on screen are read again. */
  changed(): void
  pause(): void
  resume(): void
  destroy(): void
}

type Type = "fleet" | "project" | "kind" | "rest" | "thing"
type Thing = {
  readonly id: string
  readonly title: string
  readonly what: string
  readonly who: string | null
  readonly at: number
  readonly changes: number
  readonly actors: number
  readonly path: string
  readonly live: boolean
}
type Name = {
  readonly el: HTMLElement
  readonly link: HTMLAnchorElement
  readonly count: HTMLElement
  readonly detail: HTMLElement
  tile: Tile | undefined
  pass: number
  version: number
  x: number
  y: number
  w: number
  h: number
  // How wide its words, the space between them, and its two small lines are, in CSS pixels.
  words: number[]
  space: number
  countWidth: number
  detailWidth: number
}
type Tile = {
  readonly key: string
  readonly type: Type
  readonly parent: Tile | undefined
  readonly project: string
  readonly kind: string
  name: string
  changes: number
  things: number
  actors: number
  // When its latest work was: the start of the latest bucket with any, or a thing's last change, in ms.
  last: number
  today: boolean
  thing: Thing | undefined
  children: Tile[]
  cuts: Cut[] | undefined
  // A kind's things, or the rest's: where they are read from, and whether they are.
  cursor: string | null
  read: boolean
  askedAt: number
  stale: boolean
  seenAt: number
  // Where it was, is going, and is, in the layout's own CSS pixels.
  from: Rect
  to: Rect
  at: Rect
  // The zoom that fills the stage with it, and its place among the tiles
  // drawn, and the last place of the tiles inside it.
  fill: number
  slot: number
  end: number
  // Its place along the scale (-1 for the rest of a kind).
  value: number
  label: Name | undefined
}
type FleetReply = {
  now: number
  bucket: "hour" | "day" | "week"
  kinds: [string, string, number, number, number, number, boolean][]
  keys: [string, number][]
}
type ThingsReply = {things: Thing[]; after: string | null}

const BUCKETS = {hour: 3_600_000, day: 86_400_000, week: 604_800_000}
const DAY = 86_400_000
// Children are asked for at this share of the zoom that fills the stage with
// their parent, a little before they start to show.
const ASK_FROM = 0.35
// How long an unanswered question waits before it is asked again, in ms.
const RETRY = 15_000
// The pages of things kept, the least lately seen let go first.
const KEEP_PAGES = 48
const STEP = 2
// The names on screen at once, and the room a name keeps around its words
// and the height of each line, in CSS pixels (as atlas_blocks.css sets them).
const MAX_NAMES = 160
const NAME_SIDE = 8
const NAME_TOP = 6
const LINE = 16
// The room the dot of a block changed today takes from its name's lines.
const DOT = 12
// The room between a card and its block, in CSS pixels.
const CARD_GAP = 8
// The narrowest line a word too long for it is broken across, in CSS pixels.
const BREAKS = 160
// The rest of a kind, among its things.
const REST = "+"

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value))
const inside = (rect: Rect, x: number, y: number) =>
  x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h

// The child of `t` at a point of the layout, if any.
function childAt(t: Tile, x: number, y: number) {
  for (const child of t.children) if (inside(child.at, x, y)) return child
  return undefined
}

// A tile let go, and all inside it: it is drawn no more.
function drop(t: Tile) {
  t.slot = -1
  for (const child of t.children) drop(child)
}

const numbers = new Intl.NumberFormat("en")
const plural = (count: number, one: string, many: string) => `${numbers.format(count)} ${count === 1 ? one : many}`
const dayOf = new Intl.DateTimeFormat("en-GB", {day: "numeric", month: "short", timeZone: "UTC"})
const clockOf = new Intl.DateTimeFormat("en-GB", {hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZone: "UTC"})

// How many lines words this wide, a space apart, take in a line `room` wide.
// A word wider than the line is broken across as many as it needs only on a
// line of at least `BREAKS` (a link or a long name with no spaces, on a block
// open in full); on a narrower one it does not fit (Infinity).
function rows(words: readonly number[], space: number, room: number) {
  let lines = 1
  let line = 0
  for (const word of words) {
    if (line > 0 && line + space + word <= room) {
      line += space + word
      continue
    }
    if (line > 0) lines += 1
    if (word > room && room < BREAKS) return Infinity
    const across = Math.max(1, Math.ceil(word / room))
    lines += across - 1
    line = word - (across - 1) * room
  }
  return lines
}

const blank = (): Rect => ({x: 0, y: 0, w: 0, h: 0})

function tile(type: Type, parent: Tile | undefined, key: string, project: string, kind: string, name: string): Tile {
  return {
    key,
    type,
    parent,
    project,
    kind,
    name,
    changes: 0,
    things: 0,
    actors: 0,
    last: 0,
    today: false,
    thing: undefined,
    children: [],
    cuts: undefined,
    cursor: null,
    read: false,
    askedAt: -Infinity,
    stale: false,
    seenAt: 0,
    from: blank(),
    to: blank(),
    at: blank(),
    fill: 1,
    slot: -1,
    end: -1,
    value: 0,
    label: undefined,
  }
}

export function createBlocksStage(root: HTMLElement, ask: Ask): BlocksStage {
  const stage = root.querySelector<HTMLElement>("[data-blocks-stage]")!
  const trailList = root.querySelector<HTMLOListElement>("[data-blocks-trail]")!
  const surface = root.querySelector<HTMLElement>("[data-blocks-surface]")!
  const namesBox = root.querySelector<HTMLElement>("[data-blocks-names]")!
  const empty = root.querySelector<HTMLElement>("[data-blocks-empty]")!
  const card = root.querySelector<HTMLElement>("[data-blocks-card]")!
  const level = root.querySelector<HTMLOutputElement>("[data-blocks-level]")!
  const said = root.querySelector<HTMLElement>("[data-blocks-said]")!
  const events = new AbortController()
  const listen = {signal: events.signal}

  // What the page drew: the kind of work shown, the window, and the names of projects and kinds.
  let kind = ""
  let windowKey = ""
  let from = 0
  let to = 0
  let rowsJson = ""
  let titles = new Map<string, string>()
  let kindNames = new Map<string, string>()

  // What was read: the fleet's tiles, as of `now` on the page's clock.
  let generation = 0
  let version = 0
  let now = Date.now()
  let bucket = BUCKETS.week
  let fleetAskedAt = -Infinity
  const fleet = tile("fleet", undefined, "", "", "", "Fleet")

  // The view.
  let width = 0
  let height = 0
  let focus = fleet
  let cursor: Tile | undefined
  let hover: Tile | undefined
  let hovering = false
  let pointerY = 0
  let keyed = false
  let pinned: {id: string; holder: Tile} | undefined
  let opening: Tile | undefined
  let moving: JSAnimation | undefined
  let easing: JSAnimation | undefined
  const ease = {t: 1}
  let trailPath: Tile[] = []
  let levelWord = ""

  // The tiles drawn, from the base of the tile in view, so they stay exact however deep the zoom.
  const data = new Float32Array(MAX_TILES * TILE_FLOATS)
  let count = 0
  let baseX = 0
  let baseY = 0
  let dirty = true

  // The fonts names are set in, as the page states them, for measuring.
  const measure = document.createElement("canvas").getContext("2d")!
  let titleFont = ""
  let smallFont = ""

  let island: {renderer(): BlocksRenderer | undefined; nudge(): void} | undefined

  const ZOOM = {min: 1, max: 4}
  const instant = () => still(root) || !lastInputByPointer()
  const until = () => Math.min(now, to)

  const camera = createCamera(surface, {
    onFrame: () => render(),
    onTap: (x, y, target) => tap(x, y, target),
    reducedMotion: () => still(root),
    zoom: ZOOM,
  })

  // ——— Words ———————————————————————————————————————————————————————————

  const counts = (t: Tile) =>
    t.type === "thing"
      ? [plural(t.changes, "change", "changes"), ...(t.actors > 1 ? [`${t.actors} Keys`] : [])].join(" · ")
      : [
          plural(t.changes, "change", "changes"),
          plural(t.things, "thing", "things"),
          ...(t.type === "rest" ? [] : [plural(t.actors, "Key", "Keys")]),
        ].join(" · ")

  function when(t: Tile) {
    if (t.type === "thing") {
      const thing = t.thing!
      return [thing.what, ...(thing.who ? [thing.who] : []), `${dayOf.format(thing.at)}, ${clockOf.format(thing.at)}`].join(" · ")
    }
    if (t.type === "rest") return ""
    if (t.today) return "Changed today"
    if (bucket === BUCKETS.week) return `Latest week of ${dayOf.format(t.last)}`
    if (bucket === BUCKETS.hour) return `Latest ${clockOf.format(t.last)}`
    return `Latest ${dayOf.format(t.last)}`
  }

  const describe = (t: Tile) => [t.name, counts(t), when(t)].filter(Boolean).join(", ")

  // ——— Colour ——————————————————————————————————————————————————————————

  // A tile's place along the scale: the rest of a kind has none. Every tint
  // is light enough under the page's ink (atlas.css), so names need no other.
  function colour(t: Tile) {
    if (t.type === "rest") {
      t.value = -1
      return
    }
    const last = t.type === "thing" ? t.last : Math.min(now, t.last + bucket)
    t.value = recency(last, from, until())
  }

  function recolour(t: Tile) {
    for (const child of t.children) {
      colour(child)
      recolour(child)
    }
  }

  // ——— Reading ——————————————————————————————————————————————————————————

  const titleOf = (project: string) => titles.get(project) ?? project
  const kindName = (key: string) => kindNames.get(key) ?? key

  // The children `weights` names, in the order they keep, each the one shown already or a new one.
  function merge(parent: Tile, weights: ReadonlyMap<string, number>, make: (key: string) => Tile) {
    const known = new Map(parent.children.map(child => [child.key, child]))
    const order = ordered(
      parent.children.filter(child => child.key !== REST).map(child => child.key),
      weights,
    )
    for (const child of parent.children) if (child.key !== REST && !weights.has(child.key)) drop(child)
    return order.map(key => known.get(key) ?? make(key))
  }

  function readFleet() {
    if (performance.now() - fleetAskedAt < RETRY) return
    fleetAskedAt = performance.now()
    const asOf = generation
    ask<FleetReply>("atlas_blocks_fleet", {}, reply => {
      if (asOf !== generation) return
      fleetAskedAt = -Infinity
      takeFleet(reply)
    })
  }

  function takeFleet(reply: FleetReply) {
    const update = fleet.children.length > 0
    now = reply.now * 1000
    bucket = BUCKETS[reply.bucket]
    const byProject = new Map<string, Map<string, FleetReply["kinds"][number]>>()
    for (const row of reply.kinds) {
      const kinds = byProject.get(row[0]) ?? new Map()
      kinds.set(row[1], row)
      byProject.set(row[0], kinds)
    }
    const keys = new Map(reply.keys)
    const weights = new Map<string, number>()
    for (const [project, kinds] of byProject) {
      let changes = 0
      for (const row of kinds.values()) changes += row[2]
      weights.set(project, changes)
    }

    fleet.children = merge(fleet, weights, key => tile("project", fleet, key, key, "", titleOf(key)))
    for (const project of fleet.children) {
      const kinds = byProject.get(project.key)!
      project.changes = weights.get(project.key)!
      project.things = 0
      project.last = 0
      project.today = false
      project.actors = keys.get(project.key) ?? 0
      for (const row of kinds.values()) {
        project.things += row[3]
        project.last = Math.max(project.last, row[5] * 1000)
        project.today ||= row[6]
      }
      const kindWeights = new Map<string, number>()
      for (const [key, row] of kinds) kindWeights.set(key, row[2])
      project.children = merge(project, kindWeights, key => tile("kind", project, key, project.key, key, kindName(key)))
      for (const each of project.children) {
        const row = kinds.get(each.key)!
        each.changes = row[2]
        each.things = row[3]
        each.actors = row[4]
        each.last = row[5] * 1000
        each.today = row[6]
        rest(each)
      }
    }
    empty.hidden = fleet.children.length > 0
    version += 1
    recolour(fleet)
    relayout(update && !still(root))
    if (cursor && !attached(cursor)) cursor = undefined
  }

  // The rest of a kind: its changes and things less those of the things read.
  function rest(holder: Tile) {
    const last = holder.children[holder.children.length - 1]
    if (last?.type !== "rest") return
    let changes = 0
    let things = 0
    for (const child of holder.children) {
      if (child.type !== "thing") continue
      changes += child.changes
      things += 1
    }
    last.changes = Math.max(1, holder.changes - changes)
    last.things = Math.max(1, holder.things - things)
    rest(last)
  }

  function readThings(holder: Tile) {
    if (holder.read && !holder.stale) return
    if (performance.now() - holder.askedAt < RETRY) return
    holder.askedAt = performance.now()
    const asOf = generation
    ask<ThingsReply>(
      "atlas_blocks_things",
      {project: holder.project, kind: holder.kind, after: holder.cursor},
      reply => {
        if (asOf !== generation || !attached(holder)) return
        holder.askedAt = -Infinity
        holder.stale = false
        takeThings(holder, reply)
      },
    )
  }

  function takeThings(holder: Tile, reply: ThingsReply) {
    const update = holder.read
    holder.read = true
    const byId = new Map(reply.things.map(thing => [thing.id, thing]))
    const weights = new Map(reply.things.map(thing => [thing.id, thing.changes]))
    const restWas = holder.children.find(child => child.type === "rest")
    const children = merge(holder, weights, key => tile("thing", holder, key, holder.project, holder.kind, ""))
    if (reply.after !== null) {
      const more = restWas ?? tile("rest", holder, REST, holder.project, holder.kind, "More")
      // What follows this page moved: the rest's own pages are read again.
      if (more.read && more.cursor !== reply.after) more.stale = true
      more.cursor = reply.after
      children.push(more)
    } else if (restWas) {
      drop(restWas)
    }
    holder.children = children
    const today = Math.floor(now / DAY) * DAY
    for (const child of children) {
      if (child.type !== "thing") continue
      const thing = byId.get(child.key)!
      child.thing = thing
      child.name = thing.title
      child.changes = thing.changes
      child.things = 1
      child.actors = thing.actors
      child.last = thing.at
      child.today = thing.at >= today
    }
    rest(holder)
    version += 1
    recolour(holder)
    letGo()
    relayout(update && !still(root))
    if (opening === holder) {
      opening = undefined
      cursor = holder.children[0] ?? holder
      say(cursor)
    }
    reach()
  }

  // Past the pages kept, the least lately seen are let go, unless the view is inside them.
  function letGo() {
    const held: Tile[] = []
    const gather = (t: Tile) => {
      for (const child of t.children) {
        if (child.read) held.push(child)
        gather(child)
      }
    }
    gather(fleet)
    if (held.length <= KEEP_PAGES) return
    held.sort((a, b) => a.seenAt - b.seenAt)
    let left = held.length
    for (const holder of held) {
      if (left <= KEEP_PAGES) break
      if (!attached(holder) || holds(holder, focus) || (cursor && holds(holder, cursor))) continue
      for (const child of holder.children) drop(child)
      holder.children = []
      holder.cuts = undefined
      holder.read = false
      left -= 1
    }
  }

  const holds = (outer: Tile, t: Tile) => {
    for (let at: Tile | undefined = t; at; at = at.parent) if (at === outer) return true
    return false
  }

  function attached(t: Tile) {
    for (let at = t; at.parent; at = at.parent) if (!at.parent.children.includes(at)) return false
    return true
  }

  // ——— Layout ——————————————————————————————————————————————————————————

  // Each tile as big as its changes, but the rest of a kind no bigger than a
  // third of the things beside it, so those always have the room to be seen:
  // its name and counts say what it holds.
  function lay(t: Tile) {
    if (t.children.length === 0) return
    const room = t === fleet ? t.to : inner(t.to, fills(t.to, width, height))
    let page = 0
    for (const child of t.children) if (child.type === "thing") page += child.changes
    const {rects, cuts} = squarify(
      t.children.map(child => (child.type === "rest" ? Math.min(child.changes, page / 3) : child.changes)),
      room,
      t.cuts,
    )
    t.cuts = cuts
    t.children.forEach((child, index) => {
      child.to = rects[index]
      lay(child)
    })
  }

  function snapshot(t: Tile) {
    for (const child of t.children) {
      const {from, to, at} = child
      // A new tile grows from its middle.
      if (at.w === 0 && at.h === 0) {
        from.x = to.x + to.w / 2
        from.y = to.y + to.h / 2
        from.w = 0
        from.h = 0
      } else {
        from.x = at.x
        from.y = at.y
        from.w = at.w
        from.h = at.h
      }
      snapshot(child)
    }
  }

  function tween(t: Tile) {
    for (const child of t.children) {
      between(child.from, child.to, ease.t, child.at)
      child.fill = fills(child.at, width, height)
      tween(child)
    }
  }

  // Each tile goes to its place in the layout: easing there for new counts,
  // at once for the first picture, a new size or less motion. The view keeps
  // to the tile it is in as that tile moves.
  function relayout(glide: boolean) {
    fleet.to = {x: 0, y: 0, w: width, h: height}
    fleet.at = fleet.to
    lay(fleet)
    snapshot(fleet)
    easing?.pause()
    easing = undefined
    if (!glide) return step(1)
    ease.t = 0
    easing = animate(ease, {
      t: 1,
      duration: SLOW,
      ease: EASE_OUT,
      onUpdate: () => step(ease.t),
      onComplete: () => {
        easing = undefined
      },
    })
  }

  function step(t: number) {
    const {x, y, w, h} = focus.at
    ease.t = t
    tween(fleet)
    follow(x, y, w, h, width, height)
    dirty = true
    render()
  }

  // The view, inside the tile in view as it was, moved and scaled with it to where it is.
  function follow(x: number, y: number, w: number, h: number, wasWidth: number, wasHeight: number) {
    const at = focus.at
    if (w <= 0 || h <= 0 || at.w <= 0 || at.h <= 0 || moving) return
    const scale = fills(at, width, height) / Math.min(wasWidth / w, wasHeight / h)
    camera.x = at.x + ((camera.x - x) * at.w) / w
    camera.y = at.y + ((camera.y - y) * at.h) / h
    camera.zoom = Math.max(ZOOM.min, camera.zoom * scale)
  }

  // ——— Drawing —————————————————————————————————————————————————————————

  function build() {
    dirty = false
    baseX = focus.at.x
    baseY = focus.at.y
    count = 0
    write(fleet)
    island?.renderer()?.tiles(data, count)
  }

  function write(t: Tile) {
    for (const child of t.children) {
      if (count >= MAX_TILES) {
        drop(child)
        continue
      }
      const {x, y, w, h} = child.at
      const at = count * TILE_FLOATS
      data[at] = x - baseX
      data[at + 1] = y - baseY
      data[at + 2] = w
      data[at + 3] = h
      data[at + 4] = child.value
      data[at + 5] = t === fleet ? 0 : t.fill
      data[at + 6] = count * 4 + (child.today ? 1 : 0) + (child.children.length > 0 ? 2 : 0)
      child.slot = count
      count += 1
      write(child)
      child.end = count - 1
    }
  }

  // The tile the ring is on: the keyboard's, while the picture has focus.
  const ringed = () => (keyed && document.activeElement === stage ? cursor : undefined)
  // The tile that stands out, with all inside it: the one under the pointer, or the ringed.
  const lit = () => (hovering ? hover : ringed())

  function paint() {
    const shown = lit()
    placeCard(shown)
    const renderer = island?.renderer()
    if (!renderer) return
    const ring = ringed()
    const on = shown && shown.slot >= 0
    renderer.view(
      camera.x - baseX,
      camera.y - baseY,
      camera.zoom,
      ring?.slot ?? -1,
      on ? shown.slot : -1,
      on ? shown.end : -1,
    )
    island!.nudge()
  }

  const screenX = (x: number) => (x - camera.x) * camera.zoom + width / 2
  const screenY = (y: number) => (y - camera.y) * camera.zoom + height / 2

  // The tile in view from a point at a zoom: the deepest there whose children
  // show; and the deepest tile there at all.
  function viewed(x: number, y: number, zoom: number): [Tile, Tile] {
    let next = fleet
    let deepest = fleet
    for (;;) {
      const into = childAt(next, x, y)
      if (!into) break
      deepest = into
      if (into.children.length === 0 || shown(zoom, into.fill) < 0.5) break
      next = into
    }
    return [next, deepest]
  }

  // Whether a tile is the one in view once it fills the stage: not when the
  // tile at its middle takes so much of it that that tile's children show too.
  function opens(t: Tile) {
    const zoom = Math.max(ZOOM.min, fills(t.to, width, height))
    const halfW = width / 2 / zoom
    const halfH = height / 2 / zoom
    const x = clamp(t.to.x + t.to.w / 2, halfW, width - halfW)
    const y = clamp(t.to.y + t.to.h / 2, halfH, height - halfH)
    return viewed(x, y, zoom)[0] === t
  }

  function render() {
    if (!width || !height) return
    const zoom = camera.zoom
    const halfW = width / 2 / zoom
    const halfH = height / 2 / zoom
    camera.x = clamp(camera.x, halfW, width - halfW)
    camera.y = clamp(camera.y, halfH, height - halfH)

    // The deepest tile at the middle bounds the zoom once it has no children.
    const [next, deepest] = viewed(camera.x, camera.y, zoom)
    ZOOM.max = deepest.children.length > 0 ? Infinity : Math.max(zoom, deepest.fill, 1)
    if (next !== focus) {
      focus = next
      dirty = true
      trail()
    }
    if (dirty) build()

    pass += 1
    frameAt = performance.now()
    visit(fleet, zoom)
    sweep()

    const word =
      focus === fleet
        ? "Projects"
        : focus.type === "project"
          ? "Kinds"
          : deepest.type === "thing" && zoom >= 0.9 * deepest.fill
            ? "Item"
            : "Items"
    if (word !== levelWord) level.value = levelWord = word
    paint()
  }

  // ——— Names ——————————————————————————————————————————————————————————

  const live: Name[] = []
  const spare: Name[] = []
  let pass = 0
  let frameAt = 0

  function makeName(): Name {
    const el = document.createElement("div")
    el.className = "atlas-blocks__name"
    el.hidden = true
    const link = el.appendChild(document.createElement("a"))
    // A drag that starts on a name moves the picture rather than carrying the link off,
    // and the names are reached from the picture, not by Tab.
    link.draggable = false
    link.tabIndex = -1
    const count = el.appendChild(document.createElement("small"))
    const detail = el.appendChild(document.createElement("small"))
    namesBox.append(el)
    return {
      el,
      link,
      count,
      detail,
      tile: undefined,
      pass: 0,
      version: -1,
      x: NaN,
      y: NaN,
      w: NaN,
      h: NaN,
      words: [],
      space: 0,
      countWidth: 0,
      detailWidth: 0,
    }
  }

  // How wide a line of text is in a font, a pixel to spare for the page's own setting of it.
  function widthOf(text: string, font: string) {
    measure.font = font
    return Math.ceil(measure.measureText(text).width) + 1
  }

  function fill(name: Name, t: Tile) {
    name.version = version
    name.el.toggleAttribute("data-today", t.today)
    name.link.textContent = t.name
    name.count.textContent = t.type === "thing" ? counts(t) : plural(t.changes, "change", "changes")
    name.detail.textContent = when(t)
    name.words = t.name.split(/\s+/).filter(Boolean).map(word => widthOf(word, titleFont))
    name.space = widthOf(" ", titleFont) - 1
    name.countWidth = widthOf(name.count.textContent, smallFont)
    name.detailWidth = name.detail.textContent ? widthOf(name.detail.textContent, smallFont) : 0
    name.w = NaN
    if (t.type === "thing") {
      const thing = t.thing!
      name.link.href = thing.path
      if (thing.live) {
        name.link.dataset.phxLink = "patch"
        name.link.dataset.phxLinkState = "push"
      } else {
        delete name.link.dataset.phxLink
        delete name.link.dataset.phxLinkState
      }
    } else {
      name.link.removeAttribute("href")
      delete name.link.dataset.phxLink
      delete name.link.dataset.phxLinkState
    }
  }

  // How a name fits a box `across` by `down`: its own lines, then its count
  // and when on a line each while there is room, or not at all (0) when its
  // own words do not fit whole.
  function fits(label: Name, t: Tile, across: number, down: number, opened: boolean) {
    const room = across - 2 * NAME_SIDE - (t.today ? DOT : 0)
    if (room <= 0 || label.words.length === 0) return 0
    const own = rows(label.words, label.space, room)
    const space = opened ? 1 : Math.floor((down - NAME_TOP) / LINE)
    if (own > space) return 0
    let lines = own
    if (lines < space && label.countWidth <= room) {
      lines += 1
      if (lines < space && label.detailWidth > 0 && label.detailWidth <= room) lines += 1
    }
    return lines - own + 1
  }

  // A tile's name, in its band once its children show, or in its top left,
  // in the part of either on screen.
  function name(t: Tile, zoom: number, opened: boolean) {
    const x = screenX(t.at.x)
    const y = screenY(t.at.y)
    const left = Math.round(Math.max(x, 0))
    const top = Math.round(Math.max(y, 0))
    const across = Math.round(Math.min(x + t.at.w * zoom, width) - left)
    const down = Math.round(Math.min(y + (opened ? (HEAD * zoom) / t.fill : t.at.h * zoom), height) - top)
    if (across < 2 * NAME_SIDE + 16 || down < NAME_TOP + LINE) return
    let label = t.label
    if (!label) {
      if (live.length >= MAX_NAMES) return
      label = spare.pop() ?? makeName()
      label.tile = t
      label.version = -1
      t.label = label
      live.push(label)
    }
    if (label.version !== version) fill(label, t)
    label.pass = pass
    if (left !== label.x || top !== label.y) {
      label.el.style.transform = `translate3d(${left}px, ${top}px, 0)`
      label.x = left
      label.y = top
    }
    if (across !== label.w || down !== label.h) {
      label.el.style.width = `${across}px`
      label.el.style.height = `${down}px`
      label.w = across
      label.h = down
      // 0: hidden; 1: its own words; 2: and its count; 3: and when.
      const shows = fits(label, t, across, down, opened)
      label.el.hidden = shows === 0
      label.count.hidden = shows < 2
      label.detail.hidden = shows < 3
    }
  }

  // Every tile whose parent shows its children, on screen: its name, and its things asked for as it grows.
  function visit(t: Tile, zoom: number) {
    const alpha = t === fleet ? 1 : shown(zoom, t.fill)
    for (const child of t.children) {
      const x = screenX(child.at.x)
      const y = screenY(child.at.y)
      if (x > width || y > height || x + child.at.w * zoom < 0 || y + child.at.h * zoom < 0) continue
      const opened = child.children.length > 0 && shown(zoom, child.fill) >= 0.5
      if (alpha >= 0.5) name(child, zoom, opened)
      if (child.type === "kind" || child.type === "rest") {
        child.seenAt = frameAt
        if (zoom / child.fill >= ASK_FROM) readThings(child)
      }
      if (child.children.length > 0 && zoom / child.fill >= SHOW_FROM) visit(child, zoom)
    }
  }

  function sweep() {
    for (let index = live.length - 1; index >= 0; index--) {
      const label = live[index]
      if (label.pass === pass) continue
      // A name in focus stays until focus leaves it.
      if (label.el.contains(document.activeElement)) continue
      label.el.hidden = true
      label.tile!.label = undefined
      label.tile = undefined
      label.version = -1
      label.x = label.y = label.w = label.h = NaN
      live[index] = live[live.length - 1]
      live.pop()
      spare.push(label)
    }
  }

  // ——— The path ————————————————————————————————————————————————————————

  function trail() {
    const path: Tile[] = []
    for (let at: Tile | undefined = focus; at; at = at.parent) path.unshift(at)
    trailPath = path
    trailList.replaceChildren(
      ...path.map((t, index) => {
        const item = document.createElement("li")
        if (index === path.length - 1) {
          const here = item.appendChild(document.createElement("span"))
          here.textContent = t.name
          here.setAttribute("aria-current", "location")
        } else {
          const back = item.appendChild(document.createElement("button"))
          back.type = "button"
          back.dataset.blocksStep = String(index)
          back.textContent = t.name
        }
        return item
      }),
    )
  }

  // ——— Moving ——————————————————————————————————————————————————————————

  function stop() {
    moving?.pause()
    moving = undefined
  }

  // Moves to a point and a zoom, gliding in under 300 ms or at once: the zoom
  // eases by its ratio, and the point moves across the screen as evenly as
  // the zoom allows.
  function go(x: number, y: number, zoom: number, glide: boolean) {
    stop()
    ZOOM.max = Math.max(ZOOM.max, zoom)
    const target = Math.max(ZOOM.min, zoom)
    if (!glide || still(root)) return camera.jumpTo(x, y, target)
    const [fromX, fromY, fromZoom] = [camera.x, camera.y, camera.zoom]
    const [offsetX, offsetY] = [(x - fromX) * fromZoom, (y - fromY) * fromZoom]
    const ratio = Math.log(target / fromZoom)
    const state = {t: 0}
    moving = animate(state, {
      t: 1,
      duration: SLOW,
      ease: EASE_OUT,
      onUpdate: () => {
        const at = fromZoom * Math.exp(ratio * state.t)
        camera.jumpTo(x - (offsetX * (1 - state.t)) / at, y - (offsetY * (1 - state.t)) / at, at)
      },
      onComplete: () => {
        moving = undefined
      },
    })
  }

  // Fills the stage with a tile: its children show, or, for a thing, the thing itself.
  function open(t: Tile, glide: boolean) {
    const {x, y, w, h} = t.to
    go(x + w / 2, y + h / 2, fills(t.to, width, height), glide)
  }

  const framed = (t: Tile) =>
    t.type === "thing" && camera.zoom >= 0.9 * fills(t.to, width, height) && inside(t.to, camera.x, camera.y)

  const local = (clientX: number, clientY: number) => {
    const box = surface.getBoundingClientRect()
    return [clientX - box.left - surface.clientLeft, clientY - box.top - surface.clientTop] as const
  }

  // The deepest tile shown at a point of the surface.
  function tileAt(x: number, y: number) {
    const zoom = camera.zoom
    const wx = camera.x + (x - width / 2) / zoom
    const wy = camera.y + (y - height / 2) / zoom
    let found: Tile | undefined
    let at = fleet
    while (at === fleet || shown(zoom, at.fill) >= 0.5) {
      const into = childAt(at, wx, wy)
      if (!into) break
      found = into
      at = into
    }
    return found
  }

  function tap(clientX: number, clientY: number, target: EventTarget | null) {
    if (target instanceof Element && target.closest("a[href], button")) return
    const [x, y] = local(clientX, clientY)
    const hit = tileAt(x, y)
    if (!hit) return
    leave()
    cursor = hit
    open(hit, !instant())
  }

  // ——— The keyboard ————————————————————————————————————————————————————

  const say = (t: Tile) => {
    said.textContent = describe(t)
  }

  // The sibling nearest in the direction of an arrow, by the middles of their tiles.
  function beside(t: Tile, dx: number, dy: number) {
    const cx = t.to.x + t.to.w / 2
    const cy = t.to.y + t.to.h / 2
    let best: Tile | undefined
    let score = Infinity
    for (const other of t.parent?.children ?? []) {
      if (other === t || other.to.w <= 0 || other.to.h <= 0) continue
      const ox = other.to.x + other.to.w / 2 - cx
      const oy = other.to.y + other.to.h / 2 - cy
      const ahead = ox * dx + oy * dy
      if (ahead <= 0) continue
      const aside = Math.abs(ox * dy - oy * dx)
      const distance = ahead + 2 * aside
      if (distance < score) {
        score = distance
        best = other
      }
    }
    return best
  }

  // Keeps the ringed tile in view: a thing filling the stage hands the stage
  // to its neighbour; anything else off screen is brought to the middle.
  function reveal(t: Tile, was: Tile) {
    if (framed(was)) return open(t, false)
    const x = screenX(t.to.x + t.to.w / 2)
    const y = screenY(t.to.y + t.to.h / 2)
    if (x < 0 || x > width || y < 0 || y > height) camera.jumpTo(t.to.x + t.to.w / 2, t.to.y + t.to.h / 2)
    render()
  }

  function enter(t: Tile) {
    if (t.type === "thing") {
      if (framed(t)) return t.label?.link.click()
      open(t, false)
      return say(t)
    }
    open(t, false)
    if (t.children.length > 0) {
      cursor = t.children[0]
      say(cursor)
    } else {
      // The kind's things are on their way: the ring goes to the first once read.
      opening = t
      say(t)
    }
  }

  // Back up a level: from a thing filling the stage to the things around it,
  // or from the tile in view to its parent's. A tile that one of its own
  // nearly fills still shows that one's children as it opens, so the way up
  // passes it by.
  function up() {
    if (cursor && framed(cursor)) {
      open(focus, false)
      return
    }
    if (focus === fleet) return
    let left = focus
    let target = left.parent!
    while (target !== fleet && !opens(target)) {
      left = target
      target = target.parent!
    }
    open(target, false)
    cursor = left
    say(left)
  }

  function keydown(event: KeyboardEvent) {
    if (event.altKey || event.ctrlKey || event.metaKey) return
    if (event.target instanceof Element && event.target.closest(".atlas-blocks__name, [data-blocks-card]")) {
      if (event.key !== "Escape") return
      event.preventDefault()
      event.stopPropagation()
      if (!card.hidden) closeCard()
      stage.focus({preventScroll: true})
      return
    }
    if (event.target !== stage) return
    if (event.key === "Escape") {
      // Escape only ever puts the card away or goes back up inside the picture.
      event.preventDefault()
      event.stopPropagation()
      if (!card.hidden) return closeCard()
    }
    keyed = true
    stop()
    if (!cursor || !attached(cursor)) cursor = focus.children[0]
    if (!cursor) return
    const moves: Record<string, [number, number]> = {
      ArrowLeft: [-1, 0],
      ArrowRight: [1, 0],
      ArrowUp: [0, -1],
      ArrowDown: [0, 1],
    }
    const move = moves[event.key]
    if (move) {
      event.preventDefault()
      const next = beside(cursor, move[0], move[1])
      if (next) {
        const was = cursor
        cursor = next
        reveal(next, was)
      }
      say(cursor)
      paint()
    } else if (event.key === "+" || event.key === "=" || event.key === "-" || event.key === "_") {
      event.preventDefault()
      const factor = event.key === "+" || event.key === "=" ? STEP : 1 / STEP
      const box = surface.getBoundingClientRect()
      const {x, y, w, h} = cursor.at
      camera.zoomBy(factor, box.left + screenX(x + w / 2), box.top + screenY(y + h / 2))
    } else if (event.key === "Enter") {
      event.preventDefault()
      enter(cursor)
    } else if (event.key === "Escape") {
      up()
    }
  }

  // ——— The pointer ——————————————————————————————————————————————————————

  // ——— The card ————————————————————————————————————————————————————————

  const cardKind = card.querySelector<HTMLElement>("[data-card-kind]")!
  const cardTitle = card.querySelector<HTMLElement>("[data-card-title]")!
  const cardCounts = card.querySelector<HTMLElement>("[data-card-counts]")!
  const cardWhen = card.querySelector<HTMLElement>("[data-card-when]")!
  let cardFor: Tile | undefined
  let cardVersion = -1
  // The tile whose card was put away, until another is chosen.
  let closed: Tile | undefined

  function writeCard(t: Tile) {
    cardFor = t
    cardVersion = version
    cardKind.textContent =
      t.type === "project" ? "Project" : t.type === "kind" ? "Kind" : t.type === "rest" ? kindName(t.kind) : t.thing!.what
    cardTitle.textContent = t.name
    cardCounts.textContent = counts(t)
    if (t.type === "thing") {
      const thing = t.thing!
      cardWhen.textContent = [...(thing.who ? [thing.who] : []), `${dayOf.format(thing.at)}, ${clockOf.format(thing.at)}`].join(" · ")
    } else {
      cardWhen.textContent = when(t)
    }
    cardWhen.hidden = cardWhen.textContent === ""
  }

  // The card for the tile that stands out, beside it on whichever side has
  // the room (right, left, below, above), level with the pointer or the
  // tile's top; with no side that holds it, there is none, so it never
  // covers its tile.
  function placeCard(t: Tile | undefined) {
    if (t !== closed) closed = undefined
    if (!t || t === closed || t.slot < 0) return void (card.hidden = true)
    if (t !== cardFor || cardVersion !== version) writeCard(t)
    card.hidden = false
    const w = card.offsetWidth
    const h = card.offsetHeight
    const zoom = camera.zoom
    const x0 = screenX(t.at.x)
    const y0 = screenY(t.at.y)
    const x1 = x0 + t.at.w * zoom
    const y1 = y0 + t.at.h * zoom
    const level = clamp((hovering ? pointerY - 16 : Math.max(y0, 0)), 0, Math.max(0, height - h))
    const across = clamp(Math.max(x0, 0), 0, Math.max(0, width - w))
    const spots: [number, number, boolean][] = [
      [x1 + CARD_GAP, level, x1 + CARD_GAP + w <= width],
      [x0 - CARD_GAP - w, level, x0 - CARD_GAP - w >= 0],
      [across, y1 + CARD_GAP, y1 + CARD_GAP + h <= height],
      [across, y0 - CARD_GAP - h, y0 - CARD_GAP - h >= 0],
    ]
    const spot = spots.find(([, , room]) => room)
    if (!spot) return void (card.hidden = true)
    card.style.transform = `translate3d(${Math.round(spot[0])}px, ${Math.round(spot[1])}px, 0)`
  }

  function closeCard() {
    closed = cardFor
    card.hidden = true
  }

  // The pointer left the blocks: nothing stands out but the ring.
  const leave = () => {
    if (!hovering) return
    hovering = false
    paint()
  }

  function pointermove(event: PointerEvent) {
    if (event.target instanceof Element && card.contains(event.target)) return
    if (event.pointerType === "touch" || surface.hasAttribute("data-dragging")) return leave()
    const [x, y] = local(event.clientX, event.clientY)
    const hit = tileAt(x, y)
    if (!hit) return leave()
    hover = hit
    hovering = true
    pointerY = y
    paint()
  }

  function clicked(event: MouseEvent) {
    const target = event.target instanceof Element ? event.target : null
    if (target?.closest("[data-card-close]")) {
      const focused = card.contains(document.activeElement)
      closeCard()
      if (focused) stage.focus({preventScroll: true})
      return
    }
    const zoom = target?.closest<HTMLElement>("[data-blocks-zoom]")
    if (zoom) {
      const factor = zoom.dataset.blocksZoom === "in" ? STEP : 1 / STEP
      go(camera.x, camera.y, camera.zoom * factor, byPointer(event) && !still(root))
      return
    }
    const back = target?.closest<HTMLElement>("[data-blocks-step]")
    if (back) {
      const t = trailPath[Number(back.dataset.blocksStep)]
      if (!t) return
      cursor = focus
      open(t, byPointer(event) && !still(root))
    }
  }

  // A thing chosen in the strip beside the picture: its project, then its
  // kind, then the thing itself, filling the stage once read.
  function focusThing(event: Event) {
    const {id, project, kind: of} = (event as CustomEvent<{id: string; project: string; kind: string}>).detail
    const holder = fleet.children.find(t => t.key === project)?.children.find(t => t.key === of)
    if (!holder) return
    keyed = !lastInputByPointer()
    pinned = {id, holder}
    cursor = holder
    open(holder, !instant())
    if (keyed) stage.focus({preventScroll: true})
    if (holder.read) reach()
    else {
      holder.askedAt = -Infinity
      readThings(holder)
    }
  }

  // The thing chosen in the strip, once its kind's things are read.
  function reach() {
    if (!pinned || !pinned.holder.read) return
    const {id, holder} = pinned
    const found = holder.children.find(child => child.key === id)
    if (found) {
      pinned = undefined
      cursor = found
      open(found, !instant())
      say(found)
      return
    }
    const more = holder.children.find(child => child.type === "rest")
    pinned = more ? {id, holder: more} : undefined
    if (more) readThings(more)
  }

  const interrupt = () => {
    stop()
    keyed = false
  }

  stage.addEventListener("keydown", keydown, listen)
  root.addEventListener("click", clicked, listen)
  root.addEventListener("atlas:focus", focusThing, listen)
  surface.addEventListener("pointermove", pointermove, listen)
  surface.addEventListener("pointerleave", leave, listen)
  // The card is read and pressed where it stands, and never starts a drag.
  card.addEventListener("pointerdown", event => event.stopPropagation(), listen)
  surface.addEventListener("pointerdown", interrupt, {...listen, capture: true})
  surface.addEventListener(
    "wheel",
    () => {
      stop()
      leave()
    },
    {...listen, passive: true, capture: true},
  )
  stage.addEventListener("focus", () => paint(), listen)
  stage.addEventListener("blur", () => paint(), listen)

  // ——— The page ————————————————————————————————————————————————————————

  function readNames() {
    const json = root.dataset.rows ?? "[]"
    if (json === rowsJson && kindNames.size > 0) return
    rowsJson = json
    titles = new Map(JSON.parse(json) as [string, string][])
    kindNames = new Map(JSON.parse(root.dataset.kinds ?? "[]") as [string, string][])
    for (const project of fleet.children) project.name = titleOf(project.key)
    version += 1
    trail()
  }

  function forget() {
    generation += 1
    fleetAskedAt = -Infinity
    fleet.children = []
    fleet.cuts = undefined
    focus = fleet
    cursor = undefined
    hover = undefined
    pinned = undefined
    opening = undefined
    easing?.pause()
    easing = undefined
    dirty = true
    empty.hidden = true
    trail()
  }

  function update() {
    readNames()
    const nextKind = root.dataset.kind ?? "all"
    const nextWindow = `${root.dataset.window}:${root.dataset.from}:${root.dataset.to}`
    if (nextKind !== kind || nextWindow !== windowKey) {
      kind = nextKind
      windowKey = nextWindow
      from = Number(root.dataset.from) * 1000
      to = Number(root.dataset.to) * 1000
      forget()
      readFleet()
      if (width) camera.jumpTo(width / 2, height / 2, 1)
    }
    render()
  }

  function changed() {
    fleetAskedAt = -Infinity
    const stale = (t: Tile) => {
      for (const child of t.children) {
        if (child.read) {
          child.stale = true
          child.askedAt = -Infinity
        }
        stale(child)
      }
    }
    stale(fleet)
    readFleet()
    render()
  }

  const resize = new ResizeObserver(() => {
    const [w, h] = [surface.clientWidth, surface.clientHeight]
    if (w === width && h === height) return
    const first = !width
    const {x, y, w: was, h: tall} = focus.at
    const [wasWidth, wasHeight] = [width, height]
    width = w
    height = h
    fleet.to = {x: 0, y: 0, w, h}
    fleet.at = fleet.to
    lay(fleet)
    snapshot(fleet)
    easing?.pause()
    easing = undefined
    ease.t = 1
    tween(fleet)
    if (first) camera.jumpTo(w / 2, h / 2, 1)
    else follow(x, y, was, tall, wasWidth, wasHeight)
    dirty = true
    render()
  })
  resize.observe(surface)

  if (!navigator.gpu) surface.dataset.atlasStill = "true"
  const controller = createCanvasIsland<BlocksRenderer>(surface, {}, {
    canvasSelector: "[data-blocks-canvas]",
    readyFlag: "blocksReady",
    // The picture is the page's content, so it is drawn for every reader.
    motionSensitive: false,
    continuous: false,
    browserLoad: async (canvas, size, lost) => {
      const {createBlocksRenderer} = await import("./renderer")
      return createBlocksRenderer(canvas, size, lost)
    },
    interact: ({renderer, nudge, onReady}) => {
      island = {renderer, nudge}
      onReady(() => {
        retone()
        renderer()?.tiles(data, count)
        paint()
      })
      const forgetTheme = watchTheme(retone)
      return () => {
        forgetTheme()
        island = undefined
        // The GPU is not going to draw: the page says so, and the List has it all.
        surface.dataset.atlasStill = "true"
      }
    },
  })

  // The scale, the rest of a kind, the ground, the hairline, the ring and the
  // dot of today, as the page states them now, and the fonts of the names.
  function retone() {
    island
      ?.renderer()
      ?.tones(
        tone(surface, "--atlas-tone-1"),
        tone(surface, "--atlas-tone-2"),
        tone(surface, "--atlas-tone-3"),
        tone(surface, "--atlas-rest"),
        tone(surface, "--atlas-ground"),
        tone(surface, "--atlas-line"),
        tone(surface, "--color-focus"),
        tone(surface, "--atlas-today"),
      )
    const probe = spare.pop() ?? makeName()
    titleFont = getComputedStyle(probe.link).font
    smallFont = getComputedStyle(probe.count).font
    spare.push(probe)
    version += 1
    recolour(fleet)
    dirty = true
    render()
  }

  // Names are measured again once the page's own fonts arrive.
  void document.fonts.ready.then(() => {
    if (events.signal.aborted) return
    retone()
  })

  retone()
  controller.mount()
  update()

  return {
    update,
    changed,
    pause: () => controller.pause(),
    resume() {
      controller.resume()
      changed()
    },
    destroy() {
      stop()
      easing?.pause()
      events.abort()
      resize.disconnect()
      camera.destroy()
      controller.destroy()
    },
  }
}
