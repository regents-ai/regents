import {afterEach, describe, expect, it, vi} from "vitest"

import {
  CAMERA_ENTRY_DURATION,
  CAMERA_GLIDE_DURATION,
  CAMERA_RESET_DURATION,
  TechtreeCamera,
  createCameraController,
  type CameraDriver,
} from "../js/hooks/techtree_camera"
import {
  CAMERA_ZOOM_MAX,
  CAMERA_ZOOM_MIN,
  boundsForNodes,
  clampZoom,
  fitCamera,
  focusNodeIds,
  zoomCameraAt,
} from "../js/techtree_camera_math"

const harness = () => {
  const animations: Array<{
    options: Parameters<CameraDriver["animate"]>[1]
  }> = []
  const driver: CameraDriver = {
    animate: vi.fn((_target, options) => {
      const animation = {cancel: vi.fn()}
      animations.push({options})
      return animation
    }),
  }
  const render = vi.fn()
  const controller = createCameraController(render, driver)

  return {animations, controller, render}
}

type FakeEvent = {
  target: FakeElement
  pointerType?: string
  button?: number
  pointerId?: number
  clientX?: number
  clientY?: number
  detail?: number
  preventDefault: ReturnType<typeof vi.fn>
  stopPropagation: ReturnType<typeof vi.fn>
}

class FakeElement {
  dataset: Record<string, string> = {}
  style: Record<string, string> = {}
  parentElement: FakeElement | null = null
  offsetWidth = 0
  offsetHeight = 0
  clientWidth = 1_000
  clientHeight = 600
  clickCount = 0
  queryResult: FakeElement | null = null
  private listeners = new Map<string, Set<(event: FakeEvent) => void>>()
  private capturedPointers = new Set<number>()

  constructor(
    readonly kind: "stage" | "world" | "node" | "link",
    private readonly stage?: FakeElement,
  ) {}

  closest<T>(selector: string): T | null {
    let current: FakeElement | null = this
    while (current) {
      if (selector.startsWith("a[") && current.kind === "link") return current as T
      if (selector === "[data-node-id]" && current.dataset.nodeId) return current as T
      current = current.parentElement
    }
    return null
  }

  querySelector<T>(selector: string): T | null {
    if (this.kind === "stage" && selector === "[data-techtree-map-world]") {
      return this.queryResult as T
    }
    return null
  }

  querySelectorAll<T>(selector: string): T[] {
    if (this.kind !== "world") return []
    if (selector === "[data-node-id]" && this.queryResult) {
      return [this.queryResult as T]
    }
    return []
  }

  addEventListener(type: string, listener: (event: FakeEvent) => void) {
    const listeners = this.listeners.get(type) ?? new Set()
    listeners.add(listener)
    this.listeners.set(type, listeners)
  }

  removeEventListener(type: string, listener: (event: FakeEvent) => void) {
    this.listeners.get(type)?.delete(listener)
  }

  emit(type: string, event: FakeEvent) {
    for (const listener of this.listeners.get(type) ?? []) listener(event)
  }

  setPointerCapture(pointerId: number) {
    this.capturedPointers.add(pointerId)
  }

  hasPointerCapture(pointerId: number) {
    return this.capturedPointers.has(pointerId)
  }

  releasePointerCapture(pointerId: number) {
    this.capturedPointers.delete(pointerId)
  }

  getBoundingClientRect() {
    return {left: 0, top: 0, width: this.offsetWidth, height: this.offsetHeight}
  }

  focus() {}

  click() {
    this.clickCount += 1
    this.stage?.emit("click", fakeEvent(this, {detail: 0}))
  }
}

const fakeEvent = (target: FakeElement, values: Partial<FakeEvent> = {}): FakeEvent => ({
  target,
  preventDefault: vi.fn(),
  stopPropagation: vi.fn(),
  ...values,
})

