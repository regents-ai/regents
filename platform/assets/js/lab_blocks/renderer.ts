/**
 * Draws the Overview hero's scene (`RegentsWeb.Components.LabBlocks`) with
 * WebGPU through vgpu, on the page's one device (`value_cards/page_device.ts`):
 * the tunnel, the crown's and the products' blocks and the beams between them,
 * depth-tested and antialiased. The hook tells it which composition the stage
 * shows, the theme's colours, what is picked and how far the mouse has turned
 * the view. Nothing in it moves by itself: once a pick or a turn has settled it
 * asks for no more frames.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, frame, geometry, surface, uniforms} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {pageDevice as device} from "../value_cards/page_device"
import {camera, orbit, sub, type CameraJson, type Layout, type Scene, type Vec3} from "./scene"
import {shaders} from "./shaders"

export type Palette = {
  readonly near: Vec3
  readonly far: Vec3
  readonly seam: Vec3
  readonly crownTop: Vec3
  readonly crownFoot: Vec3
  readonly beamTone: Vec3
  readonly litTone: Vec3
  /** Each place's colour, in the places' order: a product's own, Sign-in with Agent's the theme's quiet one. */
  readonly places: readonly Vec3[]
}

export type LabBlocksRenderer = IslandRenderer & {
  /** Which of the scene's two compositions the stage shows. */
  show(layout: keyof Scene): void
  paint(palette: Palette): void
  /** Lights these places and lines and sets the rest back, or settles everything with nothing picked. */
  pick(places: ReadonlySet<number>, lines: ReadonlySet<number>, active: boolean): void
  /** Where the mouse wants the view turned, in radians to the side and up. */
  tilt(yaw: number, pitch: number): void
}

/** How quickly a pick is followed, and the view the mouse turns, in seconds. */
const PICK_EASE = 0.05
const TILT_EASE = 0.2
/** A paused picture picks up where it was rather than jumping ahead, in seconds. */
const LONGEST_STEP = 1 / 20

const BOX_FLOATS = 24
const BEAM_FLOATS = 16

const fours = (names: readonly string[]) =>
  Object.fromEntries(names.map((name, index) => [name, {format: "float32x4" as const, offset: index * 16, location: index}]))

/** Moves a value part of the way to its goal, and lands on it once it is closer than `close`. */
const ease = (value: number, goal: number, amount: number, close: number) => {
  const next = value + (goal - value) * amount
  return Math.abs(goal - next) < close ? goal : next
}

