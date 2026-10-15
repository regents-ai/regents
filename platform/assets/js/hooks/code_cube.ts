import {animate, createAnimatable, createScope, type AnimatableObject, type Scope} from "animejs"

import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
} from "../canvas_island"
import type {CodeCubeRenderer, CodeCubeView} from "../code_cube/renderer"
import {aboutAxis, faceAt, multiply, normalize, type Quat} from "../world_cube/view"

/** Camera distances from the cube's centre, at rest and drawn close: the world cube's own. */
const REST = 8.4
const NEAR = 7.2
/** Tangent of half the field of view, as the world cube has it outside its rooms. */
const LENS = Math.tan((15 * Math.PI) / 180)
/** Narrower than this and the cube steps back so its corners stay on the canvas. */
const FITTED_ASPECT = 0.92

/** The slow turn the cube keeps while nobody is holding it, against the world cube's. */
const TUMBLE_SPEED = -0.21
const TUMBLE_LEAN = 0.8
const TUMBLE_SWAY = 0.15
/** Radians the cube turns for each pixel it is dragged. */
const DRAG_TURN = 0.0085
/** A press that travels less than this is a click, not a drag. */
const CLICK_SLOP = 6
/** How long the pointer rests on a face before the cube comes closer. */
const REST_MS = 240
/** The fastest the cube may be left spinning by a flick, in radians a second. */
const COAST_LIMIT = 5

const clamp = (speed: number) => Math.max(-COAST_LIMIT, Math.min(COAST_LIMIT, speed))

/**
 * The code cube: the world cube's twin, whose six faces are screens of falling
 * code, one for each site whose browser tools it lists and one for siwa-server.
 *
 * It turns by itself until it is pressed, and under a drag while it is held. A
 * pointer resting on a face lights it, brings the cube closer and names the
 * face's site; a click on a face presses that face's button, the one the
 * server rendered, which opens its card. Without WebGPU, or for a visitor who
 * asked for less motion, none of this runs and the six buttons are the cube.
 */
