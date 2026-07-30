import {describe, expect, it, vi} from "vitest"

import {
  CAMERA_ENTRY_DURATION,
  CAMERA_GLIDE_DURATION,
  CAMERA_RESET_DURATION,
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
