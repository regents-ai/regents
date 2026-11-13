/**
 * The particle field (`RegentsWeb.Components.ParticleField.particle_field/1`):
 * grains drawn over a real control, an icon, a brand mark or any drawing, as
 * many as the canvas calls for (80,000 in the lab, a few thousand in the theme
 * switch).
 *
 * Two attributes on the root are the whole of it. `data-particle-shape` names
 * the shape (a control such as `switch`, `ring`, `slider`, `bar`, `checkbox`,
 * `radio`, `spinner` or `steps:5`, or the name of a drawing in the field, an
 * `svg` marked `data-particle-source`, as `icon:<lucide name>` and
 * `mark:<name>` are) and `data-particle-value` holds its value from 0 to 1.
 * Changing the shape flies every grain to a new home; changing the value moves
 * the knob or the lit part. Whoever changes them, the server or a script, the
 * field follows. A script that owns the field can also change both at once and
 * say whether the grains fly (`show`): a key's change lands at once.
 *
 * `data-particle-glow` asks for the lab's lit grains and their glow; without it
 * the grains are flat ink in the field's colours.
 *
 * The shape stands `--particle-fill` of the root box's height, as far as its
 * width allows, drawn `--particle-aspect` wide for each unit tall
 * (particle_field.css says both for each shape), and the canvas reaches past the
 * box on every side for the flight and the halo. An icon or a mark is the
 * server's own drawing inside the root, which the grains are laid on.
 *
 * A value set by a press moves across on the design system's on-screen curve;
 * one set by a key lands at once; a stream of them, as from a drag, is followed
 * as it comes, so the knob stays under the finger. The grains' own springs
 * smooth what is left.
 *
 * Laying a new shape out takes longer than a frame, so it is done a few
 * milliseconds a frame, between the frames the picture draws; the old shape
 * holds still until it is ready, and a shape laid out once is kept for when it
 * comes back.
 *
 * Without WebGPU, with less motion asked for or in forced colours, the canvas
 * never starts and the real control below is the whole picture.
 */
import {createAnimatable} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {pictureOf} from "../particle_field/picture"
import type {FieldScene, ParticleFieldRenderer} from "../particle_field/renderer"
import {controlShape, finish, grainsFor, inFlightOrder, pictureShape, type Shape, type Steps} from "../particle_field/shapes"
import {showingTheme, watchTheme} from "../theme"
import {colourReader} from "../token_colour"
import {EASE_IN_OUT, SLOW, lastInputByPointer, still} from "./motion/shared"

export type ParticleFieldController = Pick<CanvasIslandController, "mount" | "pause" | "resume" | "destroy"> & {
  /** Shows a shape at a value, as the attributes would; the grains fly to it, or land at once. */
  show(shape: string, value: number, animated: boolean): void
}

/** Values closer together than this are a drag, followed as they come. */
const STREAM_MS = 120
/** Milliseconds of layout work one frame may take, so the frame is never missed. */
const SLICE_MS = 6
/** Shapes kept once laid out, for when they come back; at 80,000 grains each is about 4 MB. */
const KEPT = 6

/** Work under way a slice a frame: it can be dropped, or done at once when it cannot wait. */
type Slicing = {stop(): void; complete(): void}

/** Runs `steps` a few milliseconds a frame, then hands what they made to `done`. */
function slices<T>(steps: Steps<T>, done: (made: T) => void): Slicing {
  let frame = requestAnimationFrame(function slice() {
    const until = performance.now() + SLICE_MS
    for (;;) {
      const step = steps.next()
      if (step.done) {
        done(step.value)
        return
      }
      if (performance.now() >= until) break
    }
    frame = requestAnimationFrame(slice)
  })
  return {
    stop: () => cancelAnimationFrame(frame),
    complete() {
      cancelAnimationFrame(frame)
      done(finish(steps))
    },
  }
}

