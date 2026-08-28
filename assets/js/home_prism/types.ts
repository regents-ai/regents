/**
 * Scene definition, forked from the Vercel vgpu prism background at
 * `bd3b05101fdd1193a1593558d3c52a0b2b18f31d`. See THIRD_PARTY_NOTICES.md.
 *
 * The room is three-dimensional and the light transport is not, which is the whole
 * trick. `z = 0` is the wall: a flat plane facing the camera, `x` growing right and
 * `y` growing up, centred on the origin and sized by `camera.ts` to cover whatever
 * the frame can see of it. The CPU solves the spectral ray bundle in that plane —
 * enter one face, cross the glass, leave through another — and turns its finite
 * width into additive, wavelength-connected mesh sheets. The glass the camera sees
 * is that same triangle extruded towards the viewer by `PRISM_DEPTH`.
 *
 * So the triangle below is read twice: as the two-dimensional obstacle the ray
 * bundle refracts through, and as the cross-section of the three-dimensional prism.
 * One set of vertices, which is what keeps the rainbow registered with the object
 * that made it.
 *
 * Upstream exposed every value below through a debug control panel. This fork has no
 * panel, so the upstream defaults are the constants.
 */

export type Vec2 = readonly [number, number]

export interface Triangle {
  readonly a: Vec2
  readonly b: Vec2
  readonly c: Vec2
}

export interface CollimatedLight {
  /** Emitter center, in scene units. */
  readonly center: Vec2
  /** Unit direction the beam is aimed in. */
  readonly direction: Vec2
  /** Half the physical width of the collimated beam, perpendicular to its axis. */
  readonly beamHalfWidth: number
}

export interface DispersionPreset {
  readonly base: number
  readonly strength: number
}

/**
 * Cauchy dispersion, `n(l) = base + strength / l^2` with `l` in micrometres.
 *
 * Real crown and flint glass open a 400-700nm fan by 1.6 and 7.3 degrees through a
 * prism this size — a colored edge, not a rainbow. Upstream's `stylized` preset
 * keeps the geometry and only widens `strength`, opening the fan to 16 degrees.
 */
export const PRISM_DISPERSION: DispersionPreset = {base: 1.47, strength: 0.035}

/** Full beam width in scene units, measured perpendicular to its axis. */
export const PRISM_BEAM_WIDTH = 0.01

/** Exponential concentration from the beam centre toward its side edges. */
export const PRISM_EDGE_FALLOFF = 16
/** Exponential attenuation applied only to the dispersed outgoing light. */
export const PRISM_RAINBOW_FALLOFF = 8

/** Vertical field of view of the camera looking at the wall, in degrees. */
export const CAMERA_FOV_DEGREES = 70
/** How far the camera sits from the wall, in scene units. */
export const CAMERA_DISTANCE = 1.31

export interface GlassMaterial {
  /** Index of refraction used by both rasterized glass interfaces. */
  readonly ior: number
  /** Multiplier on the studio environment before it is reflected. */
  readonly reflectionStrength: number
  /** Beer-Lambert absorption per scene unit, in linear RGB. */
  readonly absorption: readonly [number, number, number]
  /** Screen-space blur radius of the transmitted image, in pixels. */
  readonly frostRadius: number
  /** Red/blue separation of the refracted lookup. */
  readonly dispersion: number
  /** Strength of the angle-dependent spectral tint on reflections. */
  readonly iridescenceStrength: number
  /** Spectral tint cycles across the Fresnel range. */
  readonly iridescenceFrequency: number
  /** Exposure applied to the studio environment before material response. */
  readonly environmentExposure: number
  /** XYZ rotation of the studio environment, in degrees. */
  readonly environmentRotation: readonly [number, number, number]
}

export const PRISM_GLASS: GlassMaterial = {
  ior: 1.244,
  reflectionStrength: 2.21,
  absorption: [0.58, 0.685, 0.15],
  frostRadius: 0.3,
  dispersion: 0.015,
  iridescenceStrength: 0.16,
  iridescenceFrequency: 2,
  environmentExposure: 1.55,
  environmentRotation: [0, 0, 0],
}

