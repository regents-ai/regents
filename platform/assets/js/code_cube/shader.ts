/**
 * The code cube, drawn by one fullscreen shader on a clear canvas.
 *
 * Every pixel casts a ray at a cube. Each face is a screen of falling code in
 * its own colours, glyphs and grain, one for each site whose tools it lists.
 * Off the cube the canvas stays clear but for a glow along the edges, so the
 * page behind it shows through.
 *
 * Faces are 0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z, as in the world cube.
 */

// The hex digits 0 to F drawn three pixels wide and five tall, top row first.
const DIGITS = [
  "111101101101111", "010110010010111", "111001111100111", "111001111001111",
  "101101111001001", "111100111001111", "111100111101111", "111001001001001",
  "111101111101111", "111101111001111", "111101111101101", "110101110101110",
  "111100100100111", "110101101101110", "111100111100111", "111100111100100",
].map(bits => `${Number.parseInt(bits, 2)}u`)

export const codeCubeWgsl = /* wgsl */ `
struct Params {
  resolution: vec2f,
  time: f32,
  // Camera distance from the cube's centre.
  distance: f32,
  // Cube orientation, object to world.
  rotation: vec4f,
  // Tangent of half the vertical field of view.
  lens: f32,
  // The face under a resting pointer, and how strongly it is lit for it.
  hover: f32,
  glow: f32,
}
@group(0) @binding(0) var<uniform> params: Params;

const DIGITS = array<u32, 16>(${DIGITS.join(", ")});

// How one face's code falls and what it is drawn with.
struct Style {
  // Columns of code across the face.
  columns: f32,
  // Rows a second the code falls, and how many rows each trail is long.
  speed: f32,
  trail: f32,
  // The leading glyph, the trail behind it, and the screen at its top and foot.
  head: vec3f,
  tail: vec3f,
  top: vec3f,
  foot: vec3f,
  // 0 mirrored glyphs, 1 narrow glyphs, 2 binary, 3 hex, 4 dots, 5 soft glyphs.
  glyphs: i32,
}

fn styleOf(face: i32) -> Style {
  switch face {
    // patchbay.help: amber phosphor on a scanned screen.
    case 0: {
      return Style(18.0, 11.0, 10.0, vec3f(1.0, 0.9, 0.62), vec3f(1.0, 0.52, 0.04),
        vec3f(0.11, 0.05, 0.0), vec3f(0.025, 0.01, 0.0), 1);
    }
    // autolaunch.sh: magenta hex, fast, across a violet dusk.
    case 1: {
      return Style(15.0, 15.0, 9.0, vec3f(1.0, 0.86, 1.0), vec3f(0.98, 0.12, 0.62),
        vec3f(0.1, 0.0, 0.15), vec3f(0.02, 0.0, 0.05), 3);
    }
    // techtree.sh: cyan binary over deep water.
    case 2: {
      return Style(16.0, 7.0, 18.0, vec3f(0.86, 1.0, 1.0), vec3f(0.0, 0.82, 0.86),
        vec3f(0.0, 0.08, 0.09), vec3f(0.0, 0.012, 0.06), 2);
    }
    // keyfleet.ai: gold dots in a royal-blue vault.
    case 3: {
      return Style(13.0, 8.0, 12.0, vec3f(1.0, 0.95, 0.72), vec3f(1.0, 0.74, 0.16),
        vec3f(0.035, 0.07, 0.2), vec3f(0.0, 0.004, 0.025), 4);
    }
    // regents.sh: the classic green rain.
    case 4: {
      return Style(14.0, 9.0, 14.0, vec3f(0.78, 1.0, 0.82), vec3f(0.06, 0.92, 0.32),
        vec3f(0.0, 0.065, 0.02), vec3f(0.0, 0.012, 0.004), 0);
    }
    // siwa-server: slow ice-blue glyphs, lighter at the foot.
    default: {
      return Style(10.0, 4.0, 16.0, vec3f(0.95, 0.98, 1.0), vec3f(0.42, 0.68, 1.0),
        vec3f(0.025, 0.04, 0.08), vec3f(0.08, 0.12, 0.21), 5);
    }
  }
}

fn qrot(q: vec4f, v: vec3f) -> vec3f {
  let t = 2.0 * cross(q.xyz, v);
  return v + q.w * t + cross(q.xyz, t);
}

fn hash11(p: f32) -> f32 {
  return fract(sin(p * 127.1) * 43758.5453);
}

fn hash21(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

// Where a point on a face sits on that face's screen: x across, y down from the top.
fn screenOf(face: i32, p: vec3f) -> vec2f {
  switch face {
    case 0: { return vec2f(1.0 - p.z, 1.0 - p.y) * 0.5; }
    case 1: { return vec2f(1.0 + p.z, 1.0 - p.y) * 0.5; }
    case 2: { return vec2f(1.0 + p.x, 1.0 + p.z) * 0.5; }
    case 3: { return vec2f(1.0 + p.x, 1.0 - p.z) * 0.5; }
    case 4: { return vec2f(1.0 + p.x, 1.0 - p.y) * 0.5; }
    default: { return vec2f(1.0 - p.x, 1.0 - p.y) * 0.5; }
  }
}

// Whether a glyph covers a point of its cell, softened by the pixel's width.
fn glyph(kind: i32, id: f32, f: vec2f, pixel: f32) -> f32 {
  var size = vec2f(5.0, 7.0);
  if (kind == 1) { size = vec2f(4.0, 6.0); }
  if (kind == 2 || kind == 3) { size = vec2f(3.0, 5.0); }
  if (kind == 4) { size = vec2f(5.0, 5.0); }
  let g = (f - vec2f(0.16, 0.1)) / vec2f(0.68, 0.8);
  if (any(g < vec2f(0.0)) || any(g >= vec2f(1.0))) { return 0.0; }
  let at = floor(g * size);
  let q = fract(g * size) - 0.5;

  var on = false;
  if (kind == 2 || kind == 3) {
    let digit = select(u32(id * 16.0), u32(id * 2.0), kind == 2);
    let bit = 14u - u32(at.y * 3.0 + at.x);
    on = ((DIGITS[digit] >> bit) & 1u) == 1u;
  } else {
    // Mirrored glyphs read as characters; the narrow ones are left as they fall.
    var column = at.x;
    if (kind != 1) { column = min(at.x, size.x - 1.0 - at.x); }
    on = hash21(vec2f(column, at.y) + id * 97.0) > 0.48;
  }
  if (!on) { return 0.0; }

  let soft = pixel * size.x * 1.5;
  if (kind == 4) { return 1.0 - smoothstep(0.34 - soft, 0.34 + soft, length(q)); }
  if (kind == 5) { return 1.0 - smoothstep(0.3, 0.62, max(abs(q.x), abs(q.y))); }
  return 1.0 - smoothstep(0.42 - soft, 0.42 + soft, max(abs(q.x), abs(q.y)));
}

// One face's screen of falling code. The screen is y-down; pixel is how much of
// it one canvas pixel covers.
fn rain(face: i32, uv: vec2f, pixel: f32) -> vec3f {
  let s = styleOf(face);
  let grid = vec2f(s.columns, floor(s.columns * 1.25));
  let cell = floor(uv * grid);
  let f = fract(uv * grid);
  let seed = hash11(cell.x + f32(face) * 31.7);
  let span = grid.y + s.trail;

  // Two drops fall down each column at their own pace.
  var lit = 0.0;
  var lead = 0.0;
  for (var drop = 0; drop < 2; drop++) {
    let pace = s.speed * (0.55 + 0.9 * hash11(seed * 13.0 + f32(drop)));
    let head = fract(params.time * pace / span + seed + f32(drop) * 0.5) * span;
    let behind = head - cell.y;
    if (behind >= 0.0 && behind < s.trail) {
      lit = max(lit, pow(1.0 - behind / s.trail, 1.7) * (1.0 - 0.35 * f32(drop)));
      lead = max(lead, 1.0 - smoothstep(0.0, 1.2, behind));
    }
  }

  // Each glyph changes now and then, the leading ones more often.
  let flicker = floor(params.time * (1.5 + 5.0 * hash21(cell + 7.0) + 8.0 * lead) + seed * 10.0);
  let id = hash21(cell + vec2f(flicker * 0.37, flicker * 1.13));
  let ink = glyph(s.glyphs, id, f, pixel * grid.x);

  var screen = mix(s.top, s.foot, uv.y);
  if (face == 1) { screen = mix(s.top, s.foot, uv.x * 0.6 + uv.y * 0.4); }
  if (face == 3) { screen = mix(s.top, s.foot, length(uv - vec2f(0.5, 0.35)) * 1.4); }

  var col = screen + s.tail * ink * 0.05;
  col += mix(s.tail, s.head, lead) * ink * lit * 1.15;
  // patchbay.help's screen is scanned; keyfleet.ai's catches a passing gleam.
  if (face == 0) { col *= 0.78 + 0.22 * sin(uv.y * 3.14159 * grid.y * 6.0); }
  if (face == 3) {
    let gleam = fract((uv.x + uv.y) * 0.5 - params.time * 0.08);
    col += s.tail * 0.12 * smoothstep(0.1, 0.0, abs(gleam - 0.5));
  }
  return col;
}

fn raySegment(ro: vec3f, rd: vec3f, a: vec3f, b: vec3f) -> f32 {
  let ab = b - a;
  let ao = ro - a;
  let rdab = dot(rd, ab);
  let denom = dot(ab, ab) - rdab * rdab;
  var s = 0.5;
  if (denom > 1e-5) { s = clamp((dot(ao, ab) - dot(ao, rd) * rdab) / denom, 0.0, 1.0); }
  let on = a + ab * s;
  let t = max(dot(on - ro, rd), 0.0);
  return length(ro + rd * t - on);
}

// How close a ray passes to the nearest of the cube's twelve edges.
fn edgeDistance(ro: vec3f, rd: vec3f) -> f32 {
  var d = 1e3;
  for (var i = 0; i < 4; i++) {
    let u = f32(i & 1) * 2.0 - 1.0;
    let v = f32(i >> 1u) * 2.0 - 1.0;
    d = min(d, raySegment(ro, rd, vec3f(-1.0, u, v), vec3f(1.0, u, v)));
    d = min(d, raySegment(ro, rd, vec3f(u, -1.0, v), vec3f(u, 1.0, v)));
    d = min(d, raySegment(ro, rd, vec3f(u, v, -1.0), vec3f(u, v, 1.0)));
  }
  return d;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let res = max(params.resolution, vec2f(1.0));
  let sp = vec2f((uv.x - 0.5) * 2.0 * res.x / res.y, (0.5 - uv.y) * 2.0);
  let rd = normalize(vec3f(sp * params.lens, -1.0));
  let inverse = vec4f(-params.rotation.xyz, params.rotation.w);
  let ro = qrot(inverse, vec3f(0.0, 0.0, params.distance));
  let dir = qrot(inverse, rd);

  let safe = select(dir, vec3f(1e-6), abs(dir) < vec3f(1e-6));
  let t1 = (vec3f(-1.0) - ro) / safe;
  let t2 = (vec3f(1.0) - ro) / safe;
  let near = min(t1, t2);
  let far = max(t1, t2);
  let enter = max(near.x, max(near.y, near.z));
  let leave = min(far.x, min(far.y, far.z));

  if (enter < leave && enter > 0.0) {
    var face = 4;
    var normal = vec3f(0.0, 0.0, 1.0);
    if (near.x >= near.y && near.x >= near.z) {
      face = select(0, 1, dir.x > 0.0);
      normal = vec3f(-sign(dir.x), 0.0, 0.0);
    } else if (near.y >= near.z) {
      face = select(2, 3, dir.y > 0.0);
      normal = vec3f(0.0, -sign(dir.y), 0.0);
    } else {
      face = select(4, 5, dir.z > 0.0);
      normal = vec3f(0.0, 0.0, -sign(dir.z));
    }
    let screen = screenOf(face, ro + dir * enter);
    // How much of the face one canvas pixel covers, wider where the face turns away.
    let facing = max(dot(normal, -dir), 0.05);
    let pixel = params.lens * enter / (res.y * facing);

    var col = rain(face, screen, pixel);
    let lit = params.glow * select(0.0, 1.0, i32(params.hover + 0.5) == face && params.hover > -0.5);
    col *= (0.5 + 0.5 * facing) * (1.0 + 0.45 * lit);
    // A bright frame round each face, in the colour of its code.
    let edge = max(abs(screen.x - 0.5), abs(screen.y - 0.5)) * 2.0;
    let frame = smoothstep(0.972 - pixel * 2.0, 0.972 + pixel * 2.0, edge);
    let s = styleOf(face);
    col += s.tail * exp(-(1.0 - edge) * 20.0) * (0.25 + 0.35 * lit);
    col = mix(col, s.head * (0.85 + 0.3 * lit), frame);
    col += (hash21(uv * res) - 0.5) / 255.0;
    return vec4f(col, 1.0);
  }

  // Off the cube the canvas is clear, but for the light along its edges.
  let d = edgeDistance(ro, dir);
  let halo = 0.03 / (d + 0.03);
  let alpha = clamp(halo * halo * (0.7 + 0.4 * params.glow), 0.0, 1.0);
  return vec4f(vec3f(0.78, 0.95, 0.86) * alpha, alpha);
}
`
