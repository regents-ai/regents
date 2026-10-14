/**
 * Draws the code cube with WebGPU through vgpu, on a clear canvas so the page
 * behind it shows round it. Loaded only once the cube is really going to be
 * shown; the page owns the camera and hands a view over for each frame.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {WorldCubeView} from "../world_cube/view"
import {codeCubeWgsl} from "./shader"

/** Everything the shader needs to draw one frame: the world cube's camera, less its rooms. */
export type CodeCubeView = Pick<
  WorldCubeView,
  "rotation" | "distance" | "lens" | "shift" | "hover" | "glow" | "time"
>

export type CodeCubeRenderer = IslandRenderer & {
  /** Width over height of the picture as last drawn. */
  aspect(): number
}

export async function createCodeCubeRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  nextView: () => CodeCubeView,
): Promise<CodeCubeRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a cube still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "code-cube"})
  stage.resize([size[0], size[1]])
  const cube = effect(gpu, prepareShader(codeCubeWgsl, "code_cube.wgsl"), {label: "code-cube.rain"})
  await cube.compile({colors: [stage.format]})

  let view = nextView()

  return {
    resize(width, height) {
      stage.resize([width, height])
    },
    // The code never stops falling: every frame is a new one.
    step() {
      view = nextView()
      return true
    },
    present() {
      cube.set({
        params: {
          resolution: stage.size,
          time: view.time,
          distance: view.distance,
          rotation: view.rotation,
          lens: view.lens,
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
