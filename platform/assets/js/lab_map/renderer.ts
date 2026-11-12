/**
 * Draws the slow glow behind the Overview hero's lab map with WebGPU through
 * vgpu. It draws on the page's one device (`value_cards/page_device.ts`), with
 * the product cards below it; when the browser takes that away, the map's island
 * hears of it and asks again.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {pageDevice as device} from "../value_cards/page_device"
import {DOT_SLOTS, wgsl} from "./shader"

/** A dot on the map: its place as fractions of the map's box, its colour and how far its glow reaches. */
export type Spot = {
  readonly at: readonly [number, number]
  readonly tint: readonly [number, number, number]
  /** How far the glow reaches, in CSS pixels; none for a dot that only colours its lines. */
  readonly reach: number
}

export type LabMapRenderer = IslandRenderer & {
  /** Lifts these dots, and glows along the line between two of them, or settles back with nothing. */
  pick(dots: ReadonlySet<number>, line: readonly [number, number] | null): void
}

/** How strong a dot's glow is at rest, lifted, and set back while others are lifted. */
const REST = 0.55
const LIFTED = 0.85
const SET_BACK = 0.22
/** How strong the glow along a picked line is. */
const LINE = 0.7
/** How strong the whole glow is over the panel's ground. */
const STRENGTH = 0.32
/** How far in from the canvas's edges the glow fades out, in CSS pixels. */
const FADE = 40
/** How quickly the glow follows a pick, in seconds. */
const EASE = 0.12
/** A paused map picks up where it was rather than jumping ahead, in seconds. */
const LONGEST_STEP = 1 / 20

export async function createLabMapRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  spots: readonly Spot[],
): Promise<LabMapRenderer> {
  if (spots.length > DOT_SLOTS) throw new Error(`the lab map lights at most ${DOT_SLOTS} dots`)
  const shared = await device.join(onDeviceLost)
  const {gpu} = shared
  let stage: ReturnType<typeof surface> | undefined
  let shader: ReturnType<typeof effect> | undefined
  try {
    stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "lab-map"})
    stage.resize([size[0], size[1]])
    const output = stage
    const pass = effect(gpu, prepareShader(wgsl, "lab_map.wgsl"), {label: "lab-map.glow"})
    shader = pass
    await pass.compile(output)

    let width = size[0]
    let height = size[1]
    let disposed = false
    let time = 0
    let last = performance.now()
    const glow = spots.map(() => REST)
    const wanted = spots.map(() => REST)
    let line: readonly [number, number] = [0, 0]
    let lineGlow = 0
    let lineWanted = 0

    return {
      pick(dots, picked) {
        for (const index of wanted.keys()) {
          wanted[index] = dots.size === 0 ? REST : dots.has(index) ? LIFTED : SET_BACK
        }
        // A line that fades keeps its ends until it has gone.
        if (picked) line = picked
        lineWanted = picked ? LINE : 0
      },
      resize(nextWidth, nextHeight) {
        width = nextWidth
        height = nextHeight
        output.resize([width, height])
      },
      step() {
        const now = performance.now()
        const seconds = Math.min(LONGEST_STEP, (now - last) / 1000)
        last = now
        time += seconds
        const ease = 1 - Math.exp(-seconds / EASE)
        for (const [index, target] of wanted.entries()) glow[index]! += (target - glow[index]!) * ease
        lineGlow += (lineWanted - lineGlow) * ease
        // The glow drifts and breathes for as long as the map is on screen.
        return true
      },
      present() {
        const ratio = width / Math.max(1, canvas.clientWidth)
        const place = (index: number) => {
          const [x, y] = spots[index]!.at
          return [x * width, y * height] as const
        }
        const slots = Array.from({length: DOT_SLOTS}, (_, index) => {
          const spot = spots[index]
          if (!spot || spot.reach === 0) return {place: [0, 0, 1, 0], tint: [0, 0, 0, 0]}
          return {place: [...place(index), spot.reach, glow[index]!], tint: [...spot.tint, index * 1.3]}
        })
        const [head, tail] = line
        pass.set({
          params: {
            spots: slots,
            ends: [...place(head), ...place(tail)],
            head: [...spots[head]!.tint, lineGlow],
            tail: [...spots[tail]!.tint, 0],
            view: [ratio, time, spots.length, STRENGTH],
            bounds: [width, height, FADE, 0],
          },
        })
        frame(gpu, current => current.pass(output, pass))
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        // The device outlives the map, so the map gives back what it made on it.
        pass.dispose()
        output.dispose()
        device.leave(shared, onDeviceLost)
      },
    }
  } catch (error) {
    shader?.dispose()
    stage?.dispose()
    device.leave(shared, onDeviceLost)
    throw error
  }
}
