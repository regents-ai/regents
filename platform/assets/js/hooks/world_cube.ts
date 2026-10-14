import {
  animate,
  createAnimatable,
  createScope,
  spring,
  utils,
  type AnimatableObject,
  type JSAnimation,
  type Scope,
} from "animejs"

import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
} from "../canvas_island"
import type {WorldCubeRenderer} from "../world_cube/renderer"
import {
  FACE_ON,
  aboutAxis,
  faceAt,
  multiply,
  normalize,
  slerp,
  type Quat,
  type WorldCubeView,
} from "../world_cube/view"

/** Camera distances from the cube's centre: at rest, drawn close, and inside a room. */
const REST = 8.4
const NEAR = 7.2
const INSIDE = 0.9
/** Tangent of half the field of view: narrow on the cube, wide inside a room. */
const LENS_OUT = Math.tan((15 * Math.PI) / 180)
const LENS_IN = Math.tan((34 * Math.PI) / 180)
/** Narrower than this and the cube steps back so its corners stay on the canvas. */
const FITTED_ASPECT = 0.92

/** The slow turn the cube keeps while nobody is holding it, in radians a second. */
const TUMBLE_SPEED = 0.24
/** How far the turn leans over, and how slowly it sways there, so every face comes round. */
const TUMBLE_LEAN = 0.85
const TUMBLE_SWAY = 0.17
/** Radians the cube turns for each pixel it is dragged. */
const DRAG_TURN = 0.0085
/** A press that travels less than this is a click, not a drag. */
const CLICK_SLOP = 6
/** How long the pointer rests on a face before the cube comes closer. */
const REST_MS = 240
/** How far the visitor's head turns inside a room, side to side and up and down. */
const LOOK: [number, number] = [0.32, 0.16]
/** How far the look must turn, of its full reach, before a pane shows, and how far back before it goes. */
const PANE_SHOW = 0.45
const PANE_HIDE = 0.3
/** How long the visitor keeps looking up before the middle pane shows. */
const HOLD_MS = 450
/** No pane is showing. */
const NO_PANE = -1

/** The fastest the cube may be left spinning by a flick, in radians a second. */
const COAST_LIMIT = 5

type Mode = "orbit" | "entering" | "inside" | "leaving"

const clamp = (speed: number) => Math.max(-COAST_LIMIT, Math.min(COAST_LIMIT, speed))

/**
 * The world cube: a turning cube whose six faces are windows onto six rooms.
 *
 * It turns by itself until it is pressed, and under a drag while it is held. It
 * keeps turning as it comes closer for a pointer resting on a face, and flies
 * through the face that is clicked. Inside, the pointer looks
 * around the room and the room's card offers its link throughout. One of the
 * room's three panes of glass shows at a time: the first for a look to the
 * left, the last for a look to the right, the middle one for a look up that is
 * held. A touch looks where it lands and stays there. The leave button or
 * Escape flies back out. Without WebGPU, or for a visitor who asked for less
 * motion, none of this runs and the six worlds stay the plain list the server
 * rendered.
 */
