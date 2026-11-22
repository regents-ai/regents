/**
 * A fleet's Worldline (`KeyfleetWeb.WorldlineLive`) in three dimensions: the
 * gold line runs through time with the sun at now, and Workspace, Code and
 * Notebooks orbit it as planets, each event a bead on its planet's helix, a
 * pixel on its room's line or a point on the line itself
 * (`../worldline/scene`).
 *
 * The page sends the newest events once it is live (`worldline:page`), older
 * ones as the reader moves back to them (the reply to `worldline_older`), and
 * new ones a moment after they happen (`worldline:heard`): the sun, or the
 * planet the event belongs to, flares, and a word for it shows over the sun.
 *
 * Dragging turns the picture; it turns on a little when let go and springs
 * back from either end of its turn, and a double-click or Reset turns it
 * back. Scrolling, or dragging with Shift held, moves through time; a pinch,
 * or scrolling with Ctrl or ⌘ held, zooms toward the time under the pointer,
 * and minus and plus zoom too. A scroll on past now, or back past the oldest
 * event, or one that began on the page, scrolls the page. On a phone a
 * sideways swipe moves through time and an upward one scrolls the page; a
 * pinch zooms and a twist of two fingers turns it. The arrow keys move
 * through time and with Alt turn it; plus and minus zoom. One real link
 * follows the mark pointed at, tapped or nearest the middle while the
 * picture has the keyboard, so it opens as any link does, in a new tab too;
 * a drag never opens it.
 *
 * The sun and each planet at now carry their names beside them, clear of
 * each other and inside the picture (`tips` in the scene). Each planet's
 * name and a ring on the planet are one real link to its place in the
 * workspace, the stops for Tab after the mark's link; pointed at or given
 * the keyboard, the planet stands out as a mark does, and a press on it that
 * drags turns the picture instead. Now only names the sun.
 *
 * While it follows now, the picture flies: the planets circle the line far
 * faster than real time, each helix turning about the line with its planet
 * and each bead on it keeping its place at its own time, and the stars drift
 * by, the nearer faster. Only real time moves anything along the line: the
 * sun moves on and new events arrive at theirs. On a mark or a planet the
 * flight eases to a twentieth of its pace, so what is there can be read and
 * pressed: while the mouse is on it, a finger is down on it, it has the
 * keyboard, or a mark's link shows from a tap. Anywhere else on the picture
 * it flies on at full pace. Moved through time, the picture eases to a stop
 * and the orbits hold where they stand, so no bead jumps; Now flies on again
 * from there, and Reset returns to the view it opens on.
 *
 * The picture is drawn only with WebGPU. Without it the line and the sun the
 * page drew stay, with a note that the List has every event. For a reader who
 * asked for less motion nothing flies, shimmers, glides, reveals or flares,
 * and a turn stops where it is let go; the picture and its links still work.
 *
 * anime.js moves every transition, by the values the GPU reads rather than
 * by the page: the first reveal (a timeline: the line and helices draw out
 * to the sun, passing each event in turn, then the planets come out onto
 * their orbits), the flight's pace, the glides of Now, Reset and the zoom
 * buttons, the mark in focus, the planet pointed at, an arrival's flare and
 * word, and a change of filter. A move asked for from the keyboard happens
 * at once. The shimmer runs by the clock.
 */
import {animate, createScope, createTimeline, type AnimationParams, type JSAnimation} from "animejs"

import {createCanvasIsland, type CanvasIslandController, type IslandRenderer} from "../canvas_island"
import type {Hook} from "../../hook_composition"
import {showingTheme, watchTheme} from "../../theme"
import {tone} from "../theme_tone"
import type {Scene, Tones, WorldlineRenderer} from "../worldline/renderer"
import {
  CHANGE,
  DAY,
  HOME,
  MAX_EVENTS,
  OPENING,
  PITCH_LIMIT,
  PLANETS,
  TONES,
  YAW_LIMIT,
  clear,
  heads,
  lens,
  lineOnScreen,
  markAt,
  nearest,
  pace,
  pack,
  paths,
  percent,
  place,
  point,
  project,
  reach,
  timeAt,
  tips,
  type Box,
  type Camera,
  type Frame,
  type Lens,
  type Mark,
  type TipName,
  type WorldEvent,
} from "../worldline/scene"
import {localTime} from "./local_time"
import {BASE, EASE_IN_OUT, EASE_OUT, FAST, SLOW, byPointer, play, still} from "./motion/shared"

type WorldlineHook = {
  el: HTMLElement
  pushEvent<Reply>(event: string, payload: unknown, onReply: (reply: Reply) => void): void
  handleEvent<Payload>(event: string, callback: (payload: Payload) => void): void
  controller?: CanvasIslandController
  scope?: ReturnType<typeof createScope>
}

type Page = {events: WorldEvent[]; older: boolean; now: number}
type Older = {events: WorldEvent[]; older: boolean}

type Island = IslandRenderer & {readonly gpu: WorldlineRenderer}

/** Where the sun stands from the middle while the picture follows now, in spans. */
const HEAD_AT = 0.4
/** The narrowest and widest stretch of time the picture shows, in seconds. */
const MIN_SPAN = 120
const MAX_SPAN = 400 * DAY
/** How near a mark must be to point at it, in CSS pixels, by mouse and by finger. */
const NEAR = 24
const NEAR_TOUCH = 36
/** How far a key press moves through time, of the span; zooms; and turns, in radians. */
const KEY_PAN = 0.12
const KEY_ZOOM = 0.7
const KEY_TURN = 0.12
/** How far a drag turns the picture, in radians a CSS pixel. */
const TURN = 0.006
/** How far a drag on past either end of the turn still turns it, of how far it is pulled. */
const STRETCH = 0.25
/** How briskly the picture springs back from past either end of its turn, in radians a second. */
const SPRING = 18
/** How fast a move or a turn let go slows, in milliseconds to lose most of its speed. */
const GLIDE = 325
/** How far a press moves before it is a drag, in CSS pixels. */
const DRAG = 4
/**
 * A pause this long between turns of the wheel, in milliseconds, ends one
 * scroll; until then it stays with what it began on, the picture or the page.
 */
