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
