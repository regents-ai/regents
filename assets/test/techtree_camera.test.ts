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
  isPrimary?: boolean
  pointerId?: number
  clientX?: number
  clientY?: number
  detail?: number
  metaKey?: boolean
  ctrlKey?: boolean
  shiftKey?: boolean
  altKey?: boolean
  defaultPrevented: boolean
  propagationStopped: boolean
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
  outboundNavigationCount = 0
  outboundNavigationEvents: FakeEvent[] = []
  href: string | null = null
  readonly children: FakeElement[] = []
  private listeners = new Map<string, Set<(event: FakeEvent) => void>>()
  private capturedPointers = new Set<number>()

  constructor(
    readonly kind: "stage" | "world" | "node" | "link",
    private readonly stage?: FakeElement,
  ) {}

  append(child: FakeElement) {
    child.parentElement = this
    this.children.push(child)
  }

  removeChild(child: FakeElement) {
    const index = this.children.indexOf(child)
    if (index === -1) return
    this.children.splice(index, 1)
    child.parentElement = null
  }

  get isConnected(): boolean {
    return this.kind === "stage" || this.parentElement?.isConnected === true
  }

  contains(element: FakeElement): boolean {
    return element === this || this.children.some((child): boolean => child.contains(element))
  }

  matches(selector: string) {
    return (
      (selector === 'a[data-phx-link="patch"][href]' ||
        selector === "a[data-phx-link=patch][href]") &&
      this.kind === "link" &&
      this.dataset.phxLink === "patch" &&
      Boolean(this.href)
    )
  }

  closest<T>(selector: string): T | null {
    let current: FakeElement | null = this
    while (current) {
      if (current.matches(selector)) {
        return current as T
      }
      if (selector === "[data-node-id]" && current.dataset.nodeId) return current as T
      current = current.parentElement
    }
    return null
  }

  querySelector<T>(selector: string): T | null {
    if (this.kind === "stage" && selector === "[data-techtree-map-world]") {
      return (this.children.find((child) => child.kind === "world") as T) ?? null
    }
    return null
  }

  querySelectorAll<T>(selector: string): T[] {
    if (this.kind !== "world") return []
    if (selector === "[data-node-id]") {
      return this.children.filter((child) => child.dataset.nodeId) as T[]
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
    if (
      type === "click" &&
      !event.defaultPrevented &&
      event.target.closest("a[data-phx-link=patch][href]")
    ) {
      this.outboundNavigationCount += 1
      this.outboundNavigationEvents.push(event)
    }
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

class FakeHTMLLIElement extends FakeElement {
  constructor() {
    super("node")
  }
}

class FakeHTMLAnchorElement extends FakeElement {
  constructor(stage: FakeElement) {
    super("link", stage)
  }
}

const fakeEvent = (target: FakeElement, values: Partial<FakeEvent> = {}): FakeEvent => {
  const event = {
    target,
    defaultPrevented: false,
    propagationStopped: false,
    preventDefault: vi.fn(),
    stopPropagation: vi.fn(),
    ...values,
  }
  event.preventDefault.mockImplementation(() => {
    event.defaultPrevented = true
  })
  event.stopPropagation.mockImplementation(() => {
    event.propagationStopped = true
  })
  return event
}

const hookHarness = (reducedMotion = false) => {
  const stage = new FakeElement("stage")
  const world = new FakeElement("world")
  const node = new FakeHTMLLIElement()
  const link = new FakeHTMLAnchorElement(stage)
  const otherNode = new FakeHTMLLIElement()
  const otherLink = new FakeHTMLAnchorElement(stage)
  let pointerHitTarget: FakeElement | null = null
  const animations: Array<{
    cancel: ReturnType<typeof vi.fn>
    options: Parameters<CameraDriver["animate"]>[1]
  }> = []

  stage.append(world)
  world.append(node)
  node.append(link)
  world.append(otherNode)
  otherNode.append(otherLink)
  world.dataset = {worldWidth: "800", worldHeight: "400"}
  node.dataset = {nodeId: "canonical-node", nodeX: "120", nodeY: "80"}
  node.offsetWidth = 240
  node.offsetHeight = 112
  link.dataset = {phxLink: "patch"}
  link.href = "/techtree/nodes/canonical-node"
  otherNode.dataset = {nodeId: "other-node", nodeX: "420", nodeY: "80"}
  otherNode.offsetWidth = 240
  otherNode.offsetHeight = 112
  otherLink.dataset = {phxLink: "patch"}
  otherLink.href = "/techtree/nodes/other-node"

  if (!link.matches('a[data-phx-link="patch"][href]')) {
    throw new Error("canonical HTML anchor is required")
  }

  vi.stubGlobal("Element", FakeElement)
  vi.stubGlobal("HTMLElement", FakeElement)
  vi.stubGlobal("HTMLLIElement", FakeHTMLLIElement)
  vi.stubGlobal("HTMLAnchorElement", FakeHTMLAnchorElement)
  vi.stubGlobal("document", {
    elementFromPoint: vi.fn(() => pointerHitTarget),
  })
  vi.stubGlobal("window", {
    matchMedia: () => ({matches: reducedMotion}),
    requestAnimationFrame: vi.fn(() => 1),
    cancelAnimationFrame: vi.fn(),
  })

  const state = {
    el: stage,
    cameraDriver: {
      animate: vi.fn((_target, options) => {
        const animation = {cancel: vi.fn()}
        animations.push({...animation, options})
        return animation
      }),
    },
  }
  TechtreeCamera.mounted.call(state as never)

  const pointerDown = (
    values: Partial<FakeEvent> = {},
    target: FakeElement = link,
  ) =>
    stage.emit(
      "pointerdown",
      fakeEvent(target, {
        pointerType: "mouse",
        button: 0,
        isPrimary: true,
        pointerId: 1,
        clientX: 140,
        clientY: 100,
        ...values,
      }),
    )
  const pointerUp = (
    values: Partial<FakeEvent> = {},
    target: FakeElement = stage,
  ) =>
    stage.emit(
      "pointerup",
      fakeEvent(target, {
        pointerId: 1,
        clientX: 140,
        clientY: 100,
        ...values,
      }),
    )
  const pointerCancel = (values: Partial<FakeEvent> = {}) =>
    stage.emit(
      "pointercancel",
      fakeEvent(stage, {
        pointerId: 1,
        clientX: 180,
        clientY: 140,
        ...values,
      }),
    )
  const losePointerCapture = (values: Partial<FakeEvent> = {}) =>
    stage.emit(
      "lostpointercapture",
      fakeEvent(stage, {pointerId: 1, ...values}),
    )

  return {
    animations,
    link,
    losePointerCapture,
    otherNode,
    node,
    pointerCancel,
    pointerDown,
    setPointerHitTarget(target: FakeElement | null) {
      pointerHitTarget = target
    },
    pointerUp,
    stage,
    state,
    world,
  }
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
  it("U1 canonical activation continues the canonical link exactly once for pointer, keyboard, and reduced motion", () => {
    for (const mode of [
      "recovered-pointer",
      "direct-pointer",
      "keyboard",
      "reduced",
      "cancel-keyboard",
    ] as const) {
      const {
        link,
        pointerCancel,
        pointerDown,
        pointerUp,
        setPointerHitTarget,
        stage,
        state,
      } = hookHarness(mode === "reduced")

      if (mode === "keyboard" || mode === "direct-pointer") {
        const directActivation = fakeEvent(link, {
          detail: mode === "keyboard" ? 0 : 1,
        })
        stage.emit("click", directActivation)

        expect(directActivation.defaultPrevented).toBe(false)
        expect(directActivation.propagationStopped).toBe(false)
        expect(stage.outboundNavigationEvents).toEqual([directActivation])
      } else if (mode === "cancel-keyboard") {
        pointerDown()
        pointerCancel()
        stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 1}))

        expect(stage.outboundNavigationCount).toBe(0)
        expect(link.clickCount).toBe(0)

        const keyboardActivation = fakeEvent(link, {detail: 0})
        stage.emit("click", keyboardActivation)

        expect(keyboardActivation.defaultPrevented).toBe(false)
        expect(keyboardActivation.propagationStopped).toBe(false)
      } else {
        pointerDown()
        setPointerHitTarget(link)
        pointerUp()
        stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 1}))
      }

      expect(stage.outboundNavigationCount, mode).toBe(1)
      expect(link.clickCount, mode).toBe(
        mode === "recovered-pointer" || mode === "reduced" ? 1 : 0,
      )
      TechtreeCamera.destroyed.call(state as never)
    }

    for (const modifier of ["metaKey", "ctrlKey", "shiftKey", "altKey"] as const) {
      const {animations, link, stage, state} = hookHarness()
      const animationCount = animations.length
      const activation = fakeEvent(link, {detail: 0, [modifier]: true})

      stage.emit("click", activation)

      expect(activation.preventDefault, modifier).not.toHaveBeenCalled()
      expect(activation.stopPropagation, modifier).not.toHaveBeenCalled()
      expect(stage.outboundNavigationEvents, modifier).toEqual([activation])
      expect(link.clickCount, modifier).toBe(0)
      expect(animations, modifier).toHaveLength(animationCount)
      TechtreeCamera.destroyed.call(state as never)
    }

    const {animations, link, stage, state} = hookHarness()
    const animationCount = animations.length
    const defaultPreventedActivation = fakeEvent(link, {
      detail: 0,
      defaultPrevented: true,
    })

    stage.emit("click", defaultPreventedActivation)

    expect(defaultPreventedActivation.preventDefault).not.toHaveBeenCalled()
    expect(defaultPreventedActivation.stopPropagation).not.toHaveBeenCalled()
    expect(stage.outboundNavigationCount).toBe(0)
    expect(link.clickCount).toBe(0)
    expect(animations).toHaveLength(animationCount)
    TechtreeCamera.destroyed.call(state as never)

    for (const {down, click, navigationCount} of [
      {down: {metaKey: true}, click: {metaKey: true}, navigationCount: 1},
      {down: {ctrlKey: true}, click: {ctrlKey: true}, navigationCount: 1},
      {down: {shiftKey: true}, click: {shiftKey: true}, navigationCount: 1},
      {down: {altKey: true}, click: {altKey: true}, navigationCount: 1},
      {
        down: {defaultPrevented: true},
        click: {defaultPrevented: true},
        navigationCount: 0,
      },
      {down: {isPrimary: false}, click: {}, navigationCount: 1},
      {down: {button: 1}, click: {}, navigationCount: 1},
    ]) {
      const {animations, link, pointerDown, pointerUp, stage, state} = hookHarness()
      const animationCount = animations.length
      const diagnostic = JSON.stringify(down)

      pointerDown(down)
      pointerUp()
      expect(animations, diagnostic).toHaveLength(animationCount)
      expect(animations.at(-1)?.cancel, diagnostic).not.toHaveBeenCalled()
      expect(stage.hasPointerCapture(1), diagnostic).toBe(false)
      const activation = fakeEvent(link, {detail: 1, pointerId: 1, ...click})
      stage.emit("click", activation)

      expect(activation.propagationStopped, diagnostic).toBe(false)
      expect(stage.outboundNavigationCount, diagnostic).toBe(navigationCount)
      expect(link.clickCount, diagnostic).toBe(0)
      TechtreeCamera.destroyed.call(state as never)
    }
  })

  it("U2 gesture separation rejects unresolved, displaced, and stale recovery while binding one pointer to its exact origin", () => {
    const {
      link,
      losePointerCapture,
      otherNode,
      pointerCancel,
      pointerDown,
      pointerUp,
      setPointerHitTarget,
      stage,
      state,
    } = hookHarness()
    pointerDown()
    stage.emit(
      "pointermove",
      fakeEvent(stage, {pointerId: 1, clientX: 180, clientY: 140}),
    )
    pointerUp()
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 1}))

    expect(link.clickCount).toBe(0)
    expect(stage.outboundNavigationCount).toBe(0)

    pointerDown({pointerId: 2})
    pointerUp({pointerId: 3})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 3}))
    expect(stage.outboundNavigationCount).toBe(0)
    pointerUp({pointerId: 2})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 3}))
    expect(stage.outboundNavigationCount).toBe(0)

    pointerDown({pointerId: 4, pointerType: "touch", isPrimary: true})
    pointerDown({pointerId: 5, pointerType: "touch", isPrimary: false})
    pointerUp({pointerId: 5})
    pointerUp({pointerId: 4})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 4}))
    expect(stage.outboundNavigationCount).toBe(0)

    pointerDown({pointerId: 6})
    pointerCancel({pointerId: 6})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 6}))
    expect(stage.outboundNavigationCount).toBe(0)

    pointerDown({pointerId: 7})
    losePointerCapture({pointerId: 7})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 7}))
    expect(stage.outboundNavigationCount).toBe(0)

    pointerDown({pointerId: 8})
    setPointerHitTarget(otherNode)
    pointerUp({pointerId: 8})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 8}))
    expect(stage.outboundNavigationCount).toBe(0)

    setPointerHitTarget(null)
    pointerDown({pointerId: 9})
    pointerUp({pointerId: 9})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 9}))
    expect(link.clickCount).toBe(0)
    expect(stage.outboundNavigationCount).toBe(0)

    pointerDown({pointerId: 10, clientX: -1, clientY: -1})
    pointerUp({pointerId: 10, clientX: -1, clientY: -1})
    stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 10}))
    expect(stage.outboundNavigationCount).toBe(0)
    TechtreeCamera.destroyed.call(state as never)

    for (const staleState of [
      "detached",
      "replaced",
      "noncanonical",
      "reparented",
    ] as const) {
      const stale = hookHarness()
      stale.pointerDown()
      stale.setPointerHitTarget(stale.link)
      stale.pointerUp()

      if (staleState === "detached" || staleState === "replaced") {
        stale.world.removeChild(stale.node)
      }
      if (staleState === "replaced") {
        const replacementNode = new FakeHTMLLIElement()
        const replacementLink = new FakeHTMLAnchorElement(stale.stage)
        replacementNode.dataset = {...stale.node.dataset}
        replacementLink.dataset = {...stale.link.dataset}
        replacementLink.href = stale.link.href
        replacementNode.append(replacementLink)
        stale.world.append(replacementNode)
      }
      if (staleState === "noncanonical") stale.link.href = null
      if (staleState === "reparented") {
        stale.node.removeChild(stale.link)
        stale.otherNode.append(stale.link)
      }

      stale.stage.emit("click", fakeEvent(stale.stage, {detail: 1, pointerId: 1}))
      expect(stale.link.clickCount, staleState).toBe(0)
      expect(stale.stage.outboundNavigationCount, staleState).toBe(0)
      TechtreeCamera.destroyed.call(stale.state as never)
    }
  })

  it("U3 motion independence continues the canonical link exactly once before animation settlement", () => {
    for (const outcome of ["completion", "interruption"] as const) {
      const {
        animations,
        link,
        pointerCancel,
        pointerDown,
        pointerUp,
        setPointerHitTarget,
        stage,
        state,
      } = hookHarness()
      pointerDown()
      setPointerHitTarget(link)
      pointerUp()
      stage.emit("click", fakeEvent(stage, {detail: 1, pointerId: 1}))

      expect(link.clickCount, outcome).toBe(1)
      expect(stage.outboundNavigationCount, outcome).toBe(1)
      const focusAnimation = animations.at(-1)
      expect(focusAnimation, outcome).toBeDefined()
      if (!focusAnimation) throw new Error("focus animation is required")
      expect(focusAnimation.options.duration, outcome).toBe(CAMERA_GLIDE_DURATION)
      const settle = focusAnimation.options.onComplete
      expect(settle, outcome).toEqual(expect.any(Function))
      if (!settle) throw new Error("focus animation settlement callback is required")

      if (outcome === "completion") {
        settle()
      } else {
        pointerDown()
        expect(focusAnimation.cancel, outcome).toHaveBeenCalledOnce()
        pointerCancel()
        settle()
      }

      expect(link.clickCount, outcome).toBe(1)
      expect(stage.outboundNavigationCount, outcome).toBe(1)
      TechtreeCamera.destroyed.call(state as never)
    }
  })
})
