/**
 * The page-wide field renderer, loaded on demand by the `HomeField` hook.
 *
 * Everything WebGPU lives behind this module so the application entry never
 * carries it. The field is one composed picture: it never moves, so a frame is
 * only ever drawn for a new canvas size.
 *
 * Adapted from the Techtree background field, itself derived from the Vercel
 * vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */

import {effect, frame, init, surface, type Gpu} from "vgpu"

import {FIELD_PALETTE} from "./palette"
import {fieldWgsl} from "./shader"

export interface FieldRenderer {
  resize(width: number, height: number): void
  /** The picture never changes on its own, so nothing is ever left to settle. */
  step(): boolean
  present(): void
  /** Resolves once the work submitted so far has finished on the GPU. */
  settled(): Promise<void>
  dispose(): void
}

async function equip(gpu: Gpu, canvas: HTMLCanvasElement, size: readonly [number, number]) {
  const canvasSurface = surface(gpu, canvas, {
    autoResize: false,
    alphaMode: "opaque",
    label: "home-field",
  })
  canvasSurface.resize(size)
  const field = effect(gpu, fieldWgsl, {label: "home-field.squares"})
  await field.compile({colors: [canvasSurface.format]})
  return {canvasSurface, field}
}

export async function createFieldRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<FieldRenderer> {
  const gpu = await init()
  let disposed = false
  // A device this call created and could not finish equipping is still this call's
  // to release; the caller only ever learns that the renderer did not arrive.
  const {canvasSurface, field} = await equip(gpu, canvas, size).catch(error => {
    gpu.dispose()
    throw error
  })
  // Disposing the renderer destroys the device, which resolves the same promise.
  void gpu.gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  // The canvas writes straight to the screen, so these are the displayed values.
  const bind = () =>
    field.set({
      params: {
        groundColor: FIELD_PALETTE.displayedGround,
        squareColor: FIELD_PALETTE.displayedSquare,
        resolution: canvasSurface.size,
        intensity: FIELD_PALETTE.intensity,
      },
    })

  return {
    resize(width, height) {
      canvasSurface.resize([width, height])
    },
    step() {
      return false
    },
    present() {
      bind()
      frame(gpu, current => current.pass(canvasSurface, field))
    },
    async settled() {
      await gpu.gpu.queue.onSubmittedWorkDone()
      await gpu.settled()
    },
    dispose() {
      if (disposed) return
      disposed = true
      canvasSurface.dispose()
      gpu.dispose()
    },
  }
}
