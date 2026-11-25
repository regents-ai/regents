/** Draws Orbit’s pill track, circular thumb and pixel glyph on a clear canvas. */

export const PIXEL_SLOTS = 96

/** How much smaller a block is halfway through its flight; whole again when it lands. */
export const FLIGHT_SHRINK = 0.28

/**
 * Lays the blocks out as the shader reads them, four floats apiece: into
 * `place` each block's x and y and the cosine and sine of its turn, into
 * `look` its half side in cells and its share of day. They go top to bottom,
 * so a pixel can find the blocks in its own band. `blocks` holds x, y, turn
 * and share of day for each, `stride` floats apiece; `half` is a block's half
 * side at rest. Slots past the last block are left empty.
 */
export function packBlocks(
  blocks: Float32Array,
  stride: number,
  count: number,
  half: number,
  place: Float32Array,
  look: Float32Array,
): void {
  place.fill(0)
  look.fill(0)
  const order = Array.from({length: count}, (_, i) => i)
  order.sort((a, b) => blocks[a * stride + 1] - blocks[b * stride + 1])
  order.forEach((block, i) => {
    const from = block * stride
    const turn = blocks[from + 2]
    const day = blocks[from + 3]
    place.set([blocks[from], blocks[from + 1], Math.cos(turn), Math.sin(turn)], i * 4)
    look.set([half * (1 - FLIGHT_SHRINK * Math.sin(Math.PI * day)), day], i * 4)
  })
}

