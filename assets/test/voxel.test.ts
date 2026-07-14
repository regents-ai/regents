import {describe, expect, it, vi} from "vitest"

import {
  VoxelDelight,
  createVoxelController,
  type VoxelAnimation,
  type VoxelController,
  type VoxelDriver,
} from "../js/hooks/voxel"

const element = () => ({style: {}, dataset: {}}) as unknown as HTMLElement

describe("voxel delight", () => {
  it("uses a static accent-and-neutral fallback until meaningful state changes", () => {
    const cells = [element(), element()]
    const animations: VoxelAnimation[] = []
    const driver: VoxelDriver = {
      animate: vi.fn(() => {
        const animation = {cancel: vi.fn(), seek: vi.fn()}
        animations.push(animation)
        return animation
      }),
    }
    const controller = createVoxelController(element(), {cells, driver, scopeFactory: () => ({revert: vi.fn()})})

    expect(cells.map((cell) => cell.dataset.voxelTone)).toEqual(["accent", "neutral"])
    expect(animations).toHaveLength(0)
    controller.respond({meaningful: false})
    expect(animations).toHaveLength(0)
  })

  it("runs one sparse 400ms response, supports deterministic seek, and cancels stale intent", () => {
    const cells = [element(), element(), element()]
    const animations: Array<VoxelAnimation & {options: Record<string, unknown>}> = []
    const driver: VoxelDriver = {
      animate: vi.fn((_targets, options) => {
        const animation = {options, cancel: vi.fn(), seek: vi.fn()}
        animations.push(animation)
        return animation
      }),
    }
    const controller = createVoxelController(element(), {cells, driver, scopeFactory: () => ({revert: vi.fn()})})

    const first = controller.respond({meaningful: true, phase: "selected"})!
    first.seek(200)
    controller.respond({meaningful: true, phase: "confirmed"})

    expect(animations[0].options.duration).toBe(400)
    expect(animations[0].seek).toHaveBeenCalledWith(200)
    expect(animations[0].cancel).toHaveBeenCalledOnce()
    expect(cells.every((cell) => cell.dataset.voxelMode === "responding")).toBe(true)
  })

  it.each(["keyboard" as const, "reduced" as const])("keeps %s responses static", (mode) => {
    const driver: VoxelDriver = {animate: vi.fn(() => ({cancel: vi.fn(), seek: vi.fn()}))}
    const cells = [element()]
    const controller = createVoxelController(element(), {cells, driver, scopeFactory: () => ({revert: vi.fn()})})

    controller.respond({
      meaningful: true,
      source: mode === "keyboard" ? "keyboard" : "pointer",
      reducedMotion: mode === "reduced",
    })

    expect(driver.animate).not.toHaveBeenCalled()
    expect(cells[0].style.transform).toBe("none")
  })

  it("offers one optional shared layer without creating a component canvas", () => {
    const root = element()
    const layer = {render: vi.fn(), destroy: vi.fn()}
    const scope = {revert: vi.fn()}
    const animation = {cancel: vi.fn(), seek: vi.fn()}
    const controller = createVoxelController(root, {
      cells: [element()],
      driver: {animate: vi.fn(() => animation)},
      scopeFactory: () => scope,
      sharedLayer: layer,
    })

    controller.respond({meaningful: true, phase: "active"})
    controller.destroy()

    expect(layer.render).toHaveBeenCalledWith({phase: "active", palette: ["accent", "neutral"]})
    expect(layer.destroy).toHaveBeenCalledOnce()
    expect(scope.revert).toHaveBeenCalledOnce()
    expect("querySelector" in root).toBe(false)
  })

  it("settles exactly and ignores a stale completion", () => {
    const cells = [element()]
    const animations: Array<VoxelAnimation & {options: Record<string, unknown>}> = []
    const controller = createVoxelController(element(), {
      cells,
      driver: {
        animate: (_targets, options) => {
          const animation = {options, cancel: vi.fn(), seek: vi.fn()}
          animations.push(animation)
          return animation
        },
      },
      scopeFactory: () => ({revert: vi.fn()}),
    })
    controller.respond({meaningful: true, phase: "first"})
    controller.respond({meaningful: true, phase: "latest"})

    ;(animations[0].options.onComplete as () => void)()
    expect(controller.active).not.toBeNull()
    ;(animations[1].options.onComplete as () => void)()

    expect(controller.active).toBeNull()
    expect(cells[0].style).toMatchObject({opacity: "1", transform: "none"})
    expect(cells[0].dataset.voxelMode).toBe("static")
  })

  it("drives meaningful phase changes through the composed hook lifecycle", () => {
    const cell = element()
    const root = element()
    root.dataset.voxelPhase = "idle"
    root.dataset.voxelMeaningful = "true"
    root.querySelectorAll = vi.fn(() => [cell]) as unknown as typeof root.querySelectorAll
    const animations: Array<VoxelAnimation & {options: Record<string, unknown>}> = []
    const scope = {revert: vi.fn()}
    const state = {
      el: root,
      voxelFactory: (voxelRoot: HTMLElement, options: {cells: HTMLElement[]}) =>
        createVoxelController(voxelRoot, {
          ...options,
          scopeFactory: () => scope,
          driver: {
            animate: (_targets, animationOptions) => {
              const animation = {options: animationOptions, cancel: vi.fn(), seek: vi.fn()}
              animations.push(animation)
              return animation
            },
          },
        }),
    }

    VoxelDelight.mounted.call(state)
    VoxelDelight.updated.call(state)
    expect(animations).toHaveLength(0)

    root.dataset.voxelPhase = "selected"
    VoxelDelight.updated.call(state)
    expect(animations).toHaveLength(1)
    expect(scope.revert).toHaveBeenCalledTimes(2)

    root.dataset.voxelPhase = "confirmed"
    VoxelDelight.updated.call(state)
    expect(animations[0].cancel).toHaveBeenCalledOnce()
    expect(animations).toHaveLength(2)

    VoxelDelight.destroyed.call(state)
    expect(animations[1].cancel).toHaveBeenCalledOnce()
    expect(scope.revert).toHaveBeenCalledTimes(4)
    expect(cell.dataset.voxelMode).toBe("static")
  })

  it("consumes the hook meaningful flag exactly", () => {
    const root = element()
    root.dataset.voxelPhase = "idle"
    root.dataset.voxelMeaningful = "false"
    root.querySelectorAll = vi.fn(() => []) as unknown as typeof root.querySelectorAll
    const controllers = Array.from({length: 2}, () => ({respond: vi.fn(), destroy: vi.fn(), active: null}))
    const state = {el: root, voxelFactory: vi.fn(() => controllers.shift()!)}

    VoxelDelight.mounted.call(state)
    root.dataset.voxelPhase = "selected"
    VoxelDelight.updated.call(state)

    expect((state as typeof state & {voxels?: VoxelController}).voxels?.respond).toHaveBeenCalledWith(
      expect.objectContaining({meaningful: false}),
    )
  })

  it("consumes the voxel-specific keyboard source at the hook boundary", () => {
    const root = element()
    root.dataset.voxelPhase = "idle"
    root.dataset.voxelMeaningful = "true"
    root.dataset.voxelSource = "keyboard"
    root.dataset.motionSource = "pointer"
    root.querySelectorAll = vi.fn(() => []) as unknown as typeof root.querySelectorAll
    const controllers = Array.from({length: 2}, () => ({respond: vi.fn(), destroy: vi.fn(), active: null}))
    const state = {el: root, voxelFactory: vi.fn(() => controllers.shift()!)}

    VoxelDelight.mounted.call(state)
    root.dataset.voxelPhase = "selected"
    VoxelDelight.updated.call(state)

    expect((state as typeof state & {voxels?: VoxelController}).voxels?.respond).toHaveBeenCalledWith(
      expect.objectContaining({source: "keyboard"}),
    )
  })
})