/** HDR operations performed after both glass interfaces. */
export const PRISM_POSTPROCESS = {
  bloomStrength: 0.6,
  bloomThreshold: 0.45,
  bloomRadius: 1,
} as const

const radians = (degrees: number): number => (degrees * Math.PI) / 180

const rotate = (point: Vec2, angle: number): Vec2 => [
  point[0] * Math.cos(angle) - point[1] * Math.sin(angle),
  point[0] * Math.sin(angle) + point[1] * Math.cos(angle),
]

/** Side length of the equilateral prism, in scene units. */
export const PRISM_SIDE = 0.57

/**
 * Equilateral prism, apex up, wound counter-clockwise.
 *
 * The winding matters: `optics.ts` takes each edge's outward normal to be
 * `(edge.y, -edge.x)`, which only points out of the triangle for counter-clockwise
 * vertices.
 */
export const PRISM_TRIANGLE: Triangle = (() => {
  const circumradius = PRISM_SIDE / Math.sqrt(3)
  const vertex = (degrees: number): Vec2 => rotate([circumradius, 0], radians(degrees))
  return {a: vertex(90), b: vertex(210), c: vertex(330)}
})()

/** Point along the entry edge, ordered left-to-right as it appears on screen. */
function prismEntryPoint(position: number): Vec2 {
  const clamped = Math.min(1, Math.max(0, position))
  return [
    PRISM_TRIANGLE.a[0] + (PRISM_TRIANGLE.c[0] - PRISM_TRIANGLE.a[0]) * clamped,
    PRISM_TRIANGLE.a[1] + (PRISM_TRIANGLE.c[1] - PRISM_TRIANGLE.a[1]) * clamped,
  ]
}

/**
 * How far outside the frame the lamp sits — and the reason there is a rainbow at all.
 *
 * Dispersion spreads this glass by about 16 degrees, so any blur wider than that
 * washes the fan back to white, and a nearby lamp is exactly that blur. At 6.5 units
 * the beam is collimated to 1.3 degrees per wavelength and the colors separate.
 */
export const PRISM_LAMP_DISTANCE = 6.5

/**
 * The arc the pointer can swing the lamp along, in degrees of incidence.
 *
 * A 60-degree apex forces the two internal angles to sum to 60, so a beam entering
 * too straight-on meets the exit face past the critical angle and leaves through the
 * base instead. The default 50 degrees keeps the whole spectrum on the exit face.
 * The negative minimum deliberately lets a high pointer send the beam steeply down.
 */
export const PRISM_INCIDENCE_ARC = {min: -35, max: 75} as const
export const PRISM_INCIDENCE_DEGREES = 50

/** Where `PRISM_INCIDENCE_DEGREES` sits on `PRISM_INCIDENCE_ARC`, in [0, 1]. */
export const PRISM_DEFAULT_ARC =
  (PRISM_INCIDENCE_DEGREES - PRISM_INCIDENCE_ARC.min) /
  (PRISM_INCIDENCE_ARC.max - PRISM_INCIDENCE_ARC.min)

/** A finite collimated beam emitted from one point and aimed at another. */
function collimatedLightBetween(center: Vec2, target: Vec2): CollimatedLight {
  const offset: Vec2 = [target[0] - center[0], target[1] - center[1]]
  const distance = Math.hypot(offset[0], offset[1])
  return {
    center,
    direction: [offset[0] / distance, offset[1] / distance],
    beamHalfWidth: PRISM_BEAM_WIDTH * 0.5,
  }
}

/**
 * The lamp for a given angle of incidence on the entry face.
 *
 * The prism never moves. The lamp swings around it on a fixed radius, always aimed
 * at a point along the entry face, so the pointer changes the incidence and the
 * point of impact independently.
 */
