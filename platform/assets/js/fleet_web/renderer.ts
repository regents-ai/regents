/**
 * Draws the home page's lines with WebGPU through vgpu. Loaded only once the
 * figure is really going to be shown; the hook measures where the lines run
 * and hands them over, and this module only draws them.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {LINE_LIMIT, fleetWebWgsl} from "./shader"

export type Rgb = readonly [number, number, number]

/** One line, in fractions of the canvas: its ends and the point its bend pulls towards. */
export type FleetLine = {
  from: readonly [number, number]
  bend: readonly [number, number]
  to: readonly [number, number]
  revenue: boolean
  lit: boolean
}

export type FleetWebLook = {
  lines: readonly FleetLine[]
  ink: Rgb
  revenue: Rgb
}

export type FleetWebRenderer = IslandRenderer & {
  look(look: FleetWebLook): void
}

/** Two four-number entries a line, as the shader reads them; unused entries stay zero. */
const packLines = (lines: readonly FleetLine[]): number[][] =>
  Array.from({length: LINE_LIMIT * 2}, (_, entry) => {
    const line = lines[entry >> 1]
    if (!line) return [0, 0, 0, 0]
    return entry % 2 === 0
      ? [...line.from, ...line.to]
      : [...line.bend, line.revenue ? 1 : 0, line.lit ? 1 : 0]
  })

export async function createFleetWebRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  first: FleetWebLook,
): Promise<FleetWebRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a figure still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {
      autoResize: false,
      alphaMode: "premultiplied",
      clearColor: [0, 0, 0, 0],
      label: "fleet-web",
    })
    stage.resize([size[0], size[1]])
    const web = effect(gpu, prepareShader(fleetWebWgsl, "fleet_web.wgsl"), {label: "fleet-web.lines"})
    await web.compile(stage)

    let look = first
    let packed = packLines(first.lines)
    const started = performance.now()

    return {
      resize(width, height) {
        stage.resize([width, height])
      },
      // The lines never stop flowing: every frame is a new one.
      step() {
        return true
      },
      present() {
        const [width] = stage.size
        web.set({
          params: {
            resolution: stage.size,
            scale: width / Math.max(1, canvas.clientWidth),
            time: (performance.now() - started) / 1000,
            count: Math.min(look.lines.length, LINE_LIMIT),
            ink: look.ink,
            revenue: look.revenue,
            lines: packed,
          },
        })
        frame(gpu, current => current.pass(stage, web))
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        stage.dispose()
        gpu.dispose()
      },
      look(next) {
        look = next
        packed = packLines(next.lines)
      },
    }
  } catch (error) {
    disposed = true
    gpu.dispose()
    throw error
  }
}
