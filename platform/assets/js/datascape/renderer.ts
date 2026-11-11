/**
 * Draws the datascape with WebGPU through vgpu. Loaded only once the picture
 * is really going to be shown.
 *
 * Each frame the field moves on, and everything near enough is written out
 * again, measured from the camera: the tubes and panels of each layer,
 * farthest layer first, then the sparks. They are drawn into a texture; what
 * is bright in it is kept at a quarter of the size and blurred twice, and the
 * last pass lays that glow back over the scene on the page.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, effect, frame, geometry, init, sampler, surface, target, texture, uniforms, type Gpu} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {drawAtlas} from "./atlas"
import {createField, type Field, type Watcher} from "./field"
import * as shaders from "./shaders"
import {ATLAS, KIND, LAYERS} from "./world"

export type DatascapeRenderer = IslandRenderer & {
  readonly field: Field
}

/** The most of each thing one frame draws. */
const MAX_PANELS = 8192
const MAX_TUBE_PIECES = 1024
const MAX_SPARKS = 512
/** Floats for each panel, each piece of a tube and each spark. */
const PANEL_FLOATS = 24
const TUBE_FLOATS = 20
const SPARK_FLOATS = 12
/** How much smaller than the picture the glow is blurred at. */
const GLOW_SCALE = 4
/** The two blurs: a tight one, then a wide one over it. */
const BLUR_STEPS = [1, 2.3] as const
/** The ground covers every pixel, so the colour the scene is cleared to never shows. */
const CLEAR: [number, number, number, number] = [0, 0, 0, 1]

/** The four numbers of each instance attribute, in the order the shader reads them. */
const fours = (names: readonly string[]) =>
  Object.fromEntries(names.map((name, index) => [name, {format: "float32x4" as const, offset: index * 16, location: index}]))

export async function createDatascapeRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  watcher: Watcher,
): Promise<DatascapeRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still on screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })
  try {
    return await build(gpu, canvas, size, watcher, () => disposed, () => void (disposed = true))
  } catch (error) {
    disposed = true
    gpu.dispose()
    throw error
  }
}

