// The datascape's rules that must hold wherever the camera flies: a place always
// holds the same things, a tube's pieces join end to end, the camera rests near
// the middle and never outruns its top speed, and the cells kept are the cells
// in reach.
import {describe, expect, it} from "vitest"
import {REST, SPEED, calmAround, createField, steerSpeed, topSpeed, type Field, type Panel} from "../js/datascape/field"
import {CELL, LAYERS, cellContents, random, type TubePiece} from "../js/datascape/world"
import {LEAVING} from "../js/hooks/datascape"

/** A few hundred cells scattered far and wide, the same ones every run. */
const cells = (() => {
  const next = random(20261110)
  return Array.from({length: 400}, () => ({
    layer: Math.floor(next() * LAYERS.length),
    column: Math.floor((next() - 0.5) * 20000),
    row: Math.floor((next() - 0.5) * 20000),
  }))
})()

/** Where a piece starts and ends, and how long it is. */
const span = (piece: TubePiece) => {
  if (!piece.turn) {
    return {start: [piece.x0, piece.y0], end: [piece.x1, piece.y1], length: Math.hypot(piece.x1 - piece.x0, piece.y1 - piece.y0)}
  }
  const at = (angle: number) => [piece.x + Math.cos(angle) * piece.radius, piece.y + Math.sin(angle) * piece.radius]
  return {start: at(piece.angle), end: at(piece.angle + (piece.sweep * Math.PI) / 2), length: (Math.PI / 2) * piece.radius}
}

describe("the world", () => {
  it("holds the same things in the same cell every time", () => {
    for (const {layer, column, row} of cells) {
      expect(cellContents(layer, column, row)).toEqual(cellContents(layer, column, row))
    }
  })

  it("joins a tube's pieces end to end, each starting at the length before it", () => {
    const tubes = cells.flatMap(({layer, column, row}) => cellContents(layer, column, row).tube ?? [])
    expect(tubes.length).toBeGreaterThan(50)
    for (const tube of tubes) {
      let along = 0
      let end: number[] | undefined
      for (const piece of tube.pieces) {
        const {start, end: next, length} = span(piece)
        expect(piece.from).toBeCloseTo(along, 6)
        if (end) {
          expect(start[0]).toBeCloseTo(end[0]!, 6)
          expect(start[1]).toBeCloseTo(end[1]!, 6)
        }
        expect(length).toBeGreaterThanOrEqual(0)
        along += length
        end = next
      }
      expect(tube.length).toBeCloseTo(along, 6)
    }
  })
})

describe("steering", () => {
  it("rests near the middle, never passes top speed, and goes the way the pointer is", () => {
    for (const [width, height] of [[320, 384], [390, 588], [1280, 644], [3840, 1024]] as const) {
      const top = topSpeed(width, height)
      expect(top).toBeGreaterThan(0)
      expect(top).toBeLessThanOrEqual(SPEED)
      let last = 0
      for (let offset = 0; offset <= 1.5; offset += 0.01) {
        const speed = steerSpeed(offset, top)
        expect(speed).toBeGreaterThanOrEqual(last)
        expect(speed).toBeLessThanOrEqual(top)
        expect(steerSpeed(-offset, top)).toBeCloseTo(-speed, 9)
        last = speed
      }
      expect(steerSpeed(0.05, top)).toBe(0)
      expect(steerSpeed(1, top)).toBe(top)
    }
  })

  it("steers nothing inside a calm zone, and reaches top speed at the edge outside it", () => {
    const top = topSpeed(1440, 900)
    for (const calm of [0, 0.1, 0.35, 0.53, 0.8, 0.9]) {
      let last = 0
      for (let offset = 0; offset <= 1; offset += 0.01) {
        const speed = steerSpeed(offset, top, calm)
        if (offset <= calm) expect(speed, `${calm} at ${offset}`).toBe(0)
        expect(speed).toBeGreaterThanOrEqual(last)
        last = speed
      }
      expect(steerSpeed(1, top, calm)).toBe(top)
      expect(steerSpeed(-1, top, calm)).toBe(-top)
    }
  })

  it("keeps the default calm zone when none is given", () => {
    const top = topSpeed(1280, 720)
    for (let offset = -1; offset <= 1; offset += 0.05) {
      expect(steerSpeed(offset, top)).toBe(steerSpeed(offset, top, 0.1))
    }
  })

  it("always leaves room to steer, however large the calm zone", () => {
    const top = topSpeed(390, 844)
    for (const calm of [0.95, 1, 1.4, 12]) {
      expect(steerSpeed(0.99, top, calm)).toBeGreaterThan(0)
      expect(steerSpeed(1, top, calm)).toBe(top)
    }
  })

  it("measures a calm zone round a box centred in the picture", () => {
    expect(calmAround([704, 600], 28, [1440, 900])).toEqual([380 / 720, 328 / 450])
    expect(calmAround([0, 0], 0, [1440, 900])).toEqual([0, 0])
  })
})

