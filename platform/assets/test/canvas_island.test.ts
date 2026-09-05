import {describe, expect, it} from "vitest"

import {
  MAX_DEVICE_PIXEL_RATIO,
  MAX_DRAWING_BUFFER_PIXELS,
  drawingBufferSize,
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
