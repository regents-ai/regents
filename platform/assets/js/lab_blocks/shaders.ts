/**
 * The Overview hero's WGSL, in three parts drawn back to front: the tunnel, the
 * blocks (the crown's and the products') and the beams between the products.
 *
 * Everything is shaded by the still picture's rules
 * (`RegentsWeb.Components.LabBlocks.Still` and `LabBlocks.Scene`), mixing in
 * sRGB as `color-mix(in srgb, …)` does, so the two pictures meet when one fades
 * over the other. A face is lit by how squarely it meets the light, times its
 * block's exposure, then shaded along itself: a side from its top edge down, a
 * top from its back edge forward. A product or beam far away takes a little of
 * the tunnel's far colour; the crown is lit and keeps its own.
 */

const view = /* wgsl */ `
struct View {
  // The camera: where it stands and which way is right, up and ahead, with the
  // tangent of half its view, the stage's proportions, and device pixels to a CSS pixel.
  eye: vec4f,
  right: vec4f,
  up: vec4f,
  forward: vec4f,
  // The canvas in device pixels, and one over each.
  size: vec4f,
  // Which way the light comes from, and how much of the scene a pick holds.
  light: vec4f,
  // The theme's colours: the tunnel near and far and its seams, the crown's two
  // ends, the tone a beam rests in and the one it lights to.
  near: vec4f,
  far: vec4f,
  seam: vec4f,
  crownTop: vec4f,
  crownFoot: vec4f,
  beamTone: vec4f,
  litTone: vec4f,
  // Half the tunnel's width and height, where it starts and ends; how deep a
  // band is, how wide a tile, and how far the camera stands from its target.
  tunnel: vec4f,
  tunnel2: vec4f,
}

@group(0) @binding(0) var<uniform> view: View;

const AMBIENT = 0.46;
const DIFFUSE = 0.54;
const FOG_FROM = 12.0;
const FOG_TO = 44.0;
const FOG_MOST = 0.3;

fn toClip(p: vec3f) -> vec4f {
  let d = p - view.eye.xyz;
  let depth = dot(d, view.forward.xyz);
  let t = view.right.w;
  // Near and far: in front of the tunnel's mouth, and past its far wall.
  let near = 0.5;
  let far = 80.0;
  return vec4f(dot(d, view.right.xyz) / (t * view.up.w), dot(d, view.up.xyz) / t, far / (far - near) * (depth - near), depth);
}

// The share of the far colour a point this deep takes.
fn fog(p: vec3f) -> f32 {
  let depth = dot(p - view.eye.xyz, view.forward.xyz);
  return FOG_MOST * clamp((depth - FOG_FROM) / (FOG_TO - FOG_FROM), 0.0, 1.0);
}

// Darker below one, toward white above it, as the still picture mixes.
fn shade(base: vec3f, k: f32) -> vec3f {
  if (k <= 1.0) {
    return base * k;
  }
  return mix(base, vec3f(1.0), min(k, 2.0) - 1.0);
}

// Breaks up the steps between neighbouring 8-bit colours.
fn grain(p: vec2f) -> f32 {
  return (fract(sin(dot(p, vec2f(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
}
`

/**
 * The tunnel, one ray a pixel: four walls stepping band by band from the near
 * colour, which is the panel's own, to the far one, each at its own pace and
 * slowly at first, and the far wall in the far colour. Seams run back along the
 * walls between the tiles and come in along them, so nothing marks the rim. As
 * `LabBlocks.Scene.tunnel/2` draws it still.
 */