const LATCH = 300
/** How far each pixel of a pinch zooms, and the most one turn of the wheel does. */
const PINCH = 0.01
const MOST_PINCH = 50
/** How long Now takes to glide back to the sun, and Reset to turn the picture back, in milliseconds. */
const HOMING = 700
const TURNING = 450
/** How long the line takes to draw out to the sun as the picture opens, and the planets to come out onto their orbits. */
const REVEAL = 1100
const ORBITING = 520
/** How long a new event's word shows over the sun, in milliseconds. */
const NEWS = 2600
/**
 * Seconds the orbits run on in a second of flight at full pace, whatever the
 * zoom: Workspace circles the line every 20 seconds, Code every minute and
 * Notebooks every 140 seconds.
 */
const SPIN = DAY / 20
/** How long the flight takes to ease to a new pace (`pace`), in milliseconds. */
const PACING = 350
/** How fast each layer of stars drifts at full pace, in radians a second, the farthest first. */
const DRIFT = [0.006, 0.014, 0.03]

const reader = () => ({locale: undefined, timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone})

const within = (value: number, limit: number) => Math.max(-limit, Math.min(limit, value))

// A drag on past either end of the turn goes on a quarter as far; `unband`
// is how far it was pulled to stand where it does.
const band = (raw: number, limit: number) =>
  Math.abs(raw) <= limit ? raw : Math.sign(raw) * (limit + (Math.abs(raw) - limit) * STRETCH)
const unband = (value: number, limit: number) =>
  Math.abs(value) <= limit ? value : Math.sign(value) * (limit + (Math.abs(value) - limit) / STRETCH)

// One step of a turn let go: on at its speed, slowing, or springing back
// from past either end. Speeds are in radians a millisecond.
const coast = (value: number, speed: number, limit: number, dt: number): [number, number] => {
  const over = Math.abs(value) > limit ? value - Math.sign(value) * limit : 0
  if (over === 0) {
    const slowed = speed * Math.exp(-dt / GLIDE)
    return [value + speed * dt, Math.abs(slowed) < 1e-6 ? 0 : slowed]
  }
  const seconds = dt / 1000
  const perSecond = speed * 1000 + (-SPRING * SPRING * over - 2 * SPRING * speed * 1000) * seconds
  const next = value + perSecond * seconds
  if (Math.abs(next) - limit < 1e-4 && Math.abs(perSecond) < 0.05) return [within(next, limit), 0]
  return [next, perSecond / 1000]
}

const wrap = (angle: number) => Math.atan2(Math.sin(angle), Math.cos(angle))

