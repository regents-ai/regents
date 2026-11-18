/**
 * The guided tour's light, drawn by one fullscreen shader on a clear canvas
 * over the dimmed page (tour/renderer.ts). The page draws the ring itself;
 * the shader adds the light the ring gives off, a soft glow just outside it,
 * and a brighter spark that runs once round the ring as it arrives on a part.
 * Nothing is drawn inside the hole, over the part itself.
 *
 * Everything is premultiplied: the canvas is clear wherever nothing is drawn.
 */
export const tourWgsl = /* wgsl */ `
struct Params {
  // Canvas size in pixels, canvas pixels per CSS pixel, and how far the
  // spark has run round the ring: 0 as it sets off, 1 back where it began.
  size: vec2f,
  scale: f32,
  run: f32,
  // The hole's centre and half size, in canvas pixels.
  hole: vec4f,
  // The ring's light, as light on this page; w is unused.
  light: vec4f,
}

@group(0) @binding(0) var<uniform> params: Params;

const PI = 3.14159265;

// How far a point lies outside a box centred on the origin: 0 on its edge,
// less than 0 inside it.
fn outside(p: vec2f, half: vec2f) -> f32 {
  let q = abs(p) - half;
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0);
}

// How far round the ring a point lies, from 0 at the top left corner,
// clockwise, to 1 back at it, read from the side of the ring it is nearest.
fn round_ring(p: vec2f, half: vec2f) -> f32 {
  let size = half * 2.0;
  let q = clamp(p + half, vec2f(0.0), size);
  let gaps = vec4f(abs(p.y + half.y), abs(p.x - half.x), abs(p.y - half.y), abs(p.x + half.x));
  let nearest = min(min(gaps.x, gaps.y), min(gaps.z, gaps.w));
  var along = 0.0;
  if (nearest == gaps.x) {
    along = q.x;
  } else if (nearest == gaps.y) {
    along = size.x + q.y;
  } else if (nearest == gaps.z) {
    along = size.x + size.y + (size.x - q.x);
  } else {
    along = 2.0 * size.x + size.y + (size.y - q.y);
  }
  return along / max(2.0 * (size.x + size.y), 1.0);
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let s = params.scale;
  let half = params.hole.zw;
  if (half.x < 1.0 || half.y < 1.0) {
    return vec4f(0.0);
  }
  let p = position.xy - params.hole.xy;
  let d = outside(p, half);
  if (d < 0.0) {
    return vec4f(0.0);
  }

  // The spark: brightest where it has run to, gone as it sets off and as it
  // comes home, so the ring is left as it was.
  let gap = abs(fract(round_ring(p, half) - params.run + 0.5) - 0.5);
  let spark = exp(-(gap * gap) / 0.003) * sin(PI * params.run);

  let ring = 1.0 - smoothstep(2.0 * s, 3.5 * s, d);
  let glow = exp(-d / (5.0 * s));
  let a = clamp(0.22 * glow + spark * (0.65 * glow + 0.35 * ring), 0.0, 1.0);

  // Light that reaches the canvas's edge fades out before it.
  let room = min(min(position.x, params.size.x - position.x), min(position.y, params.size.y - position.y));
  return vec4f(params.light.rgb * a, a) * smoothstep(0.0, 3.0 * s, room);
}
`