async function build(
  gpu: Gpu,
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  watcher: Watcher,
  isDisposed: () => boolean,
  markDisposed: () => void,
): Promise<DatascapeRenderer> {
  const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "datascape"})
  stage.resize([size[0], size[1]])
  const glowSize = (width: number, height: number): [number, number] => [
    Math.max(1, Math.ceil(width / GLOW_SCALE)),
    Math.max(1, Math.ceil(height / GLOW_SCALE)),
  ]
  const scene = target(gpu, {size: [size[0], size[1]], label: "datascape.scene"})
  const glow = [0, 1].map(index => target(gpu, {size: glowSize(size[0], size[1]), label: `datascape.glow-${index}`}))
  const smooth = sampler(gpu, {minFilter: "linear", magFilter: "linear"})

  const atlas = texture(gpu, {
    kind: "2d",
    size: [ATLAS.texels, ATLAS.texels],
    format: "r8unorm",
    usage: ["texture_binding", "copy_dst"],
    label: "datascape.atlas",
  })
  gpu.gpu.queue.writeTexture(
    {texture: atlas.gpu},
    await drawAtlas(),
    {bytesPerRow: ATLAS.texels, rowsPerImage: ATLAS.texels},
    {width: ATLAS.texels, height: ATLAS.texels},
  )

  // The picture's size on the page, in CSS pixels: the world is measured in them.
  const page = {width: canvas.clientWidth || size[0], height: canvas.clientHeight || size[1]}
  const viewValues = {
    viewport: [page.width, page.height],
    lean: [1, 0],
    ground: [0, 0],
    zoom: 1,
    time: 0,
    pixel: size[0] / page.width,
  }
  const view = uniforms(gpu, viewValues)

  const panelData = new Float32Array(MAX_PANELS * PANEL_FLOATS)
  const panelGeometry = geometry(gpu, {
    buffers: [
      {
        data: panelData,
        stride: PANEL_FLOATS * 4,
        stepMode: "instance",
        attributes: fours(["box", "place", "first", "second", "motion", "extra"]),
      },
    ],
    instanceCount: MAX_PANELS,
    label: "datascape.panels",
  })
  const tubeData = new Float32Array(MAX_TUBE_PIECES * TUBE_FLOATS)
  const tubeGeometry = geometry(gpu, {
    buffers: [
      {
        data: tubeData,
        stride: TUBE_FLOATS * 4,
        stepMode: "instance",
        attributes: fours(["ends", "shape", "place", "first", "second"]),
      },
    ],
    instanceCount: MAX_TUBE_PIECES,
    label: "datascape.tubes",
  })
  const sparkData = new Float32Array(MAX_SPARKS * SPARK_FLOATS)
  const sparkGeometry = geometry(gpu, {
    buffers: [
      {
        data: sparkData,
        stride: SPARK_FLOATS * 4,
        stepMode: "instance",
        attributes: fours(["flight", "life", "tint"]),
      },
    ],
    instanceCount: MAX_SPARKS,
    label: "datascape.sparks",
  })

  const part = (name: "backdrop" | "tubes" | "panels" | "sparks") => ({
    shader: prepareShader(shaders[name], `datascape_${name}.wgsl`),
    depth: false as const,
    label: `datascape.${name}`,
  })
  const backdrop = draw(gpu, {...part("backdrop"), set: {view}, vertices: 3})
  const tubes = draw(gpu, {...part("tubes"), set: {view}, geometry: tubeGeometry, vertices: 6, blend: "alpha"})
  const panels = draw(gpu, {
    ...part("panels"),
    set: {view, atlas, atlasSampler: smooth},
    geometry: panelGeometry,
    vertices: 6,
    blend: "alpha",
  })
  const sparks = draw(gpu, {...part("sparks"), set: {view}, geometry: sparkGeometry, vertices: 6, blend: "alpha"})

  const bright = effect(gpu, prepareShader(shaders.bright, "datascape_bright.wgsl"), {
    label: "datascape.bright",
    set: {src: scene, srcSampler: smooth},
  })
  const blur = effect(gpu, prepareShader(shaders.blur, "datascape_blur.wgsl"), {
    label: "datascape.blur",
    set: {blur: {stride: [0, 0]}, src: glow[0]!, srcSampler: smooth},
  })
  const screenValues = {resolution: [size[0], size[1]], time: 0, pixel: viewValues.pixel}
  const finish = effect(gpu, prepareShader(shaders.finish, "datascape_finish.wgsl"), {
    label: "datascape.finish",
    set: {screen: screenValues, scene, glow: glow[0]!, screenSampler: smooth},
  })
  await Promise.all([
    ...[backdrop, tubes, panels, sparks].map(each => each.compile(scene)),
    bright.compile(glow[0]!),
    blur.compile(glow[0]!),
    finish.compile(stage),
  ])

  const field = createField(watcher)
  let lastStep: number | undefined
  // Where each layer's tubes and panels start in their buffers, and how many there are.
  const tubeRuns = LAYERS.map(() => ({first: 0, count: 0}))
  const panelRuns = LAYERS.map(() => ({first: 0, count: 0}))
  let sparkCount = 0

  /**
   * Writes out everything near enough to draw, measured from the camera. The nearest layer is
   * written first, so it is the far layers that go short if a buffer ever fills; each layer's
   * run is drawn in its own turn, farthest first, wherever it sits in the buffer.
   */
  const write = () => {
    const {x: cameraX, y: cameraY} = field.camera
    let panel = 0
    let piece = 0
    for (let layer = LAYERS.length - 1; layer >= 0; layer--) {
      const {depth, light} = LAYERS[layer]!
      tubeRuns[layer] = {first: piece, count: 0}
      panelRuns[layer] = {first: panel, count: 0}
      for (const cell of field.cells.values()) {
        if (cell.layer !== layer) continue
        const tube = cell.tube
        if (tube && tube.drawn > 0) {
          for (const each of tube.pieces) {
            if (piece === MAX_TUBE_PIECES) break
            const at = piece * TUBE_FLOATS
            if (each.turn) {
              tubeData.set([each.x - cameraX, each.y - cameraY, each.radius, each.angle, tube.thickness, each.from, 1, each.sweep], at)
            } else {
              tubeData.set(
                [each.x0 - cameraX, each.y0 - cameraY, each.x1 - cameraX, each.y1 - cameraY, tube.thickness, each.from, 0, 0],
                at,
              )
            }
            tubeData.set([depth, tube.style, tube.drawn, light, ...tube.a, tube.length, ...tube.b, tube.seed], at + 8)
            piece += 1
          }
        }
        for (const each of cell.panels) {
          if (each.grow <= 0) continue
          if (panel === MAX_PANELS) break
          const at = panel * PANEL_FLOATS
          panelData.set([each.x - cameraX, each.y - cameraY, each.w, each.h, depth, each.kind, each.seed, each.alpha, ...each.a, light], at)
          // Text and labels keep where their words are in the place of a second colour.
          if (each.kind === KIND.text || each.kind === KIND.label) panelData.set(each.words, at + 12)
          else panelData.set([...each.b, 0], at + 12)
          panelData.set([each.grow, each.flash, each.assemble, each.hover, each.clock, each.entrance, 0, 0], at + 16)
          panel += 1
        }
      }
      tubeRuns[layer]!.count = piece - tubeRuns[layer]!.first
      panelRuns[layer]!.count = panel - panelRuns[layer]!.first
    }
    if (piece > 0) tubeGeometry.write(tubeData.subarray(0, piece * TUBE_FLOATS))
    if (panel > 0) panelGeometry.write(panelData.subarray(0, panel * PANEL_FLOATS))

    sparkCount = Math.min(MAX_SPARKS, field.sparks.length)
    for (let index = 0; index < sparkCount; index++) {
      const spark = field.sparks[field.sparks.length - sparkCount + index]!
      const {depth, light} = LAYERS[spark.layer]!
      sparkData.set(
        [spark.x - cameraX, spark.y - cameraY, spark.dx, spark.dy, spark.born, spark.life, spark.size, depth, ...spark.colour, light],
        index * SPARK_FLOATS,
      )
    }
    if (sparkCount > 0) sparkGeometry.write(sparkData.subarray(0, sparkCount * SPARK_FLOATS))
  }

  const wrap = (value: number) => ((value % shaders.GROUND_PERIOD) + shaders.GROUND_PERIOD) % shaders.GROUND_PERIOD

  return {
    field,
    resize(width, height) {
      stage.resize([width, height])
      scene.resize([width, height])
      for (const each of glow) each.resize(glowSize(width, height))
      page.width = canvas.clientWidth || width
      page.height = canvas.clientHeight || height
      viewValues.viewport = [page.width, page.height]
      viewValues.pixel = width / page.width
      screenValues.resolution = [width, height]
      screenValues.pixel = viewValues.pixel
    },
    step() {
      const now = performance.now() / 1000
      const elapsed = lastStep === undefined ? 0 : now - lastStep
      lastStep = now
      field.advance(elapsed, page.width, page.height)
      return true
    },
    present() {
      const {camera} = field
      viewValues.lean = [Math.cos(camera.lean), Math.sin(camera.lean)]
      viewValues.ground = [wrap(camera.x), wrap(camera.y)]
      viewValues.zoom = camera.zoom
      viewValues.time = field.time
      view.set(viewValues)
      screenValues.time = field.time
      write()
      const [glowWidth, glowHeight] = glow[0]!.size
      frame(gpu, current => {
        current.pass({target: scene, clear: CLEAR}, pass => {
          pass.draw(backdrop)
          for (const layer of LAYERS.keys()) {
            const tubeRun = tubeRuns[layer]!
            const panelRun = panelRuns[layer]!
            if (tubeRun.count > 0) pass.draw(tubes, {vertices: 6, instances: tubeRun.count, firstInstance: tubeRun.first})
            if (panelRun.count > 0) pass.draw(panels, {vertices: 6, instances: panelRun.count, firstInstance: panelRun.first})
          }
          if (sparkCount > 0) pass.draw(sparks, {vertices: 6, instances: sparkCount})
        })
        current.pass(glow[0]!, bright)
        // Each blur goes across into the second texture and down back into the first.
        for (const step of BLUR_STEPS) {
          blur.set({blur: {stride: [step / glowWidth, 0]}, src: glow[0]!})
          current.pass(glow[1]!, blur)
          blur.set({blur: {stride: [0, step / glowHeight]}, src: glow[1]!})
          current.pass(glow[0]!, blur)
        }
        finish.set({screen: screenValues})
        current.pass(stage, finish)
      })
    },
    settled() {
      return gpu.settled()
    },
    dispose() {
      if (isDisposed()) return
      markDisposed()
      stage.dispose()
      gpu.dispose()
    },
  }
}
