/**
 * This site's crown: where it sits, what its glass is like, how its beams are
 * aimed and coloured, and the field of squares drawn behind it.
 *
 * The crown itself is the shared one in `./crown`. A site that copies it keeps
 * a file like this one and nothing else of its own.
 */

import {beamOf, type CrownBackdrop, type CrownLook, type CrownRoom, type Rgba, type Vec3} from "./crown/look"

/** Cells across the canvas height, and the hash offset that chooses lit cells. */
const FIELD_SCALE = 12.05
const FIELD_HASH_OFFSET = "vec2f(170.0, 70.0)"

/**
 * One quiet composition: a soft diagonal band of light squares over the ground.
 * The grid is hashed, so which cells are lit is fixed by position alone and the
 * picture is the same on every visit and at every size.
 *
 * Derived from the Vercel vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */
const fieldWgsl = /* wgsl */ `
struct FieldParams {
  groundColor: vec4f,
  squareColor: vec4f,
  resolution: vec2f,
  intensity: f32,
};

@group(0) @binding(0) var<uniform> params: FieldParams;

fn hash21(point: vec2f) -> f32 {
  var value = fract(point * vec2f(0.1031, 0.1030));
  value = value + dot(value, value.yx + vec2f(33.33));
  return fract((value.x + value.y) * value.x);
}

// The band: full strength along one diagonal, gone well before the corners.
fn composition(uv: vec2f) -> f32 {
  let diagonal = abs((uv.x * 0.82 + 0.12) - uv.y);
  return 1.0 - smoothstep(0.02, 0.48, diagonal);
}

// Cell coverage in x, and the shading of the cell's face and rim in y.
fn squareField(uv: vec2f, aspect: f32) -> vec2f {
  let plane = vec2f((uv.x - 0.5) * aspect + 0.5, uv.y) * ${FIELD_SCALE};
  let cell = floor(plane);
  let local = fract(plane) - vec2f(0.5);
  let squareDistance = max(abs(local.x), abs(local.y));
  let body = 1.0 - smoothstep(0.36, 0.4, squareDistance);
  let edge = 1.0 - smoothstep(0.012, 0.032, abs(squareDistance - 0.38));
  let face = mix(0.76, 1.04, clamp((local.x - local.y) * 0.72 + 0.5, 0.0, 1.0));
  let occupancy = hash21(cell + ${FIELD_HASH_OFFSET});
  return vec2f(body * step(occupancy, 0.58), mix(face, 1.18, edge));
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let safeResolution = max(params.resolution, vec2f(1.0));
  let aspect = safeResolution.x / safeResolution.y;
  let band = clamp(composition(uv), 0.0, 1.0);
  let square = squareField(uv, aspect);
  let density = smoothstep(0.04, 0.96, band);
  let squareAmount = square.x * density * params.intensity * square.y;
  let groundGradient = 1.0 + (uv.y - 0.5) * 0.022 + (uv.x - 0.5) * 0.008;
  let ground = clamp(params.groundColor.rgb * groundGradient, vec3f(0.0), vec3f(1.0));
  return vec4f(mix(ground, params.squareColor.rgb, clamp(squareAmount, 0.0, 0.26)), 1.0);
}
`

/**
 * The stage's ground `#0B0B0B` and the palette's cream squares `#E5E3D2`, as the
 * values that come out of the crown's last pass as those colours: the scene is
 * composed in high dynamic range and tone-mapped once at the end.
 */
const GROUND: Rgba = [0.009185, 0.009185, 0.009185, 1]
const SQUARE: Rgba = [0.17318, 0.17147, 0.15705, 1]

const field: CrownBackdrop = {
  wgsl: fieldWgsl,
  frame: resolution => ({
    clear: GROUND,
    set: {params: {groundColor: GROUND, squareColor: SQUARE, resolution, intensity: 0.2}},
  }),
}

const clamp = (value: number): number => Math.min(1, Math.max(0, value))

/**
 * A hero crown. On a wide stage it stands to the right, clear of the words on
 * the left; as the stage narrows it comes back to the middle and drops below them.
 */
const place = (aspect: number, room: CrownRoom) => {
  const landscape = clamp((aspect - 1.35) / 0.2)
  const narrow = clamp((1.45 - aspect) / 0.6)
  return [Math.min(0.46 * landscape, room.right), Math.max(-0.55 * narrow, room.down)] as const
}

/** The beam colours on offer: this site's crown is lit in white. */
const BEAMS: Record<string, Vec3> = {
  white: [1, 1, 1],
}

/** The look for the name the page gives its crown in `data-crown-look`. */
export function crownLook(name: string): CrownLook {
  const beam = BEAMS[name]
  if (!beam) throw new Error(`No crown look is named "${name}".`)

  return {
    framing: {scale: 1, distance: 1.31, margin: 0.08, place},
    glass: {
      ior: 1.244,
      reflectionStrength: 2.21,
      absorption: [0.45, 0.48, 0.52],
      frostRadius: 0.3,
      dispersion: 0.015,
      iridescenceStrength: 0.02,
      iridescenceFrequency: 2,
      environmentExposure: 1.25,
      environmentRotation: [0, -28, 0],
    },
    bloom: {strength: 0.85, threshold: 0.45, radius: 1},
    beams: {
      side: 1,
      lift: 0,
      angleBase: -0.065,
      angleRange: 0.075,
      rowConvergence: 0.032,
      verticalTravel: 0.11,
      dispersionStrength: 0.04,
      wedgeStrength: 0.14,
      spectralSamples: 20,
      halfWidth: 0.044,
      spectralHalfWidth: 0.01,
      inputIntensity: 3.9,
      internalIntensity: 0.1,
      spectralIntensity: 0.72,
    },
    colors: beamOf(beam),
    backdrop: field,
  }
}
