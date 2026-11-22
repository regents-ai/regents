/**
 * Draws the Atlas blocks with WebGPU through vgpu, only when something
 * changed: there is no clock and no idle loop. Moving the camera, tiles
 * easing to new sizes or new counts ask for a frame (`nudge`), and nothing
 * else does.
 *
 * One layer of tiles, one quad an instance each. The tiles reach the GPU
 * only when the stage writes them, from an array it keeps; zooming and
 * moving change nothing but the draw's few numbers, written from one array
 * made once, so drawing allocates nothing.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, frame, geometry, init, surface, type Buffer, type Frame, type FramePass} from "vgpu"

import type {IslandRenderer} from "../../canvas_island"
import {SHOW_AT, SHOW_FROM} from "./layout"
import {blocksWgsl} from "./shader"

type Rgb = readonly [number, number, number]

/** As many tiles as one picture draws: every project and kind, and the things of the kinds opened. */
export const MAX_TILES = 16_384

/** Floats a tile takes: its rect, then how recent it is, its parent's fill, and its number with its marks. */
export const TILE_FLOATS = 7

// The shader's `Params`, as eleven vec4s.
const PARAMS = 44

export type BlocksRenderer = IslandRenderer & {
  /** The scale from the oldest work to the newest, the rest of a kind, the ground between the tiles, a lit tile's hairline, the ring and the dot of a tile changed today. */
  tones(low: Rgb, middle: Rgb, high: Rgb, rest: Rgb, ground: Rgb, line: Rgb, ring: Rgb, accent: Rgb): void
  /** The tiles: the first `count` of `data`. */
  tiles(data: Float32Array<ArrayBuffer>, count: number): void
  /** The point at the middle of the stage, from the layout's base, the zoom, the ringed tile's number and the numbers of the tiles lit, first and last (-1 for none). */
  view(x: number, y: number, zoom: number, ring: number, litFrom: number, litTo: number): void
}

export async function createBlocksRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<BlocksRenderer> {
  // Device pixels per CSS pixel, which the island may have capped below the screen's own.
  let scale = 1
  let width = size[0]
  let height = size[1]
  const params = new Float32Array(PARAMS)
  params[7] = -1
  params[8] = SHOW_FROM
  params[9] = SHOW_AT
  params[10] = -1
  params[11] = -1

  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still
  // on screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  const owned: {destroy(): void}[] = []
  try {
    const stage = surface(gpu, canvas, {
      autoResize: false,
      alphaMode: "premultiplied",
      clearColor: [0, 0, 0, 0],
      label: "atlas-blocks",
    })
    stage.resize([width, height])
    const shader = prepareShader(blocksWgsl, "atlas-blocks.wgsl")
    const quad = geometry(gpu, {
      topology: "triangle-strip",
      label: "atlas-blocks.tiles",
      buffers: [
        {
          stepMode: "instance",
          data: new Float32Array(MAX_TILES * TILE_FLOATS),
          attributes: {
            rect: {format: "float32x4", location: 0, offset: 0},
            tile: {format: "float32x3", location: 1, offset: 16},
          },
        },
      ],
    })
    owned.push(quad)
    const buffer: Buffer = gpu.device.createBuffer({size: PARAMS * 4, usage: ["uniform", "copy_dst"], label: "atlas-blocks.params"})
    owned.push(buffer)
    const tiles = draw(gpu, {
      shader,
      geometry: quad,
      blend: "premultiplied",
      vertices: 4,
      label: "atlas-blocks.tiles",
      set: {params: buffer},
    })
    await tiles.compile(stage)
    const call = {instances: 0}

    const unsubscribe = stage.onResize(resized => {
      scale = resized.width / Math.max(1, canvas.clientWidth)
      width = resized.width
      height = resized.height
    })

    // Made once, so a frame makes no closures of its own.
    const body = (pass: FramePass) => {
      if (call.instances > 0) pass.draw(tiles, call)
    }
    const record = (current: Frame) => current.pass(stage, body)

    return {
      tones(low, middle, high, rest, ground, line, ring, accent) {
        params.set(low, 12)
        params.set(middle, 16)
        params.set(high, 20)
        params.set(rest, 24)
        params.set(ground, 28)
        params.set(line, 32)
        params.set(ring, 36)
        params.set(accent, 40)
      },
      tiles(data, count) {
        call.instances = Math.min(count, MAX_TILES)
        if (call.instances > 0) quad.write(data.subarray(0, call.instances * TILE_FLOATS))
      },
      view(x, y, zoom, ring, litFrom, litTo) {
        params[4] = x
        params[5] = y
        params[6] = zoom
        params[7] = ring
        params[10] = litFrom
        params[11] = litTo
      },
      resize(nextWidth, nextHeight) {
        stage.resize([nextWidth, nextHeight])
      },
      step() {
        return false
      },
      present() {
        params[0] = width
        params[1] = height
        params[2] = scale
        buffer.write(params)
        frame(gpu, record)
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        unsubscribe()
        for (const resource of owned) resource.destroy()
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    // Set first, so the loss that disposing the device reports is not taken
    // for one to recover from.
    disposed = true
    for (const resource of owned) resource.destroy()
    gpu.dispose()
    throw error
  }
}
