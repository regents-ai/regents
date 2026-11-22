/**
 * LiveView hook for the Regents home hero Datascape (`vgpu` island + Anime.js v4).
 *
 * Uses `createCanvasIsland` from `canvas_island.ts` so device-loss recovery,
 * tab visibility, IntersectionObserver pausing, DPR/pixel budgets, and reduced
 * motion still-face fallback stay in one place. Every Anime.js animation runs
 * inside a `createScope` reverted cleanly on `destroyed()`.
 *
 * Supports all three hero modes (`open`, `canvas`, `crown`) via `data-hero-mode`
 * on `<html>` (set by the server from `?hero=open|canvas|crown`, default `open`),
 * plus clicking any panel or crown square to open the `#pick` products menu.
 */
import {animate, createScope, cubicBezier, utils, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {MARK_HEIGHT, MARK_WIDTH, type Square} from "../datascape/crown"
import {calmAround, type Cell, type Panel, type Tube} from "../datascape/field"
import type {DatascapeRenderer, Quiet} from "../datascape/renderer"
import type {Hook} from "../hook_composition"

const OPENING = 750
const ASSEMBLY = 2400
const FLASH = 0.55
const STAGGER = 500
const FIRST_WAVE = 900
const TUBE_SPEED = 1300
const REACTION = 350
const LARGE = 8
const OPENING_SPARKS = 3
const PRESS_SPARKS = 14

const LEAVING = 28
const ROOM = 24
const SOFT = 140
const BAND_ROOM = 12
const BAND_SOFT = 72
const DRAG = 6

const FLIGHT = 560
const SPREAD = 420
const LANDING = 0.3
const LANDING_TIME = 420
const ARRIVAL = [10, 9, 11, 8, 12, 5, 4, 6, 3, 7, 1, 0, 2]
const CROWN_QUIET = 600
const REFORM = 1400
const FREE = 1200

const OPEN_AFTER = 1600
const QUIETING = 700
const GATHER_AFTER = 800
const WORDS_AFTER = 450
const EDGE = 8
const BEGIN = ["pointerdown", "keydown", "wheel", "touchstart", "scroll"] as const

const EASE_OUT = cubicBezier(0.23, 1, 0.32, 1)

type Hoverable = {hover: number}

type DatascapeHeroHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
}

function readSession(key: string): string | null {
  try {
    return window.sessionStorage.getItem(key)
  } catch {
    return null
  }
}

function writeSession(key: string, value: string): void {
  try {
    window.sessionStorage.setItem(key, value)
  } catch {
    // Storage may be unavailable in private contexts.
  }
}

