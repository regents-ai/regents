/**
 * Draws the world cube with WebGPU through vgpu. Loaded only once the cube is
 * really going to be shown; the page owns the camera and hands a view over for
 * each frame, and this module only draws it.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {worldCubeWgsl} from "./shader"
import type {WorldCubeView} from "./view"

export type WorldCubeRenderer = IslandRenderer & {
  /** Width over height of the picture as last drawn. */
  aspect(): number
}

export async function createWorldCubeRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  nextView: () => WorldCubeView,
): Promise<WorldCubeRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a cube still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "world-cube"})
  stage.resize([size[0], size[1]])
  const cube = effect(gpu, prepareShader(worldCubeWgsl, "world_cube.wgsl"), {label: "world-cube.rooms"})
  await cube.compile({colors: [stage.format]})

  let view = nextView()

  return {
    resize(width, height) {
      stage.resize([width, height])
    },
    // The cube never comes to rest: every frame is a new one.
    step() {
      view = nextView()
      return true
    },
    present() {
      cube.set({
        params: {
          resolution: stage.size,
          look: view.look,
          time: view.time,
          distance: view.distance,
          rotation: view.rotation,
          lens: view.lens,
          face: view.face,
          hover: view.hover,
          glow: view.glow,
        },
      })
      frame(gpu, current => current.pass(stage, cube))
    },
    async settled() {
      await gpu.gpu.queue.onSubmittedWorkDone()
      await gpu.settled()
    },
    dispose() {
      if (disposed) return
      disposed = true
      stage.dispose()
      gpu.dispose()
    },
    aspect() {
      const [width, height] = stage.size
      return width / height
    },
  }
}