export function lampForIncidence(incidenceDegrees: number, entryPosition = 0.5): CollimatedLight {
  const face: Vec2 = [
    PRISM_TRIANGLE.a[0] - PRISM_TRIANGLE.c[0],
    PRISM_TRIANGLE.a[1] - PRISM_TRIANGLE.c[1],
  ]
  const faceLength = Math.hypot(face[0], face[1])
  // Outward normal of a counter-clockwise edge, flipped to point into the glass: a
  // beam along it would strike the face head on, at zero incidence. Negating the
  // incidence brings the white beam in from the right and sends its fan left.
  const inward: Vec2 = [-face[1] / faceLength, face[0] / faceLength]
  const direction = rotate(inward, radians(-incidenceDegrees))
  // Keep both finite beam boundaries on the face even at a viewport edge: at oblique
  // incidence their footprint along the face grows by 1 / cos(incidence).
  const entryMargin = Math.min(
    0.45,
    PRISM_BEAM_WIDTH /
      (2 * faceLength * Math.max(0.05, Math.abs(Math.cos(radians(incidenceDegrees))))) +
      1e-4,
  )
  const entryPoint = prismEntryPoint(
    Math.min(1 - entryMargin, Math.max(entryMargin, entryPosition)),
  )
  return collimatedLightBetween(
    [
      entryPoint[0] - direction[0] * PRISM_LAMP_DISTANCE,
      entryPoint[1] - direction[1] * PRISM_LAMP_DISTANCE,
    ],
    entryPoint,
  )
}

/** Visible wavelength range the continuous spectral mesh subdivides, in nanometres. */
export const PRISM_WAVELENGTHS = {min: 400, max: 700} as const

/** Wavelength vertices connected into the smooth spectral mesh. */
export const PRISM_SPECTRAL_SAMPLES = 64

/** Additive sheets that integrate the finite width of the collimated beam. */
export const PRISM_BEAM_SLICES = 24

/** Display exposure for the finite spectral integral represented by the mesh. */
export const PRISM_LIGHT_EXPOSURE = 88

/** Internal reflections a ray may take before the analytic solver gives up. */
export const PRISM_MAX_INTERNAL_BOUNCES = 3

/**
 * How far the triangle is extruded off the wall, towards the camera.
 *
 * Both a framing decision and the separation that gives the light sheet parallax:
 * enough for the side faces to catch the studio environment and read as a block of
 * glass, little enough that the scene still reads as one compact prism.
 */
export const PRISM_DEPTH = 0.3

/**
 * Gap between the prism's back face and the wall. Only large enough to keep the two
 * surfaces from meeting: coplanar geometry would z-fight.
 */
export const PRISM_WALL_GAP = 0.015

/** The prism occupies `z` in [`PRISM_BACK_Z`, `PRISM_FRONT_Z`]; the wall is `z = 0`. */
export const PRISM_BACK_Z = PRISM_WALL_GAP
export const PRISM_FRONT_Z = PRISM_WALL_GAP + PRISM_DEPTH
/** The emissive light sheet crosses halfway between the two glass interfaces. */
export const PRISM_LIGHT_PLANE_Z = (PRISM_BACK_Z + PRISM_FRONT_Z) * 0.5

/**
 * The resting camera is centered on the prism and square to the wall. Hovering may
 * still reveal its depth with a small orbit, but the composed shot is a straight-on
 * elevation with no keystone or perspective bias.
 */
export const CAMERA_YAW_DEGREES = 0
export const CAMERA_PITCH_DEGREES = 0

/** Widest angle the pointer can swing the camera off its resting view, in degrees. */
export const CAMERA_ORBIT_DEGREES = 3.5

/** Per-frame interpolation towards the pointer's camera angle. */
export const CAMERA_ORBIT_LERP = 0.08

/** Per-frame interpolation towards the pointer's requested lamp position. */
export const LAMP_AIM_LERP = 0.12
