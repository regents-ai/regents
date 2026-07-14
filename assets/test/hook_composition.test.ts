import {readFileSync} from "node:fs"

import {expect, it, vi} from "vitest"

import {composeHooks} from "../js/hook_composition"

it("keeps Ash behavior active while composing a Design hook", () => {
  const ashMounted = vi.fn()
  const ashUpdated = vi.fn()
  const designMounted = vi.fn()
  const hook = composeHooks(
    {mounted: ashMounted, updated: ashUpdated},
    {mounted: designMounted},
  )
  const context = {name: "shell"}

  hook.mounted?.call(context, "ready")
  hook.updated?.call(context)

  expect(ashMounted).toHaveBeenCalledWith("ready")
  expect(designMounted).toHaveBeenCalledWith("ready")
  expect(ashUpdated).toHaveBeenCalledOnce()
  expect(ashMounted.mock.instances[0]).toBe(context)
})

it("runs Ash, shell motion, and voxel delight exactly once for every lifecycle", () => {
  const calls: string[] = []
  const lifecycle = (owner: string) => ({
    mounted: vi.fn(() => calls.push(`${owner}:mounted`)),
    updated: vi.fn(() => calls.push(`${owner}:updated`)),
    destroyed: vi.fn(() => calls.push(`${owner}:destroyed`)),
  })
  const ash = lifecycle("ash")
  const motion = lifecycle("motion")
  const voxel = lifecycle("voxel")
  const hook = composeHooks(ash, motion, voxel)
  const context = {name: "shell"}

  hook.mounted?.call(context)
  hook.updated?.call(context)
  hook.destroyed?.call(context)

  expect(calls).toEqual([
    "ash:mounted",
    "motion:mounted",
    "voxel:mounted",
    "ash:updated",
    "motion:updated",
    "voxel:updated",
    "ash:destroyed",
    "motion:destroyed",
    "voxel:destroyed",
  ])
  for (const owner of [ash, motion, voxel]) {
    expect(owner.mounted).toHaveBeenCalledOnce()
    expect(owner.updated).toHaveBeenCalledOnce()
    expect(owner.destroyed).toHaveBeenCalledOnce()
    expect(owner.mounted.mock.instances[0]).toBe(context)
  }
})

it("wires both Design lifecycles into the one persistent shell hook", () => {
  const source = readFileSync(new URL("../js/app.ts", import.meta.url)).toString()

  expect(source).toContain(
    "const designShellHook: Hook = composeHooks(ShellMotion, VoxelDelight)",
  )
  expect(source).toContain("ShellBehavior: composeHooks(shellBehavior, designShellHook)")
  expect(source).not.toMatch(/^\s{2}VoxelDelight,\s*$/m)
})
