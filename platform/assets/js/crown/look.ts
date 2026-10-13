/**
 * What a site says about its crown, and the crown's own fixed shape.
 *
 * The 13 glass cubes, the way light is traced through them and the passes that
 * draw them are the same on every site. A site chooses a look: how large the
 * crown is and where it sits, what the glass is like, how the beams are aimed
 * and coloured, and what is drawn behind it.
 */

export type Vec2 = readonly [number, number]
export type Vec3 = readonly [number, number, number]
export type Rgba = readonly [number, number, number, number]

/**
 * The Regents mark on a five-column grid. y grows upward: the top row holds
 * columns 0, 2 and 4, the middle and bottom rows hold all five.
 */
export const CROWN_GRID = [
  [-2, 1],
  [0, 1],
  [2, 1],

  [-2, 0],
  [-1, 0],
  [0, 0],
  [1, 0],
  [2, 0],

  [-2, -1],
  [-1, -1],
  [0, -1],
  [1, -1],
  [2, -1],
] as const satisfies readonly Vec2[]

/** How far the pointer may swing the camera, and how quickly it follows. */
export const CAMERA_FOV_DEGREES = 70
export const CAMERA_ORBIT_DEGREES = 3.5
export const CAMERA_ORBIT_LERP = 0.08
/** The beams are rebuilt on the processor, so their aim moves in visible steps only. */
export const CROWN_AIM_STEP = 1 / 64

/** Falloff of a beam across its width and along its path. */
export const CROWN_LIGHT = {
  opacity: 1,
  edgeFalloff: 16,
  rainbowFalloffRate: 3.8,
  rainbowFalloffPower: 3.7,
} as const

/** Every length of the crown, in the scene's units, for one scale. */
export interface CrownShape {
  /** Front-face width and height of one cube. */
  readonly cellSize: number
  /** Distance between the centres of neighbouring cubes. */
  readonly pitch: number
  readonly halfSize: number
  readonly backZ: number
  readonly frontZ: number
  /** The plane the beams are drawn in, halfway through the glass. */
  readonly lightPlaneZ: number
  /** The visible mesh is rounded inward; the optics use the ideal square. */
  readonly cornerRadius: number
  readonly bevelRadius: number
  readonly cellCenters: readonly Vec2[]
  /** All eight corners of the box the whole crown fits in. */
  readonly corners: readonly Vec3[]
}

/** The gap that keeps the back of the glass off the wall behind it. */
const WALL_GAP = 0.015

export function crownShape(scale: number): CrownShape {
  const cellSize = 0.22 * scale
  // Air between neighbouring cubes: about 11% of a cube's face.
  const pitch = cellSize + 0.025 * scale
  const halfSize = cellSize * 0.5
  const backZ = WALL_GAP
  // A true shallow cube: as deep as its face is wide.
  const frontZ = WALL_GAP + cellSize
  const halfWidth = 2 * pitch + halfSize
  const halfHeight = pitch + halfSize
  return {
    cellSize,
    pitch,
    halfSize,
    backZ,
    frontZ,
    lightPlaneZ: (backZ + frontZ) * 0.5,
    cornerRadius: 0.018 * scale,
    bevelRadius: 0.014 * scale,
    cellCenters: CROWN_GRID.map(([column, row]) => [column * pitch, row * pitch] as const),
    corners: [backZ, frontZ].flatMap(z =>
      [-halfHeight, halfHeight].flatMap(y => [-halfWidth, halfWidth].map(x => [x, y, z] as const)),
    ),
  }
}

/** How far the crown may be moved each way before it crosses the margin kept clear. */
export interface CrownRoom {
  readonly left: number
  readonly right: number
  readonly down: number
  readonly up: number
}

export interface CrownFraming {
  /** 1 is the full-size hero crown. */
  readonly scale: number
  /** The closest the camera comes; it steps back further when the canvas needs it. */
  readonly distance: number
  /** The share of each screen dimension kept clear around the crown. */
  readonly margin: number
  /**
   * Where the crown sits, as a move away from the middle of the canvas: one unit
   * is half the canvas, right and up are positive. `room` is how far it can go.
   */
  place(aspect: number, room: CrownRoom): Vec2
}

export interface CrownGlass {
  readonly ior: number
  readonly reflectionStrength: number
  readonly absorption: Vec3
  readonly frostRadius: number
  readonly dispersion: number
  readonly iridescenceStrength: number
  readonly iridescenceFrequency: number
  readonly environmentExposure: number
  /** How the studio the glass reflects is turned, in degrees about x, y and z. */
  readonly environmentRotation: Vec3
}

export interface CrownBloom {
  readonly strength: number
  readonly threshold: number
  readonly radius: number
}

/** The three beams, one for each row of cubes: their shape and their strength. */
export interface CrownBeams {
  /** The side the beams enter from: 1 is the right of the crown, -1 the left. */
  readonly side: 1 | -1
  /** How far above its row each beam is aimed. */
  readonly lift: number
  readonly angleBase: number
  readonly angleRange: number
  readonly rowConvergence: number
  readonly verticalTravel: number
  readonly dispersionStrength: number
  readonly wedgeStrength: number
  readonly spectralSamples: number
  readonly halfWidth: number
  readonly spectralHalfWidth: number
  readonly inputIntensity: number
  readonly internalIntensity: number
  readonly spectralIntensity: number
}

export interface CrownBeamColors {
  /** The beam on its way to the glass. */
  readonly input: Vec3
  /** The faint path inside the glass. */
  readonly internal: Vec3
  /** The light that leaves the glass. */
  readonly fan: Vec3
  /** True when the glass fans the light into its colours, each tinted by `fan`. */
  readonly spectrum: boolean
}

/** One colour for the whole beam, fanned into a spectrum by the glass. */
export const beamOf = (color: Vec3): CrownBeamColors => ({
  input: color,
  internal: color,
  fan: color,
  spectrum: true,
})

/** What is drawn behind the crown: one full-canvas pass the site supplies. */
export interface CrownBackdrop {
  readonly wgsl: string
  /**
   * Read for every frame: the colour the scene clears to, and the values the
   * pass is given, so a page whose ground changes never disagrees with its crown.
   */
  frame(resolution: Vec2): {readonly clear: Rgba; readonly set: Record<string, unknown>}
}

/** Everything about a look that can change while the crown is on screen. */
export interface CrownStyle {
  readonly glass: CrownGlass
  readonly bloom: CrownBloom
  readonly beams: CrownBeams
  readonly colors: CrownBeamColors
}

/** A site's whole crown. Its size, its place and its backdrop pass are fixed once drawn. */
export interface CrownLook extends CrownStyle {
  readonly framing: CrownFraming
  readonly backdrop: CrownBackdrop
}

/** Snaps an aim to the grid the beam geometry is rebuilt on. */
export function quantizeCrownAim(aim: Vec2): Vec2 {
  const quantize = (value: number): number => {
    const clamped = Math.min(1, Math.max(-1, Number.isFinite(value) ? value : 0))
    return Math.round(clamped / CROWN_AIM_STEP) * CROWN_AIM_STEP
  }
  return [quantize(aim[0]), quantize(aim[1])]
}