describe("telling whoever watches about steering", () => {
  const [width, height] = [1440, 900]
  const steered = (calm?: [number, number]) => {
    const told: boolean[] = []
    const field = createField({open: () => {}, draw: () => {}, leave: () => {}, rest: () => {}, steer: steering => void told.push(steering)})
    if (calm) field.calm = calm
    const at = (pointer: [number, number] | null) => {
      field.pointer = pointer
      field.advance(1 / 60, width, height)
      field.advance(1 / 60, width, height)
    }
    return {field, told, at}
  }

  it("says nothing while the pointer stays inside the calm zone on either axis, or is away", () => {
    const {told, at} = steered([0.5, 0.7])
    at(null)
    at([0, 0])
    at([0.49 * width / 2, 0])
    at([0, -0.69 * height / 2])
    at([0.49 * width / 2, 0.69 * height / 2])
    expect(told).toEqual([])
  })

  it("is told once on leaving the zone, once on coming back, and never again for the same answer", () => {
    const {told, at} = steered([0.5, 0.7])
    at([0.6 * width / 2, 0])
    at([0.9 * width / 2, 0])
    at([0, 0.8 * height / 2])
    expect(told).toEqual([true])
    at([0.2 * width / 2, 0])
    at([0, 0])
    expect(told).toEqual([true, false])
  })

  it("is told once when the pointer goes away while steering", () => {
    const {told, at} = steered()
    at([width / 2 - 6, 0])
    at(null)
    at(null)
    expect(told).toEqual([true, false])
  })

  it("steers nothing within LEAVING of an open glass panel's edges, and everywhere past the field's own zone once it is away", () => {
    const box: [number, number] = [704, 600]
    const told: boolean[] = []
    const field = createField({open: () => {}, draw: () => {}, leave: () => {}, rest: () => {}, steer: steering => void told.push(steering)})
    const at = (x: number) => {
      field.pointer = [x, 0]
      for (let step = 0; step < 3; step++) field.advance(1 / 60, width, height)
    }

    // As the hook does while the panel is open.
    field.calm = calmAround(box, LEAVING, [width, height])
    at(box[0] / 2 + LEAVING - 1)
    expect(told).toEqual([])
    at(box[0] / 2 + LEAVING + 1)
    expect(told).toEqual([true])

    // And once it is away: the panel's place steers like the rest of the picture.
    field.calm = [REST, REST]
    at(0)
    expect(told).toEqual([true, false])
    at(box[0] / 2 - 1)
    expect(told).toEqual([true, false, true])
  })
})