export const createCodeCubeController = (
  root: HTMLElement,
  options: CanvasIslandOptions<CodeCubeRenderer> = {},
): CanvasIslandController => {
  // What Anime.js eases. The frame loop reads these and nothing else moves them.
  const camera = {approach: 0, spin: 1, glow: 0}
  let steer: AnimatableObject | undefined

  let rotation: Quat = normalize(multiply(aboutAxis([1, 0, 0], 0.42), aboutAxis([0, 1, 0], 0.62)))
  let hover = -1
  let named = -1
  let pointing = false
  let rested = false
  let pointer: [number, number] | undefined
  let movedAt = 0
  let press: {x: number; y: number; at: number; id: number} | undefined
  let dragging = false
  let coast: [number, number] = [0, 0]
  let time = 0
  let last = performance.now()
  let aspect = 1
  // How large the page wants the cube, against the most its canvas fits, read with each new shape.
  let size = 1
  let measured = 0
  let scope: Scope | undefined

  // Drawn in the middle of its own canvas.
  const view: CodeCubeView = {rotation, distance: REST, lens: LENS, shift: 0, hover, glow: 0, time}

  const turnBy = (dx: number, dy: number) => {
    rotation = normalize(
      multiply(aboutAxis([0, 1, 0], dx), multiply(aboutAxis([1, 0, 0], dy), rotation)),
    )
  }

  const caption = () => root.querySelector<HTMLElement>("[data-code-caption]")
  const button = (face: number) => root.querySelector<HTMLButtonElement>(`[data-code-face="${face}"]`)

  // The caption names the site under the pointer, and keeps the last one as it fades.
  const name = (face: number) => {
    if (face === named) return
    named = face
    scope?.methods.caption!(face >= 0 ? button(face)!.dataset.codeName! : null)
  }

  /** One frame of the camera: the cube's turn, the pointer's rest, the eased values. */
  const nextView = (): CodeCubeView => {
    const now = performance.now()
    const dt = Math.min(0.05, (now - last) / 1000)
    last = now
    time += dt

    if (!press) {
      const lean = TUMBLE_LEAN * Math.sin(time * TUMBLE_SWAY)
      rotation = normalize(
        multiply(aboutAxis([lean, 1, -0.2], TUMBLE_SPEED * camera.spin * dt), rotation),
      )
      turnBy(coast[0] * dt, coast[1] * dt)
      const drag = Math.exp(-dt * 3)
      coast = [coast[0] * drag, coast[1] * drag]
    }

    const fit = Math.max(1, FITTED_ASPECT / aspect)
    view.rotation = rotation
    view.distance = ((REST + (NEAR - REST) * camera.approach) * fit) / size
    view.time = time
    view.glow = camera.glow

    // The cube turns under a still pointer, so the face beneath it is read every frame.
    hover = pointer ? faceAt(view, aspect, pointer[0], pointer[1]) : -1
    // Pointer capture keeps a drag going beyond the cube: name its front face there.
    if (dragging && hover < 0) hover = faceAt(view, aspect, 0.5, 0.5)
    if (hover >= 0 && !rested && (dragging || now - movedAt > REST_MS)) {
      rested = true
      steer?.approach!(1).glow!(1).spin!(0.25)
    } else if (hover < 0 && rested) {
      rested = false
      steer?.approach!(0).glow!(0).spin!(1)
    }
    view.hover = hover
    if (rested) name(hover)
    else name(-1)

    // The page hears when the pointer comes onto the cube and when it leaves it.
    if (hover >= 0 !== pointing) {
      pointing = hover >= 0
      root.dispatchEvent(new CustomEvent("cube:pointing", {bubbles: true, detail: {pointing}}))
    }
    return view
  }

  const browserLoad: LoadRenderer<CodeCubeRenderer> = async (canvas, size, onDeviceLost) => {
    const {createCodeCubeRenderer} = await import("../code_cube/renderer")
    return createCodeCubeRenderer(canvas, size, onDeviceLost, nextView)
  }

  return createCanvasIsland(root, options, {
    canvasSelector: "[data-code-canvas]",
    readyFlag: "codeReady",
    browserLoad,
    motionSensitive: true,
    continuous: true,
    interact({root: cube, canvas, renderer, onReady}) {
      const ready = () => cube.dataset.codeReady === "true"
      const within = (event: PointerEvent): [number, number] => {
        const {left, top, width, height} = canvas().getBoundingClientRect()
        return [(event.clientX - left) / width, (event.clientY - top) / height]
      }

      scope = createScope({root: cube})
      scope.add(() => {
        steer = createAnimatable(camera, {
          approach: {duration: 700, ease: "outCubic"},
          spin: {duration: 900, ease: "outCubic"},
          glow: {duration: 500, ease: "outCubic"},
        })
        scope!.add("caption", (site: string | null) => {
          const line = caption()!
          if (site !== null) line.textContent = site
          animate(line, {
            opacity: site === null ? 0 : 1,
            translateY: site === null ? 6 : 0,
            duration: 260,
            ease: "outCubic",
          })
        })
      })

      // A renderer that lands, first or after a lost device, finds the cube at rest.
      onReady(() => {
        steer!.approach!(0).spin!(1).glow!(0)
        rested = false
        dragging = false
        press = undefined
        last = performance.now()
        measured = 0
        const current = renderer()
        if (!current) return
        const draw = current.present.bind(current)
        current.present = () => {
          aspect = current.aspect()
          if (aspect !== measured) {
            measured = aspect
            size = Number(getComputedStyle(cube).getPropertyValue("--code-cube-size"))
          }
          draw()
        }
      })

      const onPointerDown = (event: PointerEvent) => {
        if (!ready() || event.button !== 0) return
        press = {x: event.clientX, y: event.clientY, at: performance.now(), id: event.pointerId}
        canvas().setPointerCapture(event.pointerId)
      }

      const onPointerMove = (event: PointerEvent) => {
        if (!ready()) return
        pointer = within(event)
        movedAt = performance.now()
        if (!press || press.id !== event.pointerId) return
        const dx = event.clientX - press.x
        const dy = event.clientY - press.y
        if (!dragging) {
          if (Math.hypot(dx, dy) < CLICK_SLOP) return
          // Keep the close view and face name throughout the drag.
          dragging = true
          rested = true
          steer!.approach!(1).glow!(1).spin!(0.25)
        }
        turnBy(dx * DRAG_TURN, dy * DRAG_TURN)
        // The cube keeps the speed it was let go at, and slows from there.
        const perSecond = (DRAG_TURN * 1000) / Math.max(8, movedAt - press.at)
        coast = [clamp(dx * perSecond), clamp(dy * perSecond)]
        press = {x: event.clientX, y: event.clientY, at: movedAt, id: event.pointerId}
      }

      const onPointerUp = (event: PointerEvent) => {
        if (!press || press.id !== event.pointerId) return
        press = undefined
        movedAt = performance.now()
        if (dragging) {
          dragging = false
          return
        }
        if (!ready()) return
        const target = faceAt(view, aspect, ...within(event))
        if (target >= 0) button(target)?.click()
      }

      const onPointerCancel = () => {
        press = undefined
        dragging = false
        pointer = undefined
      }

      const onPointerLeave = () => {
        pointer = undefined
      }

      const surface = canvas()
      surface.addEventListener("pointerdown", onPointerDown)
      surface.addEventListener("pointermove", onPointerMove, {passive: true})
      surface.addEventListener("pointerup", onPointerUp)
      surface.addEventListener("pointercancel", onPointerCancel)
      surface.addEventListener("pointerleave", onPointerLeave, {passive: true})

      return () => {
        surface.removeEventListener("pointerdown", onPointerDown)
        surface.removeEventListener("pointermove", onPointerMove)
        surface.removeEventListener("pointerup", onPointerUp)
        surface.removeEventListener("pointercancel", onPointerCancel)
        surface.removeEventListener("pointerleave", onPointerLeave)
        scope?.revert()
        scope = undefined
        steer = undefined
        named = -1
      }
    },
  })
}

type CodeCubeHook = {
  el: HTMLElement
  controller?: CanvasIslandController
}

export const CodeCube = {
  mounted(this: CodeCubeHook) {
    this.controller = createCodeCubeController(this.el)
    this.controller.mount()
  },
  disconnected(this: CodeCubeHook) {
    this.controller?.pause()
  },
  reconnected(this: CodeCubeHook) {
    this.controller?.resume()
  },
  destroyed(this: CodeCubeHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
