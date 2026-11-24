/**
 * Draws the home hero's bottom double chevron with WebGPU through vgpu on the
 * page's shared GPU device (`value_cards/page_device.ts`). Loaded dynamically
 * only once the chevron island is ready to draw.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {pageDevice} from "../value_cards/page_device"
import {heroChevronWgsl} from "./shader"

export type HeroChevronRenderer = IslandRenderer & {
  setHover(hovered: boolean): void
  setPress(pressed: boolean): void
}

const EASE = 0.18

export async function createHeroChevronRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<HeroChevronRenderer> {
  const shared = await pageDevice.join(onDeviceLost)
  const {gpu} = shared
  let stage: ReturnType<typeof surface> | undefined
  let shader: ReturnType<typeof effect> | undefined

  try {
    stage = surface(gpu, canvas, {
      autoResize: false,
      alphaMode: "premultiplied",
      label: "hero-chevron",
    })
    stage.resize([size[0], size[1]])
    const output = stage

    let width = size[0]
    let height = size[1]
    let disposed = false
    let started: number | undefined
    let seconds = 0
    let hover = 0
    let hoverTarget = 0
    let press = 0
    let pressTarget = 0

    const state = () => ({
      params: {
        size: [width, height, width / Math.max(1, canvas.clientWidth), seconds],
        motion: [hover, press, 0, 0],
      },
    })

    const pass = effect(gpu, prepareShader(heroChevronWgsl, "hero_chevron.wgsl"), {
      label: "hero-chevron.pass",
      set: state(),
    })
    shader = pass
    await pass.compile(output)

    return {
      setHover(hovered) {
        hoverTarget = hovered ? 1 : 0
      },
      setPress(pressed) {
        pressTarget = pressed ? 1 : 0
      },
      resize(nextWidth, nextHeight) {
        width = nextWidth
        height = nextHeight
        output.resize([width, height])
      },
      step() {
        const hoverGap = hoverTarget - hover
        hover = Math.abs(hoverGap) > 0.002 ? hover + hoverGap * EASE : hoverTarget
        const pressGap = pressTarget - press
        press = Math.abs(pressGap) > 0.002 ? press + pressGap * 0.35 : pressTarget
        started ??= performance.now()
        seconds = (performance.now() - started) / 1000
        return true
      },
      present() {
        pass.set(state())
        frame(gpu, current => current.pass(output, pass))
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        pass.dispose()
        output.dispose()
        pageDevice.leave(shared, onDeviceLost)
      },
    }
  } catch (error) {
    shader?.dispose()
    stage?.dispose()
    pageDevice.leave(shared, onDeviceLost)
    throw error
  }
}