describe("the field", () => {
  const [width, height] = [1280, 720]
  /** Whether the picture shows where a panel is: the field's own rule, with its allowance for the lean. */
  const inSight = (field: Field, panel: Panel) => {
    const scale = LAYERS[panel.layer]!.depth * field.camera.zoom
    return (
      Math.abs(panel.x - field.camera.x) <= (width / 2 / scale) * 1.06 + panel.w &&
      Math.abs(panel.y - field.camera.y) <= (height / 2 / scale) * 1.06 + panel.h
    )
  }
  const watched = () => {
    const opened = new Set<Panel>()
    const field: Field = createField({
      open: panel => {
        // Told once, and only once the picture shows it.
        expect(opened.has(panel)).toBe(false)
        expect(inSight(field, panel)).toBe(true)
        opened.add(panel)
      },
      draw: tube => {
        expect(tube.seen).toBe(true)
      },
      leave: cell => {
        for (const panel of cell.panels) opened.delete(panel)
      },
      rest: () => {},
      steer: () => {},
    })
    return {field, opened}
  }

  it("flies towards the edge the pointer is at, bringing cells in and letting them go", () => {
    const {field, opened} = watched()
    field.advance(0, width, height)
    const first = new Set(field.cells.keys())
    expect(first.size).toBeGreaterThan(0)
    expect(opened.size).toBeGreaterThan(0)

    field.pointer = [width / 2, 0]
    for (let step = 0; step < 600; step++) field.advance(1 / 60, width, height)
    expect(field.camera.x).toBeGreaterThan(5 * CELL)
    expect(Math.abs(field.camera.y)).toBeLessThan(1)
    expect(Math.hypot(field.camera.vx, field.camera.vy)).toBeLessThanOrEqual(topSpeed(width, height))

    // The first cells are long gone, and whoever watches was told when each went: every panel still open is in a cell the field holds.
    for (const key of first) expect(field.cells.has(key)).toBe(false)
    const held = new Set([...field.cells.values()].flatMap(cell => cell.panels))
    for (const panel of opened) expect(held.has(panel)).toBe(true)
    // Every cell the picture shows is there.
    for (const [layer, {depth}] of LAYERS.entries()) {
      const scale = depth * field.camera.zoom
      const column = Math.floor((field.camera.x + width / 2 / scale) / CELL)
      const row = Math.floor((field.camera.y - height / 2 / scale) / CELL)
      expect(field.cells.has(`${layer}:${column}:${row}`)).toBe(true)
    }
  })

  it("opens each panel as the picture comes to show it, never before", () => {
    const {field, opened} = watched()
    field.advance(0, width, height)
    field.pointer = [width / 2, 0]
    let ahead = 0
    for (let step = 0; step < 300; step++) {
      field.advance(1 / 60, width, height)
      for (const cell of field.cells.values()) {
        for (const panel of cell.panels) {
          // Whatever the picture shows has been told to open; a panel brought in ahead of it waits, unopened.
          if (inSight(field, panel)) expect(opened.has(panel)).toBe(true)
          if (!opened.has(panel)) {
            expect(panel.seen).toBe(false)
            ahead += 1
          }
        }
      }
    }
    expect(ahead).toBeGreaterThan(0)
  })

  it("finds the panel under the pointer once it has opened, and tells whoever watches", () => {
    const rested: (string | null)[] = []
    const field = createField({
      open: () => {},
      draw: () => {},
      leave: () => {},
      rest: panel => void rested.push(panel && `${panel.x}:${panel.y}`),
      steer: () => {},
    })
    field.advance(0, 1280, 720)
    const near = LAYERS.length - 1
    const panel = [...field.cells.values()].filter(cell => cell.layer === near).flatMap(cell => cell.panels).find(each => each.w > 20)!
    const point: [number, number] = [panel.x - field.camera.x, panel.y - field.camera.y]

    expect(field.panelAt(...point)).toBeNull()
    panel.grow = 1
    expect(field.panelAt(...point)).toBe(panel)

    field.pointer = point
    field.advance(0, 1280, 720)
    field.pointer = null
    field.advance(0, 1280, 720)
    expect(rested).toEqual([`${panel.x}:${panel.y}`, null])
  })
})
