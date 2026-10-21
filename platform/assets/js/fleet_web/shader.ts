/**
 * The home page's lines, drawn by one fullscreen shader over a clear canvas.
 *
 * Each line is a quadratic curve between two cards' centres; the cards and the
 * labels sit on top and hide the ends. A pixel finds the nearest point on each
 * curve by walking it in short straight pieces, which knows both how far the
 * pixel is from the line and how far along the line that point is. Work lines
 * carry bright dashes outward from the fleet; USDC lines carry beads to
 * staking. Every distance is in the canvas's own pixels, so dashes and beads
 * keep their size on any screen.
 */
export const LINE_LIMIT = 8

export const fleetWebWgsl = /* wgsl */ `
struct Params {
  resolution: vec2f,
  // Canvas pixels per CSS pixel.
  scale: f32,
  time: f32,
  count: f32,
  // Colours as the page writes them: the work lines and the USDC lines.
  ink: vec3f,
  revenue: vec3f,
  // Two entries a line: its start and end, then its bend, its kind (0 work,
  // 1 USDC) and how strongly it is lit for a card under the pointer.
  lines: array<vec4f, ${LINE_LIMIT * 2}>,
}
@group(0) @binding(0) var<uniform> params: Params;

const PIECES = 24;

fn bezier(a: vec2f, b: vec2f, c: vec2f, t: f32) -> vec2f {
  let u = 1.0 - t;
  return u * u * a + 2.0 * u * t * b + t * t * c;
}

// Distance from p to the curve, and the length along it to the nearest point.
fn nearest(p: vec2f, a: vec2f, b: vec2f, c: vec2f) -> vec3f {
  var best = vec3f(1e9, 0.0, 0.0);
  var walked = 0.0;
  var start = a;
  for (var i = 1; i <= PIECES; i = i + 1) {
    let stop = bezier(a, b, c, f32(i) / f32(PIECES));
    let piece = stop - start;
    let span = max(length(piece), 1e-4);
    let h = clamp(dot(p - start, piece) / (span * span), 0.0, 1.0);
    let d = length(p - start - piece * h);
    if (d < best.x) {
      best = vec3f(d, walked + h * span, 0.0);
    }
    walked = walked + span;
    start = stop;
  }
  best.z = walked;
  return best;
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let p = uv * params.resolution;
  let px = params.scale;
  var color = vec3f(0.0);
  var alpha = 0.0;

  for (var i = 0; i < i32(params.count); i = i + 1) {
    let ends = params.lines[i * 2];
    let rest = params.lines[i * 2 + 1];
    let a = ends.xy * params.resolution;
    let c = ends.zw * params.resolution;
    let b = rest.xy * params.resolution;
    let revenue = rest.z > 0.5;
    let lit = rest.w;
    let near = nearest(p, a, b, c);
    let d = near.x;
    if (d > 8.0 * px) { continue; }
    let along = near.y;
    let tint = select(params.ink, params.revenue, revenue);

    // The line itself: thin, a little stronger for a card under the pointer.
    let width = select(0.5, 0.75, revenue) * px;
    let base = (1.0 - smoothstep(width, width + px, d)) * mix(select(0.22, 0.45, revenue), 0.7, lit);

    var flow = 0.0;
    if (revenue) {
      // Beads of USDC, every 30 CSS pixels, 34 a second.
      let gap = 30.0 * px;
      let spot = (fract((along - params.time * 34.0 * px) / gap) - 0.5) * gap;
      let r = length(vec2f(spot, d));
      flow = 1.0 - smoothstep(2.0 * px, 3.0 * px, r);
    } else {
      // A dash with a fading tail, every 64 CSS pixels, 40 a second.
      let gap = 64.0 * px;
      let spot = fract((along - params.time * 40.0 * px) / gap);
      let head = smoothstep(0.62, 0.97, spot) * (1.0 - smoothstep(0.97, 1.0, spot));
      flow = head * (1.0 - smoothstep(1.0 * px, 2.0 * px, d)) * mix(0.75, 1.0, lit);
    }
    // Lines fade in from the fleet and out at staking, under the cards.
    let ends_fade = smoothstep(0.0, 24.0 * px, along) * smoothstep(0.0, 24.0 * px, near.z - along);
    let a_line = max(base, flow * ends_fade);
    color = color * (1.0 - a_line) + tint * a_line;
    alpha = alpha + a_line * (1.0 - alpha);
  }
  return vec4f(color, alpha);
}
`
