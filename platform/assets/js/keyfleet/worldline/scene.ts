/**
 * Where everything on a fleet's Worldline stands, in space and on the
 * screen. The line is an axis through time, the past to the left. The sun
 * stands on it at now and moves on with real time, and the line is the path
 * it has come. Workspace, Code and Notebooks are planets, each orbiting the
 * line on its own circle at its own fixed period for ever, so each traces a
 * perfect helix from as far back as the picture reaches to the planet beside
 * the sun. An event of theirs is a bead on its planet's helix at the event's
 * time. Each room is a line of its own beside the axis, inside the first
 * orbit, with a square pixel for each post. Everything fleet-wide is a point
 * on the line itself.
 *
 * In symbols: with x along the line, the sun at time T stands at (v·T, 0, 0)
 * and planet p, of radius R, period P and phase φ, at
 * B(t) = (v·t, R·cos(2πt/P + φ), R·sin(2πt/P + φ)). Its trail is B(t) for
 * every t from the left of the picture up to T and no further, so the planet
 * itself always stands in the plane of the present, x = v·T, on a circle of
 * radius R around the sun. Here v is 1 / `Lens.unit` and x is measured from
 * the middle of the picture.
 *
 * The picture flies. The orbits run on ahead of now by `flown` seconds, so
 * each planet circles the line faster than real time and its whole helix
 * turns about the line with it. An event never moves along the line: its
 * bead keeps its place at its own time and turns with its helix, and the
 * line, its length and its time scale are the same however far the picture
 * has flown. Only real time moves things along the line: the sun moves on
 * and new events arrive at theirs.
 *
 * Every place is a pure function of time, the flight, the orbits' constants
 * and the camera; the events loaded decide nothing about where anything
 * stands, so pages read later extend the same helices without moving
 * anything. The shader draws the same sums (`shader.ts`) and picking reads
 * them here, so a mark is found exactly where it is drawn. The camera is
 * vgpu's orbit rig, and its matrices place everything both here and on the
 * GPU.
 *
 * Times are seconds from the anchor, the moment the page was first read; the
 * orbits turn by the absolute time, so they stand the same whenever it was.
 * Space is measured in units of half the picture's height, the line along x.
 */
import {orbitRig, perspective, rigPose, viewMatrices} from "vgpu/scene"

/** One event, as the page sends it (`KeyfleetWeb.WorldlineLive`). */
export type WorldEvent = {
  readonly id: string
  /** When it happened, in milliseconds since 1970. */
  readonly at: number
  /** "workspace", "code", "notebooks", "room:<slug>", or "line" for everything fleet-wide. */
  readonly trail: string
  readonly kind: string
  /** A room's post's place in its room, counting from 1; null for the rest. */
  readonly place: number | null
  readonly who: string | null
  readonly what: string
  readonly title: string
  readonly path: string
  readonly live: boolean
}

export const DAY = 86_400

/** The colours a picture is drawn in, in the shader's palette order; each is `--worldline-<name>` on the page. */
export const TONES = [
  "line",
  "workspace",
  "code",
  "notebooks",
  "chat-1",
  "chat-2",
  "chat-3",
  "chat-4",
  "chat-5",
  "chat-6",
  "proposals",
  "votes",
  "polls",
  "keys",
  "shards",
  "present",
  "treasury",
  "projects",
] as const

export const TONE = Object.fromEntries(TONES.map((name, index) => [name, index])) as Record<
  (typeof TONES)[number],
  number
>

/** How many tints the rooms take turns in. */
export const CHAT_TINTS = 6

/** How a mark is drawn: a round bead, a square pixel, a ring, a tick across the line, a planet or the sun. */
export const FORM = {round: 0, pixel: 1, ring: 2, tick: 3, planet: 4, sun: 5} as const

export type Planet = {
  readonly name: "workspace" | "code" | "notebooks"
  /** How far out it orbits, in units. */
  readonly radius: number
  /** The seconds one turn takes. */
  readonly period: number
  /** Where around the line it stood as 1970 began, in radians. */
  readonly offset: number
  /** Its path's width in CSS pixels, and how strongly it is drawn, 0..1. */
  readonly width: number
  readonly strength: number
  readonly tone: number
}