export const themeSwitchWgsl = /* wgsl */ `
struct Params {
  // Track centre and half size, and the thumb's centre and radius.
  track: vec4f,
  lens: vec3f,
  scale: f32,
  // Light direction and the blend between night and day.
  light: vec2f,
  icon: vec3f,
  page: vec4f,
  ink: vec4f,
  night: vec4f,
  day: vec4f,
  icon_night: vec4f,
  icon_day: vec4f,
  count: u32,
  // Block positions and rotation, then half side and share of day.
  place: array<vec4f, ${PIXEL_SLOTS}>,
  look: array<vec4f, ${PIXEL_SLOTS}>,
}

@group(0) @binding(0) var<uniform> params: Params;

const PI: f32 = 3.14159265359;
// How far from its centre, in cells, any part of a block can lie.
const REACH: f32 = 0.75;

fn round_box(q: vec2f, half: vec2f, r: f32) -> f32 {
  let d = abs(q) - half + vec2f(r);
  return length(max(d, vec2f(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

// The outward edge normal of the rounded box. Within r of the edge it is
// continuous: straight out along the sides, turning round the corners.
fn round_box_normal(q: vec2f, half: vec2f, r: f32) -> vec2f {
  let d = abs(q) - half + vec2f(r);
  let s = select(vec2f(-1.0), vec2f(1.0), q >= vec2f(0.0));
  if (d.x > 0.0 && d.y > 0.0) {
    return normalize(d) * s;
  }
  if (d.x > d.y) {
    return vec2f(s.x, 0.0);
  }
  return vec2f(0.0, s.y);
}

fn over(top: vec4f, under: vec4f) -> vec4f {
  return top + under * (1.0 - top.a);
}

fn light_colour() -> vec3f {
  return mix(params.night.rgb, params.day.rgb, params.light.y);
}

fn wrap_pi(a: f32) -> f32 {
  return a - 2.0 * PI * floor((a + PI) / (2.0 * PI));
}

// How directly the point faces the light from the thumb’s centre.
fn toward_light(q: vec2f, spread: f32) -> f32 {
  let off = wrap_pi(atan2(q.y, q.x) - params.light.x);
  return exp(-(off * off) / (2.0 * spread * spread));
}

fn lens_edge(x: vec2f) -> f32 {
  return length(x - params.lens.xy) - params.lens.z;
}

fn track(x: vec2f) -> vec4f {
  let s = params.scale;
  let q = x - params.track.xy;
  let d = round_box(q, params.track.zw, params.track.w);
  let cover = clamp(0.5 - d, 0.0, 1.0);
  if (cover <= 0.0) {
    return vec4f(0.0);
  }
  let page = params.page.rgb;
  let ink = params.ink.rgb;
  var c = mix(page, ink, 0.11);
  // A shade under the top edge sets the track into the page.
  let top = q.y + params.track.w;
  c = mix(c, mix(page, ink, 0.2), 0.6 * (1.0 - smoothstep(0.0, 3.5 * s, top)));
  // Its outline.
  c = mix(c, mix(page, ink, 0.32), 1.0 - smoothstep(0.4 * s, 1.4 * s, -d));
  return vec4f(c * cover, cover);
}

// The thumb’s pixel glyph.
fn icon(x: vec2f) -> vec4f {
  let cell = params.icon.z;
  let q = (x - params.icon.xy) / cell;
  if (dot(q, q) > 64.0) {
    return vec4f(0.0);
  }
  // A block, turned however far, lies within REACH of its centre, so only the
  // blocks whose centres lie in this band can cover the point. The first is
  // found by halving; the rest follow it, in order down the picture.
  var lo = 0u;
  var hi = params.count;
  while (lo < hi) {
    let mid = (lo + hi) / 2u;
    if (params.place[mid].y < q.y - REACH) {
      lo = mid + 1u;
    } else {
      hi = mid;
    }
  }
  // The block that covers this point most.
  var cover = 0.0;
  var best = 0u;
  var near = vec2f(0.0);
  for (var i = lo; i < params.count; i = i + 1u) {
    let place = params.place[i];
    let off = q - place.xy;
    if (off.y < -REACH) {
      break;
    }
    if (abs(off.x) > REACH) {
      continue;
    }
    let local = vec2f(place.z * off.x + place.w * off.y, place.z * off.y - place.w * off.x);
    let half = params.look[i].x;
    let a = clamp(0.5 - round_box(local, vec2f(half), 0.06 * half) * cell, 0.0, 1.0);
    if (a > cover) {
      cover = a;
      best = i;
      near = local;
    }
  }
  if (cover <= 0.0) {
    return vec4f(0.0);
  }
  let place = params.place[best];
  let look = params.look[best];
  let half = look.x;
  let corner = 0.06 * half;
  let edge = round_box(near, vec2f(half), corner) * cell;
  // The edge that faces the light catches a little more colour.
  let toward = vec2f(cos(params.light.x), sin(params.light.x));
  let side = round_box_normal(near, vec2f(half), corner);
  let facing = vec2f(place.z * side.x - place.w * side.y, place.w * side.x + place.z * side.y);
  let rim = 1.0 - smoothstep(0.0, max(1.0, 0.45 * half * cell), -edge);
  let lit = rim * max(dot(facing, toward), 0.0) * (0.45 + 0.55 * toward_light(place.xy, 1.1));
  var colour = mix(params.icon_night.rgb, params.icon_day.rgb, look.y);
  colour = mix(colour, mix(light_colour(), vec3f(1.0), 0.6), 0.85 * lit);
  return vec4f(colour * cover, cover);
}

// Colour stays inside the thumb. Its rim is the strongest part of the tint.
fn thumb(x: vec2f, edge: f32) -> vec4f {
  let s = params.scale;
  let page = params.page.rgb;
  let ink = params.ink.rgb;
  let hue = light_colour();
  let y = (x.y - params.lens.y) / params.lens.z;
  let height = clamp((y + 1.0) * 0.5, 0.0, 1.0);
  let tint = mix(0.21, 0.12, params.light.y);
  let face = mix(mix(page, ink, 0.06), mix(page, hue, tint), 1.0 - height * 0.68);
  let rim = mix(mix(page, ink, 0.28), hue, 0.48);
  let line = 1.0 - smoothstep(0.25 * s, 1.15 * s, -edge);
  return over(icon(x), vec4f(mix(face, rim, line), 1.0));
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let x = position.xy;
  let base = track(x);
  let edge = lens_edge(x);
  if (edge >= 0.5) { return base; }
  return mix(base, thumb(x, edge), clamp(0.5 - edge, 0.0, 1.0));
}
`
