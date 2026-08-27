/**
 * The homepage prism renderer, loaded on demand by the `HomePrism` hook.
 *
 * Everything WebGPU lives behind this module so the application entry never carries
 * it. The renderer owns the device, the surface and the scene; the hook owns the
 * canvas box, when a frame is worth drawing, and the fallback the visitor sees until
 * one really lands.
 *
 * Forked from the Vercel vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */

import {init, surface, type Gpu} from "vgpu"

import {
  createScene,
  destroyScene,
  prepareScene,
  presentScene,
  resizeScene,
  setLampAim,
  setOrbit,
} from "./scene"
import {CAMERA_ORBIT_LERP, LAMP_AIM_LERP, PRISM_DEFAULT_ARC, type Vec2} from "./types"

export interface PrismRenderer {
  /** Pointer position inside the hero, both components normalized to [0, 1]. */
  aim(x: number, y: number): void
  /** The pointer left the hero: ease everything back to the composed shot. */
  rest(): void
  resize(width: number, height: number): void
  /** Advances the easing one frame, or snaps it home. True when the picture moved. */
  step(snap: boolean): boolean
  present(): void
  /** Resolves once the work submitted so far has finished on the GPU. */
  settled(): Promise<void>
  dispose(): void
}

const CANONICAL_AIM: Vec2 = [PRISM_DEFAULT_ARC, 0.5]
const CANONICAL_ORBIT: Vec2 = [0, 0]
const clampUnit = (value: number): number => Math.min(1, Math.max(0, value))

/** The next easing position, or nothing when this pair has already arrived. */
function stepPair(current: Vec2, target: Vec2, rate: number, snap: boolean): Vec2 | undefined {
  const dx = target[0] - current[0]
  const dy = target[1] - current[1]
  if (dx === 0 && dy === 0) return undefined
  if (snap || (Math.abs(dx) < 1e-4 && Math.abs(dy) < 1e-4)) return target
  return [current[0] + dx * rate, current[1] + dy * rate]
}

async function equip(gpu: Gpu, canvas: HTMLCanvasElement, size: readonly [number, number]) {
  const canvasSurface = surface(gpu, canvas, {autoResize: false, label: "home-prism"})
  canvasSurface.resize(size)
  const scene = createScene(gpu, canvasSurface.size, "home-prism")
  await prepareScene(scene, canvasSurface)
  return {canvasSurface, scene}
}

export async function createPrismRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<PrismRenderer> {
  const gpu = await init()
  let disposed = false
  // A device this call created and could not finish equipping is still this call's
  // to release; the caller only ever learns that the renderer did not arrive.
  const {canvasSurface, scene} = await equip(gpu, canvas, size).catch(error => {
    gpu.dispose()
    throw error
  })
  // Disposing the renderer destroys the device, which resolves the same promise.
  void gpu.gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  let aimTarget = CANONICAL_AIM
  let aimCurrent = CANONICAL_AIM
  let orbitTarget = CANONICAL_ORBIT
  let orbitCurrent = CANONICAL_ORBIT

  return {
    // Pointer height swings the source; pointer width chooses its point of impact.
    aim(x, y) {
      aimTarget = [clampUnit(y), clampUnit(x)]
      orbitTarget = [clampUnit(x) * 2 - 1, clampUnit(y) * 2 - 1]
    },
    rest() {
      aimTarget = CANONICAL_AIM
      orbitTarget = CANONICAL_ORBIT
    },
    resize(width, height) {
      canvasSurface.resize([width, height])
      resizeScene(scene, canvasSurface.size)
    },
    step(snap) {
      const nextAim = stepPair(aimCurrent, aimTarget, LAMP_AIM_LERP, snap)
      const nextOrbit = stepPair(orbitCurrent, orbitTarget, CAMERA_ORBIT_LERP, snap)
      if (nextAim) {
        aimCurrent = nextAim
        setLampAim(scene, nextAim[0], nextAim[1])
      }
      if (nextOrbit) {
        orbitCurrent = nextOrbit
        setOrbit(scene, nextOrbit[0], nextOrbit[1])
      }
      return Boolean(nextAim || nextOrbit)
    },
    present() {
      presentScene(scene, canvasSurface)
    },
    async settled() {
      await gpu.gpu.queue.onSubmittedWorkDone()
      await gpu.settled()
    },
    dispose() {
      if (disposed) return
      disposed = true
      destroyScene(scene)
      canvasSurface.dispose()
      gpu.dispose()
    },
  }
}