/** The planets, innermost first: Workspace turns once a day, Code every three days, Notebooks once a week. */
export const PLANETS: readonly Planet[] = [
  {name: "workspace", radius: 0.3, period: DAY, offset: 0, width: 2.4, strength: 1, tone: TONE.workspace},
  {name: "code", radius: 0.48, period: 3 * DAY, offset: 2.1, width: 2, strength: 0.95, tone: TONE.code},
  {name: "notebooks", radius: 0.66, period: 7 * DAY, offset: 4.2, width: 1.6, strength: 0.9, tone: TONE.notebooks},
]

const OUTER = PLANETS[PLANETS.length - 1].radius

/** How far the camera stands from where it looks, in units: far enough that the perspective stays gentle. */
export const DISTANCE = 7

/**
 * The seconds across the picture it opens on, and shows at 100%: sixteen
 * hours, close in, so the helices read as long waves running off from the sun.
 */
export const OPENING = 16 * 3600

/**
 * How the camera looks at the line, as vgpu's orbit rig takes it: turned
 * around it (yaw, about the upright axis) and up or down (pitch), in radians.
 */
export type Camera = {readonly yaw: number; readonly pitch: number}

/**
 * The view the picture opens on and Reset returns to: three-quarters on,
 * from just above the line, so it runs off to the left into the distance and
 * the sun stands near the right, its orbits a tall ellipse.
 */
export const HOME: Camera = {yaw: 0.8, pitch: 0.08}

/** As far as the camera turns: almost down the line either way, and well short of straight down or up. */
export const YAW_LIMIT = 1.48
export const PITCH_LIMIT = 1.2

/** What the picture shows. */
export type Frame = {
  /** Its size in CSS pixels. */
  readonly width: number
  readonly height: number
  /** Seconds from the anchor at the middle, where the camera looks. */
  readonly mid: number
  /** Seconds across the picture's width, seen side on. */
  readonly span: number
  /** Seconds from the anchor to now, where the sun stands. */
  readonly now: number
  /** The anchor, in milliseconds since 1970. */
  readonly anchor: number
  readonly camera: Camera
  /** Seconds the orbits have run on ahead of now as the picture flies. */
  readonly flown: number
}

export type Vec3 = readonly [number, number, number]

/** The camera worked out for a frame: where it stands, which way it faces, and its scale. */
export type Lens = {
  readonly eye: Vec3
  readonly right: Vec3
  readonly up: Vec3
  readonly forward: Vec3
  /** vgpu's projection times view, column by column, as the shaders take it. */
  readonly viewProjection: Float32Array<ArrayBuffer>
  /** Seconds along the line in one unit. */
  readonly unit: number
  /** CSS pixels a unit spans at depth 1: a unit at the camera's distance spans half the height. */
  readonly focal: number
  /** The picture's width against its height. */
  readonly aspect: number
}

/** A point as the picture shows it: where, in CSS pixels, and how far in front of the camera, in units. */
export type Seen = {readonly x: number; readonly y: number; readonly depth: number}

const dot = (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

const smoothstep = (low: number, high: number, k: number) => {
  const x = Math.min(1, Math.max(0, (k - low) / (high - low)))
  return x * x * (3 - 2 * x)
}

// The lens's upright field of view, in degrees, so a unit at the camera's
// distance spans half the picture's height; and the depths it cuts away
// before and beyond, in units.
const FIELD = (2 * Math.atan(1 / DISTANCE) * 180) / Math.PI
const NEAR = 0.3
const FAR = 100

/** The camera for `frame`: vgpu's orbit rig looking at the line at the middle's time from `DISTANCE` away. */
export function lens(frame: Frame): Lens {
  const pose = rigPose(orbitRig({yaw: frame.camera.yaw, pitch: frame.camera.pitch, distance: DISTANCE}), {
    position: new Float32Array(3),
    quaternion: new Float32Array(4),
  })
  const aspect = frame.width / frame.height
  const projection = perspective({fov: FIELD, near: NEAR, far: FAR}, aspect, new Float32Array(16))
  const matrices = {view: new Float32Array(16), viewProjection: new Float32Array(16)}
  viewMatrices(pose, projection, matrices)
  // The view's rows: the camera's right, its up, and the way behind it.
  const view = matrices.view
  return {
    eye: [pose.position[0], pose.position[1], pose.position[2]],
    right: [view[0], view[4], view[8]],
    up: [view[1], view[5], view[9]],
    forward: [-view[2], -view[6], -view[10]],
    viewProjection: matrices.viewProjection,
    unit: frame.span / (2 * aspect),
    focal: (DISTANCE * frame.height) / 2,
    aspect,
  }
}

/** Where a point at `t`, `radius` out from the line and `angle` around it, stands in space. */
export function point(t: number, radius: number, angle: number, frame: Frame, at: Lens): Vec3 {
  return [(t - frame.mid) / at.unit, radius * Math.cos(angle), radius * Math.sin(angle)]
}

/** Where a point in space stands in the picture, by the lens's matrix as the GPU places it. */
export function project(p: Vec3, frame: Frame, at: Lens): Seen {
  const m = at.viewProjection
  const x = m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12]
  const y = m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13]
  const depth = m[3] * p[0] + m[7] * p[1] + m[11] * p[2] + m[15]
  const w = Math.max(depth, 1e-3)
  return {x: ((x / w + 1) * frame.width) / 2, y: ((1 - y / w) * frame.height) / 2, depth}
}

