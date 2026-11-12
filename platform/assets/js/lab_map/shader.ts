/** Dots the map can light; the uniform's array is always this long. */
export const DOT_SLOTS = 7

/**
 * One fullscreen pass behind the lab map: a soft glow round each dot in its
 * colour, drifting and breathing slowly, and along a picked line a glow that runs
 * from one end's colour to the other's, with a brighter bead travelling it.
 * Everywhere else the canvas stays clear, so the panel's ground shows through,
 * and every glow thins out before the canvas's edges so none of them shows one.
 */
export const wgsl = /* wgsl */ `
struct Spot {
  // Where the dot is, in canvas pixels, then how far its glow reaches in CSS pixels and how strong it is.
  place: vec4f,
  // Its colour, then a phase that keeps the dots from breathing together.
  tint: vec4f,
}

struct Params {
  spots: array<Spot, ${DOT_SLOTS}>,
  // The picked line's two ends, in canvas pixels.
  ends: vec4f,
  // Each end's colour; the first carries how strongly the line glows.
  head: vec4f,
  tail: vec4f,
  // Canvas pixels per CSS pixel, seconds, dots in use, how strong the whole glow is.
  view: vec4f,
  // The canvas's size in canvas pixels, then how far in from its edges the glow fades out, in CSS pixels.
  bounds: vec4f,
}

@group(0) @binding(0) var<uniform> params: Params;

fn grain(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(12.9898, 78.233))) * 43758.5453) - 0.5;
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let px = position.xy;
  let ratio = params.view.x;
  let t = params.view.y;
  let count = i32(params.view.z);

  var color = vec3f(0.0);
  var cover = 0.0;
  for (var i = 0; i < count; i++) {
    let spot = params.spots[i];
    let phase = spot.tint.w;
    let drift = vec2f(sin(t * 0.21 + phase * 1.7), cos(t * 0.17 + phase * 2.3)) * 7.0 * ratio;
    let d = length(px - spot.place.xy - drift) / (spot.place.z * ratio);
    let breath = 0.82 + 0.18 * sin(t * 0.55 + phase);
    let a = spot.place.w * breath * exp(-d * d * 2.2);
    color += spot.tint.rgb * a;
    cover += a;
  }

  let start = params.ends.xy;
  let run = params.ends.zw - start;
  let span = max(length(run), 1.0);
  let along = clamp(dot(px - start, run) / (span * span), 0.0, 1.0);
  let off = length(px - start - run * along) / ratio;
  let bead = exp(-pow((along - fract(t * 0.35)) * span / (28.0 * ratio), 2.0));
  let glow = params.head.w * exp(-off * off / 260.0) * (0.35 + 0.65 * bead);
  color += mix(params.head.rgb, params.tail.rgb, along) * glow;
  cover += glow;

  // The glow thins out towards the canvas's edges rather than stopping at them.
  let size = params.bounds.xy;
  let inside = min(min(px.x, size.x - px.x), min(px.y, size.y - px.y)) / (params.bounds.z * ratio);
  let edge = smoothstep(0.0, 1.0, inside);

  // Premultiplied: never more colour than cover, and never past opaque.
  let alpha = min(1.0, cover * params.view.w) * edge;
  let scale = select(alpha / cover, 0.0, cover <= 0.0001);
  let rgb = clamp(color * scale + vec3f(grain(px) / 255.0), vec3f(0.0), vec3f(alpha));
  return vec4f(rgb, alpha);
}
`
