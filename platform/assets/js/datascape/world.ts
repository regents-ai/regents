/**
 * The datascape's world: an endless plane, in three layers of depth, cut into
 * square cells. What stands in a cell comes only from the cell's place, so
 * the same cell always holds the same panels, labels, dust and tube, however
 * often a visitor leaves it and comes back.
 */

/** A cell's side, in world units. One unit is one CSS pixel on the nearest layer. */
export const CELL = 520

/** The layers, farthest first. A far layer is drawn smaller, moves slower and is darker. */
export const LAYERS = [
  {depth: 0.42, light: 0.4},
  {depth: 0.66, light: 0.68},
  {depth: 1, light: 1},
] as const

export const KIND = {
  /** A block of coloured squares, a few of them changing. */
  mosaic: 0,
  /** Lines of text, scrolling. */
  text: 1,
  /** Colour bars over a row of black and white. */
  bars: 2,
  /** A soft gradient with cloud in it. */
  gradient: 3,
  /** A row of level bars that rise and fall. */
  meter: 4,
  /** Torn horizontal bands. */
  bands: 5,
  /** A grid of thin lines with a dot at each crossing. */
  lattice: 6,
  /** One small square. */
  dust: 7,
  /** A few words. */
  label: 8,
  /** A small outlined box with a cross in it. */
  mark: 9,
} as const

export type Kind = (typeof KIND)[keyof typeof KIND]

/** How a panel arrives: growing from its middle, opening sideways, or opening downwards. */
export const ENTRANCES = 3

export const TUBE_STYLE = {solid: 0, candy: 1, rainbow: 2, dotted: 3} as const

export type Colour = readonly [number, number, number]

export type PanelSeed = {
  readonly kind: Kind
  /** The middle, in world units. */
  readonly x: number
  readonly y: number
  /** Half the width and half the height. */
  readonly w: number
  readonly h: number
  /** A number of the panel's own, from 0 to 1. */
  readonly seed: number
  readonly a: Colour
  readonly b: Colour
  readonly alpha: number
  readonly entrance: number
  /** For text and labels: where in the atlas the words are (see `pageWindow` and `labelRect`). */
  readonly words: readonly [number, number, number, number]
}

/** One piece of a tube: a straight run, or the quarter turn between two runs. */
export type TubePiece =
  | {readonly turn: false; readonly x0: number; readonly y0: number; readonly x1: number; readonly y1: number; readonly from: number}
  | {
      readonly turn: true
      /** The middle of the turn's circle, its radius and the angle it starts at. */
      readonly x: number
      readonly y: number
      readonly radius: number
      readonly angle: number
      /** 1 turns clockwise on the page, -1 the other way. */
      readonly sweep: number
      readonly from: number
    }

export type TubeSeed = {
  readonly pieces: readonly TubePiece[]
  /** The whole length, along every piece. */
  readonly length: number
  readonly thickness: number
  readonly style: number
  readonly seed: number
  readonly a: Colour
  readonly b: Colour
}

export type CellSeed = {
  readonly panels: readonly PanelSeed[]
  readonly tube: TubeSeed | null
}

/**
 * The atlas the words are drawn into, once, on a canvas (see atlas.ts). Text
 * pages stand side by side at the top; the labels sit in rows under them.
 * Everything here is in atlas units, from 0 to 1.
 */
export const ATLAS = {
  /** World units along each side. */
  span: 1024,
  /** Texels along each side: two for each world unit, so words stay sharp on a dense screen. */
  texels: 2048,
  pages: 4,
  /** A page's width and height in world units. */
  pageWidth: 256,
  pageHeight: 768,
  labels: 12,
  labelColumns: 4,
  /** A label's box in world units. */
  labelWidth: 256,
  labelHeight: 24,
} as const

const UNIT = 1 / ATLAS.span

/** The words on each label. A label's box is as wide as its words are long. */
export const LABELS = [
  "SIGNAL 2/92",
  "NOISE 92/30",
  "DECODING",
  "SYNCING",
  "ID:9D2A-41BE",
  "SPARK_67",
  "SEQUENCE 024",
  "CH 07 OPEN",
  "TRACE 11/40",
  "BUFFER 88%",
  "LINK 3 UP",
  "FRAME 0412",
] as const

/** How wide one letter of a label is, as a share of the label's height. */
const LABEL_LETTER = 0.52

