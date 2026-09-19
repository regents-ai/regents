import {afterEach, beforeEach, expect, it, vi} from "vitest"

import {InfiniteScroll} from "../js/hooks/infinite_scroll"

// Vitest here runs without a document, so the observer is the small surface
// the hook touches: what it watches and what it is told about being in view.
type Callback = (entries: Array<{isIntersecting: boolean}>) => void

let callbacks: Callback[]
let observed: unknown[]
let disconnected: number

beforeEach(() => {
  callbacks = []
  observed = []
  disconnected = 0
  vi.stubGlobal(
    "IntersectionObserver",
    class {
      constructor(callback: Callback) {
        callbacks.push(callback)
      }
      observe(target: unknown) {
        observed.push(target)
      }
      unobserve() {}
      disconnect() {
        disconnected += 1
      }
    },
  )
})

afterEach(() => vi.unstubAllGlobals())

function mountMarker(cursor: string) {
  const el = {dataset: {event: "load_more_names", cursor}}
  const pushEvent = vi.fn()
  const hook = {el, pushEvent}
  InfiniteScroll.mounted!.call(hook)
  return {
    hook,
    pushEvent,
    inView: (isIntersecting = true) => callbacks.at(-1)!([{isIntersecting}]),
  }
}

it("asks for the next rows once when the marker comes into view", () => {
  const {pushEvent, inView} = mountMarker("cursor-1")
  expect(observed).toHaveLength(1)

  inView(false)
  expect(pushEvent).not.toHaveBeenCalled()

  inView()
  inView()
  expect(pushEvent).toHaveBeenCalledOnce()
  expect(pushEvent).toHaveBeenCalledWith("load_more_names", {})
})

it("asks again only after the page has moved the marker on to a new batch", () => {
  const {hook, pushEvent, inView} = mountMarker("cursor-1")
  inView()

  InfiniteScroll.updated!.call(hook)
  inView()
  expect(pushEvent).toHaveBeenCalledOnce()

  hook.el.dataset.cursor = "cursor-2"
  InfiniteScroll.updated!.call(hook)
  inView()
  expect(pushEvent).toHaveBeenCalledTimes(2)
})

it("stops watching when the marker leaves the page", () => {
  const {hook} = mountMarker("cursor-1")
  InfiniteScroll.destroyed!.call(hook)
  expect(disconnected).toBe(1)
})
