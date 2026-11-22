/**
 * The homepage's moving parts around "Buy Key": the hex field behind the
 * hero, with the tiles nearest a mouse standing up out of it, and the
 * Key on offer's card with its turn, its dust and its shuffle. Each only presents; the
 * page is complete and readable before any of it loads, and none of it decides
 * whether the button can be pressed.
 */
import {animate, createAnimatable, createScope, type AnimatableObject, type JSAnimation, type Scope} from "animejs"
import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {FieldRenderer, Tile} from "../home_hero/renderer"
import {EASE_IN_OUT, EASE_OUT, FAST, still} from "./motion/shared"
import {watchTheme} from "../../theme"
import {tone} from "../theme_tone"

/** A number the stylesheet states in a custom property. */
const measure = (el: HTMLElement, property: string) => parseFloat(getComputedStyle(el).getPropertyValue(property)) || 0

/** Where a pointer stands across an element's box, 0..1 on each axis and held inside it. */
const across = (event: PointerEvent, box: DOMRect): [number, number] => [
  Math.min(1, Math.max(0, (event.clientX - box.left) / box.width)),
  Math.min(1, Math.max(0, (event.clientY - box.top) / box.height)),
]

const finePointer = () => matchMedia("(hover: hover) and (pointer: fine)").matches

type IslandHook = {el: HTMLElement; controller?: CanvasIslandController}

/** How many tiles apart the marks of a wake are laid, and the most one move may lay. */
const WAKE_SPACING = 0.5
const WAKE_MARKS_PER_MOVE = 12

/** How many of the tiles nearest a mouse stand raised. */
const RAISED = 5
/** How high the tile under a mouse stands, in tiles. */
const LIFT = 0.4
/** How long a tile takes to stand up, and to sink back. */
const STAND = 300

/**
 * How far apart the field's rows are, in tiles. The tiles' centres lie on two
 * grids, counted from the tile at the field's centre: whole tiles across on
 * every row, and half a tile across, half a row down, between them.
 */
const ROW = Math.sqrt(3)

/** The `count` tiles whose centres are nearest x, y (in tiles from the field's centre), nearest first. */
const nearest = (x: number, y: number, count: number) => {
  const column = Math.floor(x)
  const down = Math.floor(y / ROW)
  const centres: {x: number; y: number; away: number}[] = []
  for (let k = column - 1; k <= column + 2; k += 1) {
    for (let m = down - 1; m <= down + 2; m += 1) {
      for (const [cx, cy] of [[k, m * ROW], [k + 0.5, (m + 0.5) * ROW]] as const) {
        centres.push({x: cx, y: cy, away: Math.hypot(cx - x, cy - y)})
      }
    }
  }
  return centres.sort((a, b) => a.away - b.away).slice(0, count)
}

/**
 * How high a tile `away` tiles from the mouse stands: the one under it
 * highest, the others lower the further off they are.
 */
const heightAt = (away: number, nearestFirst: boolean) =>
  nearestFirst ? 1 : Math.min(0.7, Math.max(0.25, 0.95 - 0.45 * away))

/** A raised tile and the height it is on its way to. */
type Standing = Tile & {key: string; to: number}

/**
 * The hex field. `data-field-cell` is the distance between neighbouring tiles
 * in CSS pixels. Anywhere in the element marked `data-field-scope`, the five
 * tiles nearest a mouse stand up out of the field, the one under it highest,
 * and follow it as it moves, each rising and sinking in 0.3 seconds. A mouse
 * also lights the tiles near it, and it, or a finger on a screen that also has
 * one, leaves a wake of lit tiles that fades behind it; scrolling under a
 * resting mouse moves all of it to the tiles passing beneath. A press sends a
 * ring out across the tiles. In the hero, previewing the Key warms the tiles
 * around its card. Nothing moves unless someone does, and the field is still
 * again shortly after. All of it comes from a mouse or a desktop's keyboard,
 * so on a phone or tablet, or for a visitor who asked for less motion, the
 * stylesheet's still drawing is the field and the GPU is never asked; the
 * page's own less-motion switch drops the raised tiles, the pointer's light,
 * the wake and the ring. The fade toward the field's edges is the
 * stylesheet's `--rl-fade-*` for each layout.
 */
