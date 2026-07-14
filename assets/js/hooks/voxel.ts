import {animate, createScope, type AnimationParams} from "animejs"

export const VOXEL_RESPONSE_DURATION = 400

export type VoxelAnimation = {
  cancel(): unknown
  seek(time: number): unknown
}

export type VoxelDriver = {
  animate(target: HTMLElement | HTMLElement[], options: Record<string, unknown>): VoxelAnimation
}

export type SharedVoxelLayer = {
  render(state: {phase?: string; palette: readonly ["accent", "neutral"]}): void
  destroy(): void
}

type VoxelScope = {revert(): unknown}

type VoxelOptions = {
  cells: HTMLElement[]
  driver?: VoxelDriver
  scopeFactory?: (root: HTMLElement) => VoxelScope
  sharedLayer?: SharedVoxelLayer
}

export type VoxelResponse = {
  meaningful: boolean
  phase?: string
  reducedMotion?: boolean
  source?: "pointer" | "keyboard"
}

export type VoxelController = {
  readonly active: VoxelAnimation | null
  respond(response: VoxelResponse): VoxelAnimation | null
  destroy(): void
}

const animeDriver: VoxelDriver = {
  animate: (target, options) => animate(target, options as AnimationParams),
}

const settle = (cells: HTMLElement[]) => {
  cells.forEach((cell) => {
    cell.style.opacity = "1"
    cell.style.transform = "none"
    cell.dataset.voxelMode = "static"
  })
}

export const createVoxelController = (root: HTMLElement, options: VoxelOptions): VoxelController => {
  const driver = options.driver ?? animeDriver
  const scope = (options.scopeFactory ?? ((scopeRoot) => createScope({root: scopeRoot})))(root)
  let active: VoxelAnimation | null = null
  let generation = 0

  options.cells.forEach((cell, index) => {
    cell.dataset.voxelTone = index % 2 === 0 ? "accent" : "neutral"
  })
  settle(options.cells)

  return {
    get active() {
      return active
    },
    respond(response) {
      active?.cancel()
      active = null
      const responseGeneration = ++generation

      if (!response.meaningful || response.reducedMotion || response.source === "keyboard") {
        settle(options.cells)
        return null
      }

      options.sharedLayer?.render({phase: response.phase, palette: ["accent", "neutral"]})
      options.cells.forEach((cell, index) => {
        cell.dataset.voxelMode = "responding"
        cell.style.opacity = index % 3 === 0 ? "0.45" : "0.7"
        cell.style.transform = `translate(${index % 2 === 0 ? -4 : 4}px, ${index % 3 === 0 ? -4 : 4}px)`
      })

      const animation = driver.animate(options.cells, {
        opacity: 1,
        translateX: 0,
        translateY: 0,
        duration: VOXEL_RESPONSE_DURATION,
        ease: "outQuad",
        onComplete: () => {
          if (generation !== responseGeneration) return
          settle(options.cells)
          active = null
        },
      })
      active = animation
      return animation
    },
    destroy() {
      generation += 1
      active?.cancel()
      active = null
      options.sharedLayer?.destroy()
      scope.revert()
      settle(options.cells)
    },
  }
}

type VoxelHookState = {
  el: HTMLElement
  voxels?: VoxelController
  voxelFactory?: (root: HTMLElement, options: VoxelOptions) => VoxelController
  voxelPhase?: string
}

export const VoxelDelight = {
  mounted(this: VoxelHookState) {
    this.voxels = (this.voxelFactory ?? createVoxelController)(this.el, {
      cells: Array.from(this.el.querySelectorAll<HTMLElement>("[data-voxel-cell]")),
    })
    this.voxelPhase = this.el.dataset.voxelPhase
  },
  updated(this: VoxelHookState) {
    const nextPhase = this.el.dataset.voxelPhase
    const phaseChanged = nextPhase !== this.voxelPhase

    this.voxels?.destroy()
    this.voxels = (this.voxelFactory ?? createVoxelController)(this.el, {
      cells: Array.from(this.el.querySelectorAll<HTMLElement>("[data-voxel-cell]")),
    })
    this.voxels.respond({
      meaningful: this.el.dataset.voxelMeaningful === "true" && phaseChanged,
      phase: nextPhase,
      source: this.el.dataset.voxelSource === "keyboard" ? "keyboard" : "pointer",
      reducedMotion: this.el.dataset.reducedMotion === "true",
    })
    this.voxelPhase = nextPhase
  },
  destroyed(this: VoxelHookState) {
    this.voxels?.destroy()
    this.voxels = undefined
    this.voxelPhase = undefined
  },
}