// Nearer the camera than this, everything has faded out; past the far
// depth, everything has faded into the distance.
const NEAR_FADE = 0.15 * DISTANCE
const farFade = (at: Lens) => DISTANCE + 5 * at.aspect

/**
 * How clearly something at `depth` shows, 0..1: what comes very near the
 * camera fades out before it, and the far past fades into the distance.
 */
export function clear(depth: number, at: Lens): number {
  return smoothstep(NEAR_FADE, 0.35 * DISTANCE, depth) * (1 - smoothstep(DISTANCE + 2.2 * at.aspect, farFade(at), depth))
}

/**
 * How near the camera a point `radius` out stands against the line at its
 * time, -1 behind the line to 1 in front, which draws the far side fainter
 * and finer.
 */
export function nearness(p: Vec3, radius: number, at: Lens): number {
  if (radius === 0) return 0
  return Math.max(-1, Math.min(1, -(p[1] * at.forward[1] + p[2] * at.forward[2]) / radius))
}

/** How far around the line `planet` stands at `t`, in radians: by the absolute time, so the same whenever the page was read. */
export function orbitAngle(planet: Planet, t: number, anchor: number): number {
  const turns = (anchor / 1000 + t) / planet.period
  return 2 * Math.PI * (turns - Math.floor(turns)) + planet.offset
}

/** Never further than this along the line either way, in units. */
const MOST_REACH = 10_000

/**
 * How far the drawn history reaches, in seconds from the anchor: out either
 * way until the paths leave the picture, fade into the distance or pass
 * behind the camera, so no path ends in view; and never past now, nor past
 * `until` while the picture is first drawn out.
 */
export function reach(frame: Frame, at: Lens, until = Infinity): {readonly from: number; readonly to: number} {
  const fades = farFade(at)
  // Whether any of the paths around the line `x` units from the middle shows.
  const shows = (x: number) => {
    const depth = DISTANCE + x * at.forward[0]
    if (depth + OUTER < NEAR_FADE || depth - OUTER > fades) return false
    if (depth - OUTER < NEAR_FADE) return true
    const seen = project([x, 0, 0], frame, at)
    const margin = (OUTER * at.focal) / depth + 24
    return seen.x > -margin && seen.x < frame.width + margin && seen.y > -margin && seen.y < frame.height + margin
  }
  const out = (direction: number) => {
    let x = 0.5
    while (x < MOST_REACH && shows(direction * x)) x *= 1.25
    return direction * x * at.unit
  }
  const from = frame.mid + out(-1)
  return {from, to: Math.max(from, Math.min(frame.now, until, frame.mid + out(1)))}
}

/** Pieces of path in one instance on the GPU, and the most samples one path is drawn in. */
export const SEGMENTS = 64
const MOST_SAMPLES = 32_768

/** Instances each planet's circle in the plane of the present takes: smooth at any size it is drawn. */
export const RING_PIECES = 4

/**
 * A path as the GPU draws it this frame: from and to, in seconds from the
 * middle, the seconds between its samples, and how many instances of
 * `SEGMENTS` it takes.
 */
export type Run = {readonly from: number; readonly to: number; readonly step: number; readonly pieces: number}

