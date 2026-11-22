/**
 * Draws the workspace's places chart with WebGPU through vgpu, above the
 * four place tabs, only when something changed. There is no clock and no
 * idle loop: choosing or pointing at a place sets how far each ridge should
 * rise, the picture eases toward it for a few frames and stops.
 *
 * Each value reaches the shader when it changes: the size when the canvas is
 * resized, the colours when the theme changes, where the tabs sit when the
 * layout moves them, and the ridges on each frame.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {chartWgsl} from "./shader"

type Rgb = readonly [number, number, number]
type Four = readonly [number, number, number, number]

/** How far one frame closes the gap to a target, and when the gap counts as closed. */
const EASE = 0.2
const CLOSE = 0.002

export type ChartRenderer = IslandRenderer & {
  /** The resting lines' colour and strength, and each place's colour: the Project, Docs, Code and Public. */
  tones(line: Rgb, strength: number, project: Rgb, docs: Rgb, code: Rgb, everyone: Rgb): void
  /** The centre of each place's tab, 0..1 across the canvas, and a tab's width. */
  place(centers: Four, width: number): void
  /** How far each place's ridge should rise, 0..1. */
  rise(targets: Four): void
}

export async function createChartRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<ChartRenderer> {
  // Device pixels per CSS pixel, so a line stays one CSS pixel wide, and a
  // tab's width, 0..1 across the canvas.
  let ratio = 1
  let tab = 1 / 4
  let pixels: readonly [number, number] = [size[0], size[1]]
  const rises = [0, 0, 0, 0].map(() => ({value: 0, target: 0}))

  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a chart still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "places-chart"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(chartWgsl, "places-chart.wgsl"), {
      label: "places-chart.pass",
      set: {
        params: {
          size: [size[0], size[1], 1, 1 / 4],
          rise: [0, 0, 0, 0],
          centers: [1 / 8, 3 / 8, 5 / 8, 7 / 8],
          line: [0.5, 0.5, 0.5, 0.5],
          project: [1, 1, 1, 1],
          docs: [1, 1, 1, 1],
          code: [1, 1, 1, 1],
          everyone: [1, 1, 1, 1],
        },
      },
    })
    await shader.compile(stage)
    const unsubscribe = stage.onResize(({width, height}) => {
      ratio = width / Math.max(1, canvas.clientWidth)
      pixels = [width, height]
      shader.set({params: {size: [width, height, ratio, tab]}})
    })

    return {
      tones(line, strength, project, docs, code, everyone) {
        shader.set({
          params: {
            line: [...line, strength],
            project: [...project, 1],
            docs: [...docs, 1],
            code: [...code, 1],
            everyone: [...everyone, 1],
          },
        })
      },
      place(centers, width) {
        tab = width
        shader.set({params: {centers: [...centers], size: [pixels[0], pixels[1], ratio, tab]}})
      },
      rise(targets) {
        rises.forEach((rise, i) => (rise.target = targets[i]))
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      step(snap) {
        let moved = false
        for (const rise of rises) {
          const gap = rise.target - rise.value
          if (gap === 0) continue
          rise.value = snap || Math.abs(gap) < CLOSE ? rise.target : rise.value + gap * EASE
          moved = true
        }
        return moved
      },
      present() {
        shader.set({params: {rise: [rises[0].value, rises[1].value, rises[2].value, rises[3].value]}})
        frame(gpu, current => current.pass(stage, shader))
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        unsubscribe()
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
