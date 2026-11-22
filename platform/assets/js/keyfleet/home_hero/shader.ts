/**
 * The homepage's hex field, one fullscreen pass over a clear canvas with
 * premultiplied alpha, so the page's own ground shows through and only the
 * lines and the light are the shader's: pointy-top hex tiles behind the hero,
 * a hairline rim on each, lit near the pointer, along the
 * wake a pointer or a finger leaves, in the ring a press sends out, and around
 * the Key while it is previewed. The field fades out toward its edges here
 * rather than in the stylesheet, so a raised tile fades with the tiles around
 * it. The tiles nearest a mouse stand up out of the field, each to its own
 * height, their faces turning from the field's own look toward the deep tone
 * the higher they stand (near black in dark, a darker off-white in light), and
 * sink back into it.
 */

/** How many marks of a wake or a ring the field holds at once. */
export const MARKS = 32
/** How many tiles can stand raised, or still be sinking, at once. */
export const TILES = 24

export const fieldWgsl = /* wgsl */ `
struct Params {
  // Width and height in device pixels, the tile size, device pixels per CSS pixel.
  size: vec4f,
  line: vec4f,
  light: vec4f,
  pointer: vec4f,
  key: vec4f,
  // The fade toward the edges: its centre and its radii, 0..1 across the
  // canvas, and where along the radius it starts and ends.
  fade: vec4f,
  stops: vec4f,
  // The page's ground, and the deep tone the raised tiles turn.
  ground: vec4f,
  deep: vec4f,
  // How high a tile stands at most in device pixels, and how dark the shadow
  // of a raised tile is.
  lift: vec4f,
  // Each mark: where it is (0..1 across the canvas), how strong it still is,
  // and, for a ring, how far it has spread in tiles (below zero for a wake).
  marks: array<vec4f, ${MARKS}>,
  // Each raised tile: its centre in device pixels and how high it stands,
  // 0..1 of the most (0 for an empty place).
  tiles: array<vec4f, ${TILES}>,
}
@group(0) @binding(0) var<uniform> params: Params;

// How many heights a pixel is looked through, from the field up to the
// highest a tile stands.
const STEPS = 14;
// Where a tile's face ends and its rim runs, from its centre toward its edge.
const EDGE = 0.44;
// The light the raised tiles catch on their seams and top edges, and on their
// sides in dark, where the near black reads as standing by its lit sides.
const LIT = vec3f(0.9, 0.89, 0.82);

// Pointy-top hexagons, one unit between neighbouring centres across a row,
// with a tile centred on the canvas's centre. hex() returns the point's offset
// from its cell's centre and how far it is from that centre toward the nearest
// edge, which is 0.5 on the edge itself.
fn hex(p: vec2f) -> vec3f {
  let r = vec2f(1.0, 1.7320508);
  let h = r * 0.5;
  let a = p - r * floor(p / r) - h;
  let b = (p - h) - r * floor((p - h) / r) - h;
  let g = select(b, a, dot(a, a) < dot(b, b));
  let q = abs(g);
  return vec3f(g, max(dot(q, vec2f(0.5, 0.8660254)), q.x));
}

fn over(below: vec4f, rgb: vec3f, alpha: f32) -> vec4f {
  return vec4f(rgb * alpha + below.rgb * (1.0 - alpha), alpha + below.a * (1.0 - alpha));
}

fn grain(cell: vec2f) -> f32 {
  return fract(sin(dot(cell, vec2f(12.9898, 78.233))) * 43758.5453);
}

// How much of the field shows at a point in device pixels, 1 in the middle
// and 0 past the fade's end.
fn shown(p: vec2f) -> f32 {
  let d = length((p / params.size.xy - params.fade.xy) / max(params.fade.zw, vec2f(0.001)));
  return clamp((params.stops.y - d) / max(params.stops.y - params.stops.x, 0.001), 0.0, 1.0);
}

// How high the tile centred at c stands, 0..1 of the most.
fn height(c: vec2f) -> f32 {
  for (var i = 0u; i < ${TILES}u; i += 1u) {
    let tile = params.tiles[i];
    if (tile.z > 0.0 && distance(tile.xy, c) < params.size.z * 0.25) {
      return tile.z;
    }
  }
  return 0.0;
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let cell = params.size.z;
  let px = uv * params.size.xy;
  let middle = params.size.xy * 0.5;
  let p = (px - middle) / cell;
  let h = hex(p);
  let centre = (p - h.xy) * cell + middle;
  let aa = 1.0 / cell;
  let fade = shown(centre);

  // Each tile is inset from its neighbours by a gap, with a hairline rim.
  let rim = 1.0 - smoothstep(aa * 0.6, aa * 1.6, abs(h.z - EDGE));
  let face = 1.0 - smoothstep(EDGE - aa, EDGE, h.z);
  let faceTone = 0.025 + grain(p - h.xy) * 0.035;

  // The pointer lights the tiles within a few cells of it, tile by tile.
  let toPointer = distance(centre, params.pointer.xy * params.size.xy) / cell;
  let near = (1.0 - smoothstep(0.6, 3.4, toPointer)) * params.pointer.z;

  // While the Key is previewed, the tiles around it take the light.
  let toKey = distance(centre, params.key.xy * params.size.xy) / max(params.key.z, 1.0);
  let lit = (1.0 - smoothstep(0.15, 1.0, toKey)) * params.pointer.w;

  // A wake lights whole tiles along its path; a ring lights the tiles it is
  // passing through.
  var wake = 0.0;
  for (var i = 0u; i < ${MARKS}u; i += 1u) {
    let mark = params.marks[i];
    if (mark.z <= 0.0) { continue; }
    let d = distance(centre, mark.xy * params.size.xy) / cell;
    let reach = select(
      1.0 - smoothstep(0.0, 0.9, abs(d - mark.w)),
      1.0 - smoothstep(0.35, 1.3, d),
      mark.w < 0.0,
    );
    wake = max(wake, mark.z * reach);
  }

  var color = vec4f(0.0);
  color = over(color, params.line.rgb, fade * face * (faceTone + near * 0.08));
  color = over(color, params.line.rgb, fade * rim * (0.16 + near * 0.32));
  color = over(color, params.light.rgb, fade * (face * lit * (0.10 + grain(p - h.xy) * 0.08) + rim * lit * 0.45));
  color = over(color, params.light.rgb, fade * (face * wake * (0.30 + grain(p - h.xy) * 0.12) + rim * wake * 0.85));

  // The raised tiles, and their shadows on the field, further and softer the
  // higher a tile stands. Only pixels near a raised tile can show either.
  let lift = params.lift.x;
  let reach = cell + lift;
  var beside = false;
  var shade = 0.0;
  for (var i = 0u; i < ${TILES}u; i += 1u) {
    let tile = params.tiles[i];
    if (tile.z <= 0.0) { continue; }
    beside = beside || distance(px, tile.xy) < reach;
    let d = distance(px, tile.xy + vec2f(0.0, lift * tile.z * 0.5));
    shade = max(shade, tile.z * (1.0 - smoothstep(cell * 0.3, cell * 0.6 + lift * tile.z, d)));
  }
  if (!beside) {
    return color;
  }
  color = over(color, vec3f(0.0), params.lift.y * shade * shown(px));

  // Looking through the heights from the field up: at each height, the tile
  // whose column passes this pixel there. A tile further down the screen
  // stands nearer, so it is drawn later, over the ones behind it. Where the
  // height reaches the tile's top the pixel is on its face; below, its side.
  // Each starts as the field's own tile and turns toward the deep tone the
  // higher it stands. On a light ground a tile's sides fall into shade
  // instead of catching the light, so an off-white tile still reads as standing.
  let daylight = dot(params.ground.rgb, vec3f(0.2126, 0.7152, 0.0722)) > 0.5;
  let step = lift / f32(STEPS);
  for (var k = 0; k <= STEPS; k += 1) {
    let t = step * f32(k);
    let q = (px + vec2f(0.0, t) - middle) / cell;
    let g = hex(q);
    let c = (q - g.xy) * cell + middle;
    let r = height(c);
    let tall = lift * r;
    if (r <= 0.0 || t > tall + step * 0.5) {
      continue;
    }
    let edge = EDGE + aa;
    let shape = 1.0 - smoothstep(edge - aa * 0.5, edge + aa * 0.5, g.z);
    let fieldFace = over(params.ground, params.line.rgb, shown(c) * (0.025 + grain(q - g.xy) * 0.035)).rgb;
    let fieldRim = over(params.ground, params.line.rgb, shown(c) * 0.16).rgb;
    var rgb: vec3f;
    if (t >= tall - step * 0.5) {
      // The face. In dark its rim is a shade lighter and its top edge lit a
      // little; in light it keeps a darker hairline rim, as dark as the rims
      // lit around the pointer.
      let edged = smoothstep(edge - aa * 2.4, edge - aa * 1.2, g.z);
      let top = clamp(-g.y * 2.4, 0.0, 1.0) * smoothstep(edge - 0.1, edge, g.z);
      let deep = params.deep.rgb + select(LIT * top * 0.18, vec3f(0.0), daylight);
      let border = select(mix(params.deep.rgb, LIT, 0.07), over(vec4f(params.deep.rgb, 1.0), params.line.rgb, 0.4).rgb, daylight);
      rgb = mix(mix(fieldFace, deep, r), mix(fieldRim, border, r), edged);
    } else {
      // The side, lighter than the face in dark and darker in light, either
      // way darkest toward the field.
      let low = t / max(tall, 0.001);
      let side = select(mix(params.deep.rgb, LIT, 0.03 + 0.17 * low * low), params.deep.rgb * (0.8 + 0.1 * low), daylight);
      rgb = mix(fieldRim, side, r);
    }
    color = over(color, rgb, shape * shown(c));
  }

  return color;
}`