/** A planet's path this frame, and how far into its turn it stands at the middle's time, 0..1. */
export type Orbit = Run & {readonly phase: number}

const run = (span: {from: number; to: number}, mid: number, finest: number): Run => {
  const length = Math.max(0, span.to - span.from)
  const step = Math.max(finest, length / MOST_SAMPLES)
  return {from: span.from - mid, to: span.to - mid, step, pieces: length > 0 ? Math.ceil(length / step / SEGMENTS) : 0}
}

// As the picture flies, the orbits stand where `orbitAngle` has them
// `flown` seconds on.
const phaseAt = (planet: Planet, frame: Frame) => {
  const turns = (frame.anchor / 1000 + frame.mid + frame.flown) / planet.period
  return turns - Math.floor(turns)
}

/**
 * Every path drawn this frame: the line, and each planet's one helix,
 * sampled finely enough that every turn stays round at any zoom, up to
 * `until` while the picture is first drawn out.
 */
export function paths(frame: Frame, at: Lens, until = Infinity): {readonly line: Run; readonly orbits: readonly Orbit[]} {
  const span = reach(frame, at, until)
  return {
    line: run(span, frame.mid, at.unit / 16),
    orbits: PLANETS.map(planet => ({
      ...run(span, frame.mid, Math.min(planet.period / 48, at.unit / 8)),
      phase: phaseAt(planet, frame),
    })),
  }
}

/** The point of a planet's helix `rel` seconds from the middle, as the shader places it: where `orbitAngle` has the planet then, `flown` seconds on. */
export function helixAt(planet: Planet, rel: number, frame: Frame, at: Lens): Vec3 {
  const angle = 2 * Math.PI * (phaseAt(planet, frame) + rel / planet.period) + planet.offset
  return point(frame.mid + rel, planet.radius, angle, frame, at)
}

/** An event where it is drawn. */
export type Mark = {
  readonly event: WorldEvent
  /** Seconds from the anchor. */
  readonly t: number
  /** 0 the line, 1 to 3 the planets innermost first, 4 a room. */
  readonly lane: number
  readonly radius: number
  /**
   * How far around the line a room's line runs, in radians; 0 for the rest. A
   * planet's bead stands on its helix where it is drawn (`markAt`).
   */
  readonly angle: number
  /** How far across its room's line a post's pixel stands, in CSS pixels. */
  readonly across: number
  /** Its width in CSS pixels, its strength 0..1, its colour and its form. */
  readonly size: number
  readonly strength: number
  readonly tone: number
  readonly form: number
}

// FNV-1a, finished by MurmurHash3's mix so like names land far apart. The
// salt is the one that gives the six fixed rooms six different tints.
const hash = (text: string) => {
  let value = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    value ^= text.charCodeAt(i)
    value = Math.imul(value, 0x01000193)
  }
  value = (value >>> 0) ^ 381
  value ^= value >>> 16
  value = Math.imul(value, 0x85ebca6b)
  value ^= value >>> 13
  value = Math.imul(value, 0xc2b2ae35)
  value ^= value >>> 16
  return value >>> 0
}

/** A room's line: how far out it runs, where around the axis, and its tint, all from its name. */
export function room(trail: string): {readonly radius: number; readonly angle: number; readonly tone: number} {
  const bits = hash(trail)
  return {
    radius: 0.08 + 0.15 * (((bits >>> 24) & 0xff) / 255),
    angle: 2 * Math.PI * (((bits >>> 8) & 0xffff) / 65_535),
    tone: TONE["chat-1"] + (bits % CHAT_TINTS),
  }
}

/**
 * A room's line is an ordered dither: `ROWS` rows of square pixels `PIXEL`
 * CSS pixels wide, each post in the row its place in the room gives, in
 * Bayer order, so a run of posts spreads evenly across the line and a busier
 * stretch fills more of it. Zoomed in, the posts stand apart, one pixel each.
 */
export const ROWS = 4
export const PIXEL = 2.5
const ROW_ORDER = [0, 2, 1, 3]

/** How far across its room's line the post at `place` stands, in CSS pixels. */
export function across(place: number): number {
  return (ROW_ORDER[place % ROWS] - (ROWS - 1) / 2) * PIXEL
}

