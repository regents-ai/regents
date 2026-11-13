import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"
import type {IslandRenderer} from "../canvas_island"
import {wgsl} from "./shader"

/** A paused gradient picks up where it was rather than jumping ahead, in seconds. */
const LONGEST_STEP = 1 / 20

export async function createEnterGradientRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<IslandRenderer> {
  const gpu = await init()
  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "enter-gradient"})
    let [width, height] = size
    stage.resize([width, height])
    const shader = effect(gpu, prepareShader(wgsl, "enter_gradient.wgsl"), {label: "enter-gradient.flow"})
    await shader.compile(stage)

    let disposed = false
    void gpu.lost.then(() => {
      if (!disposed) onDeviceLost()
    })

    let time = 0
    let last = performance.now()

    return {
      resize(nextWidth, nextHeight) {
        width = nextWidth
        height = nextHeight
        stage.resize([width, height])
      },
      step() {
        const now = performance.now()
        time += Math.min(LONGEST_STEP, (now - last) / 1000)
        last = now
        // The gradient never stops while the button is on screen.
        return true
      },
      present() {
        shader.set({params: {view: [width, height, time, 0]}})
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
