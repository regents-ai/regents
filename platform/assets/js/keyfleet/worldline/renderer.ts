/**
 * Draws a fleet's Worldline with WebGPU through vgpu. Into one picture, an
 * offscreen target: the stars (an effect), then six draws, the helices' and
 * circles' far halves, the marks behind the line, the line, the near halves,
 * the marks in front, and the sun and planets at now. Then a bloom in three
 * effects at half size, and a last effect that lays the picture over its
 * bloom on the canvas.
 *
 * The paths are worked out on the GPU from time alone, so they take no
 * buffers; the events are instances of one buffer that reaches the GPU only
 * when they change, so thousands of them cost one write when they arrive and
 * nothing after. Each frame sends only the camera, how far the orbits stand
 * and the four heads, filled into the same arrays every time.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {
  draw,
  effect,
  frame as render,
  geometry,
  init,
  sampler,
  surface,
  target,
  uniforms,
  type Frame as Encoding,
  type FramePass,
} from "vgpu"

import {
  HEADS,
  MARK_FLOATS,
  MAX_EVENTS,
  PLANETS,
  RING_PIECES,
  SEGMENTS,
  TONES,
  high,
  type Frame,
  type Lens,
  type Orbit,
  type Run,
} from "./scene"
import {blurWgsl, brightWgsl, compositeWgsl, marksWgsl, pathsWgsl, starsWgsl} from "./shader"

type Rgb = readonly [number, number, number]

/** The colours: every one in `TONES` order (scene.ts), the page's ground, and the stars'. */
export type Tones = {
  readonly palette: readonly Rgb[]
  readonly ground: Rgb
  readonly sky: Rgb
  /** How strong the glow is, how faint the far side, how strongly the stars show and how strong the bloom, 0..1. */
  readonly glow: number
  readonly far: number
  readonly stars: number
  readonly bloom: number
}

/** What one frame shows. */
export type Scene = {
  readonly frame: Frame
  readonly lens: Lens
  /** The line and the helices, as `paths` in scene.ts gives them. */
  readonly paths: {readonly line: Run; readonly orbits: readonly Orbit[]}
  /** The sun and the planets at now, as `heads` in scene.ts packs them. */
  readonly heads: Float32Array<ArrayBuffer>
  /** The latest time shown yet as the picture reveals, and the earliest that just arrived, in seconds from the anchor. */
  readonly revealed: number
  readonly arrivedFrom: number
  /** The mark in focus by its index, -1 for none, and how far it stands out. */
  readonly focus: number
  readonly emphasis: number
  /** How near its arrival each head still is, 1 to 0: the sun, then the planets innermost first. */
  readonly flare: readonly number[]
  /** How far each head stands out while its link is pointed at or has the keyboard, 0..1, in the same order. */
  readonly lift: readonly number[]
  /** The clock in seconds, and 1 while things shimmer. */
  readonly clock: number
  readonly shimmer: number
  /** How far the planets have come out onto their orbits, and how far a change of filter has gone, 0..1. */
  readonly orbiting: number
  readonly change: number
  /** How far round each layer of stars has drifted as the picture flies, in radians, the farthest first. */
  readonly drift: readonly number[]
}

export type WorldlineRenderer = {
  resize(width: number, height: number): void
  tones(tones: Tones): void
  /** Every mark, as `pack` in scene.ts writes them for at most `MAX_EVENTS` events. */
  load(marks: Float32Array<ArrayBuffer>): void
  present(scene: Scene): void
  settled(): Promise<void>
  dispose(): void
}

const vector = (location: number) => ({format: "float32x4" as const, location})
const instances = (data: Float32Array<ArrayBuffer>) => [
  {stepMode: "instance" as const, data, attributes: {a: vector(0), b: vector(1), c: vector(2)}},
]
const four = () => [0, 0, 0, 0]
const half = (size: readonly [number, number]): [number, number] => [
  Math.max(1, Math.ceil(size[0] / 2)),
  Math.max(1, Math.ceil(size[1] / 2)),
]
// How bright a pixel begins to glow and glows fully, by luminance; and how
// far apart the blur's samples stand, in texels at half size.
const BRIGHT = [0.22, 0.7, 0, 0]
const SPREAD = 1.6