export const DatascapeHero: Hook = {
  mounted(this: DatascapeHeroHook) {
    const heroEl = this.el
    const docRoot = document.documentElement
    const stage = heroEl.querySelector<HTMLElement>("[data-datascape]")
    const canvas = heroEl.querySelector<HTMLCanvasElement>("[data-datascape-canvas]")
    const words = heroEl.querySelector<HTMLElement>(".hero__words")
    const actions = heroEl.querySelector<HTMLElement>(".hero__actions")
    const crownSlot = heroEl.querySelector<HTMLElement>("[data-crown]")
    const bar = document.querySelector<HTMLElement>("[data-bar]")
    const pick = document.getElementById("pick")

    if (!stage || !canvas || !words || !actions || !crownSlot || !bar || !pick) return

    const pickLinks = [...pick.querySelectorAll<HTMLAnchorElement>("a")]
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
    const fine = window.matchMedia("(hover: hover) and (pointer: fine)")

    const explicitHero = new URLSearchParams(window.location.search).has("hero")
    const mode = docRoot.dataset.heroMode ?? "open"

    // Initialize entrance state before the first paint settles.
    if (!reduced.matches) {
      if (mode === "open" && (explicitHero || readSession("regents:hero:opened") !== "yes")) {
        docRoot.dataset.hero = "closed"
      } else if (
        mode === "crown" &&
        (explicitHero || readSession("regents:hero:crowned") !== "yes")
      ) {
        docRoot.dataset.hero = "gathering"
      } else {
        delete docRoot.dataset.hero
      }
    } else {
      delete docRoot.dataset.hero
    }

    // Scoped Anime.js instance so every panel/tube/crown animation reverts cleanly on destroy.
    const scope: Scope = createScope({root: heroEl})
    const runScoped = (fn: () => void) => {
      scope.add(fn)
    }

    const closePick = () => {
      if (!pick.hasAttribute("data-open")) return
      if (pick.contains(document.activeElement) && document.activeElement instanceof HTMLElement) {
        document.activeElement.blur()
      }
      delete pick.dataset.open
    }

    const openPick = (x: number, y: number) => {
      pick.dataset.instant = ""
      delete pick.dataset.open
      const left = Math.max(EDGE, Math.min(x, window.innerWidth - pick.offsetWidth - EDGE))
      const top = Math.max(EDGE, Math.min(y, window.innerHeight - pick.offsetHeight - EDGE))
      pick.style.left = `${left}px`
      pick.style.top = `${top}px`
      pick.style.transformOrigin = `${x - left}px ${y - top}px`
      pick.getBoundingClientRect()
      delete pick.dataset.instant
      pick.dataset.open = ""
      pick.focus({preventScroll: true})
    }

    const onPickKeydown = (event: KeyboardEvent) => {
      const here = pickLinks.indexOf(document.activeElement as HTMLAnchorElement)
      const targets: Record<string, HTMLAnchorElement | undefined> = {
        ArrowDown: pickLinks[(here + 1) % pickLinks.length],
        ArrowUp: pickLinks[(here - 1 + pickLinks.length) % pickLinks.length],
        Home: pickLinks[0],
        End: pickLinks[pickLinks.length - 1],
      }
      const go = targets[event.key]
      if (go) {
        event.preventDefault()
        go.focus()
      }
      if (event.key === "Escape") closePick()
    }
    const onPickFocusOut = (event: FocusEvent) => {
      if (!pick.contains(event.relatedTarget as Node | null)) closePick()
    }
    const onDocPointerDown = (event: PointerEvent) => {
      if (!pick.contains(event.target as Node | null)) closePick()
    }

    pick.addEventListener("keydown", onPickKeydown)
    pick.addEventListener("focusout", onPickFocusOut)
    document.addEventListener("pointerdown", onDocPointerDown, true)
    window.addEventListener("scroll", closePick, {passive: true})
    window.addEventListener("resize", closePick)

    let scape: DatascapeRenderer | undefined
    let rested: Hoverable | null = null
    const quiet: Quiet = {
      x: 0,
      y: 0,
      halfWidth: 0,
      halfHeight: 0,
      soft: SOFT,
      band: 0,
      bandSoft: BAND_SOFT,
      strength: 0,
    }

    let crowned = false
    let released = false
    let reforming = 0
    let crownShown = false
    let quietAim = -1
    let crownMiddle: [number, number] = [0, 0]

    const wait = (distance: number, seed: number) =>
      scape && scape.field.time === 0 ? distance * FIRST_WAVE + seed * STAGGER : 0

    const open = (panel: Panel, distance: number) => {
      const large = panel.w > LARGE
      runScoped(() => {
        animate(panel, {
          grow: {
            to: 1,
            duration: large ? OPENING : OPENING / 2,
            ease: large ? "outBack(1.6)" : "outExpo",
          },
          flash: {from: large ? FLASH : 0, to: 0, duration: OPENING, ease: "outQuad"},
          assemble: {to: 1, duration: ASSEMBLY, ease: "outCubic"},
          delay: wait(distance, panel.seed),
          onBegin: () => {
            if (large) scape?.field.burst(panel, OPENING_SPARKS)
          },
        })
      })
    }

    const draw = (tube: Tube, distance: number) => {
      runScoped(() => {
        animate(tube, {
          drawn: tube.length,
          duration: (tube.length / TUBE_SPEED) * 1000,
          delay: wait(distance, tube.seed),
          ease: "inOutQuad",
        })
      })
    }

    const leave = (cell: Cell) => {
      utils.remove(cell.panels)
      if (cell.tube) utils.remove(cell.tube)
    }

    const rest = (target: Hoverable | null) => {
      if (target === rested) return
      const prev = rested
      runScoped(() => {
        if (prev) animate(prev, {hover: 0, duration: REACTION, ease: "outExpo"})
        if (target) animate(target, {hover: 1, duration: REACTION, ease: "outExpo"})
      })
      rested = target
      canvas.style.cursor = target ? "pointer" : ""
    }

    const flash = (target: Panel | Square) => {
      runScoped(() => {
        animate(target, {
          flash: {from: 0.85, to: 0, duration: OPENING, ease: "outQuad"},
          assemble: {from: 0, to: 1, duration: ASSEMBLY / 2, ease: "outCubic"},
        })
      })
    }

    const settleQuiet = () => {
      if (!scape) return
      const aim = crownShown && !released ? 1 : 0
      if (aim === quietAim) return
      const first = quietAim === -1
      quietAim = aim
      utils.remove(scape.crown)
      if (first) scape.crown.quiet = aim
      else {
        const crown = scape.crown
        runScoped(() => {
          animate(crown, {quiet: aim, duration: CROWN_QUIET, ease: EASE_OUT})
        })
      }
    }

    const stillSquares = () => {
      if (!scape) return
      utils.remove(scape.crown.squares)
      if (scape.crown.squares.some(square => square === rested)) rest(null)
    }

    const measure = () => {
      const box = canvas.getBoundingClientRect()
      const wordsBox = words.getBoundingClientRect()
      quiet.band = bar.offsetHeight + BAND_ROOM
      quiet.x = wordsBox.left + wordsBox.width / 2 - (box.left + box.width / 2)
      quiet.y = wordsBox.top + wordsBox.height / 2 - (box.top + box.height / 2)
      quiet.halfWidth = wordsBox.width / 2 + ROOM
      quiet.halfHeight = wordsBox.height / 2 + ROOM
      const slot = crownSlot.getBoundingClientRect()
      crownShown = slot.width > 0 && slot.height > 0
      crownMiddle = [
        slot.left + slot.width / 2 + window.scrollX,
        slot.top + slot.height / 2 + window.scrollY,
      ]
      if (!scape) return
      scape.field.calm = calmAround(
        [wordsBox.width, wordsBox.height],
        LEAVING,
        [box.width, box.height],
      )
      const {place} = scape.crown
      place.x = slot.left + slot.width / 2 - (box.left + box.width / 2)
      place.y = slot.top + slot.height / 2 - (box.top + box.height / 2)
      place.unit = Math.min(slot.width / MARK_WIDTH, slot.height / MARK_HEIGHT)
      settleQuiet()
    }

    const gather = () => {
      if (!scape) return
      const {crown} = scape
      window.clearTimeout(reforming)
      stillSquares()
      crown.clear()
      released = false
      measure()
      const squares = crown.take(canvas.clientWidth, canvas.clientHeight, quiet)
      const last = ARRIVAL.length - 1
      for (const square of squares) {
        const order = ARRIVAL.indexOf(square.slot) / last
        runScoped(() => {
          animate(square, {
            flown: {to: 1, duration: FLIGHT, ease: EASE_OUT},
            grow: {to: 1, duration: FLIGHT, ease: EASE_OUT},
            light: {to: 1, duration: FLIGHT, ease: EASE_OUT},
            alpha: {to: 1, duration: FLIGHT, ease: EASE_OUT},
            assemble: {to: 1, duration: FLIGHT, ease: "outCubic"},
            delay: SPREAD * (1 - (1 - order) ** 2),
            onComplete: () => {
              runScoped(() => {
                animate(square, {
                  flash: {from: LANDING, to: 0},
                  duration: LANDING_TIME,
                  ease: "outQuad",
                })
              })
            },
          })
        })
      }
      settleQuiet()
    }

    const land = () => {
      if (!scape) return
      const {crown, field} = scape
      window.clearTimeout(reforming)
      stillSquares()
      released = false
      measure()
      if (field.cells.size === 0) field.advance(0, canvas.clientWidth, canvas.clientHeight)
      const squares =
        crown.squares.length > 0
          ? crown.squares
          : crown.take(canvas.clientWidth, canvas.clientHeight, quiet)
      for (const square of squares) {
        Object.assign(square, {flown: 1, grow: 1, light: 1, alpha: 1, assemble: 1, flash: 0})
      }
      settleQuiet()
    }

    let down: {id: number; x: number; y: number} | null = null
    let dragging = false

    const reform = () => {
      window.clearTimeout(reforming)
      if (crowned && released && !dragging) reforming = window.setTimeout(gather, REFORM)
    }

    const letGo = () => {
      if (!scape || !crowned || released) return
      window.clearTimeout(reforming)
      stillSquares()
      released = true
      const freed = scape.crown.letGo()
      for (const panel of freed) {
        runScoped(() => {
          animate(panel, {free: 0, duration: FREE, ease: "inOutQuad"})
        })
      }
      settleQuiet()
    }

    const steer = (steering: boolean) => {
      if (steering) letGo()
      else reform()
    }

    const pointOf = (event: PointerEvent): [number, number] => {
      const box = canvas.getBoundingClientRect()
      return [event.clientX - box.left - box.width / 2, event.clientY - box.top - box.height / 2]
    }

    const lift = () => {
      down = null
      dragging = false
      delete stage.dataset.datascapeDragging
      if (scape) scape.field.pointer = null
      reform()
    }

    const onPointerDown = (event: PointerEvent) => {
      if (down || event.button !== 0) return
      down = {id: event.pointerId, x: event.clientX, y: event.clientY}
      canvas.setPointerCapture(event.pointerId)
    }

    const onPointerMove = (event: PointerEvent) => {
      if (!scape) return
      if (down?.id === event.pointerId) {
        if (!dragging && Math.hypot(event.clientX - down.x, event.clientY - down.y) >= DRAG) {
          dragging = true
          stage.dataset.datascapeDragging = ""
          rest(null)
          closePick()
        }
        if (dragging) scape.field.pointer = pointOf(event)
        return
      }
      if (event.pointerType === "mouse") {
        const point = pointOf(event)
        rest(scape.crown.squareAt(...point) ?? scape.field.panelAt(...point))
      }
    }

    const onPointerUp = (event: PointerEvent) => {
      if (down?.id !== event.pointerId) return
      const pressed = !dragging
      lift()
      if (!pressed || !scape) return
      const point = pointOf(event)
      const square = scape.crown.squareAt(...point)
      const panel = square ? null : scape.field.panelAt(...point)
      if (square) flash(square)
      else if (panel) {
        flash(panel)
        scape.field.burst(panel, PRESS_SPARKS)
      } else {
        closePick()
        return
      }
      openPick(event.clientX, event.clientY)
    }

    const onPointerCancel = (event: PointerEvent) => {
      if (down?.id === event.pointerId) lift()
    }

    const onPointerLeave = (event: PointerEvent) => {
      if (event.pointerType === "mouse" && !down) rest(null)
    }

    const onAim = (event: PointerEvent) => {
      if (!scape || event.pointerType === "touch" || !fine.matches) return
      const across = (event.pageX - crownMiddle[0]) / (window.innerWidth / 2)
      const upDown = (event.pageY - crownMiddle[1]) / (window.innerHeight / 2)
      scape.crown.aim = [Math.max(-1, Math.min(1, across)), Math.max(-1, Math.min(1, upDown))]
    }

    const onAimAway = (event: PointerEvent) => {
      if (scape && !event.relatedTarget) scape.crown.aim = null
    }

    const setQuiet = (strength: number, duration: number) => {
      utils.remove(quiet)
      if (duration <= 0) quiet.strength = strength
      else {
        runScoped(() => {
          animate(quiet, {strength, duration, ease: EASE_OUT})
        })
      }
    }

    const resized = new ResizeObserver(measure)

    const island: CanvasIslandController = createCanvasIsland<DatascapeRenderer>(
      stage,
      {},
      {
        canvasSelector: "[data-datascape-canvas]",
        readyFlag: "datascapeReady",
        browserLoad: async (canvasEl, size, onDeviceLost) => {
          const {createDatascapeRenderer} = await import("../datascape/renderer")
          return createDatascapeRenderer(
            canvasEl,
            size,
            onDeviceLost,
            {open, draw, leave, rest, steer},
            quiet,
          )
        },
        motionSensitive: true,
        continuous: true,
        interact(ctrl) {
          ctrl.onReady(() => {
            scape = ctrl.renderer()
            rested = null
            released = false
            quietAim = -1
            measure()
            if (crowned) land()
          })
          resized.observe(stage)
          resized.observe(words)
          resized.observe(crownSlot)
          canvas.addEventListener("pointerdown", onPointerDown)
          canvas.addEventListener("pointermove", onPointerMove)
          canvas.addEventListener("pointerup", onPointerUp)
          canvas.addEventListener("pointercancel", onPointerCancel)
          canvas.addEventListener("pointerleave", onPointerLeave)
          window.addEventListener("pointermove", onAim, {passive: true})
          document.addEventListener("pointerout", onAimAway, {passive: true})
          return () => {
            scape = undefined
            rested = null
            lift()
            window.clearTimeout(reforming)
            canvas.style.cursor = ""
            resized.disconnect()
            canvas.removeEventListener("pointerdown", onPointerDown)
            canvas.removeEventListener("pointermove", onPointerMove)
            canvas.removeEventListener("pointerup", onPointerUp)
            canvas.removeEventListener("pointercancel", onPointerCancel)
            canvas.removeEventListener("pointerleave", onPointerLeave)
            window.removeEventListener("pointermove", onAim)
            document.removeEventListener("pointerout", onAimAway)
          }
        },
      },
    )
    island.mount()

    // Open mode choreography.
    let opener = 0
    const closed = () => docRoot.dataset.hero === "closed"
    const openHero = ({moving}: {moving: boolean}) => {
      if (!closed()) return
      window.clearTimeout(opener)
      for (const type of BEGIN) window.removeEventListener(type, onBegin, true)
      writeSession("regents:hero:opened", "yes")
      if (moving) {
        setQuiet(1, QUIETING)
        docRoot.dataset.hero = "opening"
      } else {
        setQuiet(1, 0)
        delete docRoot.dataset.hero
      }
    }
    const onBegin = () => openHero({moving: true})
    const onBarEnter = () => openHero({moving: false})

    // Crown mode choreography.
    let gatherer = 0
    const gathering = () => docRoot.dataset.hero === "gathering"
    const stopGathering = () => {
      window.clearTimeout(gatherer)
      for (const type of BEGIN) window.removeEventListener(type, onGatherBegin, true)
    }
    const onGatherBegin = () => {
      stopGathering()
      writeSession("regents:hero:crowned", "yes")
      crowned = true
      land()
      delete docRoot.dataset.hero
    }
    const gatherCrown = () => {
      writeSession("regents:hero:crowned", "yes")
      crowned = true
      gather()
      gatherer = window.setTimeout(() => {
        if (gathering()) docRoot.dataset.hero = "opening"
      }, WORDS_AFTER)
    }

    const onActionsTransitionEnd = (event: TransitionEvent) => {
      if (
        event.target !== actions ||
        event.propertyName !== "opacity" ||
        docRoot.dataset.hero !== "opening"
      ) {
        return
      }
      delete docRoot.dataset.hero
      stopGathering()
    }
    actions.addEventListener("transitionend", onActionsTransitionEnd)

    const onReady = () => {
      if (!closed()) return
      window.clearTimeout(opener)
      if (stage.dataset.datascapeReady === "true") {
        opener = window.setTimeout(onBegin, OPEN_AFTER)
      }
      if (stage.dataset.datascapeReady === "false") {
        openHero({moving: false})
      }
    }

    const onGatherReady = () => {
      if (!gathering()) return
      window.clearTimeout(gatherer)
      if (stage.dataset.datascapeReady === "true") {
        gatherer = window.setTimeout(gatherCrown, GATHER_AFTER)
      }
      if (stage.dataset.datascapeReady === "false") {
        stopGathering()
        delete docRoot.dataset.hero
      }
    }

    const readyObserver = new MutationObserver(() => {
      onReady()
      onGatherReady()
    })
    readyObserver.observe(stage, {attributes: true, attributeFilter: ["data-datascape-ready"]})

    if (closed()) {
      for (const type of BEGIN) window.addEventListener(type, onBegin, {capture: true, passive: true})
      bar.addEventListener("pointerenter", onBarEnter, {passive: true})
      onReady()
    } else {
      setQuiet(1, 0)
    }

    if (gathering()) {
      for (const type of BEGIN) {
        window.addEventListener(type, onGatherBegin, {capture: true, passive: true})
      }
      onGatherReady()
    } else if (mode === "crown") {
      crowned = true
      land()
    }

    this.cleanup = () => {
      window.clearTimeout(opener)
      window.clearTimeout(gatherer)
      window.clearTimeout(reforming)
      for (const type of BEGIN) {
        window.removeEventListener(type, onBegin, true)
        window.removeEventListener(type, onGatherBegin, true)
      }
      bar.removeEventListener("pointerenter", onBarEnter)
      readyObserver.disconnect()
      actions.removeEventListener("transitionend", onActionsTransitionEnd)
      pick.removeEventListener("keydown", onPickKeydown)
      pick.removeEventListener("focusout", onPickFocusOut)
      document.removeEventListener("pointerdown", onDocPointerDown, true)
      window.removeEventListener("scroll", closePick)
      window.removeEventListener("resize", closePick)
      island.destroy()
      scope.revert()
      delete docRoot.dataset.hero
    }
  },

  destroyed(this: DatascapeHeroHook) {
    this.cleanup?.()
    this.cleanup = undefined
  },
}
