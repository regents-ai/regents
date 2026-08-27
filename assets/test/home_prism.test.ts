import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"

import type {PrismRenderer} from "../js/home_prism"
import {
  EASING_FRAME_LIMIT,
  MAX_DEVICE_PIXEL_RATIO,
  MAX_DRAWING_BUFFER_PIXELS,
  createHomePrismController,
  drawingBufferSize,
} from "../js/hooks/home_prism"

type Rect = {left: number; top: number; width: number; height: number}

const HERO: Rect = {left: 0, top: 0, width: 1200, height: 800}

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
  const listeners = new Set<() => void>()
  const page = {
    hidden: false,
    addEventListener: vi.fn((_type: string, listener: () => void) => void listeners.add(listener)),
    removeEventListener: vi.fn(
      (_type: string, listener: () => void) => void listeners.delete(listener),
    ),
    hide(hidden: boolean) {
      page.hidden = hidden
      listeners.forEach(listener => listener())
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

type FakeRenderer = PrismRenderer & {
  finishFrame(): void
  failFrame(): void
}

const fakeRenderer = (step: (snap: boolean) => boolean = () => false): FakeRenderer => {
  let resolveSettled: () => void
  let rejectSettled: (reason: unknown) => void
  const settled = new Promise<void>((resolve, reject) => {
    resolveSettled = resolve
    rejectSettled = reject
  })
  return {
    aim: vi.fn(),
    rest: vi.fn(),
    resize: vi.fn(),
    step: vi.fn(step),
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

const island = () => {
  const hero = element(HERO)
  const canvas = element(HERO)
  const root = element(HERO)
  Object.defineProperty(root, "parentElement", {value: hero})
  root.querySelector = vi.fn(() => canvas) as unknown as typeof root.querySelector
  return {canvas, hero, root}
}

const mount = (
  overrides: {
    fine?: boolean
    loadRenderer?: ReturnType<typeof vi.fn>
    reduce?: boolean
    renderer?: FakeRenderer
    supportsWebGpu?: boolean
  } = {},
) => {
  const nodes = island()
  const renderer = overrides.renderer ?? fakeRenderer()
  const frames = frameQueue()
  const motion = mediaQuery(overrides.reduce ?? false)
  const loadRenderer =
    overrides.loadRenderer ?? vi.fn(async () => renderer as unknown as PrismRenderer)
  const controller = createHomePrismController(nodes.root, {
    cancelFrame: frames.cancel,
    devicePixelRatio: () => 2,
    loadRenderer: loadRenderer as never,
    motionQuery: () => motion,
    pointerQuery: () => mediaQuery(overrides.fine ?? true),
    requestFrame: frames.request,
    supportsWebGpu: () => overrides.supportsWebGpu ?? true,
  })
  return {...nodes, controller, frames, loadRenderer, motion, renderer}
}

/** The newest island reports that it is in view, as a real observer does on observe. */
const enterViewport = () =>
  FakeObserver.intersection.at(-1)?.callback([{isIntersecting: true}])

/** Runs both startup frames and the first render frame, leaving the scene settled. */
const settleFirstFrame = async (harness: ReturnType<typeof mount>) => {
  harness.controller.mount()
  enterViewport()
  harness.frames.flush()
  harness.frames.flush()
  await flushPromises()
  harness.frames.flush()
  await flushPromises()
}

/** A load the test holds open, so it can decide when the renderer lands. */
const heldLoad = () => {
  const arrivals: Array<(renderer: FakeRenderer) => void> = []
  const loadRenderer = vi.fn(
    () => new Promise<FakeRenderer>(resolve => void arrivals.push(resolve)),
  )
  return {arrivals, loadRenderer}
}

const heroListener = (harness: ReturnType<typeof mount>, type: string) =>
  vi
    .mocked(harness.hero.addEventListener)
    .mock.calls.find(([name]) => name === type)?.[1] as EventListener

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
})

// The renderer chunk is the expensive part of this feature. A visitor who asked for
// reduced motion, or whose browser has no WebGPU, must never pay for it.
describe("loading the homepage prism", () => {
  it("never requests the renderer when the visitor asks for reduced motion", async () => {
    const harness = mount({reduce: true})

    await settleFirstFrame(harness)

    expect(harness.loadRenderer).not.toHaveBeenCalled()
    expect(harness.root.dataset.prismReady).toBeUndefined()
  })

  it("never requests the renderer when the browser has no WebGPU", async () => {
    const harness = mount({supportsWebGpu: false})

    await settleFirstFrame(harness)

    expect(harness.loadRenderer).not.toHaveBeenCalled()
    expect(harness.root.dataset.prismReady).toBeUndefined()
  })

  it("lets the server hero paint before it asks for the renderer", () => {
    const harness = mount()

    harness.controller.mount()
    enterViewport()
    expect(harness.frames.pending()).toBe(1)

    // The callback of the frame the hero is painting in. Asking here would put the
    // chunk request in front of the paint it is meant to follow.
    harness.frames.flush()
    expect(harness.loadRenderer).not.toHaveBeenCalled()
    expect(harness.frames.pending()).toBe(1)

    // The first callback after the hero is on screen.
    harness.frames.flush()
    expect(harness.loadRenderer).toHaveBeenCalledTimes(1)
  })

  it("asks for nothing while the island is out of view", async () => {
    const harness = mount()

    harness.controller.mount()
    harness.frames.drain()
    await flushPromises()

    expect(harness.frames.pending()).toBe(0)
    expect(harness.loadRenderer).not.toHaveBeenCalled()

    enterViewport()
    harness.frames.flush()
    harness.frames.flush()

    expect(harness.loadRenderer).toHaveBeenCalledTimes(1)
  })

  it("disposes a renderer that arrives after the island was destroyed, and ignores what follows", async () => {
    const {arrivals, loadRenderer} = heldLoad()
    const late = fakeRenderer()
    const harness = mount({loadRenderer: loadRenderer as never})
    harness.controller.mount()
    enterViewport()
    harness.frames.flush()
    harness.frames.flush()
    const observer = FakeObserver.intersection[0]!

    harness.controller.destroy()
    observer.callback([{isIntersecting: true}])
    page.hide(true)
    arrivals[0]!(late)
    await flushPromises()

    expect(late.dispose).toHaveBeenCalledTimes(1)
    expect(late.present).not.toHaveBeenCalled()
    expect(loadRenderer).toHaveBeenCalledTimes(1)
    expect(harness.frames.pending()).toBe(0)
    expect(harness.root.dataset.prismReady).toBeUndefined()
  })

  it("cancels startup on destroy, whichever of the two frames is outstanding", () => {
    const first = mount()
    first.controller.mount()
    enterViewport()
    first.controller.destroy()

    expect(first.frames.pending()).toBe(0)
    expect(first.loadRenderer).not.toHaveBeenCalled()

    const second = mount()
    second.controller.mount()
    enterViewport()
    second.frames.flush()
    expect(second.frames.pending()).toBe(1)

    second.controller.destroy()
    second.frames.drain()

    expect(second.frames.pending()).toBe(0)
    expect(second.loadRenderer).not.toHaveBeenCalled()
  })

  // An observer reports the island in view as often as it likes, including while the
  // chunk it already asked for is still on its way. One island is one renderer.
  it("starts one renderer when the island reports itself in view again mid-start", async () => {
    const {arrivals, loadRenderer} = heldLoad()
    const only = fakeRenderer()
    const harness = mount({loadRenderer: loadRenderer as never})
    harness.controller.mount()
    enterViewport()
    harness.frames.flush()
    harness.frames.flush()
    expect(loadRenderer).toHaveBeenCalledTimes(1)

    enterViewport()
    harness.frames.drain()
    expect(loadRenderer).toHaveBeenCalledTimes(1)

    arrivals[0]!(only)
    await flushPromises()
    harness.frames.drain()

    expect(only.present).toHaveBeenCalledTimes(1)
    expect(only.dispose).not.toHaveBeenCalled()
    expect(harness.frames.pending()).toBe(0)
  })

  it("keeps the server hero when the renderer fails to initialize", async () => {
    const harness = mount({loadRenderer: vi.fn(async () => Promise.reject(new Error("no adapter")))})

    await settleFirstFrame(harness)

    expect(harness.root.dataset.prismReady).toBeUndefined()
    expect(harness.frames.pending()).toBe(0)
  })
})

describe("presenting the homepage prism", () => {
  it("reveals the canvas only after real GPU work for the first frame finished", async () => {
    const harness = mount()

    await settleFirstFrame(harness)

    expect(harness.renderer.present).toHaveBeenCalledTimes(1)
    expect(harness.root.dataset.prismReady).toBeUndefined()

    harness.renderer.finishFrame()
    await flushPromises()

    expect(harness.root.dataset.prismReady).toBe("true")
  })

  it("queues no further frames once the picture has settled", async () => {
    const harness = mount()

    await settleFirstFrame(harness)
    harness.frames.drain()

    expect(harness.frames.pending()).toBe(0)
    expect(harness.renderer.present).toHaveBeenCalledTimes(1)
  })

  it("returns to the server hero when the device is lost", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    harness.renderer.finishFrame()
    await flushPromises()
    expect(harness.root.dataset.prismReady).toBe("true")

    vi.mocked(harness.loadRenderer).mock.calls[0]![2]()

    expect(harness.root.dataset.prismReady).toBeUndefined()
    expect(harness.renderer.dispose).toHaveBeenCalledTimes(1)
    expect(harness.frames.pending()).toBe(0)
  })

  it("returns to the server hero when the first frame never completes", async () => {
    const harness = mount()

    await settleFirstFrame(harness)
    harness.renderer.failFrame()
    await flushPromises()

    expect(harness.root.dataset.prismReady).toBeUndefined()
    expect(harness.renderer.dispose).toHaveBeenCalledTimes(1)
  })
})

// A visitor who asks for stillness gets it, and the island answers the request while
// it is loading just as readily as after it has drawn.
describe("honouring the motion preference", () => {
  it("returns to the server hero when the visitor asks for stillness mid-visit", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    harness.renderer.finishFrame()
    await flushPromises()
    expect(harness.root.dataset.prismReady).toBe("true")

    harness.motion.prefer(true)

    expect(harness.renderer.dispose).toHaveBeenCalledTimes(1)
    expect(harness.root.dataset.prismReady).toBeUndefined()
    expect(harness.frames.pending()).toBe(0)
  })

  it("disposes a renderer that lands after the visitor asked for stillness", async () => {
    const {arrivals, loadRenderer} = heldLoad()
    const stale = fakeRenderer()
    const harness = mount({loadRenderer: loadRenderer as never})
    harness.controller.mount()
    enterViewport()
    harness.frames.flush()
    harness.frames.flush()
    expect(loadRenderer).toHaveBeenCalledTimes(1)

    harness.motion.prefer(true)
    arrivals[0]!(stale)
    await flushPromises()
    harness.frames.drain()

    expect(stale.dispose).toHaveBeenCalledTimes(1)
    expect(stale.present).not.toHaveBeenCalled()
    expect(loadRenderer).toHaveBeenCalledTimes(1)
    expect(harness.root.dataset.prismReady).toBeUndefined()
  })

  it("starts exactly once when the visitor stops asking for stillness", async () => {
    const harness = mount({reduce: true})
    harness.controller.mount()
    enterViewport()
    harness.frames.drain()
    await flushPromises()
    expect(harness.loadRenderer).not.toHaveBeenCalled()

    harness.motion.prefer(false)
    harness.frames.flush()
    harness.frames.flush()
    await flushPromises()
    expect(harness.loadRenderer).toHaveBeenCalledTimes(1)

    harness.frames.drain()

    expect(harness.renderer.present).toHaveBeenCalledTimes(1)
    expect(harness.frames.pending()).toBe(0)
  })
})

