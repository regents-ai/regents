/**
 * The quiet field of squares behind the page, and behind the crown.
 *
 * One composition: a soft diagonal band of light squares over the page ground.
 * The grid is hashed, so which cells are lit is fixed by position alone and the
 * picture is the same on every visit and every size.
 *
 * Adapted from the Techtree background field, itself derived from the Vercel
 * vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */

/** Cells across the canvas height, and the hash offset that chooses lit cells. */
const FIELD_SCALE = 12.05
const FIELD_HASH_OFFSET = "vec2f(170.0, 70.0)"

export const fieldWgsl = /* wgsl */ `
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

/** The band: full strength along one diagonal, gone well before the corners. */
fn composition(uv: vec2f) -> f32 {
  let diagonal = abs((uv.x * 0.82 + 0.12) - uv.y);
  return 1.0 - smoothstep(0.02, 0.48, diagonal);
}

/** Cell coverage in x, and the shading of the cell's face and rim in y. */
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