const tunnel = /* wgsl */ `
${view}

// How quickly each wall's bands take the far colour, against the floor's.
const FLOOR = 1.0;
const SIDE = 1.15;
const CEILING = 1.3;
// Where along the walls, in bands from the rim, the seams start to show and where they show in full.
const SEAM_FROM = 0.5;
const SEAM_TO = 5.0;

@vertex fn vs_main(@builtin(vertex_index) vertex: u32) -> @builtin(position) vec4f {
  let x = f32((vertex << 1u) & 2u);
  let y = f32(vertex & 2u);
  return vec4f(x * 2.0 - 1.0, y * 2.0 - 1.0, 1.0, 1.0);
}

fn band(k: f32, count: f32, slope: f32) -> vec3f {
  let share = min(1.0, max(k, 0.0) / count * slope);
  return mix(view.near.rgb, view.far.rgb, share * sqrt(share));
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let ndc = vec2f(position.x * view.size.z * 2.0 - 1.0, 1.0 - position.y * view.size.w * 2.0);
  let t = view.right.w;
  let d = normalize(view.forward.xyz + view.right.xyz * ndc.x * t * view.up.w + view.up.xyz * ndc.y * t);
  let o = view.eye.xyz;
  let w = view.tunnel.x;
  let h = view.tunnel.y;
  let near = view.tunnel.z;
  let far = view.tunnel.w;
  let deep = view.tunnel2.x;
  let tile = view.tunnel2.y;

  // The nearest of the four walls and the far wall along the ray.
  var s = 1e9;
  var wall = 4;
  if (d.y < 0.0) { let at = (-h - o.y) / d.y; if (at < s) { s = at; wall = 0; } }
  if (d.y > 0.0) { let at = (h - o.y) / d.y; if (at < s) { s = at; wall = 3; } }
  if (d.x < 0.0) { let at = (-w - o.x) / d.x; if (at < s) { s = at; wall = 1; } }
  if (d.x > 0.0) { let at = (w - o.x) / d.x; if (at < s) { s = at; wall = 2; } }
  let back = (far - o.z) / d.z;
  if (d.z < 0.0 && back < s) { s = back; wall = 4; }
  let p = o + d * s;
  let level = wall == 0 || wall == 3;
  let across = select(p.y, p.x, level);
  // Derivatives are taken here, where every pixel takes them together.
  let u = (near - p.z) / deep;
  let du = max(fwidth(u), 1e-5);
  let pixel = max(fwidth(across), 1e-5);

  var colour = view.far.rgb;
  if (wall < 4) {
    let count = round((near - far) / deep);
    let slope = select(select(SIDE, CEILING, wall == 3), FLOOR, wall == 0);
    // Each band's edge is a pixel soft, the band before on one side, its own on the other.
    let k = round(u);
    colour = mix(band(k - 1.0, count, slope), band(k, count, slope), clamp((u - k) / du + 0.5, 0.0, 1.0));

    // The seams between tiles, a CSS pixel wide, coming in along the wall.
    let span = select(h, w, level);
    let nearest = round(across / tile) * tile;
    let line = clamp(view.forward.w * 0.5 + 0.5 - abs(across - nearest) / pixel, 0.0, 1.0);
    let inside = step(abs(nearest), span - 0.01);
    colour = mix(colour, view.seam.rgb, line * inside * smoothstep(SEAM_FROM, SEAM_TO, u));
  }

  return vec4f(colour + grain(position.xy), 1.0);
}
`

/** One block per instance, its six faces from the vertex index. */
const boxes = /* wgsl */ `
${view}

struct BoxIn {
  @builtin(vertex_index) vertex: u32,
  // Middle, and how lit it is.
  @location(0) place: vec4f,
  // Half its size on each axis, and how far it is set back.
  @location(1) half: vec4f,
  // Its three axes; with them, its exposure and, for the crown's, where along
  // the crown's gradient it sits (below zero for a product's).
  @location(2) ax: vec4f,
  @location(3) ay: vec4f,
  @location(4) az: vec4f,
  // A product's own colour.
  @location(5) colour: vec4f,
}

struct BoxOut {
  @builtin(position) position: vec4f,
  // The face's two shades, from its first edge to its second.
  @location(0) @interpolate(flat) first: vec3f,
  @location(1) @interpolate(flat) second: vec3f,
  @location(2) grade: f32,
  // Where on the face, from -1 to 1 each way, and whether it is a top.
  @location(3) face: vec2f,
  @location(4) @interpolate(flat) top: f32,
}

struct Face {
  normal: vec3f,
  depth: f32,
  up: vec3f,
  across: vec3f,
  kind: u32,
}

fn faceOf(index: u32, ax: vec3f, ay: vec3f, az: vec3f, h: vec3f) -> Face {
  switch index {
    case 0u: { return Face(ax, h.x, ay * h.y, az * h.z, 0u); }
    case 1u: { return Face(-ax, h.x, ay * h.y, az * h.z, 0u); }
    case 2u: { return Face(az, h.z, ay * h.y, ax * h.x, 0u); }
    case 3u: { return Face(-az, h.z, ay * h.y, ax * h.x, 0u); }
    case 4u: { return Face(ay, h.y, az * h.z, ax * h.x, 1u); }
    default: { return Face(-ay, h.y, az * h.z, ax * h.x, 2u); }
  }
}

@vertex fn vs_main(in: BoxIn) -> BoxOut {
  var corners = array<vec2f, 4>(vec2f(1.0, 1.0), vec2f(1.0, -1.0), vec2f(-1.0, -1.0), vec2f(-1.0, 1.0));
  var order = array<u32, 6>(0u, 1u, 2u, 0u, 2u, 3u);
  // How much lighter each kind of face's first edge is than its second: a side, a top, a bottom.
  var grades = array<vec2f, 3>(vec2f(1.08, 0.84), vec2f(1.16, 0.98), vec2f(0.6, 0.6));
  let face = faceOf(in.vertex / 6u, in.ax.xyz, in.ay.xyz, in.az.xyz, in.half.xyz);
  let corner = corners[order[in.vertex % 6u]];
  let p = in.place.xyz + face.normal * face.depth + face.up * corner.x + face.across * corner.y;

  // A crown block takes its place along the crown's gradient and, being lit,
  // keeps it; a product takes its own colour and the far colour by its depth.
  let crown = in.ay.w >= 0.0;
  let own = select(in.colour.rgb, mix(view.crownTop.rgb, view.crownFoot.rgb, in.ay.w), crown);
  let base = select(mix(own, view.far.rgb, fog(in.place.xyz)), own, crown);
  let k = in.ax.w * (AMBIENT + DIFFUSE * max(dot(face.normal, view.light.xyz), 0.0));
  let g = grades[face.kind];

  // A picked block lights up and the rest step back toward the ground; the crown
  // steps back toward the far wall while a pick holds.
  let lit = in.place.w;
  let back = in.half.w;
  let held = select(0.0, view.light.w * 0.45, crown);
  var first = shade(base, k * g.x);
  var second = shade(base, k * g.y);
  first = mix(mix(first, min(first * 1.18 + 0.06, vec3f(1.0)), lit), view.near.rgb, back * 0.62);
  second = mix(mix(second, min(second * 1.18 + 0.06, vec3f(1.0)), lit), view.near.rgb, back * 0.62);

  var out: BoxOut;
  out.position = toClip(p);
  out.first = mix(first, view.far.rgb, held);
  out.second = mix(second, view.far.rgb, held);
  // A side runs from its top edge down; a top from its back edge forward.
  out.grade = select((1.0 - corner.x) * 0.5, (1.0 + corner.x) * 0.5, face.kind == 1u);
  out.face = corner;
  out.top = select(0.0, 1.0, face.kind == 1u);
  return out;
}

@fragment fn fs_main(in: BoxOut) -> @location(0) vec4f {
  var colour = mix(in.first, in.second, in.grade);
  // A clean light edge round each top, a device pixel wide.
  let edge = 1.0 - max(abs(in.face.x), abs(in.face.y));
  let rim = in.top * (1.0 - smoothstep(0.0, fwidth(edge) * 1.5, edge));
  colour = mix(colour, min(colour * 1.15 + 0.04, vec3f(1.0)), rim * 0.7);
  return vec4f(colour + grain(in.position.xy), 1.0);
}
`