export async function createLabBlocksRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  scene: Scene,
  palette: Palette,
  onView: (view: CameraJson) => void,
): Promise<LabBlocksRenderer> {
  const shared = await device.join(onDeviceLost)
  const {gpu} = shared
  // Everything made on the GPU, released in reverse if a later step throws.
  const releases: (() => void)[] = []
  try {
    const output = surface(gpu, canvas, {
      autoResize: false,
      alphaMode: "premultiplied",
      depth: true,
      msaa: true,
      label: "lab-blocks",
    })
    releases.push(() => output.dispose())
    output.resize([size[0], size[1]])

    const boxCount = (layout: Layout) => layout.crown.cells.length + layout.blocks.length
    const boxCapacity = Math.max(boxCount(scene.wide), boxCount(scene.narrow))
    const beamCapacity = Math.max(scene.wide.lines.length, scene.narrow.lines.length)

    const boxGeometry = geometry(gpu, {
      buffers: [{
        data: new Float32Array(boxCapacity * BOX_FLOATS),
        stride: BOX_FLOATS * 4,
        stepMode: "instance",
        attributes: fours(["place", "half", "ax", "ay", "az", "colour"]),
      }],
      instanceCount: boxCapacity,
      label: "lab-blocks.boxes",
    })
    releases.push(() => boxGeometry.destroy())
    const beamGeometry = geometry(gpu, {
      buffers: [{
        data: new Float32Array(beamCapacity * BEAM_FLOATS),
        stride: BEAM_FLOATS * 4,
        stepMode: "instance",
        attributes: fours(["a", "b", "head", "tail"]),
      }],
      instanceCount: beamCapacity,
      label: "lab-blocks.beams",
    })
    releases.push(() => beamGeometry.destroy())

    const zero = [0, 0, 0, 0]
    const view = uniforms(gpu, {
      eye: zero,
      right: zero,
      up: zero,
      forward: zero,
      size: [size[0], size[1], 1 / size[0], 1 / size[1]],
      light: zero,
      near: zero,
      far: zero,
      seam: zero,
      crownTop: zero,
      crownFoot: zero,
      beamTone: zero,
      litTone: zero,
      tunnel: zero,
      tunnel2: zero,
    })

    const part = (name: string, source: string) => prepareShader(source, `lab_blocks_${name}.wgsl`)
    const walls = draw(gpu, {shader: part("tunnel", shaders.tunnel), set: {view}, vertices: 3, depth: false, label: "lab-blocks.tunnel"})
    const blocks = draw(gpu, {shader: part("boxes", shaders.boxes), set: {view}, geometry: boxGeometry, vertices: 36, label: "lab-blocks.boxes"})
    const beams = draw(gpu, {shader: part("beams", shaders.beams), set: {view}, geometry: beamGeometry, vertices: 6, label: "lab-blocks.beams"})
    for (const each of [walls, blocks, beams]) releases.push(() => each.dispose())
    await Promise.all([walls, blocks, beams].map(each => each.compile(output)))

    let width = size[0]
    let height = size[1]
    let disposed = false
    let layout: Layout = scene.wide
    let colours = palette

    // How lit and how set back each place and line is, where each is heading,
    // and how much of the scene the pick holds.
    const settled = () => ({places: layout.blocks.map(() => ({lit: 0, back: 0})), lines: layout.lines.map(() => ({lit: 0, back: 0})), held: 0})
    let now = settled()
    let goal = settled()
    let picked = {places: new Set<number>() as ReadonlySet<number>, lines: new Set<number>() as ReadonlySet<number>, active: false}

    let yaw = 0
    let pitch = 0
    let yawGoal = 0
    let pitchGoal = 0
    let shown: readonly [Layout, number, number] | undefined

    let last = performance.now()

    const aim = () => {
      const {places, lines, active} = picked
      goal = {
        places: layout.blocks.map((_, index) => ({lit: places.has(index) ? 1 : 0, back: active && !places.has(index) ? 1 : 0})),
        lines: layout.lines.map((_, index) => ({lit: lines.has(index) ? 1 : 0, back: active && !lines.has(index) ? 1 : 0})),
        held: active ? 1 : 0,
      }
    }

    const boxData = new Float32Array(boxCapacity * BOX_FLOATS)
    const beamData = new Float32Array(beamCapacity * BEAM_FLOATS)

    /** Writes every block and beam as they stand now. */
    const write = () => {
      const [ax, ay, az] = layout.axes
      const {half, exposure, cells} = layout.crown
      cells.forEach(([x, y, z, t], index) => {
        boxData.set([x, y, z, 0, ...half, 0, 1, 0, 0, exposure, 0, 1, 0, t, 0, 0, 1, 0, 0, 0, 0, 0], index * BOX_FLOATS)
      })
      layout.blocks.forEach((middle, index) => {
        const {lit, back} = now.places[index]!
        const h = layout.half
        boxData.set(
          [...middle, lit, h, h, h, back, ...ax, 1, ...ay, -1, ...az, 0, ...colours.places[index]!, 0],
          (cells.length + index) * BOX_FLOATS,
        )
      })
      layout.lines.forEach(([from, to], index) => {
        const {lit, back} = now.lines[index]!
        beamData.set(
          [...layout.blocks[from]!, lit, ...layout.blocks[to]!, back, ...colours.places[from]!, 0, ...colours.places[to]!, 0],
          index * BEAM_FLOATS,
        )
      })
      boxGeometry.buffers[0]!.write(boxData)
      beamGeometry.buffers[0]!.write(beamData)
    }

    aim()

    return {
      show(next) {
        if (scene[next] === layout) return
        layout = scene[next]
        aim()
        now = {places: goal.places.map(each => ({...each})), lines: goal.lines.map(each => ({...each})), held: goal.held}
      },
      paint(next) {
        colours = next
      },
      pick(places, lines, active) {
        picked = {places, lines, active}
        aim()
      },
      tilt(nextYaw, nextPitch) {
        yawGoal = nextYaw
        pitchGoal = nextPitch
      },
      resize(nextWidth, nextHeight) {
        width = nextWidth
        height = nextHeight
        output.resize([width, height])
      },
      step(snap) {
        const time = performance.now()
        const seconds = Math.min(LONGEST_STEP, (time - last) / 1000)
        last = time
        const pickBy = snap ? 1 : 1 - Math.exp(-seconds / PICK_EASE)
        const tiltBy = snap ? 1 : 1 - Math.exp(-seconds / TILT_EASE)
        const follow = (each: {lit: number; back: number}, to: {lit: number; back: number}) => ({
          lit: ease(each.lit, to.lit, pickBy, 1e-3),
          back: ease(each.back, to.back, pickBy, 1e-3),
        })
        const before = now
        now = {
          places: now.places.map((each, index) => follow(each, goal.places[index]!)),
          lines: now.lines.map((each, index) => follow(each, goal.lines[index]!)),
          held: ease(now.held, goal.held, pickBy, 1e-3),
        }
        // A turn lands within a fraction of a pixel of where the mouse asked.
        yaw = ease(yaw, yawGoal, tiltBy, 2e-4)
        pitch = ease(pitch, pitchGoal, tiltBy, 2e-4)
        const changed = (a: {lit: number; back: number}[], b: {lit: number; back: number}[]) =>
          a.some((each, index) => each.lit !== b[index]!.lit || each.back !== b[index]!.back)
        return (
          changed(before.places, now.places) ||
          changed(before.lines, now.lines) ||
          before.held !== now.held ||
          shown === undefined ||
          shown[0] !== layout ||
          shown[1] !== yaw ||
          shown[2] !== pitch
        )
      },
      present() {
        const json = orbit(layout.camera, yaw, pitch)
        if (shown === undefined || shown[0] !== layout || shown[1] !== yaw || shown[2] !== pitch) {
          shown = [layout, yaw, pitch]
          onView(json)
        }
        const eye = camera(json)
        const {half, near, far, step, tile} = layout.tunnel
        write()
        view.set({
          eye: [...eye.eye, 0],
          right: [...eye.right, eye.tan],
          up: [...eye.up, eye.aspect],
          forward: [...eye.forward, width / Math.max(1, canvas.clientWidth)],
          size: [width, height, 1 / width, 1 / height],
          light: [...layout.light, now.held],
          near: [...colours.near, 0],
          far: [...colours.far, 0],
          seam: [...colours.seam, 0],
          crownTop: [...colours.crownTop, 0],
          crownFoot: [...colours.crownFoot, 0],
          beamTone: [...colours.beamTone, 0],
          litTone: [...colours.litTone, 0],
          tunnel: [half[0], half[1], near, far],
          // A beam is its own width at the distance the camera stands from its target.
          tunnel2: [step, tile, Math.hypot(...sub(json.eye, json.target)), 0],
        })
        frame(gpu, current => {
          current.pass({target: output, clear: [0, 0, 0, 0]}, pass => {
            pass.draw(walls)
            pass.draw(blocks, {instances: boxCount(layout)})
            pass.draw(beams, {instances: layout.lines.length})
          })
        })
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        for (const release of [...releases].reverse()) release()
        device.leave(shared, onDeviceLost)
      },
    }
  } catch (error) {
    for (const release of [...releases].reverse()) release()
    device.leave(shared, onDeviceLost)
    throw error
  }
}