// What a kind on the line looks like: its colour, width and form.
const LINE_MARKS: Record<string, readonly [number, number, number]> = {
  proposal_opened: [TONE.proposals, 6.5, FORM.round],
  proposal_closed: [TONE.proposals, 6.5, FORM.ring],
  executed: [TONE.proposals, 5, FORM.round],
  cancelled: [TONE.proposals, 5, FORM.ring],
  vote: [TONE.votes, 3.5, FORM.round],
  poll: [TONE.polls, 5.5, FORM.round],
  poll_stopped: [TONE.polls, 5.5, FORM.ring],
  sold: [TONE.keys, 4.5, FORM.round],
  given: [TONE.keys, 4.5, FORM.round],
  transfer: [TONE.keys, 4.5, FORM.ring],
  shard_lent: [TONE.shards, 4, FORM.round],
  shard_ended: [TONE.shards, 4, FORM.ring],
  present: [TONE.present, 3, FORM.round],
  daily_split: [TONE.treasury, 12, FORM.tick],
  claimed: [TONE.treasury, 4, FORM.round],
  project: [TONE.projects, 5, FORM.round],
}

const byTime = (a: WorldEvent, b: WorldEvent) => a.at - b.at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)

/** As many events as the picture holds; the list holds every one. */
export const MAX_EVENTS = 12_000

/** Every event where it is drawn, oldest first, the newest `MAX_EVENTS` of them; a mark's index here is its index on the GPU. */
export function place(events: readonly WorldEvent[], anchor: number): Mark[] {
  return [...events]
    .sort(byTime)
    .slice(-MAX_EVENTS)
    .map(event => {
      const t = (event.at - anchor) / 1000
      const planet = PLANETS.findIndex(each => each.name === event.trail)
      if (planet >= 0) {
        const {radius, tone} = PLANETS[planet]
        return {event, t, lane: planet + 1, radius, angle: 0, across: 0, size: 5, strength: 1, tone, form: FORM.round}
      }
      if (event.trail.startsWith("room:")) {
        const {radius, angle, tone} = room(event.trail)
        const shift = across(event.place!)
        return {event, t, lane: 4, radius, angle, across: shift, size: PIXEL, strength: 0.9, tone, form: FORM.pixel}
      }
      const [tone, size, form] = LINE_MARKS[event.kind]
      return {event, t, lane: 0, radius: 0, angle: 0, across: 0, size, strength: 1, tone, form}
    })
}

/**
 * How far around the line a mark stands, in radians: a planet's bead where
 * its helix is at the mark's own time, `flown` seconds on, so it turns with
 * its helix as the picture flies; anything else where it always stands.
 */
export function markAngle(mark: Mark, frame: Frame): number {
  if (mark.lane < 1 || mark.lane > 3) return mark.angle
  return orbitAngle(PLANETS[mark.lane - 1], mark.t + frame.flown, frame.anchor)
}

/**
 * Where a mark stands in the picture: on its path at its own time, a
 * planet's bead where its helix is then (`markAngle`), and a post across its
 * room's line by its row.
 */
export function markAt(mark: Mark, frame: Frame, at: Lens): Seen {
  const angle = markAngle(mark, frame)
  const here = project(point(mark.t, mark.radius, angle, frame, at), frame, at)
  if (mark.across === 0) return here
  // Square to the way the room's line runs on the screen there.
  const ahead = project(point(mark.t + 0.05 * at.unit, mark.radius, angle, frame, at), frame, at)
  const dx = ahead.x - here.x
  const dy = ahead.y - here.y
  const length = Math.hypot(dx, dy)
  const [nx, ny] = length < 1e-6 ? [0, 1] : [-dy / length, dx / length]
  return {x: here.x + nx * mark.across, y: here.y + ny * mark.across, depth: here.depth}
}

/** How near two marks' distances from the pointer may be, in CSS pixels, to count as a tie. */
const TIE = 1
/** How near another mark must stand to be counted with the one found, in CSS pixels. */
const CROWD = 4

/**
 * The mark nearest (x, y) within `within` CSS pixels, by its index, with how
 * many others stand with it there; on a tie, the one nearer the camera.
 * Marks not yet shown (later than `shown`) or faded out are passed over.
 */
