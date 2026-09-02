/**
 * The crown clears to the ground the page canvas is drawing.
 *
 * The two canvases draw one continuous field, so the colour the crown scene
 * clears to and the colour it hands its own copy of the field have to be the
 * palette that is showing right now, not the one that was showing when the scene
 * was built. Reading them from a constant looks identical in every other test.
 */

import {beforeEach, describe, expect, it, vi} from "vitest"

const recorded = vi.hoisted(() => ({passes: [] as Array<Record<string, unknown>>}))

vi.mock("vgpu", () => ({
  draw: vi.fn(() => ({compile: vi.fn(), set: vi.fn()})),
  effect: vi.fn(() => ({compile: vi.fn(), set: vi.fn()})),
  // A real frame runs its passes, so the recorder runs them too and keeps what each was asked for.
  frame: vi.fn((_gpu: unknown, body: (current: unknown) => void) =>
    body({
      pass: (options: Record<string, unknown>, draws: (pass: unknown) => void) => {
        recorded.passes.push(options)
        draws({draw: vi.fn()})
      },
    }),
  ),
  geometry: vi.fn(() => ({destroy: vi.fn(), write: vi.fn()})),
  sampler: vi.fn(() => ({})),
  target: vi.fn((_gpu: unknown, options: {size: readonly [number, number]}) => ({
    size: options.size,
    resize: vi.fn(),
  })),
}))

vi.mock("vgpu/scene", () => ({
  perspectiveCamera: vi.fn(() => ({viewProjection: new Float32Array(16)})),
}))

import {HERO_PALETTES, setHeroPalette, type HeroPaletteName} from "../js/home_field/palette"
import {createScene, destroyScene, prepareScene, presentScene} from "../js/home_prism/scene"

const OUTPUT = {size: [1280, 720] as const, format: "bgra8unorm"}

describe("the crown scene's ground", () => {
  beforeEach(() => {
    recorded.passes.length = 0
    setHeroPalette("rest")
  })

  it("is the palette that is showing, in every pass and in the field it draws", async () => {
    const scene = createScene({} as never, OUTPUT.size, "ground-test")
    await prepareScene(scene, OUTPUT as never)

    for (const name of ["rest", "autolaunch", "techtree", "patchbay"] as HeroPaletteName[]) {
      recorded.passes.length = 0
      setHeroPalette(name)
      presentScene(scene, OUTPUT as never)

      const ground = [...HERO_PALETTES[name].composedGround]
      // The three passes that compose the crown over the field; the bloom passes
      // clear to black and the presentation pass clears to nothing at all.
      expect(recorded.passes.slice(0, 3).map(pass => pass.clear)).toEqual([ground, ground, ground])
      expect(vi.mocked(scene.field.set).mock.lastCall![0]).toMatchObject({
        params: {groundColor: ground},
      })
    }

    destroyScene(scene)
  })
})
