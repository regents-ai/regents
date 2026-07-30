import {describe, expect, it, vi} from "vitest"

import {
  APP_ENTRY_DURATION,
  APP_EXIT_DURATION,
  CONTENT_ENTRY_DURATION,
  CONTENT_EXIT_DURATION,
  SURFACE_ENTRY_DURATION,
  SURFACE_EXIT_DURATION,
  SURFACE_STAGGER_DELAY,
  ShellMotion,
  createMotionController,
  type MotionAnimation,
  type MotionDriver,
} from "../js/hooks/motion"

const element = (left = 0) =>
  ({style: {}, dataset: {}, getBoundingClientRect: () => ({left, width: 20})}) as unknown as HTMLElement

const harness = () => {
  const animations: Array<MotionAnimation & {options: Record<string, unknown>}> = []
  const driver: MotionDriver = {
    animate: vi.fn((_target, options) => {
      const animation = {
        options,
        cancel: vi.fn(),
        seek: vi.fn(),
      }
      animations.push(animation)
      return animation
    }),
  }
  const scope = {revert: vi.fn()}
  const root = element()
  Object.defineProperty(root, "getBoundingClientRect", {value: () => ({left: 0, width: 100})})
  return {animations, driver, root, scope}
}

describe("shell motion", () => {
  it("renders a direct load immediately without fabricating travel", () => {
    const {animations, driver, root, scope} = harness()
    const incoming = element()
    const background = element()
    const controller = createMotionController(root, driver, () => scope)

    controller.transition({kind: "direct", incoming: [incoming], incomingBackground: background})

    expect(animations).toHaveLength(0)
    expect(incoming.style.opacity).toBe("1")
    expect(incoming.style.transform).toBe("none")
    expect(background.style.opacity).toBe("1")
  })

  it("cancels an interrupted app switch and lets the latest intent win from current styles", () => {
    const {animations, driver, root, scope} = harness()
    const oldRegion = element(0)
    const firstRegion = element(90)
    const latestRegion = element(10)
    const controller = createMotionController(root, driver, () => scope)

    const first = controller.transition({kind: "app", outgoing: [oldRegion], incoming: [firstRegion]})!
    first.seek(120)
    firstRegion.style.opacity = "0.4"
    firstRegion.style.transform = "translateX(4px)"
    controller.transition({kind: "app", outgoing: [firstRegion], incoming: [latestRegion]})

    expect(animations.slice(0, 2).every((animation) => vi.mocked(animation.cancel).mock.calls.length === 1)).toBe(true)
    expect(animations.slice(0, 2).every((animation) => vi.mocked(animation.seek).mock.calls[0][0] === 120)).toBe(true)
    expect(firstRegion.style.opacity).toBe("0.4")
    expect(firstRegion.style.transform).toBe("translateX(4px)")
  })

  it("uses bounded full-scene choreography with edge-first entry and background crossfade", () => {
    const {animations, driver, root, scope} = harness()
    const edge = element(0)
    const center = element(40)
    const oldBackground = element()
    const newBackground = element()
    const controller = createMotionController(root, driver, () => scope)

    controller.transition({
      kind: "app",
      outgoing: [element()],
      incoming: [edge, center],
      outgoingBackground: oldBackground,
      incomingBackground: newBackground,
    })

    const edgeOptions = animations[1].options
    const centerOptions = animations[2].options
    expect(animations[0].options).toMatchObject({
      duration: APP_EXIT_DURATION,
      ease: "inQuart",
    })
    expect(Number(edgeOptions.delay) + Number(edgeOptions.duration)).toBe(APP_ENTRY_DURATION)
    expect(Number(edgeOptions.delay)).toBeLessThan(Number(centerOptions.delay))
    expect(Number(centerOptions.delay) + Number(centerOptions.duration)).toBeLessThanOrEqual(
      APP_ENTRY_DURATION,
    )
    expect(edge.style.transform).toBe("translateX(-12px)")
    expect(animations.at(-2)?.options).toMatchObject({
      opacity: 0,
      duration: APP_EXIT_DURATION,
      ease: "inQuart",
    })
    expect(animations.at(-1)?.options).toMatchObject({
      opacity: 1,
      duration: APP_ENTRY_DURATION,
      ease: "outQuart",
    })
    expect([edgeOptions.ease, centerOptions.ease]).toEqual(["outQuart", "outQuart"])
  })

  it.each(["keyboard" as const, "reduced" as const])("makes %s navigation immediate and travel-free", (mode) => {
    const {animations, driver, root, scope} = harness()
    const incoming = element()
    const controller = createMotionController(root, driver, () => scope)

    controller.transition({
      kind: "app",
      source: mode === "keyboard" ? "keyboard" : "pointer",
      reducedMotion: mode === "reduced",
      incoming: [incoming],
    })

    expect(animations).toHaveLength(0)
    expect(incoming.style.transform).toBe("none")
  })

  it("keeps intra-app changes short and content-only", () => {
    const {animations, driver, root, scope} = harness()
    const controller = createMotionController(root, driver, () => scope)

    controller.transition({kind: "content", outgoing: [element()], incoming: [element()]})

    expect(animations).toHaveLength(2)
    expect(animations.map(({options}) => [options.duration, options.ease])).toEqual([
      [CONTENT_EXIT_DURATION, "inQuad"],
      [CONTENT_ENTRY_DURATION, "outQuad"],
    ])
    expect(animations.every(({options}) => !("translateX" in options) && !("translateY" in options))).toBe(true)
  })

  it("accelerates Techtree surfaces away and decelerates staggered entries into place", () => {
    const {animations, driver, root, scope} = harness()
    const outgoing = element()
    outgoing.dataset.motionSurface = "list-item"
    const first = element()
    first.dataset.motionSurface = "list-item"
    const second = element()
    second.dataset.motionSurface = "list-item"
    const detail = element()
    detail.dataset.motionSurface = "detail"
    const settled = vi.fn()
    const controller = createMotionController(root, driver, () => scope)

    controller.transition({
      kind: "content",
      incoming: [],
      outgoingSurfaces: [outgoing],
      incomingSurfaces: [first, second, detail],
      onSettled: settled,
    })

    expect(animations.map(({options}) => [options.duration, options.ease])).toEqual([
      [SURFACE_EXIT_DURATION, "inQuart"],
      [SURFACE_ENTRY_DURATION, "outQuart"],
      [SURFACE_ENTRY_DURATION, "outQuart"],
      [SURFACE_ENTRY_DURATION, "outQuart"],
    ])
    expect(animations.map(({options}) => options.delay)).toEqual([
      undefined,
      0,
      SURFACE_STAGGER_DELAY,
      0,
    ])
    expect(animations[0].options.translateY).toBe(6)
    expect(first.style.transform).toBe("translateY(6px)")
    expect(detail.style.transform).toBe("translateY(10px)")

    animations.slice(0, -1).forEach(({options}) => (options.onComplete as () => void)())
    expect(settled).not.toHaveBeenCalled()
    ;(animations.at(-1)?.options.onComplete as () => void)()
    expect(settled).toHaveBeenCalledOnce()
    expect(first.style).toMatchObject({opacity: "1", transform: "none"})
    expect(detail.style).toMatchObject({opacity: "1", transform: "none"})
  })

  it("runs marked Techtree entrances through the controller on mount", () => {
    const {animations, driver, root, scope} = harness()
    const listItem = element()
    listItem.dataset.motionSurface = "list-item"
    const detail = element()
    detail.dataset.motionSurface = "detail"
    root.querySelectorAll = vi.fn((selector: string) =>
      selector.includes("motion-surface") ? [listItem, detail] : [],
    ) as unknown as typeof root.querySelectorAll
    const state = {
      el: root,
      motionFactory: (motionRoot: HTMLElement) => createMotionController(motionRoot, driver, () => scope),
    }

    ShellMotion.mounted.call(state)

    expect(animations).toHaveLength(2)
    expect(animations.every(({options}) => options.ease === "outQuart")).toBe(true)
    ShellMotion.destroyed.call(state)
    expect(animations.every(({cancel}) => vi.mocked(cancel).mock.calls.length === 1)).toBe(true)
  })

  it("settles an empty patch without retaining a phantom active handle", () => {
    const {driver, root, scope} = harness()
    const settled = vi.fn()
    const controller = createMotionController(root, driver, () => scope)

    expect(controller.transition({kind: "content", incoming: [], onSettled: settled})).toBeNull()
    expect(controller.active).toBeNull()
    expect(settled).toHaveBeenCalledOnce()
  })

  it("cancels active work and reverts its scope on teardown", () => {
    const {animations, driver, root, scope} = harness()
    const controller = createMotionController(root, driver, () => scope)
    controller.transition({kind: "content", incoming: [element()]})

    controller.destroy()

    expect(animations[0].cancel).toHaveBeenCalledOnce()
    expect(scope.revert).toHaveBeenCalledOnce()
  })

  it("does not retain repeated transition animations in the lifecycle scope", () => {
    const {animations, driver, root, scope} = harness()
    const controller = createMotionController(root, driver, () => scope)

    for (let index = 0; index < 20; index += 1) {
      controller.transition({kind: "content", incoming: [element()]})
    }

    expect(animations).toHaveLength(20)
    expect(animations.slice(0, -1).every((animation) => vi.mocked(animation.cancel).mock.calls.length === 1)).toBe(true)
    expect(Object.keys(scope)).toEqual(["revert"])
  })

  it("settles exact destination styles and clears the current handle only for the latest completion", () => {
    const {animations, driver, root, scope} = harness()
    const stale = element()
    const latest = element()
    const controller = createMotionController(root, driver, () => scope)
    controller.transition({kind: "content", incoming: [stale]})
    controller.transition({kind: "content", outgoing: [stale], incoming: [latest]})

    ;(animations[0].options.onComplete as () => void)()
    expect(controller.active).not.toBeNull()
    ;(animations[1].options.onComplete as () => void)()
    ;(animations[2].options.onComplete as () => void)()

    expect(controller.active).toBeNull()
    expect(stale.style).toMatchObject({opacity: "0", transform: "none"})
    expect(latest.style).toMatchObject({opacity: "1", transform: "none"})
  })

  it("drives mount, patch classification, rapid cancellation, copy cleanup, and teardown by hook composition", () => {
    const removed: HTMLElement[] = []
    const node = (kind: "region" | "background" | "header", left = 0): HTMLElement => {
      const target = element(left) as HTMLElement & {kind: string}
      target.kind = kind
      target.cloneNode = () => {
        const copy = node(kind, left)
        copy.removeAttribute = vi.fn()
        copy.querySelectorAll = vi.fn(() => []) as unknown as typeof copy.querySelectorAll
        copy.setAttribute = vi.fn()
        copy.remove = () => removed.push(copy)
        return copy
      }
      return target
    }
    let current = [node("region", 10), node("background"), node("header")]
    const appended: HTMLElement[] = []
    const root = element() as HTMLElement & {current: HTMLElement[]}
    root.current = current
    root.dataset.motionApp = "formation"
    root.dataset.destination = "/formation"
    root.querySelectorAll = ((selector: string) => {
      if (selector.includes("surface")) return []
      const kind = selector.includes("background") ? "background" : selector.includes("header") ? "header" : "region"
      return root.current.filter((target) => (target as HTMLElement & {kind: string}).kind === kind)
    }) as unknown as typeof root.querySelectorAll
    root.querySelector = ((selector: string) => root.querySelectorAll(selector)[0] ?? null) as typeof root.querySelector
    root.append = ((...targets: HTMLElement[]) => appended.push(...targets)) as typeof root.append
    Object.defineProperty(root, "getBoundingClientRect", {value: () => ({left: 0, width: 100})})
    const {animations, driver, scope} = harness()
    const state = {
      el: root,
      motionFactory: (motionRoot: HTMLElement) => createMotionController(motionRoot, driver, () => scope),
    }

    ShellMotion.mounted.call(state)
    expect(animations).toHaveLength(0)
    ShellMotion.beforeUpdate.call(state)
    current = [node("region", 80), node("background"), node("header")]
    root.current = current
    root.dataset.motionApp = "autolaunch"
    root.dataset.destination = "/autolaunch"
    ShellMotion.updated.call(state)
    const firstCount = animations.length
    expect(firstCount).toBeGreaterThan(0)
    expect(appended.length).toBe(3)
    expect(appended.every((copy) => copy.inert && copy.dataset.motionCopy === "true")).toBe(true)
    expect(appended.every((copy) => vi.mocked(copy.setAttribute).mock.calls[0][0] === "aria-hidden")).toBe(true)

    ShellMotion.beforeUpdate.call(state)
    root.current = [node("region", 20), node("background"), node("header")]
    root.dataset.motionApp = "techtree"
    root.dataset.destination = "/techtree"
    ShellMotion.updated.call(state)
    expect(animations.slice(0, firstCount).every((animation) => vi.mocked(animation.cancel).mock.calls.length === 1)).toBe(true)
    expect(removed.length).toBe(3)

    ShellMotion.destroyed.call(state)
    expect(removed.length).toBe(6)
    expect(scope.revert).toHaveBeenCalledOnce()
  })

  it("settles same-app hook updates and removes every outgoing copy", () => {
    const removed: HTMLElement[] = []
    const node = (kind: "region" | "background" | "header"): HTMLElement => {
      const target = element() as HTMLElement & {kind: string}
      target.kind = kind
      target.cloneNode = () => {
        const copy = node(kind)
        copy.removeAttribute = vi.fn()
        copy.querySelectorAll = vi.fn(() => []) as unknown as typeof copy.querySelectorAll
        copy.setAttribute = vi.fn()
        copy.remove = () => removed.push(copy)
        return copy
      }
      return target
    }
    const root = element() as HTMLElement & {current: HTMLElement[]}
    root.current = [node("region"), node("background"), node("header")]
    root.dataset.motionApp = "formation"
    root.dataset.destination = "/formation"
    root.querySelectorAll = ((selector: string) => {
      if (selector.includes("surface")) return []
      const kind = selector.includes("background") ? "background" : selector.includes("header") ? "header" : "region"
      return root.current.filter((target) => (target as HTMLElement & {kind: string}).kind === kind)
    }) as unknown as typeof root.querySelectorAll
    root.querySelector = ((selector: string) => root.querySelectorAll(selector)[0] ?? null) as typeof root.querySelector
    root.append = vi.fn() as typeof root.append
    Object.defineProperty(root, "getBoundingClientRect", {value: () => ({left: 0, width: 100})})
    const {animations, driver, scope} = harness()
    const state = {
      el: root,
      motionFactory: (motionRoot: HTMLElement) => createMotionController(motionRoot, driver, () => scope),
    }

    ShellMotion.mounted.call(state)
    ShellMotion.beforeUpdate.call(state)
    root.current = [node("region"), node("background"), node("header")]
    ShellMotion.updated.call(state)
    expect(animations).toHaveLength(0)
    expect(root.append).not.toHaveBeenCalled()

    expect((state as typeof state & {motion?: ReturnType<typeof createMotionController>}).motion?.active).toBeNull()
    expect(removed).toHaveLength(0)
    ShellMotion.destroyed.call(state)
  })
})