/** One beam per instance: a quad a few CSS pixels wide, wider the nearer it is. */
const beams = /* wgsl */ `
${view}

// A beam's width in CSS pixels at the camera's own distance from its target, and
// how much of its ends' colour it keeps at rest and lit.
const WIDTH = 1.4;
const REST = 0.62;
const LIT = 0.8;

struct BeamIn {
  @builtin(vertex_index) vertex: u32,
  // Its two ends, with how lit and how set back it is.
  @location(0) a: vec4f,
  @location(1) b: vec4f,
  // Each end's own colour.
  @location(2) head: vec4f,
  @location(3) tail: vec4f,
}

struct BeamOut {
  @builtin(position) position: vec4f,
  @location(0) colour: vec3f,
}

@vertex fn vs_main(in: BeamIn) -> BeamOut {
  var corners = array<vec2f, 6>(vec2f(0.0, -1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0), vec2f(0.0, -1.0), vec2f(1.0, 1.0), vec2f(0.0, 1.0));
  let corner = corners[in.vertex];
  let lit = in.a.w;
  let back = in.b.w;
  let ca = toClip(in.a.xyz);
  let cb = toClip(in.b.xyz);
  let pixels = view.size.xy;
  let along = normalize((cb.xy / cb.w - ca.xy / ca.w) * pixels);
  let normal = vec2f(-along.y, along.x);
  let at = corner.x > 0.5;
  let end = select(ca, cb, at);
  let halfWidth = WIDTH * 0.5 * view.forward.w * view.tunnel2.z / end.w * (1.0 + 0.7 * lit);
  let push = normal * corner.y * halfWidth * 2.0 / pixels;

  let own = select(in.head.rgb, in.tail.rgb, at);
  let resting = mix(view.beamTone.rgb, own, REST);
  let lighted = mix(view.litTone.rgb, own, LIT);
  let colour = mix(mix(resting, lighted, lit), view.far.rgb, fog(select(in.a.xyz, in.b.xyz, at)));

  var out: BeamOut;
  out.position = end + vec4f(push * end.w, 0.0, 0.0);
  out.colour = mix(colour, view.near.rgb, back * 0.72);
  return out;
}

@fragment fn fs_main(in: BeamOut) -> @location(0) vec4f {
  return vec4f(in.colour + grain(in.position.xy), 1.0);
}
`

export const shaders = {tunnel, boxes, beams}