export const Worldline: Hook = {
  mounted(this: WorldlineHook) {
    const root = this.el
    const link = root.querySelector<HTMLAnchorElement>("[data-worldline-focus]")!
    const card = link.querySelector<HTMLElement>("[data-focus-card]")!
    const what = link.querySelector<HTMLElement>("[data-focus-what]")!
    const title = link.querySelector<HTMLElement>("[data-focus-title]")!
    const meta = link.querySelector<HTMLElement>("[data-focus-meta]")!
    const back = root.querySelector<HTMLButtonElement>("[data-worldline-now]")!
    const news = root.querySelector<HTMLElement>("[data-worldline-news]")!
    const view = root.querySelector<HTMLElement>("[data-worldline-view]")!
    const level = view.querySelector<HTMLOutputElement>("[data-worldline-zoom-level]")!
    const layer = root.querySelector<HTMLElement>("[data-worldline-tips]")!
    const tipped = new Map(
      [...layer.querySelectorAll<HTMLElement>("[data-worldline-tip]")].map(element => [
        element.dataset.worldlineTip as TipName,
        {element, label: element.querySelector<HTMLElement>("[data-tip-name]")!},
      ]),
    )
    if (!navigator.gpu) root.dataset.worldlineStill = "true"

    // The events on show and where they are drawn, by the page's clock.
    const events = new Map<string, WorldEvent>()
    let marks: Mark[] = []
    let anchor = 0
    let skew = 0
    let older = false
    let asking = false
    let loaded = false
    let changed = false

    // Where the picture stands: how much time it shows, the time at its
    // middle, whether that follows now, and how the camera is turned.
    let span = DAY
    let mid = 0
    let following = true
    let width = 1
    let height = 1
    let yaw = HOME.yaw
    let pitch = HOME.pitch
    // How fast a turn and a move through time let go glide on: radians, and
    // seconds, a millisecond.
    let spin = {yaw: 0, pitch: 0}
    let velocity = 0
    let clock = 0
    let ticked: number | undefined
    let strained = false
    // How far the picture has flown: the orbits' seconds on (`Frame`); how
    // far each layer of stars has drifted round; and whether a finger is
    // down on a mark or a planet.
    let flown = 0
    const drift = DRIFT.map(() => 0)
    let touching = false

    // A press on the picture, while one finger or the mouse is down: where it
    // last was, how far it has moved, when, whether it turns the picture or
    // moves through time, and how fast it went.
    type Press = {
      id: number
      x: number
      y: number
      moved: number
      at: number
      turns: boolean
      touch: boolean
      speed: number
      spin: {yaw: number; pitch: number}
      pulled: {yaw: number; pitch: number}
    }
    let press: Press | undefined
    // Two fingers down: how far apart, at what angle, and their middle.
    let pair: {distance: number; angle: number; x: number; y: number} | undefined
    // Whether the press under way has dragged, so its click opens nothing.
    let dragged = false

    // What anime.js moves: the reveal, the planets coming out onto their
    // orbits, the mark in focus, the planet pointed at, an arrival, a change
    // of filter, a glide back to the sun, a zoom, a turn back home and the
    // flight's pace.
    const motion = {
      revealed: 1e12,
      orbiting: 1,
      emphasis: 1,
      lift: 1,
      arrival: 0,
      arrivedFrom: 1e12,
      change: 1,
      home: 0,
      zoom: 0,
      turn: 0,
      pace: 0,
    }
    // Which heads flare for what just arrived: the sun, then each planet.
    let flaring = [0, 0, 0, 0]
    let homing: {from: number; animation: JSAnimation} | undefined
    let zooming: {from: number; to: number; animation: JSAnimation} | undefined
    let turning: {from: Camera; animation: JSAnimation} | undefined
    // The pace the flight is easing to.
    let aim = 0
    let pacing: JSAnimation | undefined
    // While the filter changes: the events that leave and those that arrive.
    let changing: {leaving: Set<string>; arriving: Set<string>; animation: JSAnimation} | undefined
    let focus: number | undefined
    let focusBy: "pointer" | "key" | undefined
    // The planet's link the mouse is on and the one with the keyboard, and
    // the head that stands out for them: 1 to 3, the planets innermost first.
    let pointed: Element | null = null
    let keyed: Element | null = null
    let lifted: number | undefined
    // The names' sizes, and what stands over the picture that they keep
    // clear of: the zoom, and Now while it shows.
    const sizes = Object.fromEntries([...tipped.keys()].map(name => [name, {width: 0, height: 0}])) as Record<
      TipName,
      {width: number; height: number}
    >
    let blocked: Box[] = []

    let nudge = () => {}

    // Everything anime.js moves here belongs to one Scope, reverted with the hook.
    const scope = createScope({root})
    this.scope = scope

    const now = () => (Date.now() + skew - anchor) / 1000
    const frame = (): Frame => ({
      width,
      height,
      mid,
      span,
      now: now(),
      anchor,
      camera: {yaw, pitch},
      flown,
    })
    const look = () => {
      const shown = frame()
      return {shown, at: lens(shown)}
    }
    // The frame worked out for the coming draw.
    let current = (() => {
      const {shown, at} = look()
      return {shown, at, drawn: paths(shown, at)}
    })()
    const oldest = () => marks[0]?.t

    // One of anime.js's runs over `motion`, each frame of it drawn. A run
    // begun over another of the same value takes over from where it was.
    const run = (params: AnimationParams, finished = () => {}) =>
      scope.execute(() =>
        animate(motion, {
          ...params,
          onUpdate: () => nudge(),
          onComplete: () => {
            finished()
            nudge()
          },
        }),
      )

    // The flight's pace (`pace`): a twentieth while the reader is on a mark
    // or a planet, full anywhere else while the picture follows now, and
    // none away from now. Every change of pace is eased into, so taken away
    // from now the orbits slow to a stop and hold where they stand, and no
    // bead ever jumps.
    const steer = () => {
      const want = pace({
        opened: loaded && motion.revealed >= 1e12,
        following,
        still: still(root),
        shown: focus !== undefined,
        planet: lifted !== undefined,
        finger: touching,
      })
      if (want === aim) return
      aim = want
      pacing?.cancel()
      pacing = undefined
      if (still(root)) motion.pace = want
      else pacing = run({pace: want, duration: PACING, ease: EASE_IN_OUT})
    }

    // The latest the middle may stand, with the sun where it follows now; and
    // the earliest, with the oldest event a tenth of the way in, once nothing
    // older is left to read.
    const latest = () => now() - HEAD_AT * span
    const earliest = () => {
      const first = oldest()
      return older || first === undefined ? -Infinity : first + 0.4 * span
    }

    const follow = () => {
      following = true
      mid = latest()
    }

    const hold = () => {
      span = Math.min(MAX_SPAN, Math.max(MIN_SPAN, span))
      mid = Math.max(mid, earliest())
      if (mid >= latest() - span * 1e-3) follow()
    }

    // Moves through time, later for more seconds.
    const move = (seconds: number) => {
      mid += seconds
      following = false
      hold()
    }

    // Moves through time as far as a drag of (dx, dy) runs along the line on
    // the screen, so the line keeps under the finger; the seconds it moved.
    const slide = (dx: number, dy: number) => {
      const {shown, at} = look()
      const line = lineOnScreen(shown, at)
      const seconds = (-(dx * line.x + dy * line.y) / (line.length * line.length)) * at.unit
      move(seconds)
      return seconds
    }

    // Zooms by `factor`, holding the time under (x, y) in place; without a
    // place, about the middle, or about the sun while following it.
    const zoom = (factor: number, x?: number, y?: number) => {
      const next = Math.min(MAX_SPAN, Math.max(MIN_SPAN, span * factor))
      if (x === undefined || y === undefined) {
        span = next
        if (following) follow()
        hold()
        return
      }
      const {shown, at} = look()
      const held = timeAt(shown, at, x, y)
      mid = held - (held - mid) * (next / span)
      span = next
      following = false
      hold()
    }

    const stop = (each: {animation: JSAnimation} | undefined) => each?.animation.cancel()

    // The reader takes the picture's place in time: a move let go, a glide
    // to the sun and a zoom under way all stop.
    const takeOver = () => {
      velocity = 0
      stop(homing)
      homing = undefined
      stop(zooming)
      zooming = undefined
    }

    // Zooms to show `seconds` across, about the middle, or the sun while
    // following it: a glide when asked for with the pointer, at once from the
    // keyboard or for a reader who asked for less motion.
    const zoomTo = (seconds: number, glides: boolean) => {
      stop(zooming)
      zooming = undefined
      const to = Math.min(MAX_SPAN, Math.max(MIN_SPAN, seconds))
      if (!glides || still(root)) {
        zoom(to / span)
      } else {
        motion.zoom = 0
        zooming = {
          from: span,
          to,
          animation: run({zoom: [0, 1], duration: SLOW, ease: EASE_IN_OUT}, () => (zooming = undefined)),
        }
      }
      nudge()
    }

    // Zooms in or out by a step.
    const zoomBy = (factor: number, glides: boolean) => {
      takeOver()
      zoomTo(span * factor, glides)
    }

    // The reader takes the camera: a turn let go and a turn home both stop.
    const holdCamera = () => {
      spin = {yaw: 0, pitch: 0}
      stop(turning)
      turning = undefined
    }

    // Back to the sun: a glide, or at once from the keyboard or for a reader
    // who asked for less motion.
    const home = (glides: boolean) => {
      takeOver()
      if (following) return
      if (!glides || still(root)) {
        follow()
      } else {
        motion.home = 0
        homing = {
          from: mid,
          animation: run({home: [0, 1], duration: HOMING, ease: EASE_OUT}, () => {
            homing = undefined
            follow()
          }),
        }
      }
      nudge()
    }

    // Back to the view the picture opens on, turned home and at 100%, gliding
    // there unless asked from the keyboard or by a reader who asked for less
    // motion.
    const reset = (glides: boolean) => {
      holdCamera()
      zoomTo(OPENING, glides)
      if (!glides || still(root)) {
        yaw = HOME.yaw
        pitch = HOME.pitch
      } else {
        motion.turn = 0
        turning = {
          from: {yaw, pitch},
          animation: run({turn: [0, 1], duration: TURNING, ease: EASE_OUT}, () => {
            turning = undefined
            yaw = HOME.yaw
            pitch = HOME.pitch
          }),
        }
      }
      nudge()
    }

    // The names' sizes, and where the zoom and Now stand over the picture.
    const measureTips = () => {
      for (const [name, {label}] of tipped) sizes[name] = {width: label.offsetWidth, height: label.offsetHeight}
      const box = layer.getBoundingClientRect()
      blocked = [view, back]
        .filter(each => !each.hidden)
        .map(each => {
          const over = each.getBoundingClientRect()
          return {left: over.left - box.left, top: over.top - box.top, width: over.width, height: over.height}
        })
    }

    // Now shows while the picture stands away from the sun. Pressed from the
    // keyboard, the picture keeps the keyboard once Now goes.
    const showBack = () => {
      if (back.hidden === following) return
      if (following && document.activeElement === back) root.focus({preventScroll: true})
      back.hidden = following
      measureTips()
      if (!following && !still(root)) play(back, {opacity: [0, 1], duration: FAST, ease: EASE_OUT})
    }

    // The mark in focus stays the same event when others arrive around it.
    const relayout = () => {
      const kept = focus === undefined ? undefined : marks[focus].event.id
      marks = place([...events.values()], anchor)
      if (kept !== undefined) {
        const index = marks.findIndex(mark => mark.event.id === kept)
        focus = index < 0 ? undefined : index
        link.hidden = focus === undefined
      }
      changed = true
    }

    const when = (at: number) => localTime(new Date(at), new Date(Date.now() + skew), "stamp", reader())

    const showLink = (index: number, crowd: number) => {
      const event = marks[index].event
      link.href = event.path
      if (event.live) {
        link.dataset.phxLink = "patch"
        link.dataset.phxLinkState = "push"
      } else {
        delete link.dataset.phxLink
        delete link.dataset.phxLinkState
      }
      what.textContent = event.what
      title.textContent = event.title
      meta.textContent = [event.who, when(event.at), crowd > 0 ? `${crowd} nearby` : null].filter(Boolean).join(" · ")
    }

    const choose = (found: {index: number; crowd: number} | undefined, by: "pointer" | "key") => {
      const index = found?.index
      if (index === focus) {
        if (found !== undefined) {
          focusBy = by
          showLink(found.index, found.crowd)
        }
        return
      }
      const appearing = focus === undefined && found !== undefined
      focus = index
      focusBy = found === undefined ? undefined : by
      if (found === undefined) {
        link.hidden = true
      } else {
        showLink(found.index, found.crowd)
        link.hidden = false
        if (appearing && !still(root)) play(card, {opacity: [0, 1], duration: FAST, ease: EASE_OUT})
      }
      if (still(root)) motion.emphasis = 1
      else run({emphasis: [0, 1], duration: BASE, ease: EASE_OUT})
      nudge()
    }

    const pointAt = (x: number, y: number, near: number) => {
      const {shown, at} = look()
      return nearest(marks, shown, at, x, y, near, motion.revealed)
    }

    // While the picture has the keyboard, the mark nearest its middle is the one shown.
    const chooseMiddle = () => choose(pointAt(width / 2, height / 2, width), "key")

    // The planet whose link the mouse is on, or else the one with the
    // keyboard, stands out: rising for the pointer, at once for the keyboard
    // or for a reader who asked for less motion.
    const lift = (glides: boolean) => {
      const name = (pointed ?? keyed)?.getAttribute("data-worldline-tip")
      const head = name ? PLANETS.findIndex(planet => planet.name === name) + 1 : undefined
      if (head === lifted) return
      lifted = head
      if (head !== undefined) {
        if (!glides || still(root)) motion.lift = 1
        else run({lift: [0, 1], duration: BASE, ease: EASE_OUT})
      }
      nudge()
    }

    // Each head's name stands beside it, the links of the nearer heads over
    // the farther ones'. A head out of sight takes its link and name with it,
    // and gives the keyboard back to the picture.
    const placeTips = (shown: Frame, at: Lens) => {
      layer.style.opacity = `${motion.orbiting}`
      const placed = tips(shown, at, motion.orbiting, sizes, blocked)
      const depths = placed.map(tip => tip.depth).sort((a, b) => b - a)
      for (const tip of placed) {
        const {element, label} = tipped.get(tip.name)!
        if (!tip.shown && element.contains(document.activeElement)) root.focus({preventScroll: true})
        element.toggleAttribute("data-shown", tip.shown)
        if (!tip.shown) continue
        element.style.translate = `${tip.x.toFixed(1)}px ${tip.y.toFixed(1)}px`
        element.style.zIndex = `${depths.indexOf(tip.depth) + 1}`
        label.toggleAttribute("data-room", tip.label !== null)
        if (tip.label !== null)
          label.style.translate = `${(tip.label.left - tip.x).toFixed(1)}px ${(tip.label.top - tip.y).toFixed(1)}px`
      }
    }

    // The link stands on the mark in focus, its words to whichever side has
    // room, the heads' names beside them, and a new event's word over the
    // sun, each frame, so they ride along as the picture flies. A mark turned
    // out of sight is let go.
    const placeLabels = (shown: Frame, at: Lens) => {
      const sun = project(point(shown.now, 0, 0, shown, at), shown, at)
      news.style.transform = `translate(${sun.x.toFixed(1)}px, ${sun.y.toFixed(1)}px)`
      placeTips(shown, at)
      if (focus === undefined) return
      const spot = markAt(marks[focus], shown, at)
      const outside = spot.x < 0 || spot.x > width || spot.y < 0 || spot.y > height
      if (outside || clear(spot.depth, at) < 0.2) {
        choose(undefined, "pointer")
        return
      }
      link.style.transform = `translate(${spot.x.toFixed(1)}px, ${spot.y.toFixed(1)}px)`
      link.dataset.side = spot.x > width - 232 ? "left" : "right"
      link.dataset.edge = spot.y < 76 ? "below" : "above"
    }

    // Older events are read a page at a time while fewer than a picture's
    // width of them stand ready past where the drawn history begins, so they
    // are there before the reader moves back to them. Each event stands at
    // its own time, so those read later move nothing already drawn.
    const readOlder = () => {
      const first = oldest()
      if (!older || asking || first === undefined || events.size >= MAX_EVENTS) return
      if (first < current.shown.mid + current.drawn.line.from - span) return
      asking = true
      this.pushEvent<Older>("worldline_older", {}, reply => {
        asking = false
        older = reply.older
        for (const event of reply.events) events.set(event.id, event)
        relayout()
        nudge()
      })
    }

    // The picture opens on its first page: the line and the helices draw out
    // to the sun, passing each event in turn, then the planets come out from
    // the sun onto their orbits.
    const reveal = () => {
      if (still(root)) return
      const {shown, at} = look()
      const start = reach(shown, at).from
      motion.revealed = start
      motion.orbiting = 0
      scope.execute(() =>
        createTimeline({
          onUpdate: () => nudge(),
          onComplete: () => {
            motion.revealed = 1e12
            nudge()
          },
        })
          .add(motion, {revealed: [start, now()], duration: REVEAL, ease: EASE_OUT})
          .add(motion, {orbiting: [0, 1], duration: ORBITING, ease: EASE_OUT}, `-=${ORBITING / 2}`),
      )
    }

    // Each page replaces the events on show: the first opens the picture,
    // and a later one, for a new filter, keeps the view while the events
    // that no longer match leave and those that now do arrive.
    const page = ({events: newest, older: more, now: serverNow}: Page) => {
      const first = !loaded
      loaded = true
      skew = serverNow - Date.now()
      if (first) anchor = serverNow
      older = more
      asking = false
      choose(undefined, "pointer")
      takeOver()
      if (changing) {
        stop(changing)
        for (const id of changing.leaving) events.delete(id)
        changing = undefined
      }
      const next = new Set(newest.map(event => event.id))
      const leaving = new Set([...events.keys()].filter(id => !next.has(id)))
      const arriving = new Set([...next].filter(id => !events.has(id)))
      for (const event of newest) events.set(event.id, event)
      if (first || still(root) || leaving.size + arriving.size === 0) {
        for (const id of leaving) events.delete(id)
        motion.change = 1
      } else {
        motion.change = 0
        changing = {
          leaving,
          arriving,
          animation: run({change: [0, 1], duration: SLOW, ease: EASE_OUT}, () => {
            for (const id of leaving) events.delete(id)
            changing = undefined
            relayout()
          }),
        }
      }
      relayout()
      if (first) {
        span = OPENING
        follow()
        reveal()
      }
      nudge()
    }

    // How a mark takes part in the change of filter under way.
    const changeOf = (mark: Mark) =>
      changing?.leaving.has(mark.event.id)
        ? CHANGE.leaves
        : changing?.arriving.has(mark.event.id)
          ? CHANGE.arrives
          : CHANGE.stays

    // What just happened drops onto its path as its head flares, and its
    // word shows over the sun.
    const heard = ({events: arrived}: {events: WorldEvent[]}) => {
      const fresh = arrived.filter(event => !events.has(event.id))
      for (const event of arrived) events.set(event.id, event)
      relayout()
      if (fresh.length > 0 && !still(root)) {
        const ids = new Set(fresh.map(event => event.id))
        const lanes = marks.filter(mark => ids.has(mark.event.id)).map(mark => mark.lane)
        flaring = [0, 1, 2, 3].map(head =>
          lanes.some(lane => (head === 0 ? lane === 0 || lane === 4 : lane === head)) ? 1 : 0,
        )
        motion.arrivedFrom = Math.min(...fresh.map(event => (event.at - anchor) / 1000))
        run({arrival: [1, 0], duration: 1400, ease: EASE_OUT})
        news.textContent = fresh.reduce((newest, event) => (event.at > newest.at ? event : newest)).what
        play(news, {
          opacity: [
            {from: 0, to: 1, duration: BASE},
            {to: 1, duration: NEWS - BASE - 600},
            {to: 0, duration: 600},
          ],
          ease: "linear",
        })
      }
      nudge()
    }

    this.handleEvent<Page>("worldline:page", page)
    this.handleEvent<{events: WorldEvent[]}>("worldline:heard", heard)

    // One frame: the clock runs on, the orbits run on at the flight's pace
    // (`SPIN` at full) and the stars drift with them; a move or a turn let go
    // glides on or springs back, a glide to the sun, a zoom or a turn home
    // closes in, and the sun follows now. True while anything still moves.
    const advance = (time: number) => {
      const dt = ticked === undefined ? 0 : Math.min(50, time - ticked)
      ticked = time
      const moving = !still(root) && !strained
      if (moving) clock += dt / 1000
      steer()
      if (moving && motion.pace > 0) {
        const seconds = (motion.pace * dt) / 1000
        flown += seconds * SPIN
        for (let i = 0; i < drift.length; i++) drift[i] = (drift[i] + seconds * DRIFT[i]) % (2 * Math.PI)
      }
      if (zooming) {
        span = zooming.from * (zooming.to / zooming.from) ** motion.zoom
        if (following) follow()
        hold()
      }
      if (homing) mid = homing.from + (latest() - homing.from) * motion.home
      if (turning) {
        yaw = turning.from.yaw + (HOME.yaw - turning.from.yaw) * motion.turn
        pitch = turning.from.pitch + (HOME.pitch - turning.from.pitch) * motion.turn
      } else if (!press?.turns && pair === undefined) {
        ;[yaw, spin.yaw] = coast(yaw, spin.yaw, YAW_LIMIT, dt)
        ;[pitch, spin.pitch] = coast(pitch, spin.pitch, PITCH_LIMIT, dt)
      }
      if (velocity !== 0) {
        move(velocity * dt)
        velocity *= Math.exp(-dt / GLIDE)
        if (Math.abs(velocity) < (0.01 * span) / width || following) velocity = 0
      }
      if (following) follow()
      const {shown, at} = look()
      current = {shown, at, drawn: paths(shown, at, motion.revealed)}
      readOlder()
      showBack()
      const zoomed = percent(span)
      if (level.textContent !== zoomed) level.textContent = zoomed
      const turningOn =
        spin.yaw !== 0 || spin.pitch !== 0 || Math.abs(yaw) > YAW_LIMIT || Math.abs(pitch) > PITCH_LIMIT
      return moving || velocity !== 0 || turningOn
    }

    const tones = (): Tones => {
      const dark = showingTheme() === "dark"
      return {
        palette: TONES.map(name => tone(root, `--worldline-${name}`)),
        ground: tone(root, "--color-bg"),
        sky: tone(root, "--worldline-stars"),
        glow: dark ? 0.34 : 0.08,
        far: dark ? 0.3 : 0.36,
        stars: dark ? 0.6 : 0,
        bloom: dark ? 0.9 : 0.35,
      }
    }

    const scene = (): Scene => ({
      frame: current.shown,
      lens: current.at,
      paths: current.drawn,
      heads: heads(current.shown, current.at),
      revealed: motion.revealed,
      arrivedFrom: motion.arrivedFrom,
      focus: focus ?? -1,
      emphasis: motion.emphasis,
      flare: flaring.map(head => head * motion.arrival),
      lift: [0, 1, 2, 3].map(head => (head === lifted ? motion.lift : 0)),
      clock,
      shimmer: !still(root) && !strained ? 1 : 0,
      orbiting: motion.orbiting,
      change: motion.change,
      drift,
    })

    this.controller = createCanvasIsland<Island>(root, {}, {
      canvasSelector: "[data-worldline-canvas]",
      readyFlag: "worldlineReady",
      // The picture is the page's content, so it is drawn for every reader;
      // for one who asked for less motion it holds still.
      motionSensitive: false,
      continuous: true,
      browserLoad: async (canvas, size, lost) => {
        const {createWorldlineRenderer} = await import("../worldline/renderer")
        const gpu = await createWorldlineRenderer(canvas, size, lost)
        return {
          gpu,
          resize: (w, h) => gpu.resize(w, h),
          step: () => advance(performance.now()),
          present: () => {
            if (changed) {
              gpu.load(pack(marks, changeOf))
              changed = false
            }
            gpu.present(scene())
            placeLabels(current.shown, current.at)
          },
          settled: () => gpu.settled(),
          dispose: () => gpu.dispose(),
        }
      },
      interact: island => {
        nudge = island.nudge
        const canvas = island.canvas()
        const measure = () => {
          const box = canvas.getBoundingClientRect()
          width = Math.max(1, box.width)
          height = Math.max(1, box.height)
          measureTips()
          if (following) follow()
        }
        measure()
        island.onReady(() => {
          island.renderer()?.gpu.tones(tones())
          changed = true
        })
        island.onStrain(hold => {
          strained = hold
          island.nudge()
        })

        const listening = new AbortController()
        const options = {signal: listening.signal}
        const local = (event: MouseEvent) => {
          const box = canvas.getBoundingClientRect()
          return {x: event.clientX - box.left, y: event.clientY - box.top}
        }
        const onControl = (event: Event) =>
          back.contains(event.target as Node) || view.contains(event.target as Node)
        // The planet's link an event happened on, if any.
        const onTip = (event: Event) =>
          event.target instanceof Element ? event.target.closest("a[data-worldline-tip]") : null
        const pointers = new Map<number, {x: number; y: number}>()
        const fingers = () => {
          const [a, b] = [...pointers.values()]
          return {
            distance: Math.hypot(a.x - b.x, a.y - b.y),
            angle: Math.atan2(b.y - a.y, b.x - a.x),
            x: (a.x + b.x) / 2,
            y: (a.y + b.y) / 2,
          }
        }

        root.addEventListener(
          "pointerdown",
          event => {
            dragged = false
            if (event.button !== 0 || onControl(event)) return
            const spot = local(event)
            pointers.set(event.pointerId, spot)
            // A finger down on a mark or a planet slows the flight; one down
            // anywhere else on the picture does not.
            if (event.pointerType === "touch" && (onTip(event) || pointAt(spot.x, spot.y, NEAR_TOUCH))) touching = true
            takeOver()
            holdCamera()
            if (pointers.size === 1) {
              const touch = event.pointerType === "touch"
              press = {
                id: event.pointerId,
                x: spot.x,
                y: spot.y,
                moved: 0,
                at: event.timeStamp,
                turns: !touch && !event.shiftKey,
                touch,
                speed: 0,
                spin: {yaw: 0, pitch: 0},
                pulled: {yaw: unband(yaw, YAW_LIMIT), pitch: unband(pitch, PITCH_LIMIT)},
              }
            }
            if (pointers.size === 2) {
              press = undefined
              pair = fingers()
            }
          },
          options,
        )

        root.addEventListener(
          "pointermove",
          event => {
            const spot = local(event)
            if (!pointers.has(event.pointerId)) {
              // The mark shown stays while the pointer is on its link, card
              // and all; on a planet's link no mark shows, and the planet
              // stands out. Either slows the flight; the rest of the picture
              // does not.
              if (event.pointerType !== "mouse") return
              const onLink = link.contains(event.target as Node)
              pointed = onTip(event)
              lift(true)
              if (focusBy !== "key" && !onLink && !onControl(event))
                choose(pointed ? undefined : pointAt(spot.x, spot.y, NEAR), "pointer")
              return
            }
            pointers.set(event.pointerId, spot)
            if (pair !== undefined && pointers.size === 2) {
              // Two fingers: apart or together zooms, a twist turns the
              // picture, and their middle moving sideways moves through time.
              const next = fingers()
              zoom(pair.distance / Math.max(1, next.distance), next.x, next.y)
              yaw = within(yaw - wrap(next.angle - pair.angle), YAW_LIMIT)
              slide(next.x - pair.x, 0)
              pair = next
              dragged = true
              island.nudge()
              return
            }
            if (press?.id !== event.pointerId) return
            const dx = spot.x - press.x
            const dy = spot.y - press.y
            const dt = Math.max(1, event.timeStamp - press.at)
            press.moved += Math.hypot(dx, dy)
            if (press.moved > DRAG && !root.hasPointerCapture(event.pointerId)) {
              root.setPointerCapture(event.pointerId)
              root.dataset.dragging = "true"
              dragged = true
            }
            if (press.turns) {
              const was = {yaw, pitch}
              press.pulled.yaw -= dx * TURN
              press.pulled.pitch += dy * TURN
              yaw = band(press.pulled.yaw, YAW_LIMIT)
              pitch = band(press.pulled.pitch, PITCH_LIMIT)
              press.spin.yaw = 0.8 * ((yaw - was.yaw) / dt) + 0.2 * press.spin.yaw
              press.spin.pitch = 0.8 * ((pitch - was.pitch) / dt) + 0.2 * press.spin.pitch
            } else {
              // A finger moves through time sideways only; up and down are the page's.
              const seconds = slide(dx, press.touch ? 0 : dy)
              press.speed = 0.8 * (seconds / dt) + 0.2 * press.speed
            }
            press.x = spot.x
            press.y = spot.y
            press.at = event.timeStamp
            island.nudge()
          },
          options,
        )

        const release = (event: PointerEvent) => {
          if (!pointers.delete(event.pointerId)) return
          if (pointers.size < 2) pair = undefined
          if (press?.id === event.pointerId) {
            if (press.moved <= DRAG && press.touch && !onTip(event)) {
              const spot = local(event)
              choose(pointAt(spot.x, spot.y, NEAR_TOUCH), "pointer")
            }
            // A drag let go while still moving glides on, unless motion was
            // turned down; a turn let go past either end springs back.
            const recent = event.timeStamp - press.at < 80
            const glides = press.moved > DRAG && recent && !still(root) && event.type !== "pointercancel"
            if (press.turns) spin = glides ? press.spin : {yaw: 0, pitch: 0}
            else velocity = glides ? press.speed : 0
            press = undefined
          }
          if (still(root)) {
            yaw = within(yaw, YAW_LIMIT)
            pitch = within(pitch, PITCH_LIMIT)
          }
          if (pointers.size === 0) {
            delete root.dataset.dragging
            touching = false
          }
          island.nudge()
        }
        root.addEventListener("pointerup", release, options)
        root.addEventListener("pointercancel", release, options)
        root.addEventListener(
          "pointerleave",
          event => {
            if (event.pointerType !== "mouse") return
            pointed = null
            lift(true)
            if (focusBy === "pointer" && !pointers.size) choose(undefined, "pointer")
          },
          options,
        )
        // A drag that ends on a link opens nothing; a click does.
        root.addEventListener(
          "click",
          event => {
            if (!dragged) return
            dragged = false
            event.preventDefault()
            event.stopPropagation()
          },
          {signal: listening.signal, capture: true},
        )
        root.addEventListener(
          "dblclick",
          event => {
            if (onControl(event) || link.contains(event.target as Node) || onTip(event)) return
            event.preventDefault()
            reset(true)
          },
          options,
        )

        // Which of the picture and the page the scroll under way belongs to,
        // and when it last turned.
        let scroll = {owner: "page", at: -Infinity}
        document.addEventListener(
          "wheel",
          event => {
            if (!root.contains(event.target as Node)) scroll = {owner: "page", at: event.timeStamp}
          },
          {signal: listening.signal, passive: true},
        )
        root.addEventListener(
          "wheel",
          event => {
            const lines = event.deltaMode === WheelEvent.DOM_DELTA_LINE ? 16 : 1
            const dx = event.deltaX * lines
            const dy = event.deltaY * lines
            if (event.ctrlKey || event.metaKey) {
              // A pinch on a trackpad, or Ctrl or ⌘ and the wheel, zooms
              // toward the time under the pointer.
              event.preventDefault()
              takeOver()
              const spot = local(event)
              zoom(Math.exp(within(dy, MOST_PINCH) * PINCH), spot.x, spot.y)
              island.nudge()
              return
            }
            const sideways = Math.abs(dx) > Math.abs(dy)
            const toward = sideways ? dx : dy
            // Down or right moves toward now. Past either end the page
            // scrolls on, unless the picture has this scroll already.
            const stuck = !sideways && (toward > 0 ? following : mid <= earliest())
            if (event.timeStamp - scroll.at > LATCH) scroll.owner = stuck ? "page" : "picture"
            scroll.at = event.timeStamp
            if (scroll.owner === "page" && !sideways) return
            event.preventDefault()
            takeOver()
            move(toward * (span / width))
            island.nudge()
          },
          {signal: listening.signal, passive: false},
        )

        const turnsByKey: Record<string, [number, number]> = {
          ArrowLeft: [KEY_TURN, 0],
          ArrowRight: [-KEY_TURN, 0],
          ArrowUp: [0, -KEY_TURN],
          ArrowDown: [0, KEY_TURN],
        }
        root.addEventListener(
          "keydown",
          event => {
            if (event.target !== root || event.metaKey || event.ctrlKey) return
            if (event.altKey) {
              const turn = turnsByKey[event.key]
              if (turn === undefined) return
              event.preventDefault()
              holdCamera()
              yaw = within(yaw + turn[0], YAW_LIMIT)
              pitch = within(pitch + turn[1], PITCH_LIMIT)
              chooseMiddle()
              island.nudge()
              return
            }
            switch (event.key) {
              case "ArrowLeft":
                move(-KEY_PAN * span)
                break
              case "ArrowRight":
                move(KEY_PAN * span)
                break
              case "+":
              case "=":
                zoom(KEY_ZOOM)
                break
              case "-":
              case "_":
                zoom(1 / KEY_ZOOM)
                break
              case "Home": {
                const first = oldest()
                if (first === undefined) return
                mid = first + 0.4 * span
                following = false
                hold()
                break
              }
              case "End":
                home(false)
                break
              case "Enter":
                if (focus === undefined) return
                link.click()
                break
              case "Escape":
                // The picture's own: no open panel elsewhere on the page closes with it.
                event.stopPropagation()
                choose(undefined, "key")
                break
              default:
                return
            }
            event.preventDefault()
            if (event.key !== "End") takeOver()
            if (event.key !== "Escape" && event.key !== "Enter") chooseMiddle()
            island.nudge()
          },
          options,
        )
        back.addEventListener("click", event => home(byPointer(event)), options)
        for (const button of view.querySelectorAll<HTMLButtonElement>("[data-worldline-zoom]")) {
          button.addEventListener(
            "click",
            event => zoomBy(button.dataset.worldlineZoom === "in" ? KEY_ZOOM : 1 / KEY_ZOOM, byPointer(event)),
            options,
          )
        }
        view
          .querySelector<HTMLButtonElement>("[data-worldline-reset]")!
          .addEventListener("click", event => reset(byPointer(event)), options)
        root.addEventListener(
          "focus",
          () => {
            if (root.matches(":focus-visible")) chooseMiddle()
          },
          options,
        )
        root.addEventListener(
          "focusin",
          event => {
            keyed = event.target instanceof Element && event.target.matches("a[data-worldline-tip]:focus-visible") ? event.target : null
            lift(false)
          },
          options,
        )
        root.addEventListener(
          "focusout",
          event => {
            keyed = null
            lift(false)
            if (!root.contains(event.relatedTarget as Node | null) && focusBy === "key") choose(undefined, "key")
          },
          options,
        )

        const forget = watchTheme(() => {
          island.renderer()?.gpu.tones(tones())
          island.nudge()
        })
        // The picture's size, and each name's as its font arrives.
        const resized = new ResizeObserver(() => {
          measure()
          island.nudge()
        })
        resized.observe(canvas)
        for (const {label} of tipped.values()) resized.observe(label)

        return () => {
          listening.abort()
          forget()
          resized.disconnect()
          nudge = () => {}
        }
      },
    })
    this.controller.mount()
  },
  disconnected(this: WorldlineHook) {
    this.controller?.pause()
  },
  reconnected(this: WorldlineHook) {
    this.controller?.resume()
  },
  destroyed(this: WorldlineHook) {
    this.scope?.revert()
    this.controller?.destroy()
    this.controller = undefined
  },
}
