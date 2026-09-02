import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"

import type {FieldRenderer} from "../js/home_field"
import {HERO_PALETTE_EVENT, setHeroPalette} from "../js/home_field/palette"
import {createHomeFieldController} from "../js/hooks/home_field"

type Rect = {left: number; top: number; width: number; height: number}

const PAGE: Rect = {left: 0, top: 0, width: 1200, height: 900}

const element = (rect: Rect) =>
  ({
    dataset: {} as DOMStringMap,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    getBoundingClientRect: () => ({
      ...rect,
      right: rect.left + rect.width,
      bottom: rect.top + rect.height,
    }),
  }) as unknown as HTMLElement

/** A preference the visitor can really change, which really tells whoever asked. */
const mediaQuery = (initial: boolean) => {
  const listeners = new Set<() => void>()
  const query = {
    matches: initial,
    addEventListener: vi.fn((_type: "change", listener: () => void) => void listeners.add(listener)),
    removeEventListener: vi.fn(
      (_type: "change", listener: () => void) => void listeners.delete(listener),
    ),
    prefer(next: boolean) {
      query.matches = next
      listeners.forEach(listener => listener())
    },
  }
  return query
}

/** A page the test can really hide and show. */
const pageDocument = () => {
  const listeners = new Map<string, Set<() => void>>()
  const page = {
    hidden: false,
    addEventListener: vi.fn((type: string, listener: () => void) => {
      const registered = listeners.get(type) ?? new Set<() => void>()
      listeners.set(type, registered.add(listener))
    }),
    removeEventListener: vi.fn(
      (type: string, listener: () => void) => void listeners.get(type)?.delete(listener),
    ),
    hide(hidden: boolean) {
      page.hidden = hidden
      listeners.get("visibilitychange")?.forEach(listener => listener())
    },
  }
  return page
}

class FakeObserver {
  static resize: FakeObserver[] = []
  static intersection: FakeObserver[] = []
  observed: unknown[] = []
  disconnects = 0
  constructor(readonly callback: (entries: unknown[]) => void) {}
  observe(target: unknown) {
    this.observed.push(target)
  }
  disconnect() {
    this.disconnects += 1
  }
}

const frameQueue = () => {
  const queued = new Map<number, FrameRequestCallback>()
  let next = 1
  return {
    request: vi.fn((callback: FrameRequestCallback) => {
      const handle = next++
      queued.set(handle, callback)
      return handle
    }),
    cancel: vi.fn((handle: number) => void queued.delete(handle)),
    pending: () => queued.size,
    flush() {
      const due = [...queued.values()]
      queued.clear()
      due.forEach(callback => callback(0))
    },
    drain(limit = 200) {
      let rounds = 0
      while (queued.size > 0 && rounds < limit) {
        this.flush()
        rounds += 1
      }
    },
  }
}

type FakeRenderer = FieldRenderer & {
  finishFrame(): void
  failFrame(): void
}

/** The field is one composed picture, so its renderer never has anything to settle. */
const fakeRenderer = (): FakeRenderer => {
  let resolveSettled: () => void
  let rejectSettled: (reason: unknown) => void
  const settled = new Promise<void>((resolve, reject) => {
    resolveSettled = resolve
    rejectSettled = reject
  })
  return {
    resize: vi.fn(),
    step: vi.fn(() => false),
    present: vi.fn(),
    settled: vi.fn(() => settled),
    dispose: vi.fn(),
    finishFrame: () => resolveSettled(),
    failFrame: () => {
      settled.catch(() => {})
      rejectSettled(new Error("device lost"))
    },
  }
}

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0))