export const HexField = {
  mounted(this: IslandHook) {
    if (!finePointer()) return
    const root = this.el
    const scope = root.closest<HTMLElement>("[data-field-scope]")!
    const buy = scope.querySelector<HTMLElement>("[data-key-preview]")
    const card = buy?.querySelector<HTMLElement>("[data-key-card]")
    const cell = Number(root.dataset.fieldCell)

    this.controller = createCanvasIsland<FieldRenderer>(root, {}, {
      canvasSelector: "[data-field-canvas]",
      readyFlag: "fieldReady",
      motionSensitive: true,
      continuous: false,
      browserLoad: async (canvas, size, lost) => {
        const {createFieldRenderer} = await import("../home_hero/renderer")
        return createFieldRenderer(canvas, size, lost, cell)
      },
      interact: ({canvas, renderer, nudge, onReady}) => {
        const retone = () => {
          const ground = tone(root, "--color-bg")
          const light = 0.2126 * ground[0] + 0.7152 * ground[1] + 0.0722 * ground[2] > 0.5
          renderer()?.tones(
            tone(root, "--rl-field-line"),
            tone(root, "--rl-field-light"),
            ground,
            tone(root, "--rl-field-deep"),
            light ? 0.18 : 0.32,
          )
          nudge()
        }
        // The fade toward the field's edges, as the stylesheet states it for this layout.
        const refade = () => {
          renderer()?.fade(
            measure(root, "--rl-fade-x"),
            measure(root, "--rl-fade-y"),
            measure(root, "--rl-fade-width"),
            measure(root, "--rl-fade-height"),
            measure(root, "--rl-fade-from"),
            measure(root, "--rl-fade-to"),
          )
          nudge()
        }
        // The Key's light is centred on the card wherever the layout has put it.
        const aim = () => {
          if (!card) return
          const box = canvas().getBoundingClientRect()
          const at = card.getBoundingClientRect()
          renderer()?.key(
            (at.left + at.width / 2 - box.left) / box.width,
            (at.top + at.height / 2 - box.top) / box.height,
            Math.max(at.width, at.height) * 0.95,
          )
        }
        let hovering = false
        let focused = false
        const preview = () => {
          aim()
          renderer()?.lit(hovering || focused)
          nudge()
        }

        // The raised tiles, by where they sit, until each has sunk back.
        const standing = new Map<string, Standing>()
        const draw = () => {
          for (const [key, tile] of standing) if (tile.h === 0 && tile.to === 0) standing.delete(key)
          renderer()?.stand([...standing.values()].sort((a, b) => b.h - a.h), cell * LIFT)
          nudge()
        }
        const motion = createScope({root})
        motion.add(() => {
          // A new height takes over from the one a tile is still moving to, from wherever it got to.
          motion.add("stand", (tile: Standing, to: number, duration: number) => {
            animate(tile, {
              h: to,
              duration,
              ease: to > tile.h ? EASE_OUT : EASE_IN_OUT,
              onUpdate: draw,
              onComplete: draw,
            })
          })
        })
        const stand = (tile: Standing, to: number) => {
          if (Math.abs(tile.to - to) < 0.02) return
          tile.to = to
          motion.methods.stand!(tile, to, STAND)
        }
        // The tiles nearest the mouse stand; every other tile sinks.
        const follow = (clientX: number, clientY: number) => {
          const box = canvas().getBoundingClientRect()
          const near = nearest(
            (clientX - box.left - box.width / 2) / cell,
            (clientY - box.top - box.height / 2) / cell,
            RAISED,
          )
          const keys = new Set<string>()
          near.forEach((centre, rank) => {
            const key = `${centre.x * 2},${Math.round((centre.y * 2) / ROW)}`
            keys.add(key)
            let tile = standing.get(key)
            if (!tile) {
              tile = {key, x: centre.x * cell + box.width / 2, y: centre.y * cell + box.height / 2, h: 0, to: 0}
              standing.set(key, tile)
            }
            stand(tile, heightAt(centre.away, rank === 0))
          })
          for (const tile of standing.values()) if (!keys.has(tile.key)) stand(tile, 0)
        }
        const sink = () => {
          for (const tile of standing.values()) stand(tile, 0)
        }
        // Less motion, or a new size: the raised tiles are back in the field at once.
        const flatten = () => {
          for (const tile of standing.values()) {
            tile.to = 0
            motion.methods.stand!(tile, 0, 0)
          }
        }

        onReady(() => {
          retone()
          refade()
          preview()
          draw()
        })

        // The last place the wake reached, in CSS pixels across the canvas, so a
        // fast move or a scroll still leaves an unbroken line of tiles.
        let trail: [number, number] | undefined
        let mouse: [number, number] | undefined
        const leave = (clientX: number, clientY: number) => {
          const drawn = renderer()
          if (!drawn) return
          const box = canvas().getBoundingClientRect()
          const to: [number, number] = [clientX - box.left, clientY - box.top]
          const from = trail ?? to
          const spacing = cell * WAKE_SPACING
          const gap = Math.hypot(to[0] - from[0], to[1] - from[1])
          if (trail && gap < spacing) return
          const count = Math.min(WAKE_MARKS_PER_MOVE, Math.max(1, Math.round(gap / spacing)))
          for (let i = 1; i <= count; i += 1) {
            const t = i / count
            drawn.wake((from[0] + (to[0] - from[0]) * t) / box.width, (from[1] + (to[1] - from[1]) * t) / box.height)
          }
          trail = to
        }

        const onMove = (event: PointerEvent) => {
          if (!event.isPrimary || event.pointerType === "touch") return
          if (still(root)) {
            if (standing.size > 0) flatten()
            return
          }
          const box = canvas().getBoundingClientRect()
          renderer()?.point((event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height)
          mouse = [event.clientX, event.clientY]
          follow(event.clientX, event.clientY)
          leave(event.clientX, event.clientY)
          nudge()
        }
        const onLeave = (event: PointerEvent) => {
          if (event.pointerType === "touch") return
          mouse = undefined
          trail = undefined
          sink()
          renderer()?.rest()
          nudge()
        }
        const onPress = (event: PointerEvent) => {
          if (!event.isPrimary || still(root)) return
          const box = canvas().getBoundingClientRect()
          renderer()?.ring((event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height)
          nudge()
        }
        const onTouch = (event: TouchEvent) => {
          const touch = event.touches[0]
          if (!touch || still(root)) return
          leave(touch.clientX, touch.clientY)
          nudge()
        }
        const onLift = () => {
          trail = undefined
        }
        // The page moves under a resting mouse, so the raised tiles and the
        // pointer's light move to the tiles now beneath it, and the wake follows.
        const onScroll = () => {
          if (!mouse || still(root)) return
          const box = canvas().getBoundingClientRect()
          renderer()?.point((mouse[0] - box.left) / box.width, (mouse[1] - box.top) / box.height)
          follow(mouse[0], mouse[1])
          leave(mouse[0], mouse[1])
          nudge()
        }
        const onEnter = () => {
          hovering = true
          preview()
        }
        const onExit = () => {
          hovering = false
          preview()
        }
        const onFocus = (event: FocusEvent) => {
          focused = (event.target as Element).matches(":focus-visible")
          preview()
        }
        const onBlur = () => {
          focused = false
          preview()
        }

        const events = new AbortController()
        const options = {signal: events.signal, passive: true}
        scope.addEventListener("pointermove", onMove, options)
        scope.addEventListener("pointerleave", onLeave, options)
        scope.addEventListener("pointerdown", onPress, options)
        scope.addEventListener("touchstart", onTouch, options)
        scope.addEventListener("touchmove", onTouch, options)
        scope.addEventListener("touchend", onLift, options)
        scope.addEventListener("touchcancel", onLift, options)
        window.addEventListener("scroll", onScroll, options)
        buy?.addEventListener("pointerenter", onEnter, options)
        buy?.addEventListener("pointerleave", onExit, options)
        buy?.addEventListener("focusin", onFocus, options)
        buy?.addEventListener("focusout", onBlur, options)
        const forget = watchTheme(retone)
        // A new size moves every tile, so the raised ones go back into the field.
        const resized = new ResizeObserver(() => {
          flatten()
          refade()
          preview()
        })
        resized.observe(root)
        if (card) resized.observe(card)

        return () => {
          events.abort()
          forget()
          resized.disconnect()
          motion.revert()
        }
      },
    })
    this.controller.mount()
  },
  disconnected(this: IslandHook) {
    this.controller?.pause()
  },
  reconnected(this: IslandHook) {
    this.controller?.resume()
  },
  destroyed(this: IslandHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}

type KeyCardHook = {el: HTMLElement; scope?: Scope; release?: () => void}

/** The pass's own card inside its picture's box, as fractions of it: columns 52 to 597
 * of 600 and rows 1 to 751 of 754, with corners rounded a twentieth of its width. */
const PASS = {left: 52 / 600, right: 597 / 600, top: 1 / 754, bottom: 751 / 754, corner: 0.05}
/** How far from the card's edge the dust starts to show, in card widths. */
const DUST_REACH = 1.5
/** How far out a mote drifts before it fades, in card widths, and how many there are. */
const DUST_DRIFT = 0.1
const MOTES = 360
/** How quickly the dust follows the pointer and brightens or dims: the share of the way it closes each millisecond. */
const FOLLOW = 0.012
/** How long the shuffle takes to dissolve back to the pass. */
const DISSOLVE = 500

type Point = [number, number]
type Outline = {x0: number; y0: number; x1: number; y1: number; r: number}
/** A mote of dust: where along the card's edge it rises from (0..1), how far out it has drifted, its pace, size and twinkle. */
type Mote = {along: number; out: number; pace: number; size: number; phase: number}

/** The point on the card's rounded edge nearest `p`, the way out from it there, and how far `p` is outside it (below 0 inside). */
function nearestOnEdge([px, py]: Point, {x0, y0, x1, y1, r}: Outline): {at: Point; away: number} {
  const qx = Math.min(Math.max(px, x0 + r), x1 - r)
  const qy = Math.min(Math.max(py, y0 + r), y1 - r)
  const dx = px - qx
  const dy = py - qy
  const length = Math.hypot(dx, dy)
  if (length > 1e-6) return {at: [qx + (dx / length) * r, qy + (dy / length) * r], away: length - r}
  // Inside the straight part: the nearest side.
  const sides: [number, Point][] = [
    [px - x0, [x0, py]],
    [x1 - px, [x1, py]],
    [py - y0, [px, y0]],
    [y1 - py, [px, y1]],
  ]
  const [inside, at] = sides.reduce((near, side) => (side[0] < near[0] ? side : near))
  return {at, away: -inside}
}

/** The point `along` (0..1) the card's rounded edge, going round it, and the way out from the card there. */
function pointOnEdge(along: number, {x0, y0, x1, y1, r}: Outline): {at: Point; out: Point} {
  const w = x1 - x0 - 2 * r
  const h = y1 - y0 - 2 * r
  const arc = (Math.PI / 2) * r
  let d = along * (2 * (w + h) + 4 * arc)
  const corners: [Point, number][] = [
    [[x1 - r, y0 + r], -Math.PI / 2],
    [[x1 - r, y1 - r], 0],
    [[x0 + r, y1 - r], Math.PI / 2],
    [[x0 + r, y0 + r], Math.PI],
  ]
  const sides: [Point, Point, number][] = [
    [[x0 + r, y0], [0, -1], w],
    [[x1, y0 + r], [1, 0], h],
    [[x1 - r, y1], [0, 1], w],
    [[x0, y1 - r], [-1, 0], h],
  ]
  const runs: Point[] = [[1, 0], [0, 1], [-1, 0], [0, -1]]
  for (let i = 0; i < 4; i++) {
    const [[sx, sy], out, length] = sides[i]
    if (d <= length) return {at: [sx + runs[i][0] * d, sy + runs[i][1] * d], out}
    d -= length
    if (d <= arc || i === 3) {
      const [[cx, cy], from] = corners[i]
      const a = from + Math.min(d, arc) / r
      return {at: [cx + Math.cos(a) * r, cy + Math.sin(a) * r], out: [Math.cos(a), Math.sin(a)]}
    }
    d -= arc
  }
  throw new Error("unreachable")
}

/** A soft round glow in `color`, drawn once and stamped for every mote. */
function glowSprite(color: string): HTMLCanvasElement {
  const sprite = document.createElement("canvas")
  sprite.width = sprite.height = 32
  const g = sprite.getContext("2d")!
  const light = g.createRadialGradient(16, 16, 0, 16, 16, 16)
  light.addColorStop(0, color)
  light.addColorStop(0.35, color)
  light.addColorStop(1, "transparent")
  g.fillStyle = light
  g.fillRect(0, 0, 32, 32)
  return sprite
}

/**
 * Dust just outside the card's edge, gathered on the side facing the pointer
 * and brighter the nearer the pointer is. It draws only while there is some to
 * see, and clears when the pointer is gone. `near` hears each frame the
 * pointer is within reach.
 */
function dustAround(canvas: HTMLCanvasElement, card: HTMLElement, near: () => void, signal: AbortSignal) {
  const g = canvas.getContext("2d")!
  const spawn = (out: number): Mote => ({
    along: Math.random(),
    out,
    pace: 0.35 + Math.random() * 0.65,
    size: 0.6 + Math.random() ** 2 * 1.6,
    phase: Math.random() * Math.PI * 2,
  })
  const motes = Array.from({length: MOTES}, () => spawn(Math.random()))
  let sprite = glowSprite(getComputedStyle(canvas).color)
  let pointer: Point | undefined
  let aim: Point | undefined
  let glow = 0
  let frame = 0
  let last = 0

  const draw = (now: number) => {
    const step = Math.min(now - last, 64)
    last = now
    const w = canvas.offsetWidth
    const h = canvas.offsetHeight
    const dpr = Math.min(devicePixelRatio, 2)
    if (canvas.width !== Math.round(w * dpr)) canvas.width = Math.round(w * dpr)
    if (canvas.height !== Math.round(h * dpr)) canvas.height = Math.round(h * dpr)
    const margin = -canvas.offsetLeft
    const cw = card.offsetWidth
    const ch = card.offsetHeight
    const edge = {
      x0: margin + PASS.left * cw,
      x1: margin + PASS.right * cw,
      y0: margin + PASS.top * ch,
      y1: margin + PASS.bottom * ch,
      r: PASS.corner * cw,
    }

    let bright = 0
    if (pointer && !still(card)) {
      const box = canvas.getBoundingClientRect()
      const local: Point = [((pointer[0] - box.left) * w) / box.width, ((pointer[1] - box.top) * h) / box.height]
      const {at, away} = nearestOnEdge(local, edge)
      bright = Math.max(0, 1 - Math.max(away, 0) / (DUST_REACH * cw)) ** 1.2
      if (bright > 0) near()
      aim = aim ? [aim[0] + (at[0] - aim[0]) * Math.min(1, step * FOLLOW * 1.5), aim[1] + (at[1] - aim[1]) * Math.min(1, step * FOLLOW * 1.5)] : at
    }
    glow += (bright - glow) * Math.min(1, step * FOLLOW)

    g.setTransform(dpr, 0, 0, dpr, 0, 0)
    g.clearRect(0, 0, w, h)
    if (glow < 0.004 && bright === 0) {
      frame = 0
      aim = undefined
      return
    }
    g.globalCompositeOperation = "lighter"
    const drift = DUST_DRIFT * cw
    // Near the card the dust gathers tightly toward the pointer; further off it spreads wide and faint.
    const spread = cw * (0.16 + 0.3 * (1 - glow))
    for (const mote of motes) {
      mote.out += (step / 1000) * mote.pace * 0.6
      if (mote.out >= 1) Object.assign(mote, spawn(0))
      const {at, out} = pointOnEdge(mote.along, edge)
      const toward = aim ? Math.exp(-((Math.hypot(at[0] - aim[0], at[1] - aim[1]) / spread) ** 2)) : 0
      const alpha = 1.5 * glow * toward * Math.sin(Math.PI * mote.out) * (0.65 + 0.35 * Math.sin(mote.phase + now / 260))
      if (alpha < 0.01) continue
      const reach = 2 + mote.out * drift
      const size = mote.size * (4 + 9 * glow)
      g.globalAlpha = Math.min(1, alpha)
      g.drawImage(sprite, at[0] + out[0] * reach - size / 2, at[1] + out[1] * reach - size / 2, size, size)
    }
    g.globalAlpha = 1
    g.globalCompositeOperation = "source-over"
    frame = requestAnimationFrame(draw)
  }
  const wake = () => {
    if (frame) return
    last = performance.now()
    frame = requestAnimationFrame(draw)
  }

  const options = {signal, passive: true}
  document.addEventListener(
    "pointermove",
    (event: PointerEvent) => {
      if (event.pointerType !== "mouse") return
      pointer = [event.clientX, event.clientY]
      wake()
    },
    options,
  )
  document.documentElement.addEventListener("pointerleave", () => (pointer = undefined), options)
  window.addEventListener("blur", () => (pointer = undefined), options)
  const forget = watchTheme(() => {
    sprite = glowSprite(getComputedStyle(canvas).color)
  })
  return () => {
    forget()
    cancelAnimationFrame(frame)
    g.clearRect(0, 0, canvas.width, canvas.height)
  }
}

/**
 * The next Key's card. Under a mouse, pointing at the card or its button turns
 * the card a little toward the pointer, and it settles when the pointer leaves.
 * Once it is level again it keeps no turn of its own: the stylesheet has it.
 * Dust gathers outside its edge on the side facing the pointer, and pointing at
 * the card or the button flashes it into a shuffle of a hundred Keys, the pass
 * fading out under it, and the two dissolve back when the pointer leaves both. The shuffle's
 * picture loads the first time the dust shows. A finger, a keyboard or less
 * motion gets the card as it is.
 */
export const NextKeyCard = {
  mounted(this: KeyCardHook) {
    const root = this.el
    const area = root.closest<HTMLElement>("[data-key-preview]") ?? root
    const tilt = root.querySelector<HTMLElement>("[data-key-tilt]")!
    const dust = root.querySelector<HTMLCanvasElement>("[data-key-dust]")!
    const pass = root.querySelector<HTMLImageElement>("[data-key-pass]")!
    const shuffle = root.querySelector<HTMLImageElement>("[data-key-shuffle]")!
    let turn: AnimatableObject | undefined
    let point: ((on: boolean) => void) | undefined

    const scope = createScope({root, mediaQueries: {reduced: "(prefers-reduced-motion: reduce)"}})
    this.scope = scope.add(() => {
      if (scope.matches.reduced || !finePointer()) return
      const level = createAnimatable(tilt, {
        rotateX: 0,
        rotateY: 0,
        duration: 420,
        ease: EASE_OUT,
        onComplete: () => {
          if (level.rotateX() === 0 && level.rotateY() === 0) tilt.style.removeProperty("transform")
        },
      })
      turn = level

      const load = () => {
        if (!shuffle.getAttribute("src")) shuffle.src = shuffle.dataset.src!
      }
      const drawing = new AbortController()
      const stopDust = dustAround(dust, root, load, drawing.signal)

      let pointing = false
      let flash: JSAnimation | undefined
      let fades: JSAnimation[] = []
      // The shuffle comes in as the pass goes, and the other way round; each
      // Key's key reaches past the card, where the pass's own would show.
      const reveal = () => {
        if (!pointing) return
        shuffle.style.visibility = "visible"
        fades = [
          animate(shuffle, {opacity: 1, duration: FAST, ease: EASE_OUT}),
          animate(pass, {opacity: 0, duration: FAST, ease: EASE_OUT}),
        ]
      }
      point = on => {
        if (on === pointing) return
        pointing = on
        fades.forEach(fade => fade.cancel())
        if (on) {
          flash?.cancel()
          flash = animate(tilt, {
            filter: [
              {to: "brightness(2.4)", duration: 90, ease: "outQuad"},
              {to: "brightness(1)", duration: 300, ease: EASE_OUT},
            ],
            onComplete: () => tilt.style.removeProperty("filter"),
          })
          load()
          shuffle.decode().then(reveal, () => {})
        } else {
          fades = [
            animate(shuffle, {
              opacity: 0,
              duration: DISSOLVE,
              ease: EASE_IN_OUT,
              onComplete: () => {
                shuffle.style.visibility = "hidden"
              },
            }),
            animate(pass, {
              opacity: 1,
              duration: DISSOLVE,
              ease: EASE_IN_OUT,
              onComplete: () => pass.style.removeProperty("opacity"),
            }),
          ]
        }
      }
      return () => {
        drawing.abort()
        stopDust()
        flash?.cancel()
        fades.forEach(fade => fade.cancel())
        tilt.style.removeProperty("filter")
        shuffle.style.removeProperty("visibility")
        shuffle.style.removeProperty("opacity")
        pass.style.removeProperty("opacity")
        turn = undefined
        point = undefined
      }
    })

    const onTurn = (event: PointerEvent) => {
      if (!turn || !event.isPrimary || still(root)) return
      const [x, y] = across(event, root.getBoundingClientRect())
      turn.rotateY((x - 0.5) * 9)
      turn.rotateX((0.5 - y) * 7)
    }
    const onSettle = () => {
      turn?.rotateX(0)
      turn?.rotateY(0)
    }
    // The card and its button: the area between them, or anything else, is neither.
    const onOver = (event: PointerEvent) => {
      if (event.pointerType !== "mouse") return
      const target = event.target as Element
      point?.(!still(root) && target.closest("[data-key-card], #home-buy-key") !== null)
    }
    const events = new AbortController()
    area.addEventListener("pointermove", onTurn, {signal: events.signal, passive: true})
    area.addEventListener("pointerover", onOver, {signal: events.signal, passive: true})
    area.addEventListener(
      "pointerleave",
      () => {
        onSettle()
        point?.(false)
      },
      {signal: events.signal, passive: true},
    )
    this.release = () => events.abort()
  },
  destroyed(this: KeyCardHook) {
    this.release?.()
    this.scope?.revert()
  },
}
