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

it("runs Ash and shell motion exactly once for every lifecycle", () => {
  const calls: string[] = []
  const lifecycle = (owner: string) => ({
    mounted: vi.fn(() => calls.push(`${owner}:mounted`)),
    updated: vi.fn(() => calls.push(`${owner}:updated`)),
    destroyed: vi.fn(() => calls.push(`${owner}:destroyed`)),
  })
  const ash = lifecycle("ash")
  const motion = lifecycle("motion")
  const hook = composeHooks(ash, motion)
  const context = {name: "shell"}

  hook.mounted?.call(context)
  hook.updated?.call(context)
  hook.destroyed?.call(context)

  expect(calls).toEqual([
    "ash:mounted",
    "motion:mounted",
    "ash:updated",
    "motion:updated",
    "ash:destroyed",
    "motion:destroyed",
  ])
  for (const owner of [ash, motion]) {
    expect(owner.mounted).toHaveBeenCalledOnce()
    expect(owner.updated).toHaveBeenCalledOnce()
    expect(owner.destroyed).toHaveBeenCalledOnce()
    expect(owner.mounted.mock.instances[0]).toBe(context)
  }
})