/** Where a label sits in the atlas: left, top, right, bottom. */
export const labelRect = (index: number): readonly [number, number, number, number] => {
  const column = index % ATLAS.labelColumns
  const row = Math.floor(index / ATLAS.labelColumns)
  const left = column * ATLAS.labelWidth * UNIT
  const top = (ATLAS.pageHeight + 8 + row * ATLAS.labelHeight) * UNIT
  const width = Math.min(ATLAS.labelWidth, LABELS[index]!.length * ATLAS.labelHeight * LABEL_LETTER + 8)
  return [left, top, left + width * UNIT, top + ATLAS.labelHeight * UNIT]
}

/** A small, fast random number source: the same seed always gives the same run. */
export const random = (seed: number) => {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let mixed = Math.imul(state ^ (state >>> 15), state | 1)
    mixed ^= mixed + Math.imul(mixed ^ (mixed >>> 7), mixed | 61)
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296
  }
}

/** One number for a cell of a layer, different for every neighbour. */
export const cellSeed = (layer: number, column: number, row: number) => {
  let mixed = Math.imul(column | 0, 0x1f123bb5) ^ Math.imul(row | 0, 0x5f356495) ^ Math.imul(layer + 1, 0x2545f491)
  mixed = Math.imul(mixed ^ (mixed >>> 15), 0x2c1b3c6d)
  mixed = Math.imul(mixed ^ (mixed >>> 12), 0x297a2d39)
  return (mixed ^ (mixed >>> 15)) >>> 0
}

const hex = (value: number): Colour => [((value >> 16) & 255) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255]

/** The colours a panel may take. */
const BRIGHT = [0xff3d8b, 0xff38d1, 0x29d8ff, 0x3d6bff, 0xa35cff, 0xff9a2e, 0xffd23d, 0x2fe0a0, 0x35f0e0].map(hex)
const QUIET = [0x1f8a8a, 0x2a3350, 0x4a2a66, 0x1b2430, 0x6a7386, 0x7c2f52].map(hex)
const PAPER = hex(0xf2f4ff)

/** How likely each kind of panel is, in parts of the whole. */
const PANEL_ODDS: readonly (readonly [Kind, number])[] = [
  [KIND.text, 24],
  [KIND.mosaic, 20],
  [KIND.gradient, 14],
  [KIND.bands, 14],
  [KIND.meter, 8],
  [KIND.lattice, 7],
  [KIND.mark, 7],
  [KIND.bars, 6],
]
const PANEL_ODDS_TOTAL = PANEL_ODDS.reduce((sum, [, odds]) => sum + odds, 0)

/** The corner a tube turns through is this wide, unless the runs beside it are too short for it. */
const TURN = 28

/** What stands in one cell of one layer. */
export function cellContents(layer: number, column: number, row: number): CellSeed {
  const next = random(cellSeed(layer, column, row))
  const between = (low: number, high: number) => low + (high - low) * next()
  const pick = <T>(from: readonly T[]): T => from[Math.floor(next() * from.length)]!
  const left = column * CELL
  const top = row * CELL
  const panels: PanelSeed[] = []

  const roll = next()
  const count = roll < 0.1 ? 0 : roll < 0.4 ? 1 : roll < 0.74 ? 2 : 3
  for (let index = 0; index < count; index++) {
    let chosen = next() * PANEL_ODDS_TOTAL
    const kind = PANEL_ODDS.find(([, odds]) => (chosen -= odds) < 0)![0]
    const [w, h] = sizeOf(kind, between)
    const a = kind === KIND.text ? (next() < 0.6 ? PAPER : pick(BRIGHT)) : pick(BRIGHT)
    const b = next() < 0.45 ? pick(QUIET) : pick(BRIGHT)
    const x = left + between(0.1, 0.9) * CELL
    const y = top + between(0.1, 0.9) * CELL
    const seed = next()
    panels.push({
      kind,
      x,
      y,
      w,
      h,
      seed,
      a,
      b,
      alpha: kind === KIND.gradient || kind === KIND.mosaic ? (next() < 0.3 ? between(0.45, 0.8) : 1) : 1,
      entrance: Math.floor(next() * ENTRANCES),
      words: kind === KIND.text ? pageWindow(Math.floor(next() * ATLAS.pages), w, h, next()) : [0, 0, 0, 0],
    })
    // A panel in three is named by a label at its top left corner.
    if (kind !== KIND.mark && next() < 0.34) {
      const label = Math.floor(next() * ATLAS.labels)
      const rect = labelRect(label)
      const height = 5
      const width = (height * (rect[2] - rect[0])) / (rect[3] - rect[1])
      panels.push({
        kind: KIND.label,
        x: x - w + width,
        y: y - h - height - 4,
        w: width,
        h: height,
        seed: next(),
        a: next() < 0.5 ? PAPER : a,
        b,
        alpha: 0.85,
        entrance: 1,
        words: rect,
      })
    }
  }

  const dust = 3 + Math.floor(next() * 5)
  for (let index = 0; index < dust; index++) {
    const size = between(1.2, 3.6)
    panels.push({
      kind: KIND.dust,
      x: left + next() * CELL,
      y: top + next() * CELL,
      w: size * (next() < 0.25 ? between(2, 6) : 1),
      h: size,
      seed: next(),
      a: next() < 0.3 ? PAPER : pick(BRIGHT),
      b: PAPER,
      alpha: between(0.6, 1),
      entrance: 0,
      words: [0, 0, 0, 0],
    })
  }

  return {panels, tube: next() < 0.3 ? tubeFrom(left + next() * CELL, top + next() * CELL, next, between, pick) : null}
}