const hookHarness = (reducedMotion = false) => {
  const stage = new FakeElement("stage")
  const world = new FakeElement("world")
  const node = new FakeElement("node")
  const link = new FakeElement("link", stage)
  const animations: Array<Parameters<CameraDriver["animate"]>[1]> = []

  stage.queryResult = world
  world.queryResult = node
  world.dataset = {worldWidth: "800", worldHeight: "400"}
  node.parentElement = world
  node.dataset = {nodeId: "canonical-node", nodeX: "120", nodeY: "80"}
  node.offsetWidth = 240
  node.offsetHeight = 112
  link.parentElement = node

  vi.stubGlobal("Element", FakeElement)
  vi.stubGlobal("window", {
    matchMedia: () => ({matches: reducedMotion}),
    requestAnimationFrame: vi.fn(() => 1),
    cancelAnimationFrame: vi.fn(),
  })

  const state = {
    el: stage,
    cameraDriver: {
      animate: vi.fn((_target, options) => {
        animations.push(options)
        return {cancel: vi.fn()}
      }),
    },
  }
  TechtreeCamera.mounted.call(state as never)

  const pointerDown = () =>
    stage.emit(
      "pointerdown",
      fakeEvent(link, {
        pointerType: "mouse",
        button: 0,
        pointerId: 1,
        clientX: 140,
        clientY: 100,
      }),
    )
  const pointerUp = () =>
    stage.emit(
      "pointerup",
      fakeEvent(stage, {pointerId: 1, clientX: 140, clientY: 100}),
    )

  return {animations, link, pointerDown, pointerUp, stage, state}
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe("Techtree camera math", () => {
  it("fits and centers a world rectangle inside the viewport margin", () => {
    expect(
      fitCamera(
        {width: 1_000, height: 600},
        {x: 100, y: 50, width: 800, height: 400},
        50,
      ),
    ).toEqual({x: -62.5, y: 18.75, zoom: 1.125})

    expect(
      fitCamera(
        {width: 1_000, height: 600},
        {x: 100, y: 50, width: 200, height: 100},
        50,
        1,
      ).zoom,
    ).toBe(1)
  })

  it("keeps the world point under the cursor fixed while zooming", () => {
    const before = {x: 10, y: 20, zoom: 1}
    const cursor = {x: 110, y: 70}
    const after = zoomCameraAt(before, cursor, 2)

    expect(after).toEqual({x: -90, y: -30, zoom: 2})
    expect((cursor.x - after.x) / after.zoom).toBe(
      (cursor.x - before.x) / before.zoom,
    )
    expect((cursor.y - after.y) / after.zoom).toBe(
      (cursor.y - before.y) / before.zoom,
    )
  })

  it("clamps zoom at both camera limits", () => {
    expect(clampZoom(0.01)).toBe(CAMERA_ZOOM_MIN)
    expect(clampZoom(20)).toBe(CAMERA_ZOOM_MAX)
    expect(zoomCameraAt({x: 0, y: 0, zoom: 1}, {x: 50, y: 50}, 20).zoom).toBe(
      CAMERA_ZOOM_MAX,
    )
  })

  it("focuses only the selected node and its direct prerequisite neighbors", () => {
    const focused = focusNodeIds("selected", [
      {
        kind: "prerequisite",
        fromNodeId: "parent",
        toNodeId: "selected",
      },
      {
        kind: "prerequisite",
        fromNodeId: "selected",
        toNodeId: "child",
      },
      {
        kind: "prerequisite",
        fromNodeId: "child",
        toNodeId: "grandchild",
      },
      {kind: "related", fromNodeId: "selected", toNodeId: "related"},
    ])

    expect([...focused].sort()).toEqual(["child", "parent", "selected"])
    expect(
      boundsForNodes(
        [
          {id: "parent", x: 20, y: 30, width: 100, height: 50},
          {id: "selected", x: 200, y: 100, width: 100, height: 50},
          {id: "child", x: 400, y: 200, width: 100, height: 50},
          {id: "related", x: 900, y: 900, width: 100, height: 50},
        ],
        focused,
      ),
    ).toEqual({x: 20, y: 30, width: 480, height: 220})
  })
})

describe("Techtree camera controller", () => {
  it("uses decelerating entry/focus curves and an accelerating reset curve", () => {
    const {animations, controller} = harness()

    controller.transition({x: 1, y: 2, zoom: 0.8}, {kind: "entry"})
    controller.transition({x: 3, y: 4, zoom: 1.2}, {kind: "focus"})
    controller.transition({x: 5, y: 6, zoom: 1}, {kind: "reset"})

    expect(
      animations.map(({options}) => [options.duration, options.ease]),
    ).toEqual([
      [CAMERA_ENTRY_DURATION, "outQuart"],
      [CAMERA_GLIDE_DURATION, "outQuart"],
      [CAMERA_RESET_DURATION, "inQuart"],
    ])
  })

  it("cancels an active glide and lets only the latest generation settle", () => {
    const {animations, controller} = harness()
    const firstSettled = vi.fn()
    const latestSettled = vi.fn()
    const first = controller.transition(
      {x: 100, y: 50, zoom: 1.2},
      {kind: "focus", onSettled: firstSettled},
    )
    const latest = controller.transition(
      {x: 200, y: 80, zoom: 1.4},
      {kind: "focus", onSettled: latestSettled},
    )

    expect(first?.cancel).toHaveBeenCalledOnce()
    animations[0].options.onComplete()
    expect(controller.active).toBe(latest)
    expect(firstSettled).not.toHaveBeenCalled()
    animations[1].options.onComplete()
    expect(controller.active).toBeNull()
    expect(controller.state).toEqual({x: 200, y: 80, zoom: 1.4})
    expect(latestSettled).toHaveBeenCalledOnce()
  })

  it.each([
    {source: "pointer" as const, reducedMotion: true},
    {source: "keyboard" as const, reducedMotion: false},
  ])("jumps immediately for reduced-motion and keyboard input", (intent) => {
    const {animations, controller, render} = harness()
    const target = {x: 40, y: 20, zoom: 1.1}
    const settled = vi.fn()

    expect(
      controller.transition(target, {kind: "focus", ...intent, onSettled: settled}),
    ).toBeNull()
    expect(animations).toHaveLength(0)
    expect(controller.state).toEqual(target)
    expect(render).toHaveBeenLastCalledWith(target)
    expect(settled).toHaveBeenCalledOnce()
  })

  it("cancels a glide when a direct gesture takes control", () => {
    const {controller} = harness()
    const active = controller.transition(
      {x: 100, y: 50, zoom: 1.2},
      {kind: "focus"},
    )

    controller.jump({x: 12, y: 18, zoom: 0.9})

    expect(active?.cancel).toHaveBeenCalledOnce()
    expect(controller.active).toBeNull()
    expect(controller.state).toEqual({x: 12, y: 18, zoom: 0.9})
  })
})

describe("Techtree camera node activation invariants", () => {
  it("U1 canonical activation navigates exactly once for pointer, keyboard, and reduced motion", () => {
    for (const mode of ["pointer", "keyboard", "reduced"] as const) {
      const {link, pointerDown, pointerUp, stage, state} = hookHarness(mode === "reduced")

      if (mode === "keyboard") {
        stage.emit("click", fakeEvent(link, {detail: 0}))
      } else {
        pointerDown()
        pointerUp()
        stage.emit("click", fakeEvent(stage, {detail: 1}))
      }

      expect(link.clickCount, mode).toBe(1)
      TechtreeCamera.destroyed.call(state as never)
    }
  })

  it("U2 gesture separation never navigates after a drag", () => {
    const {link, pointerDown, stage, state} = hookHarness()
    pointerDown()
    stage.emit(
      "pointermove",
      fakeEvent(stage, {pointerId: 1, clientX: 180, clientY: 140}),
    )
    stage.emit("click", fakeEvent(stage, {detail: 1}))

    expect(link.clickCount).toBe(0)
    TechtreeCamera.destroyed.call(state as never)
  })

  it("U3 motion independence continues synchronously and never repeats on animation settlement", () => {
    const {animations, link, pointerDown, pointerUp, stage, state} = hookHarness()
    pointerDown()
    pointerUp()
    stage.emit("click", fakeEvent(stage, {detail: 1}))

    expect(link.clickCount).toBe(1)
    const focusAnimation = animations.at(-1)
    expect(focusAnimation?.duration).toBe(CAMERA_GLIDE_DURATION)
    focusAnimation?.onComplete()
    expect(link.clickCount).toBe(1)

    TechtreeCamera.destroyed.call(state as never)
  })
})
