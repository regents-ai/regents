import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"
import type {IslandRenderer} from "../canvas_island"
import {labelRange, type TileLook} from "./look"
import {TILE_SLOTS, wgsl} from "./shader"

/** Left, top, right and bottom, as fractions of the canvas box. */
export type Box = readonly [number, number, number, number]

/** The row the canvas sits behind. */
export type TileRow = {
  readonly look: TileLook
  /** Tiles in the row. */
  readonly count: number
  /** Where each tile stands this frame, press included. */
  measure(): readonly Box[]
  /** CSS pixels across the canvas's own box, whatever transform stands round it. */
  width(): number
}

export type ProductTilesRenderer = IslandRenderer & {
  /** The pointer stands over a tile, at a point given as fractions of the canvas box. */
  point(tile: number, at: readonly [number, number]): void
  /** The pointer has left the tiles; their light fades where it was. */
  rest(): void
}

/** A paused row picks up where it was rather than jumping ahead, in seconds. */
const LONGEST_STEP = 1 / 20
/** How quickly the pointer's light comes and goes, in seconds. */
const GLOW_EASE = 0.12

const zero = [0, 0, 0, 0] as const
const EMPTY = {box: zero, pointer: zero}

export async function createProductTilesRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  row: TileRow,
): Promise<ProductTilesRenderer> {
  const {look, count} = row
  if (count > TILE_SLOTS) throw new Error(`the product row draws at most ${TILE_SLOTS} tiles`)
  const [low, high] = labelRange(look)
  const colors = {
    deep: [...look.deep, 1],
    mid: [...look.mid, 1],
    light: [...look.light, 1],
    sheen: [...look.sheen, 1],
    calm: [low, high, 0, 0],
  }
  const slots = Array.from({length: count}, (_, tile) => tile)

  const gpu = await init()
  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "product-tiles"})
    let width = size[0]
    let height = size[1]
    stage.resize([width, height])
    const shader = effect(gpu, prepareShader(wgsl, "product_tiles.wgsl"), {label: "product-tiles.flow"})
    await shader.compile(stage)

    let disposed = false
    void gpu.lost.then(() => {
      if (!disposed) onDeviceLost()
    })

    let time = 0
    let last = performance.now()
    const glow = slots.map(() => 0)
    const wanted = slots.map(() => 0)
    const pointer = slots.map((): readonly [number, number] => [0, 0])

    return {
      point(tile, at) {
        wanted.fill(0)
        wanted[tile] = 1
        pointer[tile] = at
      },
      rest() {
        wanted.fill(0)
      },
      resize(nextWidth, nextHeight) {
        width = nextWidth
        height = nextHeight
        stage.resize([width, height])
      },
      step() {
        const now = performance.now()
        const seconds = Math.min(LONGEST_STEP, (now - last) / 1000)
        last = now
        time += seconds
        const ease = 1 - Math.exp(-seconds / GLOW_EASE)
        for (const [tile, target] of wanted.entries()) glow[tile]! += (target - glow[tile]!) * ease
        // The flow never stops while the row is on screen.
        return true
      },
      present() {
        const boxes = row.measure()
        const px = ([left, top, right, bottom]: Box) =>
          [left * width, top * height, right * width, bottom * height] as const
        const tiles = Array.from({length: TILE_SLOTS}, (_, tile) => {
          // The row measures one box for each tile, so the slots past them stay empty.
          const placed = boxes[tile]
          if (!placed) return EMPTY
          const [x, y] = pointer[tile]!
          return {box: px(placed), pointer: [x * width, y * height, glow[tile]!, 0]}
        })
        shader.set({params: {tiles, ...colors, view: [width / row.width(), time, count, 0]}})
        frame(gpu, current => current.pass(stage, shader))
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        shader.dispose()
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    gpu.dispose()
    throw error
  }
}