export function createParticleField(root: HTMLElement): ParticleFieldController {
  const canvas = root.querySelector<HTMLCanvasElement>("[data-particle-canvas]")!
  const readColour = colourReader()
  const valueNow = () => Number(root.dataset.particleValue)

  // What Anime.js moves: the value the grains show.
  const shown = {value: valueNow()}
  let name = root.dataset.particleShape!
  let target = shown.value
  // The shape the grains are on or flying to, the name and box it was laid out for, the share of the
  // box's height it stands, and its homes in flying order.
  let shape: Shape | undefined
  let shapeName: string | undefined
  let aspect = 1
  let fill = 1
  let homes: Float32Array<ArrayBuffer> | undefined
  // How many grains the renderer draws, set by the canvas it starts on.
  let grains = 0
  const layouts = new Map<string, Shape>()
  let building: Slicing | undefined
  // The picture is going to be drawn, so laying shapes out is worth it.
  let started = false
  let box = {width: 1, height: 1}
  let view = {width: 1, height: 1}
  let light = showingTheme() === "light"
  let colours: FieldScene["colours"] | undefined
  let lastValueAt = -Infinity
  let renderer: () => ParticleFieldRenderer | undefined = () => undefined
  let draw = () => {}
  let connected = true

  const motion = createAnimatable(shown, {value: 0, onUpdate: () => draw()})

  /** A name's shape in a box `wide` units across: the one kept from before, or laid out now. */
  function* layout(named: string, wide: number): Steps<Shape> {
    const key = `${named} ${wide} ${grains}`
    const kept = layouts.get(key)
    if (kept) {
      // The most recently used last, so the one let go is the one used longest ago.
      layouts.delete(key)
      layouts.set(key, kept)
      return kept
    }
    const drawing = root.querySelector<SVGSVGElement>(`svg[data-particle-source="${CSS.escape(named)}"]`)
    const made = drawing ? yield* pictureShape(named, pictureOf(drawing, wide), grains) : yield* controlShape(named, wide, grains)
    layouts.set(key, made)
    if (layouts.size > KEPT) layouts.delete(layouts.keys().next().value!)
    return made
  }

  /**
   * Lays out the shape the root names now; once it is ready the grains fly to it,
   * or land at once, at the value the root holds by then.
   */
  const change = (atOnce: boolean) => {
    building?.stop()
    const named = name
    const style = getComputedStyle(root)
    const wide = Number(style.getPropertyValue("--particle-aspect"))
    const share = Number(style.getPropertyValue("--particle-fill"))
    function* ready() {
      const made = yield* layout(named, wide)
      return {made, ordered: yield* inFlightOrder(made.homes, target)}
    }
    building = slices(ready(), ({made, ordered}) => {
      building = undefined
      shape = made
      shapeName = named
      aspect = wide
      fill = share
      homes = ordered
      jumpTo(target)
      renderer()?.place(ordered, atOnce)
    })
  }

  // Each token is resolved on an element inside the field, so a colour that differs by theme
  // (`light-dark()`) is the one the page shows, then read as red, green and blue.
  const readColours = (): FieldScene["colours"] => {
    const probe = document.createElement("span")
    probe.hidden = true
    root.append(probe)
    const token = (property: string) => {
      probe.style.color = `var(${property})`
      return readColour(getComputedStyle(probe).color)
    }
    const colours = {muted: token("--particle-muted"), lit: token("--particle-lit"), far: token("--particle-far")}
    probe.remove()
    return colours
  }

  const scene = (): FieldScene => {
    colours ??= readColours()
    const scale = Math.min(box.width / aspect, box.height * fill)
    return {
      width: view.width,
      height: view.height,
      scale,
      box: box.height,
      half: (aspect * scale) / 2,
      value: shown.value,
      area: shape!.area,
      knob: shape!.knob,
      turns: shape!.turns,
      light,
      colours,
    }
  }

  const measure = () => {
    box = {width: root.clientWidth || 1, height: root.clientHeight || 1}
    view = {width: canvas.clientWidth || 1, height: canvas.clientHeight || 1}
  }

  const jumpTo = (value: number) => {
    motion.value(value, 0)
    shown.value = value
    draw()
  }

  /** Shows a shape at a value: a new shape flies, or lands at once; a new value moves as `animated` says. */
  const showing = (nextName: string, nextValue: number, animated: boolean) => {
    if (nextName !== name) {
      name = nextName
      target = nextValue
      if (started) change(!animated)
      return
    }
    if (nextValue === target) return
    target = nextValue
    // A shape still being laid out takes the latest value when it is ready.
    if (building) return
    const now = performance.now()
    const streaming = now - lastValueAt < STREAM_MS
    lastValueAt = now
    if (streaming || !animated) jumpTo(nextValue)
    else motion.value(nextValue, SLOW, EASE_IN_OUT)
  }

  // The attributes changed: a new shape always flies; a new value moves as the last input asks.
  const follow = () => {
    const nextName = root.dataset.particleShape!
    showing(nextName, valueNow(), nextName !== name || lastInputByPointer())
  }

  const island = createCanvasIsland<ParticleFieldRenderer>(root, {}, {
    canvasSelector: "[data-particle-canvas]",
    readyFlag: "particleReady",
    motionSensitive: true,
    // The grains keep moving after every change until they come to rest; the
    // renderer says when they have.
    continuous: true,
    // Each grain is a speck a pixel or two across; below the screen's own
    // sharpness the specks smear into a haze.
    maxDevicePixelRatio: 2,
    browserLoad: async (view, size, lost) => {
      // The shape is laid out while the GPU starts, for as many grains as this canvas draws.
      started = true
      const count = grainsFor(size)
      if (count !== grains) {
        grains = count
        building?.stop()
        building = undefined
        shapeName = undefined
      }
      if (!building && shapeName !== name) change(true)
      const {createParticleFieldRenderer} = await import("../particle_field/renderer")
      return createParticleFieldRenderer(view, size, lost, {grains: count, glow: root.dataset.particleGlow !== undefined})
    },
    interact: island => {
      renderer = island.renderer
      draw = island.nudge
      island.onReady(() => {
        // The first picture cannot wait for the rest of the layout.
        building?.complete()
        const current = island.renderer()!
        current.show(scene)
        current.place(homes!, true)
      })
      return () => {
        renderer = () => undefined
        draw = () => {}
      }
    },
  })

  const forced = window.matchMedia("(forced-colors: active)")
  // A page's own Less motion switch (`data-motion="reduced"` round it) and forced
  // colours keep the real control alone, as the device setting does.
  const syncMotion = () => {
    if (!connected || still(root) || forced.matches) island.pause()
    else island.resume()
  }
  const calm = new MutationObserver(syncMotion)
  const changes = new MutationObserver(follow)
  const resized = new ResizeObserver(() => {
    measure()
    draw()
  })
  const events = new AbortController()
  let stopWatchingTheme = () => {}

  return {
    show(nextName, nextValue, animated) {
      showing(nextName, nextValue, animated)
      // The attributes say what shows; the field already follows them.
      root.dataset.particleShape = nextName
      root.dataset.particleValue = String(nextValue)
    },
    mount() {
      measure()
      changes.observe(root, {attributes: true, attributeFilter: ["data-particle-shape", "data-particle-value"]})
      calm.observe(document.documentElement, {subtree: true, attributes: true, attributeFilter: ["data-motion"]})
      forced.addEventListener("change", syncMotion, {signal: events.signal})
      resized.observe(root)
      stopWatchingTheme = watchTheme(theme => {
        light = theme === "light"
        colours = undefined
        draw()
      })
      island.mount()
      syncMotion()
    },
    pause() {
      connected = false
      island.pause()
    },
    resume() {
      connected = true
      syncMotion()
    },
    destroy() {
      building?.stop()
      events.abort()
      stopWatchingTheme()
      calm.disconnect()
      changes.disconnect()
      resized.disconnect()
      island.destroy()
      motion.revert()
    },
  }
}

type ParticleFieldHook = {el: HTMLElement; controller?: ParticleFieldController}

export const ParticleField = {
  mounted(this: ParticleFieldHook) {
    this.controller = createParticleField(this.el)
    this.controller.mount()
  },
  disconnected(this: ParticleFieldHook) {
    this.controller?.pause()
  },
  reconnected(this: ParticleFieldHook) {
    this.controller?.resume()
  },
  destroyed(this: ParticleFieldHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
