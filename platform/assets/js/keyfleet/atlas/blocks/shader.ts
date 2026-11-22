import {GAP, RADIUS} from "./layout"

/**
 * The Atlas blocks: one quad an instance for each tile, a project, a kind of
 * work, a thing or the rest of a kind, drawn as a rounded block standing a
 * little apart from its neighbours (`gutter` and `corner` in `./layout`, the
 * same sums written again here), tinted along the page's scale by how
 * recently it was worked on. A tile shows only once its parent has grown far
 * enough toward filling the stage, fading in over its parent, and a tile
 * whose own children show quietens toward the ground so they read on it. A
 * tile changed today carries a small dot in the page's warm accent, ringed
 * by the ground; the rest of a kind is a neutral tile. The tiles lit, the one
 * pointed at or ringed and all inside it, lift a little and wear a hairline
 * edge while the others dim toward the ground; the ringed tile wears a ring
 * in the page's focus colour. Edges are smoothed over a device pixel, and
 * everything is premultiplied over a clear canvas.
 */
export const blocksWgsl = /* wgsl */ `
const GAP = ${GAP.toFixed(1)};
const RADIUS = ${RADIUS.toFixed(1)};

struct Params {
  // Width and height in device pixels, and device pixels per CSS pixel.
  size: vec4f,
  // The camera: the point at the middle of the stage, from the layout's
  // base, the zoom, and the ringed tile's number (-1 for none).
  view: vec4f,
  // Children start to show at x of the zoom that fills the stage with their
  // parent, and show fully at y; the tiles lit run from number z to w (z is
  // -1 when none is).
  show: vec4f,
  // The scale from the oldest work to the newest, the rest of a kind, the
  // ground between the tiles, the hairline of a lit tile, the ring, and the
  // dot of a tile changed today.
  tone1: vec4f,
  tone2: vec4f,
  tone3: vec4f,
  rest: vec4f,
  ground: vec4f,
  line: vec4f,
  ring: vec4f,
  accent: vec4f,
}
@group(0) @binding(0) var<uniform> params: Params;

struct Tile {
  @builtin(position) position: vec4f,
  // Where in the tile, and how big it is, in CSS pixels.
  @location(0) local: vec2f,
  @location(1) extent: vec2f,
  // How recent its work is (-1 for the rest of a kind), how fully it shows,
  // and how fully its own children show.
  @location(2) look: vec3f,
  // Whether it changed today, whether it is ringed, and whether it is lit
  // (1), dimmed (0) or neither (-1).
  @location(3) marks: vec3f,
}

fn gutter(side: f32) -> f32 {
  return min(GAP, max(side, 0.0) * 0.15);
}

fn corner(side: f32) -> f32 {
  return min(RADIUS, max(side - gutter(side), 0.0) * 0.2);
}

// rect: x, y, width and height from the layout's base. tile: how recent its
// work is, the zoom that fills the stage with its parent (0 for a project),
// and its number times four, plus one when it changed today and two when it
// has children.
@vertex fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @location(0) rect: vec4f,
  @location(1) tile: vec3f,
) -> Tile {
  let zoom = params.view.z;
  let css = params.size.xy / params.size.z;
  var alpha = 1.0;
  if (tile.y > 0.0) {
    alpha = smoothstep(params.show.x, params.show.y, zoom / tile.y);
  }
  let start = (rect.xy - params.view.xy) * zoom + css * 0.5;
  let extent = rect.zw * zoom;
  let gone = alpha < 0.002 || start.x > css.x || start.y > css.y || start.x + extent.x < 0.0 || start.y + extent.y < 0.0;
  let reach = vec2f(f32(vertex & 1u), f32(vertex >> 1u)) * select(1.0, 0.0, gone);
  let at = (start + reach * extent) * params.size.z;

  let code = tile.z;
  let slot = floor(code / 4.0);
  let flags = code - slot * 4.0;
  let today = flags - 2.0 * floor(flags / 2.0);
  let parent = floor(flags / 2.0);
  // Its own fill: the zoom at which it fills the stage.
  let fill = min(css.x / max(rect.z, 1e-9), css.y / max(rect.w, 1e-9));
  let open = parent * smoothstep(params.show.x, params.show.y, zoom / fill);
  var lit = -1.0;
  if (params.show.z >= 0.0) {
    lit = select(0.0, 1.0, slot >= params.show.z && slot <= params.show.w);
  }

  var out: Tile;
  out.position = vec4f(at.x / params.size.x * 2.0 - 1.0, 1.0 - at.y / params.size.y * 2.0, 0.0, 1.0);
  out.local = reach * extent;
  out.extent = extent;
  out.look = vec3f(tile.x, alpha, open);
  out.marks = vec3f(today, select(0.0, 1.0, slot == params.view.w), lit);
  return out;
}

fn ramp(value: f32) -> vec3f {
  if (value < 0.5) {
    return mix(params.tone1.rgb, params.tone2.rgb, value * 2.0);
  }
  return mix(params.tone2.rgb, params.tone3.rgb, value * 2.0 - 1.0);
}

// How far outside a rounded box of half size half and corner radius r a
// point p from its middle is: negative inside.
fn rounded(p: vec2f, half: vec2f, r: f32) -> f32 {
  let q = abs(p) - half + r;
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

@fragment fn fs_main(tile: Tile) -> @location(0) vec4f {
  let side = min(tile.extent.x, tile.extent.y);
  let inset = gutter(side) * 0.5;
  let r = corner(side);
  let half = tile.extent * 0.5 - inset;
  let p = tile.local - tile.extent * 0.5;
  let edge = rounded(p, half, r);
  // Smoothed over one device pixel.
  let cover = clamp(0.5 - edge * params.size.z, 0.0, 1.0);
  if (cover <= 0.0) {
    discard;
  }

  let rest = tile.look.x < 0.0;
  var color = select(ramp(tile.look.x), params.rest.rgb, rest);
  // Opened: quieter, so its children read on it.
  color = mix(color, params.ground.rgb, 0.7 * tile.look.z);

  // Changed today: a dot in the top right, ringed by the ground.
  let inner = side - 2.0 * inset;
  if (tile.marks.x > 0.5 && inner >= 16.0) {
    let centre = vec2f(half.x - 5.0 - r * 0.3, -half.y + 5.0 + r * 0.3);
    let distance = length(p - centre);
    color = mix(color, params.ground.rgb, 1.0 - smoothstep(4.0, 4.5, distance));
    color = mix(color, params.accent.rgb, 1.0 - smoothstep(2.6, 3.1, distance));
  }

  let lit = tile.marks.z;
  if (lit > 0.5) {
    color = mix(color, params.line.rgb, 0.1);
    if (edge > -1.0 && tile.look.z < 0.5) {
      color = params.line.rgb;
    }
  } else if (lit > -0.5) {
    color = mix(color, params.ground.rgb, 0.45);
  }
  if (tile.marks.y > 0.5 && edge > -2.0) {
    color = params.ring.rgb;
  }

  let alpha = tile.look.y * cover;
  return vec4f(color * alpha, alpha);
}
`