export function nearest(
  marks: readonly Mark[],
  frame: Frame,
  at: Lens,
  x: number,
  y: number,
  within: number,
  shown = Infinity,
): {readonly index: number; readonly crowd: number} | undefined {
  const seen = marks.map(mark => markAt(mark, frame, at))
  const showing = (i: number) => marks[i].t <= shown && clear(seen[i].depth, at) >= 0.2
  let best = -1
  let bestDistance = within
  let bestDepth = Infinity
  for (let i = 0; i < marks.length; i++) {
    if (!showing(i)) continue
    const distance = Math.hypot(seen[i].x - x, seen[i].y - y)
    if (distance > within) continue
    const tie = best >= 0 && Math.abs(distance - bestDistance) <= TIE
    if (tie ? seen[i].depth < bestDepth : distance < bestDistance) {
      best = i
      bestDistance = distance
      bestDepth = seen[i].depth
    }
  }
  if (best < 0) return undefined
  const there = seen[best]
  let crowd = 0
  for (let i = 0; i < marks.length; i++) {
    if (i !== best && showing(i) && Math.hypot(seen[i].x - there.x, seen[i].y - there.y) <= CROWD) crowd++
  }
  return {index: best, crowd}
}

/**
 * The time on the line nearest the ray through (x, y), in seconds from the
 * anchor, kept to the drawn history: what a zoom holds in place under the
 * pointer.
 */
export function timeAt(frame: Frame, at: Lens, x: number, y: number): number {
  const sx = (x - frame.width / 2) / at.focal
  const sy = -(y - frame.height / 2) / at.focal
  const ray: Vec3 = [
    at.forward[0] + at.right[0] * sx + at.up[0] * sy,
    at.forward[1] + at.right[1] * sx + at.up[1] * sy,
    at.forward[2] + at.right[2] * sx + at.up[2] * sy,
  ]
  // The closest points of the line, through the middle along x, and the ray.
  const b = ray[0]
  const c = dot(ray, ray)
  const d = -at.eye[0]
  const e = -dot(ray, at.eye)
  const denominator = c - b * b
  const along = denominator < 1e-9 ? 0 : (b * e - c * d) / denominator
  const {from, to} = reach(frame, at)
  return Math.min(to, Math.max(from, frame.mid + along * at.unit))
}

/**
 * CSS pixels the line runs across the picture per unit near the middle, and
 * which way, as a drag moving through time is measured along it. Looking
 * almost down the line it runs short, so a drag is measured as if it ran a
 * sixth of the height per unit at least.
 */
export function lineOnScreen(frame: Frame, at: Lens): {readonly x: number; readonly y: number; readonly length: number} {
  const scale = at.focal / DISTANCE
  const x = at.right[0] * scale
  const y = -at.up[0] * scale
  const length = Math.hypot(x, y)
  const least = frame.height / 6
  if (length >= least) return {x, y, length}
  return {x: (x / Math.max(length, 1e-6)) * least, y: (y / Math.max(length, 1e-6)) * least, length: least}
}

/** The flight's pace while the reader is on a mark or a planet, of full. */
export const CRUISE = 0.05

/** What the flight's pace turns on. */
export type Flight = {
  /** Whether the picture has opened: its first page read and drawn out to the sun. */
  readonly opened: boolean
  /** Whether it follows now. */
  readonly following: boolean
  /** Whether the reader asked for less motion. */
  readonly still: boolean
  /** Whether a mark's link shows: pointed at, tapped or chosen from the keyboard. */
  readonly shown: boolean
  /** Whether a planet's link is pointed at or has the keyboard. */
  readonly planet: boolean
  /** Whether a finger is down on a mark or a planet. */
  readonly finger: boolean
}

/**
 * The flight's pace, of full: none before the picture has opened, while it
 * stands away from now, or for a reader who asked for less motion; `CRUISE`
 * while the reader is on a mark or a planet, so it can be read and pressed;
 * and full otherwise, wherever else on the picture the pointer is.
 */
export function pace(flight: Flight): number {
  if (!flight.opened || !flight.following || flight.still) return 0
  return flight.shown || flight.planet || flight.finger ? CRUISE : 1
}

/** The zoom as the picture names it: 100% is the view it opens on. */
export function percent(span: number): string {
  const value = (100 * OPENING) / span
  return `${value >= 10 ? Math.round(value) : Math.round(value * 10) / 10}%`
}

