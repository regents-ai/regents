export type Vec2 = readonly [number, number];
export type Vec3 = readonly [number, number, number];

/**
 * Exact Regents mark, expressed as a 5-column grid.
 *
 * y grows upward in the prism scene. The top row occupies columns 0, 2 and 4;
 * the middle and bottom rows occupy all five columns.
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
] as const satisfies readonly Vec2[];

export const CROWN_CELL_COUNT = 13;

/** Front-face width and height of one cube, in the prism scene's world units. */
export const CROWN_CELL_SIZE = 0.22;
/** Air between adjacent cubes. This is about 11% of the cube face width. */
export const CROWN_GAP = 0.025;
export const CROWN_PITCH = CROWN_CELL_SIZE + CROWN_GAP;

/** A true shallow cube: depth equals front-face width. */
export const CROWN_DEPTH = CROWN_CELL_SIZE;
/** Same anti-z-fighting gap used by the VGPU prism scene. */
export const CROWN_WALL_GAP = 0.015;
export const CROWN_BACK_Z = CROWN_WALL_GAP;
export const CROWN_FRONT_Z = CROWN_WALL_GAP + CROWN_DEPTH;
export const CROWN_LIGHT_PLANE_Z = (CROWN_BACK_Z + CROWN_FRONT_Z) * 0.5;

/**
 * The visible mesh is rounded inward, while the optical shader uses the ideal
 * square envelope. This is the same visual-mesh/analytic-envelope split used by
 * the original triangle prism.
 */
export const CROWN_XY_CORNER_RADIUS = 0.018;
export const CROWN_Z_BEVEL_RADIUS = 0.014;
export const CROWN_CORNER_SEGMENTS = 4;
export const CROWN_Z_BEVEL_SEGMENTS = 4;

export const CROWN_CELL_CENTERS = CROWN_GRID.map(
  ([column, row]) => [column * CROWN_PITCH, row * CROWN_PITCH] as const,
);

export const CROWN_HALF_SIZE = CROWN_CELL_SIZE * 0.5;

export const CROWN_BOUNDS = {
  halfWidth: 2 * CROWN_PITCH + CROWN_HALF_SIZE,
  halfHeight: CROWN_PITCH + CROWN_HALF_SIZE,
} as const;

/** All eight corners used to fit the complete three-dimensional crown. */
export const CROWN_AABB_CORNERS = [CROWN_BACK_Z, CROWN_FRONT_Z].flatMap((z) =>
  [-CROWN_BOUNDS.halfHeight, CROWN_BOUNDS.halfHeight].flatMap((y) =>
    [-CROWN_BOUNDS.halfWidth, CROWN_BOUNDS.halfWidth].map(
      (x) => [x, y, z] as const,
    ),
  ),
) satisfies readonly Vec3[];

/** Vertical field of view and preferred distance from the reviewed predecessor. */
export const CAMERA_FOV_DEGREES = 70;
export const CAMERA_DISTANCE = 1.31;
export const CAMERA_YAW_DEGREES = 0;
export const CAMERA_PITCH_DEGREES = 0;
export const CAMERA_ORBIT_DEGREES = 3.5;
export const CAMERA_ORBIT_LERP = 0.08;
/** The beams are rebuilt on the CPU, so their aim moves in visible steps only. */
export const CROWN_AIM_QUANTIZATION_STEP = 1 / 64;

export interface CrownGlassMaterial {
  readonly ior: number;
  readonly reflectionStrength: number;
  readonly absorption: readonly [number, number, number];
  readonly frostRadius: number;
  readonly dispersion: number;
  readonly iridescenceStrength: number;
  readonly iridescenceFrequency: number;
  readonly environmentExposure: number;
  readonly environmentRotation: readonly [number, number, number];
}

/**
 * Reviewed prism material, tuned for the dark hero: the environment is turned
 * to graze the flat crown faces, absorption is close to neutral so the cubes
 * read as smoked glass rather than a colour, and the spectral film stays at the
 * faint titanium edge.
 */
export const CROWN_GLASS: CrownGlassMaterial = {
  ior: 1.244,
  reflectionStrength: 2.21,
  absorption: [0.45, 0.48, 0.52],
  frostRadius: 0.3,
  dispersion: 0.015,
  iridescenceStrength: 0.02,
  iridescenceFrequency: 2,
  environmentExposure: 1.25,
  environmentRotation: [0, -28, 0],
};

/** HDR operations: the beams and the lit glass edges bloom, the dark field does not. */
export const CROWN_POSTPROCESS = {
  bloomStrength: 0.85,
  bloomThreshold: 0.45,
  bloomRadius: 1,
} as const;

/** Falloff of a beam across its width and along its path. */
export const CROWN_LIGHT = {
  opacity: 1,
  edgeFalloff: 16,
  rainbowFalloffRate: 3.8,
  rainbowFalloffPower: 3.7,
} as const;

/**
 * The three lasers. They enter from the right of the crown, one per cube row,
 * and the pointer swings them within a narrow angle. The beams themselves are
 * white; only what the glass separates out of them carries colour.
 */
export const CROWN_BEAM = {
  angleBase: -0.065,
  angleRange: 0.075,
  rowConvergence: 0.032,
  verticalTravel: 0.11,
  dispersionStrength: 0.04,
  wedgeStrength: 0.14,
  spectralSamples: 20,
  beamHalfWidth: 0.044,
  spectralHalfWidth: 0.01,
  inputIntensity: 3.9,
  internalIntensity: 0.1,
  spectralIntensity: 0.72,
  inputColor: [1, 1, 1],
  internalColor: [1, 1, 1],
} as const satisfies {readonly inputColor: Vec3; readonly internalColor: Vec3} & Record<
  string,
  number | Vec3
>;

/** Snaps an aim to the grid the beam geometry is rebuilt on. */
export function quantizeCrownAim(aim: Vec2): Vec2 {
  const quantize = (value: number): number => {
    const clamped = Math.min(1, Math.max(-1, Number.isFinite(value) ? value : 0));
    return (
      Math.round(clamped / CROWN_AIM_QUANTIZATION_STEP) * CROWN_AIM_QUANTIZATION_STEP
    );
  };

  return [quantize(aim[0]), quantize(aim[1])];
}
