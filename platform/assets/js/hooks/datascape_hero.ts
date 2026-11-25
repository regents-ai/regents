/**
 * LiveView hook for the Regents home hero Datascape (`vgpu` island + Anime.js v4).
 *
 * Uses `createCanvasIsland` from `canvas_island.ts` so device-loss recovery,
 * tab visibility, IntersectionObserver pausing, DPR/pixel budgets, and reduced
 * motion still-face fallback stay in one place. Every Anime.js animation runs
 * inside a `createScope` reverted cleanly on `destroyed()`.
 *
 * Interactive behavior:
 * - Cursor movement steers smoothly across the infinite Datascape canvas (with
 *   lenient, faster acceleration near the viewport edges).
 * - Before the first click (in default `open`/`canvas` mode), the center hero
 *   area starts hidden so visitors can explore the Datascape freely; the first
 *   click anywhere on the hero canvas reveals the center hero area.
 * - Subsequent clicks animate the clicked shape out and animate a fresh random
 *   shape in (never opening a product picker menu).
 * - `?hero=crown` preserves the crown-gathering choreography, with clicks
 *   morphing crown squares or field shapes in place.
 */
import {animate, createScope, cubicBezier, utils, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {MARK_HEIGHT, MARK_WIDTH, type Square} from "../datascape/crown"
import {calmAround, REST, type Cell, type Panel, type Tube} from "../datascape/field"
import type {DatascapeRenderer, Quiet} from "../datascape/renderer"
import {randomCrownStyle, randomPanelSeed} from "../datascape/world"
import type {Hook} from "../hook_composition"

const OPENING = 680
const ENTRANCE_EXTRA = 200
const MORPH_OUT = 260
const MORPH_IN = 580 + ENTRANCE_EXTRA
const ASSEMBLY = 2200
const FLASH = 0.55
const STAGGER = 500
const FIRST_WAVE = 900
const TUBE_SPEED = 1300
const REACTION = 320
const LARGE = 8
const OPENING_SPARKS = 3
const PRESS_SPARKS = 14
const MORPH_IN_SPARKS = 9
const NEAREST_CLICK_RADIUS = 180

const LEAVING = 16
const ROOM = 24
const SOFT = 140
const BAND_ROOM = 12
const BAND_SOFT = 72
const DRAG = 6
const MAX_OPEN_CALM_X = 0.42
const MAX_OPEN_CALM_Y = 0.36

const FLIGHT = 560
const SPREAD = 420
const LANDING = 0.3
const LANDING_TIME = 420
const ARRIVAL = [10, 9, 11, 8, 12, 5, 4, 6, 3, 7, 1, 0, 2]
const CROWN_QUIET = 600
const REFORM = 1400
const FREE = 1200

const QUIETING = 700
const GATHER_AFTER = 800
const WORDS_AFTER = 450
const GATHER_BEGIN = ["pointerdown", "keydown", "wheel", "touchstart", "scroll"] as const

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

function isInteractiveTarget(target: EventTarget | null, heroEl: HTMLElement): boolean {
  if (!(target instanceof Element)) return false
  if (target.closest("a, button, input, select, textarea, summary, [role='button'], [role='menuitem'], dialog")) {
    return true
  }
  if (!heroEl.contains(target)) return true
  return false
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

    if (!stage || !canvas || !words || !actions || !crownSlot || !bar) return

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
    const fine = window.matchMedia("(hover: hover) and (pointer: fine)")

    const explicitHero = new URLSearchParams(window.location.search).has("hero")
    const mode = docRoot.dataset.heroMode ?? "open"

    // Start with the center hero area hidden until the first click (except
    // reduced-motion users or `?hero=crown`).
    if (!reduced.matches) {
      if (mode === "crown") {
        if (explicitHero || readSession("regents:hero:crowned") !== "yes") {
          docRoot.dataset.hero = "gathering"
        } else {
          delete docRoot.dataset.hero
        }
      } else {
        docRoot.dataset.hero = "closed"
      }
    } else {
      delete docRoot.dataset.hero
    }

    // Scoped Anime.js instance so every panel/tube/crown animation reverts cleanly on destroy.
    const scope: Scope = createScope({root: heroEl})
    const runScoped = (fn: () => void) => {
      scope.add(fn)
    }

    let scape: DatascapeRenderer | undefined
    let rested: Hoverable | null = null
    const morphingPanels = new WeakSet<Panel>()
    const morphingSquares = new WeakSet<Square>()

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
    const stillArea = {left: 0, right: 0, top: 0, bottom: 0}

    const inStillArea = ({pageX, pageY}: PointerEvent) =>
      pageX >= stillArea.left && pageX <= stillArea.right &&
      pageY >= stillArea.top && pageY < stillArea.bottom

    const closed = () => docRoot.dataset.hero === "closed"

    const wait = (distance: number, seed: number) =>
      scape && scape.field.time === 0 ? distance * FIRST_WAVE + seed * STAGGER : 0

    const open = (panel: Panel, distance: number) => {
      const large = panel.w > LARGE
      runScoped(() => {
        animate(panel, {
          grow: {
            to: 1,
            duration: (large ? OPENING : OPENING / 2) + ENTRANCE_EXTRA,
            ease: large ? "outBack(1.6)" : "outExpo",
          },
          flash: {from: large ? FLASH : 0, to: 0, duration: OPENING + ENTRANCE_EXTRA, ease: "outQuad"},
          assemble: {to: 1, duration: ASSEMBLY + ENTRANCE_EXTRA, ease: "outCubic"},
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
          duration: (tube.length / TUBE_SPEED) * 1000 + ENTRANCE_EXTRA,
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
      heroEl.style.cursor = target ? "pointer" : ""
    }

    const flash = (target: Panel | Square) => {
      runScoped(() => {
        animate(target, {
          flash: {from: 0.85, to: 0, duration: OPENING, ease: "outQuad"},
          assemble: {from: 0, to: 1, duration: ASSEMBLY / 2, ease: "outCubic"},
        })
      })
    }

    const animatePanelIn = (panel: Panel, onDone?: () => void) => {
      runScoped(() => {
        animate(panel, {
          grow: {from: 0, to: 1, duration: MORPH_IN, ease: "outBack(1.6)"},
          flash: {from: 0.68, to: 0, duration: MORPH_IN, ease: "outQuad"},
          assemble: {from: 0, to: 1, duration: ASSEMBLY * 0.6, ease: "outCubic"},
          onBegin: () => {
            scape?.field.burst(panel, MORPH_IN_SPARKS)
          },
          onComplete: () => {
            onDone?.()
          },
        })
      })
    }

    const morphPanel = (panel: Panel) => {
      if (!scape || morphingPanels.has(panel)) return
      morphingPanels.add(panel)
      if (rested === panel) rest(null)
      scape.field.burst(panel, PRESS_SPARKS)
      utils.remove(panel)
      runScoped(() => {
        animate(panel, {
          grow: {to: 0, duration: MORPH_OUT, ease: "inBack(1.8)"},
          flash: {from: 0.78, to: 0, duration: MORPH_OUT, ease: "outQuad"},
          assemble: {to: 0, duration: MORPH_OUT, ease: "inQuad"},
          hover: {to: 0, duration: MORPH_OUT / 2, ease: "outQuad"},
          onComplete: () => {
            if (!scape || !scape.field.hasPanel(panel)) {
              morphingPanels.delete(panel)
              return
            }
            const next = randomPanelSeed(panel.x, panel.y, panel.kind)
            scape.field.replacePanel(panel, next)
            panel.grow = 0
            panel.assemble = 0
            panel.hover = 0
            animatePanelIn(panel, () => {
              morphingPanels.delete(panel)
            })
          },
        })
      })
    }

    const morphSquare = (square: Square) => {
      if (!scape || morphingSquares.has(square)) return
      morphingSquares.add(square)
      if (rested === square) rest(null)
      utils.remove(square)
      runScoped(() => {
        animate(square, {
          grow: {to: 0, duration: MORPH_OUT, ease: "inBack(1.8)"},
          flash: {from: 0.75, to: 0, duration: MORPH_OUT, ease: "outQuad"},
          assemble: {to: 0, duration: MORPH_OUT, ease: "inQuad"},
          hover: {to: 0, duration: MORPH_OUT / 2, ease: "outQuad"},
          onComplete: () => {
            if (!scape || !scape.crown.squares.includes(square)) {
              morphingSquares.delete(square)
              return
            }
            const next = randomCrownStyle(square.kind)
            square.kind = next.kind
            square.seed = next.seed
            square.a = next.a
            square.b = next.b
            square.entrance = next.entrance
            square.grow = 0
            square.assemble = 0
            square.hover = 0
            runScoped(() => {
              animate(square, {
                grow: {from: 0, to: 1, duration: MORPH_IN, ease: "outBack(1.6)"},
                flash: {from: 0.65, to: 0, duration: MORPH_IN, ease: "outQuad"},
                assemble: {from: 0, to: 1, duration: ASSEMBLY * 0.6, ease: "outCubic"},
                onComplete: () => {
                  morphingSquares.delete(square)
                },
              })
            })
          },
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

    const syncCalm = () => {
      if (!scape) return
      if (closed()) {
        scape.field.calm = [REST, REST]
        return
      }
      const box = canvas.getBoundingClientRect()
      const wordsBox = words.getBoundingClientRect()
      const [cx, cy] = calmAround([wordsBox.width, wordsBox.height], LEAVING, [box.width, box.height])
      scape.field.calm = [Math.min(MAX_OPEN_CALM_X, cx), Math.min(MAX_OPEN_CALM_Y, cy)]
    }

    const measure = () => {
      const box = canvas.getBoundingClientRect()
      const wordsBox = words.getBoundingClientRect()
      stillArea.left = wordsBox.left + window.scrollX
      stillArea.right = wordsBox.right + window.scrollX
      stillArea.top = box.top + window.scrollY
      stillArea.bottom = wordsBox.top + window.scrollY
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
      syncCalm()
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

    const lift = (clearPointer = false) => {
      down = null
      dragging = false
      delete stage.dataset.datascapeDragging
      if (clearPointer && scape) scape.field.pointer = null
      reform()
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

    let openSettle = 0

    const openHero = ({moving}: {moving: boolean}) => {
      if (!closed()) return
      window.clearTimeout(openSettle)
      if (moving) {
        setQuiet(1, QUIETING)
        docRoot.dataset.hero = "opening"
        openSettle = window.setTimeout(() => {
          if (docRoot.dataset.hero === "opening") {
            delete docRoot.dataset.hero
            syncCalm()
          }
        }, 1000)
      } else {
        setQuiet(1, 0)
        delete docRoot.dataset.hero
      }
      syncCalm()
    }

    const onPointerDown = (event: PointerEvent) => {
      if (down || event.button !== 0) return
      if (isInteractiveTarget(event.target, heroEl)) return
      down = {id: event.pointerId, x: event.clientX, y: event.clientY}
    }

    const onPointerMove = (event: PointerEvent) => {
      if (!scape) return
      if (down?.id === event.pointerId) {
        if (!dragging && Math.hypot(event.clientX - down.x, event.clientY - down.y) >= DRAG) {
          dragging = true
          stage.dataset.datascapeDragging = ""
          rest(null)
        }
        if (dragging) {
          scape.field.cameraHeld = false
          scape.field.pointer = pointOf(event)
        }
        return
      }
      if (event.pointerType === "mouse") {
        scape.field.cameraHeld = inStillArea(event)
        // Pause steering when interacting with the top nav bar or an open modal dialog.
        if (
          scape.field.cameraHeld ||
          (event.target instanceof Element &&
            (event.target.closest("[data-bar]") || document.querySelector("dialog[open]")))
        ) {
          scape.field.pointer = null
          rest(null)
          return
        }
        const point = pointOf(event)
        scape.field.pointer = point
        if (isInteractiveTarget(event.target, heroEl)) {
          rest(null)
        } else {
          rest(scape.crown.squareAt(...point) ?? scape.field.panelAt(...point))
        }
      }
    }

    const onPointerUp = (event: PointerEvent) => {
      if (down?.id !== event.pointerId) return
      const pressed = !dragging
      lift(event.pointerType !== "mouse")
      if (!pressed || !scape) return
      if (isInteractiveTarget(event.target, heroEl)) return

      const point = pointOf(event)

      // 1. First click reveals the center of the hero area.
      if (closed()) {
        const panel = scape.field.panelAt(...point)
        if (panel) {
          flash(panel)
          scape.field.burst(panel, PRESS_SPARKS)
        }
        openHero({moving: true})
        return
      }

      // 2. Subsequent clicks animate the clicked shape out and a new random shape in.
      const square = scape.crown.squareAt(...point)
      if (square) {
        morphSquare(square)
        return
      }
      const panel = scape.field.panelAt(...point) ?? scape.field.nearestPanel(...point, NEAREST_CLICK_RADIUS)
      if (panel) {
        morphPanel(panel)
        return
      }
      const spawned = scape.field.spawnPanelAt(...point, (wx, wy) => randomPanelSeed(wx, wy))
      if (spawned) animatePanelIn(spawned)
    }

    const onPointerCancel = (event: PointerEvent) => {
      if (down?.id === event.pointerId) lift(true)
    }

    const onPointerLeave = (event: PointerEvent) => {
      if (event.pointerType === "mouse") {
        if (scape) {
          scape.field.cameraHeld = false
          scape.field.pointer = null
        }
        if (!down) rest(null)
      }
    }

    const onKeydown = (event: KeyboardEvent) => {
      if (!closed()) return
      if (event.key !== "Enter" && event.key !== " ") return
      if (event.target instanceof Element && event.target.closest("a, button, input, select, textarea, dialog")) {
        return
      }
      openHero({moving: true})
    }

    const onAim = (event: PointerEvent) => {
      if (!scape || event.pointerType === "touch" || !fine.matches) return
      if (inStillArea(event)) {
        scape.crown.aim = null
        return
      }
      const across = (event.pageX - crownMiddle[0]) / (window.innerWidth / 2)
      const upDown = (event.pageY - crownMiddle[1]) / (window.innerHeight / 2)
      scape.crown.aim = [Math.max(-1, Math.min(1, across)), Math.max(-1, Math.min(1, upDown))]
    }

    const onAimAway = (event: PointerEvent) => {
      if (scape && !event.relatedTarget) {
        scape.crown.aim = null
        scape.field.pointer = null
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
          heroEl.addEventListener("pointerdown", onPointerDown)
          heroEl.addEventListener("pointermove", onPointerMove)
          window.addEventListener("pointerup", onPointerUp)
          window.addEventListener("pointercancel", onPointerCancel)
          heroEl.addEventListener("pointerleave", onPointerLeave)
          window.addEventListener("pointermove", onAim, {passive: true})
          document.addEventListener("pointerout", onAimAway, {passive: true})
          window.addEventListener("keydown", onKeydown)
          return () => {
            scape = undefined
            rested = null
            lift(true)
            window.clearTimeout(reforming)
            heroEl.style.cursor = ""
            resized.disconnect()
            heroEl.removeEventListener("pointerdown", onPointerDown)
            heroEl.removeEventListener("pointermove", onPointerMove)
            window.removeEventListener("pointerup", onPointerUp)
            window.removeEventListener("pointercancel", onPointerCancel)
            heroEl.removeEventListener("pointerleave", onPointerLeave)
            window.removeEventListener("pointermove", onAim)
            document.removeEventListener("pointerout", onAimAway)
            window.removeEventListener("keydown", onKeydown)
          }
        },
      },
    )
    island.mount()

    // Crown mode choreography (`?hero=crown`).
    let gatherer = 0
    const gathering = () => docRoot.dataset.hero === "gathering"
    const stopGathering = () => {
      window.clearTimeout(gatherer)
      for (const type of GATHER_BEGIN) window.removeEventListener(type, onGatherBegin, true)
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
      syncCalm()
    }
    actions.addEventListener("transitionend", onActionsTransitionEnd)

    const onReady = () => {
      if (!closed()) return
      // Only fall back to immediately showing the center hero when live WebGPU is unavailable.
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
      onReady()
    } else {
      setQuiet(1, 0)
    }

    if (gathering()) {
      for (const type of GATHER_BEGIN) {
        window.addEventListener(type, onGatherBegin, {capture: true, passive: true})
      }
      onGatherReady()
    } else if (mode === "crown") {
      crowned = true
      land()
    }

    this.cleanup = () => {
      window.clearTimeout(openSettle)
      window.clearTimeout(gatherer)
      window.clearTimeout(reforming)
      for (const type of GATHER_BEGIN) {
        window.removeEventListener(type, onGatherBegin, true)
      }
      readyObserver.disconnect()
      actions.removeEventListener("transitionend", onActionsTransitionEnd)
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