const mount = (
  overrides: {
    loadRenderer?: ReturnType<typeof vi.fn>
    reduce?: boolean
    renderer?: FakeRenderer
    supportsWebGpu?: boolean
  } = {},
) => {
  const canvas = element(PAGE)
  const page = element(PAGE)
  const root = element(PAGE)
  // The field is rendered inside the page section, and reads the hero's palette from it.
  Object.defineProperty(root, "parentElement", {value: page})
  root.querySelector = vi.fn(() => canvas) as unknown as typeof root.querySelector
  const renderer = overrides.renderer ?? fakeRenderer()
  const frames = frameQueue()
  const motion = mediaQuery(overrides.reduce ?? false)
  const loadRenderer =
    overrides.loadRenderer ?? vi.fn(async () => renderer as unknown as FieldRenderer)
  const controller = createHomeFieldController(root, {
    cancelFrame: frames.cancel,
    devicePixelRatio: () => 2,
    loadRenderer: loadRenderer as never,
    motionQuery: () => motion,
    requestFrame: frames.request,
    supportsWebGpu: () => overrides.supportsWebGpu ?? true,
  })
  return {canvas, controller, frames, loadRenderer, motion, page, renderer, root}
}

/** The newest island reports that it is in view, as a real observer does on observe. */
const enterViewport = () =>
  FakeObserver.intersection.at(-1)?.callback([{isIntersecting: true}])

/** Runs both startup frames and the first render frame, leaving the field settled. */
const settleFirstFrame = async (harness: ReturnType<typeof mount>) => {
  harness.controller.mount()
  enterViewport()
  harness.frames.flush()
  harness.frames.flush()
  await flushPromises()
  harness.frames.flush()
  await flushPromises()
}

let page: ReturnType<typeof pageDocument>

beforeEach(() => {
  FakeObserver.resize = []
  FakeObserver.intersection = []
  vi.stubGlobal(
    "ResizeObserver",
    class extends FakeObserver {
      constructor(callback: (entries: unknown[]) => void) {
        super(callback)
        FakeObserver.resize.push(this)
      }
    },
  )
  vi.stubGlobal(
    "IntersectionObserver",
    class extends FakeObserver {
      constructor(callback: (entries: unknown[]) => void) {
        super(callback)
        FakeObserver.intersection.push(this)
      }
    },
  )
  page = pageDocument()
  vi.stubGlobal("document", page)
})

afterEach(() => {
  vi.unstubAllGlobals()
  setHeroPalette("rest")
})

describe("loading the page field", () => {
  it("never requests the renderer when the browser has no WebGPU", async () => {
    const harness = mount({supportsWebGpu: false})

    await settleFirstFrame(harness)

    expect(harness.loadRenderer).not.toHaveBeenCalled()
    expect(harness.root.dataset.fieldReady).toBeUndefined()
  })

  // The field is a still picture, so there is nothing in it for a visitor who asked
  // for less movement to be spared.
  it("still draws for a visitor who asked for reduced motion", async () => {
    const harness = mount({reduce: true})

    await settleFirstFrame(harness)
    harness.renderer.finishFrame()
    await flushPromises()

    expect(harness.loadRenderer).toHaveBeenCalledTimes(1)
    expect(harness.renderer.present).toHaveBeenCalledTimes(1)
    expect(harness.root.dataset.fieldReady).toBe("true")
  })

  it("lets the page paint before it asks for the renderer", () => {
    const harness = mount()

    harness.controller.mount()
    enterViewport()
    expect(harness.frames.pending()).toBe(1)

    harness.frames.flush()
    expect(harness.loadRenderer).not.toHaveBeenCalled()
    expect(harness.frames.pending()).toBe(1)

    harness.frames.flush()
    expect(harness.loadRenderer).toHaveBeenCalledTimes(1)
  })

  it("keeps a page-wide backing store inside the ceiling the crown obeys", async () => {
    const harness = mount()

    await settleFirstFrame(harness)

    // A 1200 x 900 window at the capped ratio of 1.5 wants 2.4 million pixels, which
    // is more than the island allows; both axes take the same reduction.
    const [width, height] = harness.loadRenderer.mock.calls[0]![1] as [number, number]
    expect(width * height).toBeLessThanOrEqual(1_500_000)
    expect(width / height).toBeCloseTo(1200 / 900, 2)
  })
})