/** Floats in one mark, and the four heads: the sun and the planets beside it. */
export const MARK_FLOATS = 12
export const HEADS = 4

/** How wide the sun and each planet at now are drawn, in CSS pixels, before perspective. */
export const SUN_SIZE = 13
export const PLANET_SIZE = 8

/** How much larger what is nearer is drawn, gently, as `perspective` in the marks shader. */
export function magnify(depth: number): number {
  return Math.min(1.4, Math.max(0.7, Math.sqrt(DISTANCE / Math.max(depth, 0.01))))
}

// Times reach the GPU in two parts, whole stretches of `SPLIT` seconds and
// what is left, so subtracting the middle's time loses nothing, however far
// back the picture looks.
const SPLIT = 4096

/** The whole stretches of a time, its first part as the GPU takes it. */
export const high = (t: number) => Math.floor(t / SPLIT) * SPLIT

/** A time as the GPU takes it. */
export const split = (t: number): [number, number] => [high(t), t - high(t)]

/** How a mark takes part in a change of filter: it stays, it leaves, or it arrives. */
export const CHANGE = {stays: 0, leaves: 1, arrives: 2} as const

/** Every mark as the GPU draws it, in `marks` order, with how each takes part in a change of filter under way. */
export function pack(marks: readonly Mark[], change: (mark: Mark) => number = () => CHANGE.stays): Float32Array<ArrayBuffer> {
  const data = new Float32Array(marks.length * MARK_FLOATS)
  marks.forEach((mark, i) => {
    const [hi, lo] = split(mark.t)
    data.set(
      [hi, lo, mark.radius, mark.angle, mark.tone, mark.size, i, mark.strength, mark.form, mark.across, mark.lane, change(mark)],
      i * MARK_FLOATS,
    )
  })
  return data
}

/**
 * The sun at now and the three planets beside it, where their orbits stand
 * `flown` seconds on, farthest first, so the nearer stand over the farther.
 */
export function heads(frame: Frame, at: Lens): Float32Array<ArrayBuffer> {
  const [hi, lo] = split(frame.now)
  const depth = (radius: number, angle: number) => project(point(frame.now, radius, angle, frame, at), frame, at).depth
  const standing = [
    {depth: depth(0, 0), data: [hi, lo, 0, 0, TONE.line, SUN_SIZE, -1, 1, FORM.sun, 0, 0, 0]},
    ...PLANETS.map((planet, i) => {
      const angle = orbitAngle(planet, frame.now + frame.flown, frame.anchor)
      return {
        depth: depth(planet.radius, angle),
        data: [hi, lo, planet.radius, angle, planet.tone, PLANET_SIZE, -1, 1, FORM.planet, 0, i + 1, 0],
      }
    }),
  ].sort((a, b) => b.depth - a.depth)
  const data = new Float32Array(HEADS * MARK_FLOATS)
  standing.forEach((head, i) => data.set(head.data, i * MARK_FLOATS))
  return data
}

/** What stands beside each head at now: each planet's name, and Now beside the sun. */
export type TipName = Planet["name"] | "now"

/** A box in the picture, in CSS pixels. */
export type Box = {readonly left: number; readonly top: number; readonly width: number; readonly height: number}

/**
 * A head at now as the picture shows it: where, how far in front of the
 * camera, whether it shows at all, and the box its name stands in, or null
 * when the name has no room.
 */
export type Tip = {
  readonly name: TipName
  readonly x: number
  readonly y: number
  readonly depth: number
  readonly shown: boolean
  readonly label: Box | null
}

// A name stands this far clear of its own head, in CSS pixels; this far
// clear of every other head, name and box over the picture; and this far
// inside the picture's edges. Beside the sun it keeps clear of its glow too,
// and off the ring each other planet's link takes on it (`.worldline-tip`,
// 2rem across), so a press on a name follows that name.
const GAP = 6
const APART = 4
const EDGE = 8
const GLOW = 8
const RING = 16

// The eight sides of its head a name may stand on, as which way from it.
const AROUND = [
  [1, 0],
  [1, 1],
  [0, 1],
  [-1, 1],
  [-1, 0],
  [-1, -1],
  [0, -1],
  [1, -1],
] as const

const overlaps = (a: Box, b: Box) =>
  a.left < b.left + b.width + APART &&
  b.left < a.left + a.width + APART &&
  a.top < b.top + b.height + APART &&
  b.top < a.top + a.height + APART

