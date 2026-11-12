import {BAND, GLOW} from "./look"

/** Tiles the row can hold; the uniform's array is always this long. */
export const TILE_SLOTS = 5

/**
 * One fullscreen pass over the whole row. A single flow runs across the row in CSS
 * pixels, so its waves pass from tile to tile, and each tile maps it through the
 * stretch of its own product's ramp that its words read on. Outside every tile the
 * canvas stays clear.
 */
export const wgsl = /* wgsl */ `
struct Tile {
  // Left, top, right and bottom, in canvas pixels, as the press scales the tile.
  box: vec4f,
  deep: vec4f,
  mid: vec4f,
  light: vec4f,
  sheen: vec4f,
  // The stretch of the ramp the words read on, then the pointer's light from 0 to 1.
  calm: vec4f,
  // The pointer, in canvas pixels.
  pointer: vec4f,
}

struct Params {
  tiles: array<Tile, ${TILE_SLOTS}>,
  // Canvas pixels per CSS pixel, seconds, tiles in use.
  view: vec4f,
}

@group(0) @binding(0) var<uniform> params: Params;

const BAND = ${BAND};
const GLOW = ${GLOW};

fn ramp(tile: Tile, v: f32) -> vec3f {
  let low = mix(tile.deep.rgb, tile.mid.rgb, smoothstep(0.0, 0.5, v));
  return mix(low, tile.light.rgb, smoothstep(0.5, 1.0, v));
}

// How far outside a box a point lies, in pixels; below zero inside it.
fn outside(p: vec2f, box: vec4f) -> f32 {
  let d = max(box.xy - p, p - box.zw);
  return max(d.x, d.y);
}

fn grain(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(12.9898, 78.233))) * 43758.5453) - 0.5;
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let px = position.xy;
  let ratio = params.view.x;
  let t = params.view.y;
  let count = i32(params.view.z);

  var index = 0;
  var cover = 0.0;
  for (var i = 0; i < count; i++) {
    let c = clamp(0.5 - outside(px, params.tiles[i].box), 0.0, 1.0);
    if (c > cover) {
      cover = c;
      index = i;
    }
  }
  if (cover <= 0.0) {
    return vec4f(0.0);
  }
  let tile = params.tiles[index];

  let p = px / (ratio * 70.0);
  var q = p;
  q += 0.7 * vec2f(sin(q.y * 2.2 + t * 0.55), sin(q.x * 1.1 - t * 0.45));
  q += 0.3 * vec2f(sin(q.y * 3.1 - t * 0.38 + 1.7), sin(q.x * 2.3 + t * 0.5 + 0.4));
  let v = mix(tile.calm.x, tile.calm.y, 0.5 + 0.5 * sin(q.x * 1.3 + q.y * 0.8 + t * 0.32));
  let band = pow(0.5 + 0.5 * sin(q.x * 0.8 - q.y * 1.6 - t * 0.5 + 2.0), 4.0);

  let d = (px - tile.pointer.xy) / ratio;
  let glow = tile.calm.z * exp(-dot(d, d) / 2400.0);
  let color = mix(ramp(tile, v), tile.sheen.rgb, band * BAND + glow * GLOW);
  return vec4f((color + grain(px) / 255.0) * cover, cover);
}
`
