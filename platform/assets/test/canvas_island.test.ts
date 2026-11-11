// R-20261019-failed-start-lets-go: an island whose GPU never started kept every
// listener it had added, including whatever steered the picture, until the page
// left (found by the design lane in Keyfleet, 19 Oct).
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"
import {
  MAX_DEVICE_PIXEL_RATIO,
  MAX_DRAWING_BUFFER_PIXELS,
  createCanvasIsland,
  drawingBufferSize,
  type IslandRenderer,
} from "../js/canvas_island"

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

describe("letting go", () => {
  const drawing: IslandRenderer = {
    resize() {},
    step: () => false,
    present() {},
    settled: async () => {},
    dispose() {},
  }

  let disconnected = 0
  let visibilityListeners = 0

  beforeEach(() => {
    disconnected = 0
    visibilityListeners = 0
    vi.stubGlobal("document", {
      hidden: false,
      addEventListener: () => void (visibilityListeners += 1),
      removeEventListener: () => void (visibilityListeners -= 1),
    })
    vi.stubGlobal("ResizeObserver", class {
      observe() {}
      disconnect() { disconnected += 1 }
    })
    vi.stubGlobal("IntersectionObserver", class {
      constructor(private seen: (entries: {isIntersecting: boolean}[]) => void) {}
      observe() { this.seen([{isIntersecting: true}]) }
      disconnect() { disconnected += 1 }
    })
  })

  afterEach(() => vi.unstubAllGlobals())

  // An island on screen in a showing tab, its first frame handed out at once. It
  // answers how often what steered the picture was let go, and the root's flag.
  async function runIsland(load: () => Promise<IslandRenderer>) {
    let released = 0
    const root = {dataset: {} as Record<string, string>, querySelector: () => ({
      getBoundingClientRect: () => ({width: 300, height: 200}),
    })} as unknown as HTMLElement

    createCanvasIsland(root, {
      requestFrame: callback => { queueMicrotask(() => callback(0)); return 1 },
      cancelFrame() {},
      devicePixelRatio: () => 1,
      motionQuery: () => ({matches: false, addEventListener() {}, removeEventListener() {}}),
      supportsWebGpu: () => true,
      loadRenderer: load,
    }, {
      canvasSelector: "canvas",
      readyFlag: "ready",
      browserLoad: load,
      motionSensitive: false,
      continuous: false,
      interact: () => () => void (released += 1),
    }).mount()

    for (let turn = 0; turn < 20; turn += 1) await Promise.resolve()
    return {released, ready: root.dataset.ready}
  }

  it("lets go of everything it watches with, once, when its GPU does not start", async () => {
    const {released, ready} = await runIsland(() => Promise.reject(new Error("no device")))
    expect(ready).toBe("false")
    expect(released).toBe(1)
    expect(disconnected).toBe(2)
    expect(visibilityListeners).toBe(0)
  })

  it("keeps hold of them while the picture draws", async () => {
    const {released, ready} = await runIsland(async () => drawing)
    expect(ready).toBe("true")
    expect(released).toBe(0)
    expect(visibilityListeners).toBe(1)
  })
})