// Whether a box comes within `radius` of (x, y).
const touches = (box: Box, x: number, y: number, radius: number) => {
  const dx = x - Math.min(Math.max(x, box.left), box.left + box.width)
  const dy = y - Math.min(Math.max(y, box.top), box.top + box.height)
  return Math.hypot(dx, dy) < radius
}

// A box `width` by `height` on the side (ax, ay) of (x, y), its nearest
// point `reach` away.
const beside = (x: number, y: number, [ax, ay]: readonly [number, number], reach: number, width: number, height: number) => {
  const slant = ax !== 0 && ay !== 0 ? Math.SQRT1_2 : 1
  const along = (a: number, centre: number, extent: number) =>
    a > 0 ? centre + reach * slant : a < 0 ? centre - reach * slant - extent : centre - extent / 2
  return {left: along(ax, x, width), top: along(ay, y, height), width, height}
}

/**
 * The sun and the planets at now where the picture draws them, the planets
 * `orbiting` of the way out onto their orbits, and where each one's name
 * stands. A head shows while it stands in the picture, not faded out and
 * not hidden behind a nearer one. The names are placed in order, the planets
 * innermost first and Now last, each beside its head on the side away from
 * the sun (Now under the sun), or the next side round with room: clear of
 * every head that shows and every other planet's link, of the names placed
 * before it, of `blocked` and of the picture's edges. A name with no room on
 * any side is left out.
 */
export function tips(
  frame: Frame,
  at: Lens,
  orbiting: number,
  sizes: Readonly<Record<TipName, {readonly width: number; readonly height: number}>>,
  blocked: readonly Box[] = [],
): Tip[] {
  const seen = (radius: number, angle: number) => project(point(frame.now, radius, angle, frame, at), frame, at)
  const standing = [
    ...PLANETS.map(planet => ({
      name: planet.name as TipName,
      seen: seen(planet.radius * orbiting, orbitAngle(planet, frame.now + frame.flown, frame.anchor)),
      size: PLANET_SIZE,
      glow: 0,
    })),
    {name: "now" as TipName, seen: seen(0, 0), size: SUN_SIZE, glow: GLOW},
  ].map(head => ({...head, disc: (head.size / 2) * magnify(head.seen.depth)}))
  const sun = standing[standing.length - 1].seen
  const shown = standing.map(
    head =>
      head.seen.x >= 0 &&
      head.seen.x <= frame.width &&
      head.seen.y >= 0 &&
      head.seen.y <= frame.height &&
      clear(head.seen.depth, at) >= 0.2 &&
      !standing.some(
        other =>
          other.seen.depth < head.seen.depth &&
          Math.hypot(other.seen.x - head.seen.x, other.seen.y - head.seen.y) < other.disc,
      ),
  )
  const showing = standing.filter((_, i) => shown[i])
  const placed: Box[] = []
  const fits = (box: Box, own: TipName) =>
    box.left >= EDGE &&
    box.top >= EDGE &&
    box.left + box.width <= frame.width - EDGE &&
    box.top + box.height <= frame.height - EDGE &&
    !showing.some(head => {
      const ringed = head.name !== own && head.name !== "now"
      return touches(box, head.seen.x, head.seen.y, Math.max(head.disc + head.glow + APART, ringed ? RING : 0))
    }) &&
    !placed.some(other => overlaps(box, other)) &&
    !blocked.some(other => overlaps(box, other))
  return standing.map((head, i) => {
    const {x, y, depth} = head.seen
    if (!shown[i]) return {name: head.name, x, y, depth, shown: false, label: null}
    const [awayX, awayY] = head.name === "now" ? [0, 1] : [x - sun.x, y - sun.y]
    const toward = ([ax, ay]: readonly [number, number]) => (ax * awayX + ay * awayY) / Math.hypot(ax, ay)
    const {width, height} = sizes[head.name]
    const reach = head.disc + head.glow + GAP
    const label =
      [...AROUND]
        .sort((a, b) => toward(b) - toward(a))
        .map(side => beside(x, y, side, reach, width, height))
        .find(box => fits(box, head.name)) ?? null
    if (label) placed.push(label)
    return {name: head.name, x, y, depth, shown: true, label}
  })
}