describe("showing the page field", () => {
  it("keeps the plain ground until a first frame has really finished", async () => {
    const harness = mount()

    await settleFirstFrame(harness)
    expect(harness.renderer.present).toHaveBeenCalledTimes(1)
    expect(harness.root.dataset.fieldReady).toBeUndefined()

    harness.renderer.finishFrame()
    await flushPromises()

    expect(harness.root.dataset.fieldReady).toBe("true")
  })

  it("goes back to the plain ground when the first frame never lands", async () => {
    const harness = mount()
    await settleFirstFrame(harness)

    harness.renderer.failFrame()
    await flushPromises()

    expect(harness.root.dataset.fieldReady).toBeUndefined()
    expect(harness.renderer.dispose).toHaveBeenCalledTimes(1)
  })

  it("goes back to the plain ground when the device is lost", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    harness.renderer.finishFrame()
    await flushPromises()
    expect(harness.root.dataset.fieldReady).toBe("true")

    harness.loadRenderer.mock.calls[0]![2]()

    expect(harness.root.dataset.fieldReady).toBeUndefined()
    expect(harness.renderer.dispose).toHaveBeenCalledTimes(1)
  })

  // The picture never changes on its own, so a window that stops changing size stops
  // asking for frames entirely.
  it("draws once for the window it was given, and again only for a new one", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    expect(harness.frames.pending()).toBe(0)

    FakeObserver.resize[0]!.callback([])
    harness.frames.drain()

    expect(harness.renderer.resize).toHaveBeenCalledTimes(1)
    expect(harness.renderer.present).toHaveBeenCalledTimes(2)
    expect(harness.frames.pending()).toBe(0)
  })
})

describe("owning the page field", () => {
  it("watches the page and nothing else", async () => {
    const harness = mount()

    await settleFirstFrame(harness)

    expect(FakeObserver.resize).toHaveLength(1)
    expect(FakeObserver.intersection).toHaveLength(1)
    expect(vi.mocked(page.addEventListener).mock.calls.map(([type]) => type)).toEqual([
      "visibilitychange",
    ])
    expect(vi.mocked(harness.page.addEventListener).mock.calls.map(([type]) => type)).toEqual([
      HERO_PALETTE_EVENT,
    ])
    expect(harness.canvas.addEventListener).not.toHaveBeenCalled()
  })

  // The ground is read fresh for every frame, so the field needs telling only that the
  // hero has changed its mind — not what the new colour is.
  it("redraws the ground when the hero says the palette changed", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    harness.renderer.finishFrame()
    await flushPromises()
    expect(harness.frames.pending()).toBe(0)

    setHeroPalette("autolaunch")
    const announce = vi
      .mocked(harness.page.addEventListener)
      .mock.calls.find(([type]) => type === HERO_PALETTE_EVENT)![1] as EventListener
    announce(new Event(HERO_PALETTE_EVENT))
    harness.frames.drain()

    expect(harness.renderer.present).toHaveBeenCalledTimes(2)
  })

  it("draws nothing while the tab is hidden", async () => {
    const harness = mount()
    await settleFirstFrame(harness)

    page.hide(true)
    FakeObserver.resize[0]!.callback([])
    expect(harness.frames.pending()).toBe(0)

    page.hide(false)
    expect(harness.frames.pending()).toBe(1)
  })

  it("stops drawing while the LiveView connection is down", async () => {
    const harness = mount()
    await settleFirstFrame(harness)

    harness.controller.pause()
    FakeObserver.resize[0]!.callback([])
    expect(harness.frames.pending()).toBe(0)

    harness.controller.resume()
    expect(harness.frames.pending()).toBe(1)
  })

  it("releases every observer and the renderer when the page goes", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    harness.renderer.finishFrame()
    await flushPromises()

    harness.controller.destroy()

    expect(FakeObserver.resize[0]!.disconnects).toBe(1)
    expect(FakeObserver.intersection[0]!.disconnects).toBe(1)
    expect(vi.mocked(page.removeEventListener).mock.calls.map(([type]) => type)).toEqual([
      "visibilitychange",
    ])
    expect(vi.mocked(harness.page.removeEventListener).mock.calls.map(([type]) => type)).toEqual([
      HERO_PALETTE_EVENT,
    ])
    expect(harness.renderer.dispose).toHaveBeenCalledTimes(1)
    expect(harness.root.dataset.fieldReady).toBeUndefined()
  })
})
