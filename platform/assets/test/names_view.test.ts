import {afterEach, beforeEach, expect, it, vi} from "vitest"

import {NamesView} from "../js/hooks/names_view"

let stored: Map<string, string>

beforeEach(() => {
  stored = new Map()
  vi.stubGlobal("window", {
    localStorage: {
      getItem: (key: string) => stored.get(key) ?? null,
      setItem: (key: string, value: string) => stored.set(key, value),
    },
  })
})

afterEach(() => vi.unstubAllGlobals())

function mountToggle(view: string) {
  const el = {dataset: {view}}
  const pushEvent = vi.fn()
  const hook = {el, pushEvent}
  NamesView.mounted!.call(hook)
  return {hook, pushEvent}
}

it("asks the page for the form this browser chose before, when it differs", () => {
  stored.set("regents:names-view", "basename")
  const {pushEvent} = mountToggle("ens")
  expect(pushEvent).toHaveBeenCalledWith("set_names_view", {view: "basename"})
})

it("leaves the page alone when nothing is remembered or the same form is shown", () => {
  expect(mountToggle("ens").pushEvent).not.toHaveBeenCalled()

  stored.set("regents:names-view", "ens")
  expect(mountToggle("ens").pushEvent).not.toHaveBeenCalled()
})

it("ignores a remembered value that is not a form of the name", () => {
  stored.set("regents:names-view", "sideways")
  expect(mountToggle("ens").pushEvent).not.toHaveBeenCalled()
})

it("remembers every form the page switches to", () => {
  const {hook} = mountToggle("ens")
  hook.el.dataset.view = "basename"
  NamesView.updated!.call(hook)
  expect(stored.get("regents:names-view")).toBe("basename")
})

it("still works in a browser that keeps nothing", () => {
  vi.stubGlobal("window", {
    get localStorage(): Storage {
      throw new Error("blocked")
    },
  })
  const {hook, pushEvent} = mountToggle("ens")
  expect(pushEvent).not.toHaveBeenCalled()
  expect(() => NamesView.updated!.call(hook)).not.toThrow()
})