describe("responding to the pointer", () => {
  it("eases for exactly the frames it is allowed and then stops asking for more", async () => {
    const harness = mount({renderer: fakeRenderer(() => true)})
    await settleFirstFrame(harness)
    harness.frames.drain()
    const requestsBefore = vi.mocked(harness.frames.request).mock.calls.length
    const presentsBefore = vi.mocked(harness.renderer.present).mock.calls.length

    heroListener(harness, "pointermove")({
      isPrimary: true,
      clientX: 600,
      clientY: 400,
    } as unknown as Event)
    harness.frames.drain()

    expect(harness.renderer.aim).toHaveBeenCalledWith(0.5, 0.5)
    expect(vi.mocked(harness.frames.request).mock.calls.length - requestsBefore).toBe(
      EASING_FRAME_LIMIT,
    )
    expect(vi.mocked(harness.renderer.present).mock.calls.length - presentsBefore).toBe(
      EASING_FRAME_LIMIT,
    )
    expect(harness.frames.pending()).toBe(0)
  })

  it("leaves a coarse pointer with the composed shot and no listeners", async () => {
    const harness = mount({fine: false})

    await settleFirstFrame(harness)

    expect(harness.hero.addEventListener).not.toHaveBeenCalled()
  })
})

describe("owning the island", () => {
  it("releases every hero listener and observer, and remounts exactly one of each", async () => {
    const harness = mount()
    await settleFirstFrame(harness)

    expect(FakeObserver.resize).toHaveLength(1)
    expect(FakeObserver.intersection).toHaveLength(1)
    expect(FakeObserver.intersection[0]!.observed).toEqual([harness.root])
    expect(vi.mocked(harness.hero.addEventListener).mock.calls.map(([type]) => type)).toEqual([
      "pointermove",
      "pointerleave",
    ])

    harness.controller.destroy()

    expect(FakeObserver.resize[0]!.disconnects).toBe(1)
    expect(FakeObserver.intersection[0]!.disconnects).toBe(1)
    expect(vi.mocked(harness.hero.removeEventListener).mock.calls.map(([type]) => type)).toEqual([
      "pointermove",
      "pointerleave",
    ])

    await settleFirstFrame(harness)

    expect(FakeObserver.resize).toHaveLength(2)
    expect(FakeObserver.intersection).toHaveLength(2)
    expect(harness.renderer.dispose).toHaveBeenCalledTimes(1)
  })

  it("stops drawing offscreen and asks for exactly one frame on return", async () => {
    const harness = mount()
    await settleFirstFrame(harness)

    FakeObserver.intersection[0]!.callback([{isIntersecting: false}])
    expect(harness.frames.pending()).toBe(0)

    FakeObserver.intersection[0]!.callback([{isIntersecting: true}])
    expect(harness.frames.pending()).toBe(1)

    harness.frames.drain()
    expect(harness.frames.pending()).toBe(0)
  })

  // Out of view and out of sight are two different reasons to stop, and either one on
  // its own is reason enough. Coming back on one of them is not coming back.
  it("draws nothing when the tab returns while the island is still out of view", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    FakeObserver.intersection[0]!.callback([{isIntersecting: false}])

    page.hide(true)
    expect(harness.frames.pending()).toBe(0)

    page.hide(false)
    expect(harness.frames.pending()).toBe(0)

    FakeObserver.intersection[0]!.callback([{isIntersecting: true}])
    expect(harness.frames.pending()).toBe(1)
  })

  it("draws nothing when the island returns to view while the tab is hidden", async () => {
    const harness = mount()
    await settleFirstFrame(harness)
    page.hide(true)

    FakeObserver.intersection[0]!.callback([{isIntersecting: false}])
    FakeObserver.intersection[0]!.callback([{isIntersecting: true}])
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

  it("starts nothing while the connection is down, and one renderer when it returns", async () => {
    const harness = mount()
    harness.controller.mount()
    enterViewport()
    expect(harness.frames.pending()).toBe(1)

    harness.controller.pause()
    expect(harness.frames.pending()).toBe(0)
    harness.frames.drain()
    await flushPromises()
    expect(harness.loadRenderer).not.toHaveBeenCalled()

    harness.controller.resume()
    harness.frames.flush()
    harness.frames.flush()
    await flushPromises()
    expect(harness.loadRenderer).toHaveBeenCalledTimes(1)

    harness.frames.drain()
    expect(harness.renderer.present).toHaveBeenCalledTimes(1)
    expect(harness.frames.pending()).toBe(0)
  })

  it("disposes a renderer that lands after the connection dropped, and starts one replacement", async () => {
    const {arrivals, loadRenderer} = heldLoad()
    const stale = fakeRenderer()
    const replacement = fakeRenderer()
    const harness = mount({loadRenderer: loadRenderer as never})
    harness.controller.mount()
    enterViewport()
    harness.frames.flush()
    harness.frames.flush()
    expect(loadRenderer).toHaveBeenCalledTimes(1)

    harness.controller.pause()
    arrivals[0]!(stale)
    await flushPromises()
    expect(stale.dispose).toHaveBeenCalledTimes(1)
    expect(stale.present).not.toHaveBeenCalled()

    harness.controller.resume()
    harness.frames.flush()
    harness.frames.flush()
    expect(loadRenderer).toHaveBeenCalledTimes(2)

    arrivals[1]!(replacement)
    await flushPromises()
    harness.frames.drain()

    expect(replacement.present).toHaveBeenCalledTimes(1)
    expect(replacement.dispose).not.toHaveBeenCalled()
    expect(harness.frames.pending()).toBe(0)
  })
})

// The visitor never asked for a 4K backing store behind a headline.
describe("bounding the drawing buffer", () => {
  it("never exceeds the device pixel ratio ceiling", () => {
    expect(drawingBufferSize(400, 300, 3)).toEqual([
      400 * MAX_DEVICE_PIXEL_RATIO,
      300 * MAX_DEVICE_PIXEL_RATIO,
    ])
    expect(drawingBufferSize(400, 300, 0.5)).toEqual([400, 300])
  })

  it("never exceeds the pixel budget, at any shape", () => {
    for (const [width, height] of [
      [3840, 2160],
      [2560, 1080],
      [1200, 3000],
      [1600, 900],
      [390, 844],
    ] as const) {
      const [bufferWidth, bufferHeight] = drawingBufferSize(width, height, 3)

      expect(bufferWidth * bufferHeight, `${width}x${height}`).toBeLessThanOrEqual(
        MAX_DRAWING_BUFFER_PIXELS,
      )
      expect(bufferWidth / bufferHeight, `${width}x${height}`).toBeCloseTo(width / height, 1)
    }
  })

  it("always produces a drawable size", () => {
    expect(drawingBufferSize(0, 0, 1)).toEqual([1, 1])
  })
})