export const createWorldCubeController = (
  root: HTMLElement,
  options: CanvasIslandOptions<WorldCubeRenderer> = {},
): CanvasIslandController => {
  // What Anime.js eases. The frame loop reads these and nothing else moves them.
  const camera = {approach: 0, zoom: 0, turn: 1, spin: 1, glow: 0}
  // How close the cube is drawn, how fast it turns by itself and how brightly the
  // face under the pointer is lit: steered many times a visit, so one easing each.
  let steer: AnimatableObject | undefined
  // The flight into a room or back out of it.
  let flight: JSAnimation[] = []
  // Which of the room's panes of glass is showing, and since when the look has been up.
  let shown = NO_PANE
  let lookingUp = false
  let upSince = 0
  // Where the visitor's look was last written for the panes to lean with.
  let leaned: [number, number] = [0, 0]

  let mode: Mode = "orbit"
  let rotation: Quat = normalize(multiply(aboutAxis([1, 0, 0], 0.42), aboutAxis([0, 1, 0], -0.62)))
  let from: Quat = rotation
  let to: Quat = rotation
  let face = 4
  let hover = -1
  let rested = false
  let pointer: [number, number] | undefined
  let movedAt = 0
  let press: {x: number; y: number; at: number; id: number} | undefined
  let dragging = false
  let coast: [number, number] = [0, 0]
  let look: [number, number] = [0, 0]
  let lookTarget: [number, number] = [0, 0]
  let time = 0
  let last = performance.now()
  let aspect = 1
  let scope: Scope | undefined

  const view: WorldCubeView = {
    rotation,
    distance: REST,
    lens: LENS_OUT,
    look: [0, 0],
    face,
    hover,
    glow: 0,
    time,
  }

  const setMode = (next: Mode) => {
    mode = next
    root.dataset.worldState = next
    root.dataset.worldFace = String(face)
  }

  const turnBy = (dx: number, dy: number) => {
    rotation = normalize(
      multiply(aboutAxis([0, 1, 0], dx), multiply(aboutAxis([1, 0, 0], dy), rotation)),
    )
  }

  /** One frame of the camera: the cube's turn, the pointer's rest, the eased values. */
  const nextView = (): WorldCubeView => {
    const now = performance.now()
    const dt = Math.min(0.05, (now - last) / 1000)
    last = now
    time += dt

    if (mode === "entering") {
      rotation = slerp(from, to, camera.turn)
    } else if (mode === "orbit" && !press) {
      const lean = TUMBLE_LEAN * Math.sin(time * TUMBLE_SWAY)
      rotation = normalize(
        multiply(aboutAxis([lean, 1, 0.2], TUMBLE_SPEED * camera.spin * dt), rotation),
      )
      turnBy(coast[0] * dt, coast[1] * dt)
      const drag = Math.exp(-dt * 3)
      coast = [coast[0] * drag, coast[1] * drag]
    }

    const fit = Math.max(1, FITTED_ASPECT / aspect)
    const outside = (REST + (NEAR - REST) * camera.approach) * fit
    view.rotation = rotation
    view.distance = outside * (INSIDE / outside) ** camera.zoom
    view.lens = LENS_OUT + (LENS_IN - LENS_OUT) * camera.zoom
    view.face = face
    view.time = time
    view.glow = camera.glow

    if (mode === "orbit") {
      // The cube turns under a still pointer, so the face beneath it is read every frame.
      hover = pointer && !dragging ? faceAt(view, aspect, pointer[0], pointer[1]) : -1
      if (hover >= 0 && !rested && now - movedAt > REST_MS) {
        rested = true
        steer?.approach!(1).glow!(1)
      } else if (hover < 0 && rested) {
        rested = false
        steer?.approach!(0).glow!(0)
      }
    }
    view.hover = hover

    const ease = 1 - Math.exp(-dt * 7)
    look = [look[0] + (lookTarget[0] - look[0]) * ease, look[1] + (lookTarget[1] - look[1]) * ease]
    view.look = [look[0] * camera.zoom, look[1] * camera.zoom]
    return view
  }

  const browserLoad: LoadRenderer<WorldCubeRenderer> = async (canvas, size, onDeviceLost) => {
    const {createWorldCubeRenderer} = await import("../world_cube/renderer")
    return createWorldCubeRenderer(canvas, size, onDeviceLost, nextView)
  }

  return createCanvasIsland(root, options, {
    canvasSelector: "[data-world-canvas]",
    readyFlag: "worldReady",
    browserLoad,
    motionSensitive: true,
    continuous: true,
    interact({root: cube, canvas, renderer, onReady}) {
      const ready = () => cube.dataset.worldReady === "true"
      const within = (event: PointerEvent): [number, number] => {
        const {left, top, width, height} = canvas().getBoundingClientRect()
        return [(event.clientX - left) / width, (event.clientY - top) / height]
      }

      const panesOf = (room: number) =>
        cube.querySelectorAll<HTMLElement>(`[data-room="${room}"] [data-world-glass]`)

      scope = createScope({root: cube})
      const moves = scope
      moves.add(() => {
        steer = createAnimatable(camera, {
          approach: {duration: 700, ease: "outCubic"},
          spin: {duration: 900, ease: "outCubic"},
          glow: {duration: 500, ease: "outCubic"},
        })
        moves.add("enter", () => {
          for (const move of flight) move.cancel()
          steer!.spin!(0).glow!(0)
          flight = [
            animate(camera, {turn: [0, 1], duration: 800, ease: "inOutCubic"}),
            animate(camera, {
              zoom: 1,
              duration: 1600,
              ease: "inOutCubic",
              onComplete: () => setMode("inside"),
            }),
          ]
        })
        // One pane shows at a time: the one leaving fades back as the next swings in.
        moves.add("show", (next: number) => {
          const glass = panesOf(face)
          const leaving = glass[shown]
          const arriving = glass[next]
          shown = next
          if (leaving) animate(leaving, {"--world-glass": 0, duration: 260, ease: "inCubic"})
          if (arriving) {
            animate(arriving, {"--world-glass": 1, ease: spring({bounce: 0.3, duration: 520})})
          }
        })
        moves.add("leave", () => {
          for (const move of flight) move.cancel()
          steer!.approach!(0)
          flight = [
            animate(camera, {
              zoom: 0,
              duration: 1300,
              ease: "inOutCubic",
              onComplete: () => {
                setMode("orbit")
                steer!.spin!(1)
              },
            }),
          ]
        })
      })

      const enter = (target: number) => {
        face = target
        from = rotation
        to = FACE_ON[target]!
        hover = -1
        rested = false
        coast = [0, 0]
        lookTarget = [0, 0]
        // A room is entered with none of its panes showing.
        utils.set(panesOf(target), {"--world-glass": 0})
        shown = NO_PANE
        lookingUp = false
        setMode("entering")
        moves.methods.enter!()
      }

      const leave = () => {
        if (mode !== "inside" && mode !== "entering") return
        // Wherever the turn had got to is where the cube is left.
        from = rotation
        to = rotation
        lookTarget = [0, 0]
        moves.methods.show!(NO_PANE)
        setMode("leaving")
        moves.methods.leave!()
      }

      // The pane for where the visitor is looking: left, right, or up once that look
      // has been held. A pane already showing stays until the look is well clear of it.
      const gaze = (x: number, y: number) => {
        if (mode !== "inside") return
        const past = (showing: boolean) => (showing ? PANE_HIDE : PANE_SHOW)
        const now = performance.now()
        const up = y > past(lookingUp)
        if (up && !lookingUp) upSince = now
        lookingUp = up
        const next =
          up && now - upSince >= HOLD_MS
            ? 1
            : x < -past(shown === 0)
              ? 0
              : x > past(shown === 2)
                ? 2
                : NO_PANE
        if (next !== shown) moves.methods.show!(next)
      }

      // The panes lean with the look the room was just drawn with.
      const lean = () => {
        const x = view.look[0] / LOOK[0]
        const y = view.look[1] / LOOK[1]
        gaze(x, y)
        if (Math.abs(x - leaned[0]) < 0.002 && Math.abs(y - leaned[1]) < 0.002) return
        leaned = [x, y]
        cube.style.setProperty("--world-look-x", x.toFixed(3))
        cube.style.setProperty("--world-look-y", y.toFixed(3))
      }

      // A renderer that lands, first or after a lost device, finds the cube at rest.
      onReady(() => {
        for (const move of flight) move.cancel()
        flight = []
        shown = NO_PANE
        lookingUp = false
        camera.zoom = 0
        camera.turn = 1
        steer!.approach!(0).spin!(1).glow!(0)
        rested = false
        dragging = false
        press = undefined
        last = performance.now()
        setMode("orbit")
        const current = renderer()
        if (!current) return
        const draw = current.present.bind(current)
        current.present = () => {
          aspect = current.aspect()
          draw()
          lean()
        }
      })

      const onPointerDown = (event: PointerEvent) => {
        if (!ready() || mode !== "orbit" || event.button !== 0) return
        press = {x: event.clientX, y: event.clientY, at: performance.now(), id: event.pointerId}
        canvas().setPointerCapture(event.pointerId)
      }

      const inRoom = () => mode === "inside" || mode === "entering"

      const lookAt = ([x, y]: [number, number]) => {
        lookTarget = [(x - 0.5) * 2 * LOOK[0], (0.5 - y) * 2 * LOOK[1]]
      }

      // A finger does not hover, so inside a room a touch looks where it lands.
      const onTouchLook = (event: PointerEvent) => {
        if (ready() && inRoom() && event.pointerType === "touch") lookAt(within(event))
      }

      const onPointerMove = (event: PointerEvent) => {
        if (!ready()) return
        const [x, y] = within(event)
        pointer = [x, y]
        movedAt = performance.now()
        if (inRoom()) {
          lookAt([x, y])
          return
        }
        if (!press || press.id !== event.pointerId) return
        const dx = event.clientX - press.x
        const dy = event.clientY - press.y
        if (!dragging) {
          if (Math.hypot(dx, dy) < CLICK_SLOP) return
          // The press already holds the cube still; a drag also steps it back.
          dragging = true
          rested = false
          steer!.approach!(0).glow!(0)
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
        if (!ready() || mode !== "orbit") return
        const target = faceAt(view, aspect, ...within(event))
        if (target >= 0) enter(target)
      }

      const onPointerCancel = () => {
        press = undefined
        dragging = false
      }

      // A lifted finger leaves the look where it was, so the pane it found can be read.
      const onPointerLeave = (event: PointerEvent) => {
        pointer = undefined
        if (event.pointerType !== "touch") lookTarget = [0, 0]
      }

      const onKeyDown = (event: KeyboardEvent) => {
        if (event.key === "Escape") leave()
      }

      const onClick = (event: MouseEvent) => {
        if ((event.target as Element).closest("[data-world-leave]")) leave()
      }

      const surface = canvas()
      surface.addEventListener("pointerdown", onPointerDown)
      // The stage hears the pointer wherever it is, so the room's card under it
      // does not stop the look round the room.
      cube.addEventListener("pointerdown", onTouchLook, {passive: true})
      cube.addEventListener("pointermove", onPointerMove, {passive: true})
      surface.addEventListener("pointerup", onPointerUp)
      surface.addEventListener("pointercancel", onPointerCancel)
      cube.addEventListener("pointerleave", onPointerLeave, {passive: true})
      cube.addEventListener("click", onClick)
      document.addEventListener("keydown", onKeyDown)

      return () => {
        surface.removeEventListener("pointerdown", onPointerDown)
        cube.removeEventListener("pointerdown", onTouchLook)
        cube.removeEventListener("pointermove", onPointerMove)
        surface.removeEventListener("pointerup", onPointerUp)
        surface.removeEventListener("pointercancel", onPointerCancel)
        cube.removeEventListener("pointerleave", onPointerLeave)
        cube.removeEventListener("click", onClick)
        document.removeEventListener("keydown", onKeyDown)
        scope?.revert()
        scope = undefined
        steer = undefined
        flight = []
        shown = NO_PANE
        cube.style.removeProperty("--world-look-x")
        cube.style.removeProperty("--world-look-y")
        delete cube.dataset.worldState
        delete cube.dataset.worldFace
      }
    },
  })
}

type WorldCubeHook = {
  el: HTMLElement
  controller?: CanvasIslandController
}

export const WorldCube = {
  mounted(this: WorldCubeHook) {
    this.controller = createWorldCubeController(this.el)
    this.controller.mount()
  },
  disconnected(this: WorldCubeHook) {
    this.controller?.pause()
  },
  reconnected(this: WorldCubeHook) {
    this.controller?.resume()
  },
  destroyed(this: WorldCubeHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