export async function createWorldlineRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<WorldlineRenderer> {
  // Device pixels per CSS pixel, which the island may have capped below the
  // screen's own.
  let scale = 1
  let stars = 0
  let bloom = 0

  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still
  // on screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {
      autoResize: false,
      alphaMode: "premultiplied",
      clearColor: [0, 0, 0, 0],
      label: "worldline",
    })
    stage.resize([size[0], size[1]])
    const picture = target(gpu, {size: [size[0], size[1]], format: "rgba16float", label: "worldline.picture"})
    const glow = target(gpu, {size: half(size), format: "rgba16float", label: "worldline.glow"})
    const across = target(gpu, {size: half(size), format: "rgba16float", label: "worldline.glow-across"})
    const filtering = sampler(gpu, {minFilter: "linear", magFilter: "linear"})

    const strips = geometry(gpu, {topology: "triangle-strip", label: "worldline.paths", buffers: []})
    const quads = geometry(gpu, {
      topology: "triangle-strip",
      label: "worldline.marks",
      buffers: instances(new Float32Array(MAX_EVENTS * MARK_FLOATS)),
    })
    const tops = geometry(gpu, {
      topology: "triangle-strip",
      label: "worldline.heads",
      buffers: instances(new Float32Array(HEADS * MARK_FLOATS)),
    })
    // One buffer that every draw of the paths and the marks reads.
    const params = uniforms(gpu, {
      size: [size[0], size[1], 1, 1],
      time: four(),
      viewProjection: new Float32Array(16),
      forward: four(),
      line: four(),
      orbits: PLANETS.map(four),
      pieces: four(),
      focus: [1e12, 1e12, -1, 0],
      flare: four(),
      lift: four(),
      mood: four(),
      pulse: four(),
      entrance: [1, 1, 0, 0],
      ground: four(),
      tones: TONES.map(() => [1, 1, 1, 1]),
    })
    const pathsShader = prepareShader(pathsWgsl, "worldline-paths.wgsl")
    const marksShader = prepareShader(marksWgsl, "worldline-marks.wgsl")
    const paths = (side: number, label: string) =>
      draw(gpu, {
        shader: pathsShader,
        geometry: strips,
        blend: "premultiplied",
        vertices: (SEGMENTS + 1) * 2,
        constants: {SIDE: side},
        label,
        set: {params},
      })
    const marks = (side: number, shape: typeof quads, label: string) =>
      draw(gpu, {
        shader: marksShader,
        geometry: shape,
        blend: "premultiplied",
        vertices: 4,
        constants: {SIDE: side},
        label,
        set: {params},
      })
    const farPaths = paths(-1, "worldline.paths.far")
    const farMarks = marks(-1, quads, "worldline.marks.far")
    const line = paths(0, "worldline.line")
    const nearPaths = paths(1, "worldline.paths.near")
    const nearMarks = marks(1, quads, "worldline.marks.near")
    const headMarks = marks(2, tops, "worldline.heads")
    const draws = [farPaths, farMarks, line, nearPaths, nearMarks, headMarks]

    const sky = effect(gpu, prepareShader(starsWgsl, "worldline-stars.wgsl"), {
      label: "worldline.stars",
      set: {sky: {size: four(), right: four(), up: four(), forward: four(), tone: four(), drift: four()}},
    })
    const bright = effect(gpu, prepareShader(brightWgsl, "worldline-bright.wgsl"), {
      label: "worldline.bright",
      set: {picture, filtering, bright: {level: BRIGHT}},
    })
    const blur = prepareShader(blurWgsl, "worldline-blur.wgsl")
    const blurAcross = effect(gpu, blur, {
      label: "worldline.blur-across",
      set: {source: glow, filtering, blur: {step: [SPREAD * glow.texelSize[0], 0, 0, 0]}},
    })
    const blurDown = effect(gpu, blur, {
      label: "worldline.blur-down",
      set: {source: across, filtering, blur: {step: [0, SPREAD * glow.texelSize[1], 0, 0]}},
    })
    const composite = effect(gpu, prepareShader(compositeWgsl, "worldline-composite.wgsl"), {
      label: "worldline.composite",
      set: {picture, glow, filtering, composite: {strength: four()}},
    })

    await Promise.all([
      ...draws.map(each => each.compile(picture)),
      sky.compile(picture),
      bright.compile(glow),
      blurAcross.compile(across),
      blurDown.compile(glow),
      composite.compile(stage),
    ])
    const unsubscribe = stage.onResize(({width}) => {
      scale = width / Math.max(1, canvas.clientWidth)
    })

    // What each frame sets, filled into the same arrays every time, and the
    // frame drawn by the same calls, so drawing a frame allocates nothing of
    // its own.
    const live = {
      size: four(),
      time: four(),
      viewProjection: new Float32Array(16),
      forward: four(),
      line: four(),
      orbits: PLANETS.map(four),
      pieces: four(),
      focus: four(),
      flare: four(),
      lift: four(),
      pulse: four(),
      entrance: four(),
    }
    const heavens = {size: four(), right: four(), up: four(), forward: four(), drift: four()}
    const skyUpdate = {sky: heavens}
    const put = (into: number[], a: number, b: number, c: number, d: number) => {
      into[0] = a
      into[1] = b
      into[2] = c
      into[3] = d
    }
    // How many instances each draw takes this frame: each planet's helix,
    // then its circle in the plane of the present; the line; the events.
    const turns = {instances: 0}
    const lineRun = {instances: 0}
    const events = {instances: 0}
    const tips = {instances: HEADS}
    const clear = [0, 0, 0, 0] as const
    const intoPicture = {target: picture, clear}
    const intoGlow = {target: glow, clear}
    const intoAcross = {target: across, clear}
    const intoStage = {target: stage, clear}
    const drawPicture = (pass: FramePass) => {
      if (stars > 0) pass.draw(sky)
      pass.draw(farPaths, turns)
      if (events.instances > 0) pass.draw(farMarks, events)
      if (lineRun.instances > 0) pass.draw(line, lineRun)
      pass.draw(nearPaths, turns)
      if (events.instances > 0) pass.draw(nearMarks, events)
      pass.draw(headMarks, tips)
    }
    const paint = (current: Encoding) => {
      current.pass(intoPicture, drawPicture)
      if (bloom > 0) {
        current.pass(intoGlow, bright)
        current.pass(intoAcross, blurAcross)
        current.pass(intoGlow, blurDown)
      }
      current.pass(intoStage, composite)
    }

    return {
      resize(width, height) {
        stage.resize([width, height])
        picture.resize([width, height])
        glow.resize(half([width, height]))
        across.resize(half([width, height]))
        blurAcross.set({blur: {step: [SPREAD * glow.texelSize[0], 0, 0, 0]}})
        blurDown.set({blur: {step: [0, SPREAD * glow.texelSize[1], 0, 0]}})
      },
      tones(tones) {
        params.set({
          mood: [tones.glow, tones.far, 0, 0],
          ground: [...tones.ground, 1],
          tones: tones.palette.map(rgb => [...rgb, 1]),
        })
        stars = tones.stars
        bloom = tones.bloom
        sky.set({sky: {tone: [...tones.sky, tones.stars]}})
        composite.set({composite: {strength: [tones.bloom, 0, 0, 0]}})
      },
      load(packed) {
        events.instances = packed.length / MARK_FLOATS
        quads.write(packed)
      },
      present(scene) {
        const {frame, lens: at, paths: drawn} = scene
        const hi = high(frame.mid)
        put(live.size, frame.width, frame.height, scale, at.aspect)
        put(live.time, hi, frame.mid - hi, at.unit, 0)
        live.viewProjection.set(at.viewProjection)
        put(live.forward, at.forward[0], at.forward[1], at.forward[2], 0)
        put(live.line, drawn.line.from, drawn.line.to, drawn.line.step, drawn.line.pieces)
        let helices = 0
        for (let i = 0; i < PLANETS.length; i++) {
          const orbit = drawn.orbits[i]
          put(live.orbits[i], orbit.from, orbit.to, orbit.step, orbit.phase)
          live.pieces[i] = orbit.pieces
          helices += orbit.pieces
        }
        live.pieces[3] = frame.now - frame.mid
        put(live.focus, scene.revealed - frame.mid, scene.arrivedFrom - frame.mid, scene.focus, scene.emphasis)
        put(live.flare, scene.flare[0], scene.flare[1], scene.flare[2], scene.flare[3])
        put(live.lift, scene.lift[0], scene.lift[1], scene.lift[2], scene.lift[3])
        put(live.pulse, scene.clock, scene.shimmer, 0, 0)
        put(live.entrance, scene.orbiting, scene.change, 0, 0)
        params.set(live)
        if (stars > 0) {
          put(heavens.size, frame.width, frame.height, scale, at.focal)
          put(heavens.right, at.right[0], at.right[1], at.right[2], 0)
          put(heavens.up, at.up[0], at.up[1], at.up[2], 0)
          put(heavens.forward, at.forward[0], at.forward[1], at.forward[2], 0)
          put(heavens.drift, scene.drift[0], scene.drift[1], scene.drift[2], 0)
          sky.set(skyUpdate)
        }
        tops.write(scene.heads)
        turns.instances = helices + PLANETS.length * RING_PIECES
        lineRun.instances = drawn.line.pieces
        render(gpu, paint)
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        unsubscribe()
        strips.destroy()
        quads.destroy()
        tops.destroy()
        // The offscreen targets go with the device.
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    // Set first, so the loss that disposing the device reports is not taken
    // for one to recover from.
    disposed = true
    gpu.dispose()
    throw error
  }
}