function sizeOf(kind: Kind, between: (low: number, high: number) => number): [number, number] {
  switch (kind) {
    case KIND.text:
      return [between(50, 120), between(40, 170)]
    case KIND.mosaic: {
      const side = between(30, 115)
      return [side, side * between(0.75, 1.25)]
    }
    case KIND.bars:
      return [between(90, 140), between(70, 120)]
    case KIND.gradient:
      return [between(60, 170), between(40, 210)]
    case KIND.meter:
      return [between(50, 80), between(24, 42)]
    case KIND.bands:
      return [between(60, 200), between(18, 70)]
    case KIND.lattice: {
      const side = between(40, 76)
      return [side, side]
    }
    default: {
      const side = between(10, 18)
      return [side, side]
    }
  }
}

/**
 * The part of a text page a panel shows, as the page's index, the share of
 * its width and of its height the panel covers, and where down the page it
 * starts. A panel never stretches the words: it shows more or less of them.
 */
function pageWindow(page: number, w: number, h: number, start: number): readonly [number, number, number, number] {
  return [page, Math.min(1, (2 * w) / ATLAS.pageWidth), Math.min(1, (2 * h) / ATLAS.pageHeight), start]
}

/** A tube: a few runs, each at a right angle to the last, with a rounded turn between them. */
function tubeFrom(
  startX: number,
  startY: number,
  next: () => number,
  between: (low: number, high: number) => number,
  pick: <T>(from: readonly T[]) => T,
): TubeSeed {
  const runs = 2 + Math.floor(next() * 3)
  const thickness = pick([1.5, 1.5, 4, 7, 11])
  let across = next() < 0.5
  // Each run as a direction and a length; a run goes along the page, the next one up or down it.
  const legs = Array.from({length: runs}, () => {
    const leg = {dx: across ? (next() < 0.5 ? -1 : 1) : 0, dy: across ? 0 : next() < 0.5 ? -1 : 1, length: between(90, 380)}
    across = !across
    return leg
  })

  const pieces: TubePiece[] = []
  let x = startX
  let y = startY
  let along = 0
  let cutBefore = 0
  for (const [index, leg] of legs.entries()) {
    const after = legs[index + 1]
    const radius = after ? Math.min(TURN, leg.length / 2, after.length / 2) : 0
    const run = leg.length - cutBefore - radius
    const endX = x + leg.dx * run
    const endY = y + leg.dy * run
    pieces.push({turn: false, x0: x, y0: y, x1: endX, y1: endY, from: along})
    along += run
    if (!after) break
    // The turn's circle sits inside the corner: one radius on from the run's end, towards the next run.
    const middleX = endX + after.dx * radius
    const middleY = endY + after.dy * radius
    const sweep = leg.dx * after.dy - leg.dy * after.dx
    pieces.push({
      turn: true,
      x: middleX,
      y: middleY,
      radius,
      angle: Math.atan2(endY - middleY, endX - middleX),
      sweep,
      from: along,
    })
    along += (Math.PI / 2) * radius
    x = middleX + leg.dx * radius
    y = middleY + leg.dy * radius
    cutBefore = radius
  }

  return {
    pieces,
    length: along,
    thickness,
    style: thickness < 2 ? pick([TUBE_STYLE.solid, TUBE_STYLE.dotted]) : pick([TUBE_STYLE.solid, TUBE_STYLE.candy, TUBE_STYLE.candy, TUBE_STYLE.rainbow]),
    seed: next(),
    a: pick(BRIGHT),
    b: next() < 0.5 ? PAPER : pick(BRIGHT),
  }
}
