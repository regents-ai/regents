/**
 * A tree canvas's links, one ribbon each over a clear canvas with
 * premultiplied alpha, so the page shows through. Each ribbon follows its
 * link's curve through the camera, fades from where the link leaves to where
 * it arrives, and widens into a soft glow as it lights up. Lit links take
 * the page's link colour; one that contradicts its target takes the error
 * colour; the rest recede while any link is lit. A fork's, a review's or a
 * contradiction's link is dashed, as is one that closes a loop.
 */
export const graphWgsl = /* wgsl */ `
struct Params {
  // Width and height in device pixels, device pixels per CSS pixel, and how
  // far the unlit links recede, 0..1.
  size: vec4f,
  // Where the world's origin is on the canvas, in CSS pixels, and CSS pixels
  // per world pixel.
  view: vec4f,
  // The resting links' colour and strength.
  ink: vec4f,
  // The lit links' colour.
  lit: vec4f,
  // A contradicting link's colour.
  against: vec4f,
}
@group(0) @binding(0) var<uniform> params: Params;

// Pieces each curve is cut into; a strip of (SEGMENTS + 1) * 2 vertices.
const SEGMENTS = 32u;

struct Ribbon {
  @builtin(position) position: vec4f,
  // Distance from the middle of the line, in device pixels, either side.
  @location(0) across: f32,
  // Half the solid line's width, in device pixels.
  @location(1) half: f32,
  // 0 where the link leaves, 1 where it arrives.
  @location(2) along: f32,
  @location(3) light: f32,
  @location(4) against: f32,
  // How long the link runs on screen, in CSS pixels, when it is dashed; 0
  // when solid.
  @location(5) dashed: f32,
}

// A dash and the gap after it, in CSS pixels, as the page draws them.
const DASH = 5.0;
const PERIOD = 9.0;

fn curve(a: vec4f, b: vec4f, t: f32) -> vec2f {
  let s = 1.0 - t;
  return s * s * s * a.xy + 3.0 * s * s * t * a.zw + 3.0 * s * t * t * b.xy + t * t * t * b.zw;
}

fn slope(a: vec4f, b: vec4f, t: f32) -> vec2f {
  let s = 1.0 - t;
  return 3.0 * s * s * (a.zw - a.xy) + 6.0 * s * t * (b.xy - a.zw) + 3.0 * t * t * (b.zw - b.xy);
}

// a: start and first handle, b: second handle and end, in world pixels;
// c: how lit the link is, 0..1, 1 when it contradicts, and how long it runs
// in world pixels when it is dashed.
@vertex fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @location(0) a: vec4f,
  @location(1) b: vec4f,
  @location(2) c: vec4f,
) -> Ribbon {
  let t = f32(vertex / 2u) / f32(SEGMENTS);
  let side = select(-1.0, 1.0, (vertex & 1u) == 1u);
  let scale = params.size.z;
  let light = c.x;

  var direction = slope(a, b, t);
  if (length(direction) < 0.0001) {
    direction = b.zw - a.xy;
  }
  let normal = normalize(vec2f(-direction.y, direction.x));
  let half = (0.6 + 0.65 * light) * scale;
  let reach = half + (1.0 + 6.0 * light) * scale;
  let at = (curve(a, b, t) * params.view.z + params.view.xy) * scale + normal * side * reach;

  var ribbon: Ribbon;
  ribbon.position = vec4f(at.x / params.size.x * 2.0 - 1.0, 1.0 - at.y / params.size.y * 2.0, 0.0, 1.0);
  ribbon.across = side * reach;
  ribbon.half = half;
  ribbon.along = t;
  ribbon.light = light;
  ribbon.against = c.y;
  ribbon.dashed = c.z * params.view.z;
  return ribbon;
}

@fragment fn fs_main(ribbon: Ribbon) -> @location(0) vec4f {
  if (ribbon.dashed > 0.0 && (ribbon.along * ribbon.dashed) % PERIOD > DASH) {
    discard;
  }
  let scale = params.size.z;
  let distance = abs(ribbon.across);
  let solid = 1.0 - smoothstep(ribbon.half - 0.5, ribbon.half + 0.75, distance);
  let spread = max(distance - ribbon.half, 0.0) / (3.0 * scale);
  let glow = exp(-spread * spread) * ribbon.light * 0.3;

  let base = select(params.ink.rgb, params.against.rgb, ribbon.against > 0.5);
  let color = mix(base, params.lit.rgb, ribbon.light);
  let resting = params.ink.a * (1.0 - 0.6 * params.size.w);
  let strength = mix(resting, 1.0, ribbon.light) * mix(0.5, 1.0, ribbon.along);
  let alpha = clamp(solid * strength + glow, 0.0, 1.0);
  return vec4f(color * alpha, alpha);
}
`
