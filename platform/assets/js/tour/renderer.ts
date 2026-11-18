/**
 * Draws the guided tour's light with WebGPU through vgpu, on a clear canvas
 * over the dimmed page (tour/shader.ts). Loaded only once a tour is showing
 * and the light is really going to be drawn; the tour's script moves the ring
 * and hands over a picture whenever it changes, and nothing here moves by
 * itself.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {asLight, type Rgb} from "../theme_switch/light"
import type {Box} from "./place"
import {tourWgsl} from "./shader"

/** One frame of the light, in CSS pixels from the canvas's top left. */
export type TourPicture = {
  /** The canvas's own CSS size. */
  width: number
  height: number
  /** The hole round the part the step points at; none for a step that points at nothing. */
  hole: Box | undefined
  /** How far the spark has run round the ring, from 0 to 1. */
  run: number
  /** The page and the ring's own colour. */
  colours: {page: Rgb; ring: Rgb}
}

export type TourRenderer = IslandRenderer & {
  /** The picture the next present() draws. */
  show(picture: TourPicture): void
}

export async function createTourRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<TourRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a tour still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "tour"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(tourWgsl, "tour.wgsl"), {label: "tour.light"})
    await shader.compile(stage)

    let picture: TourPicture | undefined
    let lit: {colours: TourPicture["colours"]; light: Rgb} | undefined

    return {
      show(next) {
        picture = next
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      // The ring is moved by the page's own animation; there is nothing to ease here.
      step() {
        return false
      },
      present() {
        if (!picture) return
        const [width, height] = stage.size
        const scale = width / picture.width
        const {hole, run, colours} = picture
        if (lit?.colours !== colours) lit = {colours, light: asLight(colours.ring, colours.page)}
        shader.set({
          params: {
            size: [width, height],
            scale,
            run,
            hole: hole
              ? [(hole.x + hole.w / 2) * scale, (hole.y + hole.h / 2) * scale, (hole.w / 2) * scale, (hole.h / 2) * scale]
              : [0, 0, 0, 0],
            light: [lit.light[0], lit.light[1], lit.light[2], 1],
          },
        })
        frame(gpu, current => current.pass({target: stage, clear: [0, 0, 0, 0]}, shader))
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
    }
  } catch (error) {
    gpu.dispose()
    throw error
  }
}
