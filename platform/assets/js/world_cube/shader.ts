/**
 * The world cube, drawn by one fullscreen shader.
 *
 * Every pixel casts a ray at a cube. The face the ray enters is a window, and
 * behind each window is a room far larger than the cube that holds it: the ray
 * is carried into that face's own space and walked through the room there. So
 * turning the cube slides each room behind its frame, and flying the camera
 * through a window is the same picture with the frame left behind.
 *
 * Every room is built of blocks, the way the crown is. A room is described as
 * plain shapes, and the walk through it asks only whether the middle of each
 * block-sized cell is inside one: a cell that is becomes a block, in one of
 * three sizes, so curves and slopes come out as steps. Behind each room hangs a
 * sheet of squares in the palette's gradient.
 *
 * Rooms are indexed by the face they sit behind: 0 +x, 1 -x, 2 +y, 3 -y, 4 +z,
 * 5 -z. In a room's own space the window is the square at z = 1, x runs right,
 * y runs up and the floor is y = -1. Rooms are laid out in blocks: one block is
 * a twelfth of that, so the window is 24 blocks across.
 */
export const worldCubeWgsl = /* wgsl */ `
struct Params {
  resolution: vec2f,
  // Yaw and pitch of the visitor's head once inside a room.
  look: vec2f,
  time: f32,
  // Camera distance from the cube's centre; under 1 it is inside.
  distance: f32,
  // Cube orientation, object to world.
  rotation: vec4f,
  // Tangent of half the vertical field of view.
  lens: f32,
  // The room the camera is flying into or standing in.
  face: f32,
  // The face under a resting pointer, and how strongly it is lit for it.
  hover: f32,
  glow: f32,
  // How far the cube is drawn from the middle of the canvas, across, in the
  // units the screen is measured in: half the canvas height is one.
  shift: f32,
}
@group(0) @binding(0) var<uniform> params: Params;

const PI = 3.14159265;
// One block: the smallest of the three sizes a room is built in.
const U = 0.0833333333;
// The palette, in linear light.
const TANGERINE = vec3f(1.0, 0.105, 0.010);
const POWDER = vec3f(0.423, 0.591, 0.610);
const PLATINUM = vec3f(0.783, 0.767, 0.646);
const GOLD = vec3f(1.0, 0.62, 0.18);

fn rot(a: f32) -> mat2x2f {
  let c = cos(a);
  let s = sin(a);
  return mat2x2f(c, s, -s, c);
}

fn qrot(q: vec4f, v: vec3f) -> vec3f {
  let t = 2.0 * cross(q.xyz, v);
  return v + q.w * t + cross(q.xyz, t);
}

fn hash21(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn hash31(p: vec3f) -> f32 {
  var q = fract(p * vec3f(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn sdBox(p: vec3f, b: vec3f) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3f(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCapsule(p: vec3f, a: vec3f, b: vec3f, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

// A box given by its two opposite corners, in blocks.
fn slab(p: vec3f, lo: vec3f, hi: vec3f) -> f32 {
  return sdBox(p - (lo + hi) * (0.5 * U), (hi - lo) * (0.5 * U));
}

fn pick(a: vec2f, d: f32, m: f32) -> vec2f {
  if (d < a.x) { return vec2f(d, m); }
  return a;
}

// The same, for loose blocks that only ever fill open air.
fn pickLoose(a: vec2f, d: f32, m: f32) -> vec2f {
  if (a.x > 0.0 && d < a.x) { return vec2f(d, m); }
  return a;
}

// Keeps a shape in the smallest blocks however thick it is.
fn fine(d: f32) -> f32 {
  return max(d, -0.2 * U);
}

// A shape repeated along a row knows only its own copy. This keeps its distance
// honest by never promising more room than there is to the next copy's ground.
fn fence(d: f32, edge: f32) -> f32 {
  return select(d, min(d, edge + 0.7 * U), d > 0.0);
}

// A falling edge: 1 below low, 0 above high.
fn fade(high: f32, low: f32, x: f32) -> f32 {
  return 1.0 - smoothstep(low, high, x);
}

fn brandWeight(phase: f32, centre: f32) -> f32 {
  return max(0.0, 1.0 - abs(fract(phase - centre + 0.5) - 0.5) * 3.0);
}

// The palette's gradient, as the foil card runs it: tangerine, powder blue,
// platinum, and round again.
fn brand(phase: f32) -> vec3f {
  return TANGERINE * brandWeight(phase, 0.0)
    + POWDER * brandWeight(phase, 1.0 / 3.0)
    + PLATINUM * brandWeight(phase, 2.0 / 3.0);
}

// Blocks adrift far behind a room: one cell in eleven holds one, whole or an eighth.
fn drift(p: vec3f, seed: f32) -> f32 {
  let g = p / (4.0 * U);
  let id = floor(g);
  let h = hash31(id + seed);
  let local = (g - id - 0.5) * (4.0 * U);
  let edge = 2.0 * U - max(abs(local.x), max(abs(local.y), abs(local.z)));
  var d = 1e3;
  if (h > 0.955) {
    d = sdBox(local, vec3f(2.0 * U));
  } else if (h > 0.91) {
    let corner = sign(vec3f(fract(h * 31.0), fract(h * 57.0), fract(h * 91.0)) - 0.5);
    d = sdBox(local - corner * U, vec3f(U));
  }
  return fence(d, edge);
}

// ---------------------------------------------------------------- Autolaunch
// A launch pad at dawn: a rocket holding over its pad, bids stacking up beside it.

// Where the rocket stands, across and deep, in blocks.
const LAUNCH_AT = vec2f(0.0, -18.0);

// Which bid stack a depth belongs to, counted back from the window.
fn launchStack(z: f32) -> f32 {
  return clamp(round((-14.0 - z) / 8.0), 0.0, 3.0);
}

fn fillLaunch(p: vec3f, loose: bool) -> vec2f {
  let b = p / U;
  var res = vec2f(slab(p, vec3f(-32.0, -16.0, -52.0), vec3f(32.0, -12.0, 12.0)), 1.0);
  res = pick(res, slab(p, vec3f(-8.0, -12.0, -26.0), vec3f(8.0, -10.0, -10.0)), 2.0);

  let q = vec3f(b.x - LAUNCH_AT.x, b.y, b.z - LAUNCH_AT.y);
  let wide = max(abs(q.x), abs(q.z));
  let thin = min(abs(q.x), abs(q.z));
  var rocket = max(wide - 2.0, abs(q.y) - 6.0);
  rocket = min(rocket, max(wide - (11.0 - q.y) * 0.5, 6.0 - q.y));
  rocket = min(rocket, max(max(thin - 1.0, wide - 4.0), max(-6.0 - q.y, q.y + 0.75 + wide)));
  res = pick(res, rocket * U * 0.85, 3.0);
  res = pick(res, max(wide - 1.0, abs(q.y + 6.5) - 0.5) * U, 8.0);

  var gantry = slab(p, vec3f(-14.0, -12.0, -19.0), vec3f(-12.0, 8.0, -17.0));
  gantry = min(gantry, slab(p, vec3f(-12.0, 2.0, -19.0), vec3f(-2.0, 3.0, -17.0)));
  res = pick(res, gantry, 4.0);
  res = pick(res, slab(p, vec3f(-14.0, 8.0, -19.0), vec3f(-12.0, 10.0, -17.0)), 5.0);

  // Bid stacks down both sides: each one further back stands a block taller.
  let side = abs(b.x);
  let id = launchStack(b.z);
  let zc = -14.0 - 8.0 * id;
  let top = -12.0 + 4.0 * (id + 1.0);
  let dz = abs(b.z - zc);
  let edge = select((4.0 - dz) * U, 1e3, dz > 4.0);
  let stack = sdBox(vec3f(side - 14.0, b.y - (top - 12.0) * 0.5, b.z - zc), vec3f(2.0, (top + 12.0) * 0.5, 2.0)) * U;
  res = pick(res, fence(stack, edge), 6.0);

  // The skyline along the back edge.
  let ahead = -44.0 * U - p.z;
  if (ahead < 0.3) {
    let col = floor(b.x / 4.0);
    let h = 4.0 * (1.0 + floor(hash21(vec2f(col, 3.0)) * 4.0));
    let lx = b.x - col * 4.0 - 2.0;
    let tower = sdBox(vec3f(lx, b.y + 12.0 - h * 0.5, b.z + 48.0), vec3f(2.0, h * 0.5, 4.0)) * U;
    res = pick(res, max(fence(tower, (2.0 - abs(lx)) * U), (side - 32.0) * U), 7.0);
  } else {
    res.x = min(res.x, ahead);
  }

  if (loose) {
    res = pickLoose(res, fine(max(wide - 2.0, abs(q.y + 8.5) - 1.5) * U), 10.0);
    res = pickLoose(res, max(max(wide - 12.0, 2.0 - wide), abs(q.y + 9.5) - 2.5) * U, 11.0);
    let bid = sdBox(vec3f(side - 15.0, b.y - top - 3.0, b.z - zc + 1.0), vec3f(1.0)) * U;
    res = pickLoose(res, fence(bid, edge), 12.0);
  }
  return res;
}

// ------------------------------------------------------------------ Techtree
// One luminous tree on its mound, branching and branching again.

// The foot of the trunk, in blocks.
const TREE_AT = vec3f(0.0, -8.0, -18.0);

fn fillTree(p: vec3f, loose: bool) -> vec2f {
  var res = vec2f(slab(p, vec3f(-28.0, -16.0, -48.0), vec3f(28.0, -12.0, 12.0)), 1.0);
  var mound = slab(p, vec3f(-10.0, -12.0, -28.0), vec3f(10.0, -10.0, -8.0));
  mound = min(mound, slab(p, vec3f(-6.0, -10.0, -24.0), vec3f(6.0, -8.0, -12.0)));
  res = pick(res, mound, 2.0);

  // Four standing stones at the corners of the grove.
  let stone = vec3f(abs(p.x) - 20.0 * U, p.y + 8.0 * U, abs(p.z + 18.0 * U) - 16.0 * U);
  res = pick(res, sdBox(stone, vec3f(2.0, 4.0, 2.0) * U), 5.0);

  var q = p - TREE_AT * U;
  let near = length(q - vec3f(0.0, 0.85, 0.0)) - 1.5;
  if (near < 0.3) {
    var s = 1.0;
    var wood = sdCapsule(q, vec3f(0.0), vec3f(0.0, 0.5, 0.0), 0.09);
    var nodes = 1e3;
    for (var i = 0; i < 4; i++) {
      q.y -= 0.5;
      nodes = min(nodes, length(q) / s - 0.07);
      q = vec3f(abs(q.x), q.y, abs(q.z));
      let xy = rot(0.62) * q.xy;
      let zy = rot(0.44) * vec2f(q.z, xy.y);
      q = vec3f(xy.x, zy.y, zy.x) * 1.3;
      s *= 1.3;
      wood = min(wood, sdCapsule(q, vec3f(0.0), vec3f(0.0, 0.5, 0.0), 0.062 * s) / s);
    }
    res = pick(res, wood, 3.0);
    res = pick(res, nodes, 4.0);
    if (loose) {
      res = pickLoose(res, length(q - vec3f(0.0, 0.5, 0.0)) / s - 0.13, 10.0);
    }
  } else {
    res.x = min(res.x, near);
  }
  return res;
}

// ------------------------------------------------------------------ Patchbay
// The exchange: a great hall whose whole end wall is a switchboard, cords slung
// from socket to socket across it and signals running along them. Rows of desks
// face it, an aisle of light runs up to it, and over it the hall is glass, with
// a planet rising in the night beyond.

// Where the board's first socket starts, across and up, in blocks.
const PATCH_BOARD = vec2f(-48.0, -6.0);

// How far a point on the far sheet is past the planet's edge; under zero is on it.
fn patchPlanet(v: vec2f) -> f32 {
  return length(v - vec2f(0.3, 0.12)) - 0.42;
}

// The cord nearest a point: how far, which one, and how far along it.
fn patchCable(p: vec3f) -> vec3f {
  // Each cord: its two sockets, then how far it sags.
  var ends = array<vec4f, 8>(
    vec4f(-42.0, 15.0, -10.0, 7.0),
    vec4f(-34.0, 3.0, 6.0, 15.0),
    vec4f(-22.0, 15.0, 30.0, 11.0),
    vec4f(-6.0, 3.0, 42.0, 15.0),
    vec4f(-46.0, -1.0, 22.0, -1.0),
    vec4f(10.0, 7.0, 38.0, 3.0),
    vec4f(-30.0, 11.0, -14.0, 15.0),
    vec4f(18.0, 15.0, 46.0, 7.0));
  var sags = array<f32, 8>(8.0, 8.0, 10.0, 7.0, 4.0, 5.0, 4.0, 6.0);
  let b = p / U;
  var best = vec3f(1e3, 0.0, 0.0);
  for (var i = 0; i < 8; i++) {
    let e = ends[i];
    let x = clamp(b.x, e.x, e.z);
    let u = (x - e.x) / (e.z - e.x);
    let droop = 4.0 * u * (1.0 - u);
    let y = mix(e.y, e.w, u) - sags[i] * droop;
    let slope = (e.w - e.y - sags[i] * 4.0 * (1.0 - 2.0 * u)) / (e.z - e.x);
    let z = -47.0 + 4.0 * droop;
    let d = (length(vec3f(b.x - x, (b.y - y) / sqrt(1.0 + slope * slope), b.z - z)) - 1.0) * U;
    if (d < best.x) { best = vec3f(d, f32(i), u); }
  }
  return best;
}

fn fillPatch(p: vec3f, loose: bool) -> vec2f {
  let b = p / U;
  let side = abs(b.x);
  var res = vec2f(slab(p, vec3f(-56.0, -16.0, -56.0), vec3f(56.0, -12.0, 12.0)), 1.0);

  // The hall's frame: its side walls, the plinth the board stands on, the beam
  // over the board, and the bars of the glass above and overhead.
  let rib = b.z + 6.0 - 12.0 * clamp(round((b.z + 6.0) / 12.0), -3.0, 1.0);
  let bar = b.x - 12.0 * clamp(round(b.x / 12.0), -4.0, 4.0);
  var frame = sdBox(vec3f(side - 52.0, b.y - 12.0, b.z + 20.0), vec3f(2.0, 24.0, 32.0));
  frame = min(frame, sdBox(vec3f(b.x, b.y + 9.0, b.z + 49.0), vec3f(50.0, 3.0, 3.0)));
  frame = min(frame, sdBox(vec3f(b.x, b.y - 19.0, b.z + 49.0), vec3f(50.0, 1.0, 1.5)));
  frame = min(frame, sdBox(vec3f(bar, b.y - 27.5, b.z + 49.0), vec3f(1.0, 7.5, 1.0)));
  frame = min(frame, sdBox(vec3f(b.x, b.y - 35.5, b.z + 49.0), vec3f(50.0, 0.5, 1.0)));
  frame = min(frame, sdBox(vec3f(b.x, b.y - 36.0, rib), vec3f(50.0, 1.0, 1.0)));
  res = pick(res, frame * U, 2.0);

  // The board fills the end wall, in the smallest blocks so each socket shows.
  res = pick(res, fine(slab(p, vec3f(-48.0, -6.0, -50.0), vec3f(48.0, 18.0, -48.0))), 3.0);

  // Desks in three rows, two each side of the aisle: a body, its keys, its screen.
  let row = clamp(round((-10.0 - b.z) / 12.0), 0.0, 2.0);
  let lz = b.z + 10.0 + 12.0 * row;
  let lx = abs(side - 22.0) - 8.0;
  let apart = select((6.0 - abs(lz)) * U, 1e3, abs(lz) > 6.0);
  res = pick(res, fence(sdBox(vec3f(lx, b.y + 10.0, lz), vec3f(4.0, 2.0, 2.0)) * U, apart), 4.0);
  res = pick(res, fence(sdBox(vec3f(lx, b.y + 7.5, lz - 0.5), vec3f(3.0, 0.5, 1.0)) * U, apart), 5.0);
  res = pick(res, fence(sdBox(vec3f(lx, b.y + 6.0, lz + 1.5), vec3f(2.0, 1.0, 0.5)) * U, apart), 9.0);

  // A lamp under every other bar of the roof, down the middle of the hall.
  let lamp = b.z + 18.0 - 24.0 * clamp(round((b.z + 18.0) / 24.0), -1.0, 0.0);
  res = pick(res, sdBox(vec3f(b.x, b.y - 34.0, lamp), vec3f(1.0)) * U, 6.0);

  let near = slab(p, vec3f(-50.0, -8.0, -48.0), vec3f(50.0, 18.0, -41.0));
  if (near < 0.3) {
    res = pick(res, fine(patchCable(p).x), 7.0);
  } else {
    res.x = min(res.x, near);
  }
  return res;
}

// ----------------------------------------------------------------- Regents X
// A black observatory: a great X sending rings out, and posts wheeling round it.

// The middle of the X, in blocks.
const SIGNAL_AT = vec3f(0.0, 5.0, -18.0);

fn fillSignal(p: vec3f, loose: bool) -> vec2f {
  var res = vec2f(slab(p, vec3f(-32.0, -16.0, -52.0), vec3f(32.0, -12.0, 12.0)), 1.0);
  var plinth = slab(p, vec3f(-8.0, -12.0, -26.0), vec3f(8.0, -10.0, -10.0));
  plinth = min(plinth, slab(p, vec3f(-4.0, -10.0, -22.0), vec3f(4.0, -8.0, -14.0)));
  res = pick(res, plinth, 2.0);

  let m = p - SIGNAL_AT * U;
  let a = rot(PI * 0.25) * m.xy;
  let c = rot(-PI * 0.25) * m.xy;
  let bars = min(
    sdBox(vec3f(a, m.z), vec3f(1.25, 9.5, 1.0) * U),
    sdBox(vec3f(c, m.z), vec3f(1.25, 9.5, 1.0) * U));
  res = pick(res, bars, 3.0);
  return res;
}

// ------------------------------------------------------------- Regents stake
// A hall of gates leading to the crown, with stakes piling up before it.

// Where the crown hangs, in blocks.
const HALL_CROWN = vec3f(0.0, 4.0, -22.0);
const CROWN_PITCH = 0.2;
const CROWN_HALF = 0.086;

// How tall each pile of stakes stands right now, in blocks: it grows a block at
// a time, then starts again.
fn stakeHeight(pile: f32) -> f32 {
  return 1.0 + 9.0 * fract(params.time * 0.045 + pile * 0.31);
}

// Which pile a block belongs to, from how deep it sits.
fn stakePile(z: f32) -> f32 {
  if (z < -16.0) { return 0.0; }
  if (z < -8.0) { return 1.0; }
  return 2.0;
}

fn fillHall(p: vec3f, loose: bool) -> vec2f {
  let b = p / U;
  let side = abs(b.x);
  var res = vec2f(slab(p, vec3f(-24.0, -16.0, -56.0), vec3f(24.0, -12.0, 12.0)), 1.0);

  // The gates: two columns and the beam across them, bay after bay.
  let bay = clamp(round((-2.0 - b.z) / 12.0), 0.0, 3.0);
  let lz = b.z + 2.0 + 12.0 * bay;
  var gate = sdBox(vec3f(side - 18.0, b.y - 2.0, lz), vec3f(2.0, 14.0, 2.0));
  gate = min(gate, sdBox(vec3f(side - 18.0, b.y + 11.0, lz), vec3f(3.0, 1.0, 3.0)));
  gate = min(gate, sdBox(vec3f(side, b.y - 18.0, lz), vec3f(22.0, 2.0, 2.0)));
  res = pick(res, fence(gate * U, select((6.0 - abs(lz)) * U, 1e3, abs(lz) > 6.0)), 2.0);

  var dais = slab(p, vec3f(-12.0, -12.0, -30.0), vec3f(12.0, -10.0, -14.0));
  dais = min(dais, slab(p, vec3f(-9.0, -10.0, -28.0), vec3f(9.0, -8.0, -16.0)));
  dais = min(dais, slab(p, vec3f(-6.0, -8.0, -26.0), vec3f(6.0, -6.0, -18.0)));
  res = pick(res, dais, 3.0);

  // The end wall, and the stepped arch cut through it.
  let wall = slab(p, vec3f(-24.0, -12.0, -56.0), vec3f(24.0, 28.0, -52.0));
  let arch = max(side - 8.0, b.y - 16.0 + max(side - 4.0, 0.0)) * U * 0.7;
  res = pick(res, max(wall, -arch), 4.0);

  if (loose) {
    var piles = sdBox(vec3f(side - 11.0, b.y + 5.0, b.z + 23.0), vec3f(1.0, 5.0, 1.0));
    piles = min(piles, sdBox(vec3f(side - 7.0, b.y + 7.0, b.z + 11.0), vec3f(1.0, 5.0, 1.0)));
    piles = min(piles, sdBox(vec3f(side - 9.0, b.y + 7.0, b.z + 5.0), vec3f(1.0, 5.0, 1.0)));
    res = pickLoose(res, piles * U, 10.0);
  }
  return res;
}

// ------------------------------------------------------------------ Keyfleet
// A harbour at dusk: keys standing guard round the harbour wall, a lighthouse,
// lantern boats on the water.

// The lighthouse lamp, in blocks.
const HARBOUR_LAMP = vec3f(14.0, 10.0, -30.0);
// How far apart a key's blocks sit, and half a block's width.
const KEY_PITCH = 0.1;
const KEY_HALF = 0.043;

// How far round the lighthouse beam has swept.
fn harbourSweep() -> f32 {
  return params.time * 0.45;
}

// How squarely the beam, which shines both ways, falls on a point: 1 in its path.
fn harbourBeam(b: vec3f) -> f32 {
  let angle = atan2(b.z - HARBOUR_LAMP.z, b.x - HARBOUR_LAMP.x) - harbourSweep();
  let off = abs(fract(angle / PI + 0.5) - 0.5) * PI;
  return fade(0.2, 0.04, off);
}

fn fillHarbour(p: vec3f, loose: bool) -> vec2f {
  let b = p / U;
  var res = vec2f(slab(p, vec3f(-40.0, -16.0, -60.0), vec3f(40.0, -12.0, 12.0)), 1.0);

  // The harbour wall: down both sides and across the back, open at the mouth.
  var wall = slab(vec3f(abs(p.x), p.y, p.z), vec3f(18.0, -12.0, -48.0), vec3f(22.0, -10.0, 12.0));
  wall = min(wall, max(slab(p, vec3f(-22.0, -12.0, -52.0), vec3f(22.0, -10.0, -48.0)), 4.0 * U - abs(p.x)));
  res = pick(res, wall, 9.0);

  let ashore = slab(p, vec3f(4.0, -12.0, -40.0), vec3f(18.0, 13.0, -22.0));
  if (ashore < 0.3) {
    var rock = slab(p, vec3f(4.0, -12.0, -40.0), vec3f(18.0, -10.0, -22.0));
    rock = min(rock, slab(p, vec3f(8.0, -10.0, -36.0), vec3f(18.0, -8.0, -24.0)));
    res = pick(res, rock, 2.0);
    var tower = slab(p, vec3f(12.0, -8.0, -32.0), vec3f(16.0, 4.0, -28.0));
    tower = min(tower, slab(p, vec3f(13.0, 4.0, -31.0), vec3f(15.0, 8.0, -29.0)));
    tower = min(tower, slab(p, vec3f(11.0, 8.0, -33.0), vec3f(17.0, 9.0, -27.0)));
    tower = min(tower, slab(p, vec3f(12.0, 11.0, -32.0), vec3f(16.0, 12.0, -28.0)));
    tower = min(tower, slab(p, vec3f(13.0, 12.0, -31.0), vec3f(15.0, 13.0, -29.0)));
    res = pick(res, tower, 3.0);
    res = pick(res, slab(p, vec3f(13.0, 9.0, -31.0), vec3f(15.0, 11.0, -29.0)), 4.0);
  } else {
    res.x = min(res.x, ashore);
  }

  // The jetty running out from the wall, on its posts.
  var pier = slab(p, vec3f(-18.0, -11.0, -10.0), vec3f(-8.0, -10.0, -6.0));
  pier = min(pier, slab(p, vec3f(-9.0, -12.0, -10.0), vec3f(-8.0, -8.0, -9.0)));
  pier = min(pier, slab(p, vec3f(-9.0, -12.0, -7.0), vec3f(-8.0, -8.0, -6.0)));
  res = pick(res, pier, 5.0);

  // The fleet: one boat to a berth, where the berth is open water.
  let afloat = p.y + 4.0 * U;
  if (afloat < 0.3) {
    let cell = floor(b.xz / 16.0);
    let h = hash21(cell + 5.0);
    let moored = h > 0.3 && cell.x > -1.5 && cell.x < 0.5 && cell.y > -3.5 && cell.y < -0.5
      && !(cell.x > -0.5 && cell.y < -1.5);
    let at = cell * 16.0 + 8.0 + floor(vec2f(h, fract(h * 7.3)) * 5.0) - 2.0;
    let l = vec3f(b.x - at.x, b.y, b.z - at.y);
    let reach = (8.0 - max(abs(b.x - cell.x * 16.0 - 8.0), abs(b.z - cell.y * 16.0 - 8.0))) * U;
    var hull = 1e3;
    var sail = 1e3;
    var lantern = 1e3;
    if (moored) {
      hull = sdBox(l - vec3f(0.0, -11.5, 0.0), vec3f(3.0, 0.5, 1.0));
      hull = min(hull, sdBox(l - vec3f(0.0, -10.5, 0.0), vec3f(2.0, 0.5, 1.0)));
      hull = min(hull, sdBox(l - vec3f(-0.5, -7.0, 0.5), vec3f(0.5, 3.0, 0.5)));
      sail = max(max(-l.x, l.x - (-4.0 - l.y) * 0.5), max(abs(l.z - 0.5) - 0.5, -9.0 - l.y));
      lantern = sdBox(l - vec3f(-2.5, -9.5, -0.5), vec3f(0.5));
    }
    res = pick(res, fence(hull * U, reach), 6.0);
    res = pick(res, fence(sail * U * 0.85, reach), 8.0);
    res = pick(res, fence(lantern * U, reach), 7.0);
  } else {
    res.x = min(res.x, afloat);
  }

  if (loose) {
    // The beam: a wheel of motes round the lamp, lit where the light is passing.
    let spoke = length(b.xz - HARBOUR_LAMP.xz);
    let wheel = max(abs(b.y - HARBOUR_LAMP.y) - 1.0, max(spoke - 34.0, 5.0 - spoke)) * U;
    res = pickLoose(res, fine(wheel), 10.0);
  }
  return res;
}

// ----------------------------------------------------------------- Every room

// How far a point is from the nearest block of a room, and what that block is
// made of. Loose blocks (smoke, leaves, motes) are left out when asking about
// shade, which only the standing parts of a room cast.
fn fill(room: i32, p: vec3f, loose: bool) -> vec2f {
  var res: vec2f;
  switch room {
    case 0 { res = fillLaunch(p, loose); }
    case 1 { res = fillTree(p, loose); }
    case 2 { res = fillPatch(p, loose); }
    case 3 { res = fillSignal(p, loose); }
    case 4 { res = fillHall(p, loose); }
    default { res = fillHarbour(p, loose); }
  }
  if (loose && room != 2) {
    // Blocks adrift in the distance, up where the room leaves the sky clear.
    let far = max(p.z + 40.0 * U, 2.0 * U - p.y);
    if (far < 0.3) {
      let band = max(max(far, p.y - 28.0 * U), max(abs(p.x) - 44.0 * U, -64.0 * U - p.z));
      res = pickLoose(res, max(drift(p, f32(room) * 7.0), band), 20.0);
    } else {
      res.x = min(res.x, far);
    }
  }
  return res;
}

// How much of its cell a block fills. Standing blocks fill it; loose ones
// swell, shrink and vanish, which is how smoke rolls and a beam sweeps.
fn grow(room: i32, mat: i32, c: vec3f, h: f32) -> f32 {
  let t = params.time;
  let b = c / U;
  if (mat == 20) { return 0.62 + 0.26 * sin(t * 0.5 + h * 30.0); }
  switch room {
    case 0 {
      let wide = max(abs(b.x - LAUNCH_AT.x), abs(b.z - LAUNCH_AT.y));
      if (mat == 10) {
        let down = clamp((-7.0 - b.y) / 3.0, 0.0, 1.0);
        let flicker = 0.5 + 0.5 * sin(t * 17.0 + h * 40.0 + b.y * 2.0);
        return (0.95 - 0.5 * down) * (0.55 + 0.45 * flicker) * step(wide, 2.0 - down * 0.9);
      }
      if (mat == 11) {
        let roll = 0.5 + 0.25 * sin(b.x * 0.6 + t * 0.9 + b.z * 0.3)
          + 0.25 * sin(b.z * 0.7 - t * 0.7 + b.y * 0.9 + h * 6.0);
        let room1 = fade(12.0, 5.0, wide) * fade(-7.0, -11.0, b.y);
        return smoothstep(0.3, 0.75, roll * (0.45 + 0.75 * room1)) * 0.9;
      }
      if (mat == 12) { return 0.5 + 0.35 * sin(t * 1.6 + launchStack(b.z) * 1.3); }
    }
    case 1 {
      if (mat == 10) { return select(0.0, 0.62 + 0.28 * sin(t * 0.7 + h * 40.0), h > 0.35); }
    }
    case 2 {
      if (mat == 5) {
        let key = floor(b.xz);
        let press = step(0.82, fract(hash21(key) * 9.0 + t * 0.35));
        return select(0.0, 0.8 - 0.25 * press, fract((key.x + key.y) * 0.5) < 0.25);
      }
    }
    case 4 {
      if (mat == 10) {
        let floor1 = select(-12.0, -10.0, b.z < -16.0);
        return clamp(stakeHeight(stakePile(b.z)) - (b.y - floor1) + 0.5, 0.0, 1.0) * 0.86;
      }
    }
    case 5 {
      if (mat == 10) { return harbourBeam(b) * step(0.45, h) * 0.5; }
    }
    default {}
  }
  return 1.0;
}

// --------------------------------------------------------------- The backdrop

// Three colours laid end to end, and a fourth to fade out into.
fn ramp(a: vec3f, b: vec3f, c: vec3f, d: vec3f, x: f32) -> vec3f {
  let ab = mix(a, b, smoothstep(0.0, 0.34, x));
  let abc = mix(ab, c, smoothstep(0.3, 0.68, x));
  return mix(abc, d, smoothstep(0.62, 1.0, x));
}

// The wash of colour behind a room, at a point on the far sheet.
fn wash(room: i32, v: vec2f) -> vec3f {
  switch room {
    case 0 {
      // Dawn: tangerine on the horizon, clearing to powder blue.
      let x = clamp(v.y * 1.1 + 0.25 + v.x * 0.15, 0.0, 1.0);
      return ramp(TANGERINE, PLATINUM * 0.5, POWDER * 0.3, vec3f(0.015, 0.03, 0.075), x);
    }
    case 1 {
      // A cool glow gathered behind the tree.
      let x = length(v - vec2f(0.0, 0.25)) * 0.75;
      return ramp(PLATINUM * 0.6, POWDER * 0.36, vec3f(0.015, 0.06, 0.08), vec3f(0.003, 0.012, 0.022), x);
    }
    case 2 {
      // Night past the glass, and a planet's lit edge rising into it.
      let d = patchPlanet(v);
      if (d > 0.0) { return vec3f(0.004, 0.007, 0.016) + POWDER * 0.3 * exp(-d * 14.0); }
      // Lit from the upper left: day on that side of it, dusk across the middle,
      // its own night on the other.
      let day = smoothstep(-0.25, 0.3, dot(v - vec2f(0.3, 0.12), vec2f(-0.6, 0.8)));
      return mix(vec3f(0.02, 0.055, 0.1), POWDER * 0.85 + PLATINUM * 0.15, day)
        + TANGERINE * 0.2 * day * (1.0 - day);
    }
    case 3 {
      // Night, with one lane of the gradient across it.
      let lane = (v.y - 0.3 - v.x * 0.45) * 3.2;
      return vec3f(0.004, 0.005, 0.008)
        + brand(v.x * 0.35 + v.y * 0.2 + params.time * 0.01) * 0.3 * exp(-lane * lane);
    }
    case 4 {
      // The arch's light: gold at the heart, then ember, then plum.
      let x = length((v - vec2f(0.0, 0.3)) * vec2f(1.0, 0.8)) * 0.75;
      return ramp(GOLD * 0.5, TANGERINE * 0.32, vec3f(0.09, 0.012, 0.03), vec3f(0.02, 0.006, 0.02), x);
    }
    default {
      // Dusk at sea: an ember on the horizon under powder blue and deep night.
      let x = abs(v.y * 1.2 + 0.15);
      return ramp(TANGERINE * 0.85, POWDER * 0.3, vec3f(0.012, 0.035, 0.1), vec3f(0.003, 0.007, 0.022), x);
    }
  }
}

// Where a ray meets the sheet hanging far behind a room.
fn sheet(rd: vec3f) -> vec2f {
  return rd.xy / max(-rd.z, 0.3);
}

// What a ray sees when it leaves a room: the wash, cut into squares.
fn sky(room: i32, rd: vec3f) -> vec3f {
  let t = params.time;
  let v = sheet(rd);
  let cells = v * 8.0;
  let id = floor(cells);
  let f = abs(fract(cells) - 0.5);
  let at = (id + 0.5) / 8.0;
  let h = hash21(id + f32(room) * 17.0 + 0.5);
  let body = fade(0.48, 0.44, max(f.x, f.y));
  var col = wash(room, mix(v, at, 0.8)) * (0.84 + 0.32 * h);
  let lit = step(0.6, h) * body;
  col *= 1.0 + lit * (0.3 + 0.2 * sin(t * (0.3 + h) + h * 40.0));
  col *= mix(0.78, 1.0, body);

  // The lights in the sky are squares too.
  if (room == 0) {
    let sun = max(abs(v.x - 0.3), abs(v.y + 0.02));
    col = mix(col, PLATINUM * 2.6 + TANGERINE * 0.8, fade(0.2, 0.19, sun));
  } else if (room == 2) {
    col += vec3f(0.9, 0.95, 1.0) * step(0.8, h) * step(0.0, patchPlanet(at)) * fade(0.14, 0.1, max(f.x, f.y))
      * (0.55 + 0.45 * sin(t * (0.4 + h * 2.0) + h * 60.0));
  } else if (room == 3) {
    col += vec3f(1.0, 0.98, 0.92) * step(0.9, h) * fade(0.16, 0.12, max(f.x, f.y))
      * (0.5 + 0.5 * sin(t * (0.5 + h * 2.0) + h * 60.0));
  } else if (room == 5) {
    let moon = max(abs(v.x + 0.42), abs(v.y - 0.5));
    col = mix(col, PLATINUM * 1.5, fade(0.075, 0.07, moon));
    col += vec3f(0.9, 0.95, 1.0) * step(0.86, h) * step(0.25, v.y) * fade(0.12, 0.08, max(f.x, f.y)) * 0.8;
  }
  return col;
}

// ------------------------------------------------------------------ Materials

struct Surface {
  albedo: vec3f,
  emit: vec3f,
  gloss: f32,
}

// What a block is painted. A block is one flat colour, chosen from where its
// middle sits (c), how big it is (girth) and its own number (h); only the
// writing on a post is drawn across a face.
fn paint(room: i32, mat: i32, c: vec3f, girth: f32, h: f32, local: vec3f, face: vec3f) -> Surface {
  let t = params.time;
  let b = c / U;
  var s = Surface(vec3f(0.03), vec3f(0.0), 0.0);
  if (mat == 20) {
    s.albedo = brand(h * 7.0 + f32(room) * 0.21);
    s.emit = s.albedo * 0.35;
    s.gloss = 0.7;
    return s;
  }
  switch room {
    // Autolaunch
    case 0 {
      let q = vec3f(b.x - LAUNCH_AT.x, b.y, b.z - LAUNCH_AT.y);
      let wide = max(abs(q.x), abs(q.z));
      if (mat == 1) {
        s.albedo = vec3f(0.06, 0.05, 0.055);
        let ring = fade(1.9, 0.9, abs(wide - 11.0));
        s.emit = TANGERINE * ring * (0.45 + 0.35 * sin(t * 2.0 + (q.x - q.z) * 0.5));
        s.gloss = 0.4;
      } else if (mat == 2) {
        s.albedo = PLATINUM * 0.3;
        if (wide > 6.0) {
          let stripe = step(0.5, fract((b.x + b.z) * 0.25));
          s.albedo = mix(vec3f(0.03), TANGERINE * 0.8, stripe);
          s.emit = TANGERINE * stripe * 0.25;
        }
        s.gloss = 0.3;
      } else if (mat == 3) {
        s.albedo = PLATINUM;
        if ((q.y > 0.0 && q.y < 2.0) || q.y > 8.0 || wide > 2.0) {
          s.albedo = TANGERINE;
          s.emit = TANGERINE * 0.12;
        }
        if (q.y > 3.0 && q.y < 5.0 && abs(q.x) < 1.0) {
          s.albedo = POWDER;
          s.emit = POWDER * 0.9;
        }
        s.gloss = 0.8;
      } else if (mat == 4) {
        let lattice = fract((floor(b.x) + floor(b.y) + floor(b.z)) * 0.5) * 2.0;
        s.albedo = mix(vec3f(0.05), vec3f(0.16), lattice);
        s.gloss = 0.5;
      } else if (mat == 5) {
        s.albedo = vec3f(0.05);
        s.emit = vec3f(1.0, 0.06, 0.03) * 4.0 * step(0.0, sin(t * 3.0));
      } else if (mat == 6) {
        let id = launchStack(b.z);
        let tall = 4.0 * (id + 1.0);
        let tick = fract(t * 0.35 + id * 0.17);
        let wave = exp(-pow((b.y + 12.0) / tall - tick, 2.0) * 60.0);
        s.albedo = vec3f(0.05, 0.04, 0.045);
        s.emit = TANGERINE * (0.03 + 0.6 * wave);
        if (b.y + 12.0 + girth / U * 0.5 > tall - 0.1) { s.emit = TANGERINE * (1.1 + 0.4 * sin(t * 2.0 + id)); }
      } else if (mat == 7) {
        s.albedo = vec3f(0.03, 0.028, 0.045);
        if (girth < U * 1.5 && h > 0.6) { s.emit = mix(TANGERINE, PLATINUM, step(0.8, h)) * 1.2; }
      } else if (mat == 8) {
        s.albedo = vec3f(0.03);
        s.emit = vec3f(1.0, 0.3, 0.05) * 0.8;
      } else if (mat == 10) {
        let down = clamp((-7.0 - b.y) / 3.0, 0.0, 1.0);
        s.emit = mix(vec3f(1.0, 0.75, 0.3), vec3f(1.0, 0.16, 0.02), down) * 3.5;
      } else if (mat == 11) {
        s.albedo = PLATINUM * 0.8;
        s.emit = vec3f(1.0, 0.4, 0.12) * 0.3 * fade(10.0, 2.0, wide);
      } else {
        s.albedo = TANGERINE;
        s.emit = TANGERINE * 2.4;
      }
    }
    // Techtree
    case 1 {
      let q = b - TREE_AT;
      let wide = max(abs(q.x), abs(q.z));
      // Light climbing the tree from the root, over and over.
      let rise = exp(-pow(q.y - fract(t * 0.22) * 26.0 + 4.0, 2.0) * 0.25);
      if (mat == 1) {
        let ring = smoothstep(0.3, 0.5, abs(fract(wide * 0.2 - t * 0.2) - 0.5));
        s.albedo = vec3f(0.02, 0.05, 0.06);
        s.emit = POWDER * ring * 0.4 * exp(-wide * 0.06);
        s.gloss = 0.6;
      } else if (mat == 2) {
        s.albedo = vec3f(0.07, 0.1, 0.11);
        if (min(abs(q.x), abs(q.z)) < 1.0) { s.emit = TANGERINE * (0.35 + 0.9 * rise); }
        s.gloss = 0.4;
      } else if (mat == 3) {
        s.albedo = vec3f(0.25, 0.33, 0.35);
        s.emit = POWDER * 0.14 + TANGERINE * rise * 1.3;
      } else if (mat == 4) {
        s.albedo = TANGERINE;
        s.emit = TANGERINE * (1.5 + 1.5 * rise);
      } else if (mat == 5) {
        s.albedo = vec3f(0.05, 0.08, 0.09);
        if (b.y > -6.0) { s.emit = POWDER * (0.5 + 0.3 * sin(t * 0.9 + b.x + b.z)); }
        s.gloss = 0.5;
      } else {
        s.albedo = vec3f(0.3, 0.5, 0.55);
        s.emit = mix(vec3f(0.3, 0.75, 0.9), PLATINUM, step(0.75, h)) * (0.55 + 0.3 * sin(t * 0.8 + h * 30.0));
      }
    }
    // Patchbay
    case 2 {
      if (mat == 1) {
        let tile = floor(b.xz / 4.0);
        s.albedo = mix(vec3f(0.05, 0.045, 0.045), vec3f(0.2, 0.18, 0.15), fract((tile.x + tile.y) * 0.5) * 2.0);
        s.gloss = 0.6;
        if (abs(b.x) < 2.5 && b.z > -46.0) {
          // The aisle: a lane of light, with a question running up it to the board.
          let along = (fract(b.z / 30.0 + t * 0.12) - 0.5) * 8.0;
          s.albedo = TANGERINE * 0.4;
          s.emit = TANGERINE * (0.12 + 2.2 * exp(-along * along));
        }
      } else if (mat == 2) {
        s.albedo = vec3f(0.06, 0.055, 0.055);
        s.gloss = 0.5;
        if (abs(b.x) > 49.0) {
          // The side walls: pale panels over a dark foot, a lit line between
          // them, and a lamp here and there.
          s.albedo = vec3f(0.11, 0.105, 0.1);
          if (b.y < -4.0) { s.albedo = vec3f(0.05, 0.045, 0.04); }
          if (b.y > -6.0 && b.y < -4.0) {
            s.albedo = TANGERINE * 0.7;
            s.emit = TANGERINE * 0.3;
          }
          let lamp = hash21(floor(b.zy / 4.0) + 9.0);
          if (b.y > 0.0 && lamp > 0.84) { s.emit = POWDER * (0.5 + 0.4 * sin(t * (0.6 + lamp) + lamp * 50.0)); }
        } else if (b.y < -6.0 && b.y > -8.0) {
          // The lit lip of the plinth, under the board.
          s.albedo = TANGERINE * 0.7;
          s.emit = TANGERINE * 0.45;
        }
      } else if (mat == 3) {
        // The board: four blocks to a socket, a dark hole and a lamp over it.
        let cell = floor(b.xy - PATCH_BOARD);
        let tile = floor(cell / 4.0);
        let at = cell - tile * 4.0;
        let th = hash21(tile + 2.0);
        let across = at.x > 0.5 && at.x < 2.5;
        s.albedo = vec3f(0.04, 0.036, 0.034);
        s.gloss = 0.4;
        if (across && at.y < 1.5) {
          s.albedo = vec3f(0.004);
          s.gloss = 0.9;
        } else if (across && at.y > 2.5) {
          var lamp = TANGERINE;
          if (th > 0.6) { lamp = POWDER * 1.4; }
          if (th > 0.82) { lamp = PLATINUM; }
          let on = step(0.3, th) * (0.25 + 0.75 * step(0.0, sin(t * (1.0 + th * 3.0) + th * 40.0)));
          s.emit = lamp * on * 2.0;
        }
      } else if (mat == 4) {
        s.albedo = vec3f(0.04, 0.035, 0.03);
        if (b.y > -9.0) { s.emit = TANGERINE * 0.3; }
        s.gloss = 0.4;
      } else if (mat == 5) {
        let key = floor(b.xz);
        let kh = hash21(key);
        let press = step(0.82, fract(kh * 9.0 + t * 0.35));
        s.albedo = mix(PLATINUM, TANGERINE, step(0.7, kh));
        s.emit = s.albedo * (0.25 + 1.8 * press);
      } else if (mat == 6) {
        s.albedo = vec3f(1.0, 0.78, 0.5);
        s.emit = vec3f(1.0, 0.78, 0.5) * 2.2;
      } else if (mat == 9) {
        // A desk's screen, each its own colour and its own slow breath.
        let sh = hash21(floor(vec2f(b.x / 8.0, b.z / 12.0)) + 5.0);
        let tint = mix(POWDER * 1.3, PLATINUM, step(0.6, sh));
        s.albedo = tint * 0.25;
        s.emit = tint * (0.32 + 0.16 * sin(t * (0.7 + sh * 1.5) + sh * 40.0));
        s.gloss = 0.8;
      } else {
        let cable = patchCable(c);
        let hue = i32(cable.y + 0.5) % 3;
        var tint = TANGERINE;
        if (hue == 1) { tint = PLATINUM; }
        if (hue == 2) { tint = POWDER * 1.3; }
        let pulse = fract(t * 0.22 + cable.y * 0.37);
        let along = (cable.z - pulse) * 7.0;
        s.albedo = tint * 0.5;
        s.emit = tint * (0.08 + 3.5 * exp(-along * along));
        s.gloss = 0.5;
      }
    }
    // Regents X
    case 3 {
      let wide = max(abs(b.x - SIGNAL_AT.x), abs(b.z - SIGNAL_AT.z));
      if (mat == 1) {
        let ring = fade(0.16, 0.0, fract(wide / 14.0 - t * 0.11));
        s.albedo = vec3f(0.01);
        s.emit = vec3f(1.0, 0.98, 0.94) * ring * 0.55 * exp(-wide * 0.035);
        s.gloss = 1.0;
      } else if (mat == 2) {
        s.albedo = vec3f(0.04);
        s.emit = vec3f(0.35) * step(2.0, wide) * step(-10.0, b.y);
        s.gloss = 0.8;
      } else if (mat == 3) {
        s.albedo = vec3f(0.6);
        s.emit = vec3f(1.0, 0.98, 0.94) * (1.0 + 0.3 * sin(t * 1.3 + h * 20.0));
      } else {
        // A post: a few lines of writing on dark glass.
        let row = floor(local.y * 3.0 + 3.0);
        let line = step(0.3, abs(fract(local.y * 3.0) - 0.5));
        let length1 = 0.75 - 0.9 * hash21(vec2f(row, h * 50.0));
        s.albedo = vec3f(0.02);
        s.emit = vec3f(0.9) * (1.0 - line) * step(local.x, length1) * step(-0.8, local.x) * 0.7 * abs(face.z) + vec3f(0.04);
        s.gloss = 0.9;
      }
    }
    // Regents stake
    case 4 {
      let side = abs(b.x);
      if (mat == 1) {
        s.albedo = vec3f(0.05, 0.046, 0.05);
        if (side < 6.0 && b.z > -14.0) { s.albedo = PLATINUM * 0.4; }
        if (side < 4.0 && b.z > -14.0) {
          s.albedo = TANGERINE * 0.6;
          s.emit = TANGERINE * 0.08;
        }
        s.gloss = 0.7;
      } else if (mat == 2) {
        s.albedo = PLATINUM * 0.3;
        if (b.y > 14.0 && b.y < 16.0) { s.emit = GOLD * 0.6; }
        s.gloss = 0.3;
      } else if (mat == 3) {
        s.albedo = vec3f(0.1, 0.092, 0.08);
        if (b.y > -8.0 && (side > 5.0 || abs(b.z + 22.0) > 3.0)) { s.emit = GOLD * 0.45; }
        s.gloss = 0.5;
      } else if (mat == 4) {
        let hole = max(side - 8.0, b.y - 16.0 + max(side - 4.0, 0.0));
        s.albedo = vec3f(0.06, 0.045, 0.05);
        s.emit = GOLD * 0.45 * fade(2.6, 0.6, hole);
      } else if (mat == 10) {
        s.albedo = TANGERINE;
        s.emit = TANGERINE * 1.3;
      } else {
        // The crown.
        s.albedo = PLATINUM;
        s.emit = PLATINUM * 0.3;
        s.gloss = 1.0;
      }
    }
    // Keyfleet
    default {
      if (mat == 1) {
        let swell = 0.5 + 0.5 * sin(b.x * 0.35 + t * 0.9 + sin(b.z * 0.3 + t * 0.4) * 1.5);
        let path = -0.42 * (10.8 - b.z);
        let glint = fade(3.5, 0.5, abs(b.x - path)) * (0.5 + 0.5 * sin(t * 2.0 + h * 30.0));
        s.albedo = mix(vec3f(0.004, 0.02, 0.04), vec3f(0.02, 0.07, 0.1), swell);
        // Gold off the keys lies on the water under the wall.
        let gilt = fade(5.0, 0.5, abs(abs(b.x) - 17.0)) * step(abs(b.x), 18.0) * (0.5 + 0.5 * sin(t * 1.3 + b.z * 0.9 + h * 20.0));
        s.emit = POWDER * 0.05 * swell + PLATINUM * 0.3 * glint + GOLD * 0.22 * gilt
          + vec3f(1.0, 0.85, 0.6) * 0.3 * harbourBeam(b) * fade(40.0, 4.0, length(b.xz - HARBOUR_LAMP.xz));
        s.gloss = 1.0;
      } else if (mat == 2) {
        s.albedo = vec3f(0.04, 0.045, 0.055);
      } else if (mat == 3) {
        s.albedo = mix(PLATINUM, TANGERINE, step(0.5, fract((b.y + 8.0) / 8.0)));
        if (b.y > 8.0) { s.albedo = vec3f(0.05); }
        s.emit = s.albedo * 0.05;
      } else if (mat == 4) {
        s.emit = vec3f(1.0, 0.9, 0.7) * 3.5;
      } else if (mat == 5) {
        s.albedo = vec3f(0.1, 0.065, 0.045);
      } else if (mat == 6) {
        s.albedo = select(vec3f(0.07, 0.045, 0.04), PLATINUM * 0.5, b.y > -11.0);
      } else if (mat == 7) {
        s.albedo = GOLD;
        s.emit = GOLD * 1.6;
      } else if (mat == 8) {
        s.albedo = PLATINUM * 0.85;
        s.emit = PLATINUM * 0.05;
      } else if (mat == 9) {
        s.albedo = vec3f(0.07, 0.08, 0.1);
        s.gloss = 0.3;
      } else if (mat == 10) {
        s.emit = vec3f(1.0, 0.9, 0.7) * 1.5;
      } else {
        // A key.
        s.albedo = vec3f(1.0, 0.5, 0.08);
        s.emit = vec3f(1.0, 0.45, 0.05) * 0.6;
        s.gloss = 1.0;
      }
    }
  }
  return s;
}

// How each room is lit, and how far and how hazily a ray may travel in it.
struct Rig {
  key: vec3f,
  keyColor: vec3f,
  fill: vec3f,
  fillColor: vec3f,
  ambient: vec3f,
  // How much of the backdrop's colour falls on the blocks.
  bounce: f32,
  thickness: f32,
  reach: f32,
}

fn rig(room: i32) -> Rig {
  switch room {
    case 0 {
      return Rig(vec3f(0.0, -8.0, -18.0) * U, vec3f(1.0, 0.34, 0.07) * 1.0, vec3f(0.6, 2.0, 0.6), vec3f(0.62, 0.66, 0.8) * 2.0,
        vec3f(0.05, 0.045, 0.05), 0.5, 0.05, 9.0);
    }
    case 1 {
      return Rig(vec3f(0.0, 1.3, -1.2), vec3f(0.55, 0.85, 1.0) * 2.4, vec3f(-1.6, -0.3, 0.2), TANGERINE * 0.9,
        vec3f(0.03, 0.05, 0.055), 0.45, 0.06, 9.0);
    }
    case 2 {
      return Rig(vec3f(0.0, 2.6, -2.6), vec3f(1.0, 0.8, 0.55) * 3.4, vec3f(0.0, 0.3, 0.8), vec3f(0.6, 0.66, 0.7) * 1.0,
        vec3f(0.045, 0.042, 0.048), 0.5, 0.0, 8.0);
    }
    case 3 {
      return Rig(vec3f(-1.5, 2.2, -0.8), vec3f(1.0) * 2.0, SIGNAL_AT * U, vec3f(1.0) * 1.3,
        vec3f(0.015), 0.4, 0.03, 12.0);
    }
    case 4 {
      return Rig(vec3f(0.0, 2.2, -0.7), vec3f(1.0, 0.9, 0.74) * 2.0, HALL_CROWN * U, GOLD * 1.1,
        vec3f(0.03, 0.026, 0.024), 0.3, 0.045, 11.0);
    }
    default {
      return Rig(vec3f(-2.6, 2.6, -5.0), vec3f(0.55, 0.7, 1.0) * 3.2, vec3f(0.0, -4.0, -20.0) * U, GOLD * 0.8,
        vec3f(0.02, 0.03, 0.05), 0.45, 0.035, 12.0);
    }
  }
}

// Light scattered toward the eye by the air round a lamp, summed along a ray
// as far as it runs.
fn halo(ro: vec3f, rd: vec3f, reach: f32, at: vec3f, radius: f32) -> f32 {
  let o = ro - at;
  let h = dot(o, rd);
  let k = sqrt(max(dot(o, o) - h * h, 0.0) + radius * radius);
  return (atan((reach + h) / k) - atan(h / k)) / PI * radius * radius / (k * k);
}

fn halos(room: i32, ro: vec3f, rd: vec3f, reach: f32) -> vec3f {
  let t = params.time;
  switch room {
    case 0 {
      return vec3f(1.0, 0.32, 0.05) * halo(ro, rd, reach, vec3f(0.0, -8.5, -18.0) * U, 0.16) * (0.5 + 0.08 * sin(t * 19.0));
    }
    case 1 {
      return vec3f(0.4, 0.8, 1.0) * halo(ro, rd, reach, vec3f(0.0, 5.0, -18.0) * U, 0.6) * 0.14;
    }
    case 2 {
      return vec3f(1.0, 0.78, 0.5) * (halo(ro, rd, reach, vec3f(0.0, 34.0, -18.0) * U, 0.16)
          + halo(ro, rd, reach, vec3f(0.0, 34.0, -42.0) * U, 0.16)) * 0.22;
    }
    case 3 {
      return vec3f(1.0) * halo(ro, rd, reach, SIGNAL_AT * U, 0.5) * 0.12;
    }
    case 4 {
      return PLATINUM * halo(ro, rd, reach, HALL_CROWN * U, 0.55) * 0.05
        + GOLD * halo(ro, rd, reach, vec3f(0.0, 4.0, -50.0) * U, 0.8) * 0.06;
    }
    default {
      return vec3f(1.0, 0.9, 0.7) * halo(ro, rd, reach, HARBOUR_LAMP * U, 0.14) * 0.5;
    }
  }
}

// ---------------------------------------------------------------- The walk

// The block a ray lands on.
struct Hit {
  // How far along the ray; under zero for a ray that lands on nothing.
  t: f32,
  // The face it lands on, in the block's own frame, and where on the block,
  // from -1 to 1 along each side.
  face: vec3f,
  local: vec3f,
  centre: vec3f,
  half: vec3f,
  mat: f32,
  // 1 for a block standing shoulder to shoulder with its neighbours.
  joined: f32,
  // How far the block's frame is turned about the upright.
  yaw: f32,
}

fn miss() -> Hit {
  return Hit(-1.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), 0.0, 0.0, 0.0);
}

// Where a ray enters and leaves a box about a centre: x in, y out, and the
// side it enters by.
struct Span {
  near: f32,
  far: f32,
  face: vec3f,
}

fn span(ro: vec3f, inv: vec3f, way: vec3f, centre: vec3f, half: vec3f) -> Span {
  let a = (centre - ro) * inv;
  let k = abs(inv) * half;
  let tn = a - k;
  let tf = a + k;
  return Span(
    max(tn.x, max(tn.y, tn.z)),
    min(tf.x, min(tf.y, tf.z)),
    -way * step(tn.yzx, tn.xyz) * step(tn.zxy, tn.xyz));
}

// Walks a ray through a room cell by cell. Each step asks first about the
// largest cell the ray is in: far from everything, it strides on; deep inside
// something, that whole cell is one large block; near a surface, it asks again
// at the next size down. Which solid cells stay whole and which break into
// smaller blocks is settled by each cell's own number, so a wall is a mix.
fn trace(ro: vec3f, rd: vec3f, room: i32, reach: f32) -> Hit {
  var hit = miss();
  let safe = select(rd, vec3f(1e-6), abs(rd) < vec3f(1e-6));
  let inv = 1.0 / safe;
  let way = sign(safe);
  var t = 0.0;
  var nudge = vec3f(0.0);
  for (var i = 0; i < 110; i++) {
    let p = ro + rd * t + nudge;
    var size = 4.0 * U;
    var centre = (floor(p / size) + 0.5) * size;
    var f = fill(room, centre, true);
    let leap = f.x - size * 1.75;
    if (leap > size) {
      t += leap;
      nudge = vec3f(0.0);
      if (t > reach) { break; }
      continue;
    }
    var m = 0.0;
    if (f.x < -size * (0.3 + 0.35 * hash31(centre / U))) {
      m = f.y;
    } else if (f.x < size * 0.65) {
      size = 2.0 * U;
      centre = (floor(p / size) + 0.5) * size;
      f = fill(room, centre, true);
      if (f.x < -size * (0.3 + 0.35 * hash31(centre / U))) {
        m = f.y;
      } else if (f.x < size * 0.44) {
        size = U;
        centre = (floor(p / size) + 0.5) * size;
        f = fill(room, centre, true);
        if (f.x < 0.0) { m = f.y; }
      }
    }
    if (m > 0.5) {
      let h = hash31(centre / U + 0.37);
      let g = grow(room, i32(m + 0.5), centre, h);
      if (g > 0.03) {
        let half = vec3f(size * 0.5 * g);
        let s = span(ro, inv, way, centre, half);
        if (s.near < s.far && s.far > 0.0) {
          hit.t = max(s.near, 0.0);
          hit.face = s.face;
          hit.local = (ro + rd * hit.t - centre) / half;
          hit.centre = centre;
          hit.half = half;
          hit.mat = m;
          hit.joined = step(0.999, g);
          break;
        }
      }
    }
    let edge = (centre + way * (size * 0.5) - ro) * inv;
    t = min(edge.x, min(edge.y, edge.z));
    nudge = way * step(edge, vec3f(t)) * (U * 0.02);
    if (t > reach) { break; }
  }
  return hit;
}

// ----------------------------------------------------------- Blocks set free
// A few blocks are not part of a room's grid: they hang in the air and move
// smoothly. They come in groups (the crown, each key, the ring of posts), and
// each group has its own frame, which may turn about the upright.

// How many groups a room has, and how many blocks are in each.
fn freeGroups(room: i32) -> i32 {
  if (room == 3 || room == 4) { return 1; }
  if (room == 5) { return 10; }
  return 0;
}

fn freeCount(room: i32) -> i32 {
  if (room == 3) { return 7; }
  if (room == 4) { return 13; }
  return 14;
}

// A group's frame: where it hangs, and how far it is turned.
fn freeFrame(room: i32, group: i32) -> vec4f {
  let t = params.time;
  if (room == 4) { return vec4f(HALL_CROWN * U + vec3f(0.0, 0.05 * sin(t * 0.8), 0.0), 0.32 * sin(t * 0.35)); }
  if (room == 5) {
    // The keys stand guard round the harbour wall: four down each side and two
    // at the mouth, each turning and bobbing in its own time.
    let g = f32(group);
    let side = f32(group % 2) * 2.0 - 1.0;
    var at = vec2f(side * 20.0, -2.0 - 12.0 * f32(group / 2));
    if (group >= 8) { at = vec2f(side * 9.0, -50.0); }
    return vec4f(vec3f(at.x, -5.5 + 0.5 * sin(t * 0.9 + g * 2.1), at.y) * U, t * 0.5 + g * 1.7);
  }
  return vec4f(SIGNAL_AT * U, 0.0);
}

// The box, about its frame, that holds a whole group.
fn freeBound(room: i32) -> vec3f {
  if (room == 4) { return vec3f(2.0 * CROWN_PITCH + CROWN_HALF, CROWN_PITCH + CROWN_HALF, CROWN_HALF); }
  if (room == 5) { return vec3f(KEY_PITCH + KEY_HALF, 3.0 * KEY_PITCH + KEY_HALF, KEY_HALF); }
  return vec3f(15.0, 15.0, 6.0) * U;
}

// One free block in its group's frame: its middle in xyz and its material in
// w, then its half-size.
struct Free {
  at: vec4f,
  half: vec3f,
}

fn freeBlock(room: i32, i: i32) -> Free {
  let t = params.time;
  if (room == 4) {
    // The Regents crown, block for block: three blocks over two rows of five.
    var at = vec2f(f32(i % 5) - 2.0, -f32(i / 5));
    if (i >= 10) { at = vec2f(f32(i - 11) * 2.0, 1.0); }
    return Free(vec4f(at * CROWN_PITCH, 0.0, 30.0), vec3f(CROWN_HALF));
  }
  if (room == 5) {
    // A key: a ring of eight for a bow, a shaft of four, two teeth.
    var cells = array<vec2f, 14>(
      vec2f(-1.0, 3.0), vec2f(0.0, 3.0), vec2f(1.0, 3.0),
      vec2f(-1.0, 2.0), vec2f(1.0, 2.0),
      vec2f(-1.0, 1.0), vec2f(0.0, 1.0), vec2f(1.0, 1.0),
      vec2f(0.0, 0.0), vec2f(0.0, -1.0), vec2f(0.0, -2.0), vec2f(0.0, -3.0),
      vec2f(1.0, -1.0), vec2f(1.0, -3.0));
    return Free(vec4f(cells[i] * KEY_PITCH, 0.0, 31.0), vec3f(KEY_HALF));
  }
  // The posts, wheeling slowly round the X, each at its own depth.
  let angle = f32(i) * (2.0 * PI / 7.0) + t * 0.08;
  return Free(
    vec4f(vec2f(cos(angle), sin(angle)) * 11.5 * U, 5.0 * U * sin(f32(i) * 2.4), 32.0),
    vec3f(2.2, 3.2, 0.4) * U);
}

fn traceFree(ro: vec3f, rd: vec3f, room: i32) -> Hit {
  var hit = miss();
  let groups = freeGroups(room);
  let count = freeCount(room);
  let bound = freeBound(room);
  var best = 1e9;
  for (var g = 0; g < groups; g++) {
    let frame = freeFrame(room, g);
    let turn = rot(-frame.w);
    let o3 = ro - frame.xyz;
    let oxz = turn * o3.xz;
    let dxz = turn * rd.xz;
    let o = vec3f(oxz.x, o3.y, oxz.y);
    let d = vec3f(dxz.x, rd.y, dxz.y);
    let safe = select(d, vec3f(1e-6), abs(d) < vec3f(1e-6));
    let inv = 1.0 / safe;
    let way = sign(safe);
    let whole = span(o, inv, way, vec3f(0.0), bound);
    if (whole.near >= whole.far || whole.far < 0.0 || whole.near > best) { continue; }
    for (var i = 0; i < count; i++) {
      let block = freeBlock(room, i);
      let s = span(o, inv, way, block.at.xyz, block.half);
      if (s.near < s.far && s.near > 0.0 && s.near < best) {
        best = s.near;
        hit.t = s.near;
        hit.face = s.face;
        hit.local = (o + d * s.near - block.at.xyz) / block.half;
        hit.half = block.half;
        hit.mat = block.at.w;
        hit.yaw = frame.w;
        let back = rot(frame.w) * block.at.xz;
        hit.centre = frame.xyz + vec3f(back.x, block.at.y, back.y);
      }
    }
  }
  return hit;
}

// ------------------------------------------------------------------ The room

// How much of the key light reaches a point past the standing blocks.
fn shade(room: i32, p: vec3f, toward: vec3f, far: f32) -> f32 {
  var s = 1.0;
  var t = 0.1;
  for (var i = 0; i < 8; i++) {
    let d = fill(room, p + toward * t, false).x + 0.03;
    s = min(s, 7.0 * d / t);
    t += clamp(d, 0.05, 0.35);
    if (s < 0.02 || t > far) { break; }
  }
  return clamp(s, 0.0, 1.0);
}

// footprint: how far the eye is from where the ray starts, and how wide a
// pixel grows for each unit the ray travels.
fn renderRoom(ro: vec3f, rd: vec3f, room: i32, footprint: vec2f) -> vec3f {
  let g = rig(room);
  var hit = trace(ro, rd, room, g.reach);
  let free = traceFree(ro, rd, room);
  if (free.t >= 0.0 && (hit.t < 0.0 || free.t < hit.t)) { hit = free; }

  var col = sky(room, rd);
  var reach = g.reach;
  if (hit.t >= 0.0) {
    reach = hit.t;
    let p = ro + rd * hit.t;
    let pixel = (footprint.x + hit.t) * footprint.y;
    let girth = 2.0 * min(hit.half.x, min(hit.half.y, hit.half.z));
    let h = hash31(hit.centre / U * 1.7 + girth * 40.0);

    // How near the edge of its face the ray lands: the seam between blocks is a
    // dark groove there, and the block's corner is rounded just inside it.
    let away = (vec3f(1.0) - abs(hit.local)) * hit.half + abs(hit.face) * 1e3;
    let rim = min(away.x, min(away.y, away.z));
    let seam = 0.0025 + 0.02 * girth;
    let groove = (1.0 - smoothstep(seam, seam + pixel, rim)) * min(1.0, seam * 2.0 / max(pixel, 1e-4)) * hit.joined;
    let round = (1.0 - smoothstep(seam, seam * 3.5 + pixel, rim)) * min(1.0, seam * 5.0 / max(pixel, 1e-4));
    let lean = sign(hit.local) * step(away, vec3f(rim + 1e-5));
    let tilted = normalize(hit.face + lean * round * 0.55);
    let turn = rot(hit.yaw);
    let nxz = turn * hit.face.xz;
    let bxz = turn * tilted.xz;
    let n = vec3f(nxz.x, hit.face.y, nxz.y);
    let nb = vec3f(bxz.x, tilted.y, bxz.y);

    let s = paint(room, i32(hit.mat + 0.5), hit.centre, girth, h, hit.local, hit.face);
    let tone = 0.84 + 0.32 * h;
    let open = clamp((fill(room, p + n * 0.14, false).x + 0.02) / 0.14, 0.0, 1.0) * 0.7 + 0.3;

    let toKey = g.key - p;
    let keyD = length(toKey);
    let keyL = toKey / keyD;
    let toFill = g.fill - p;
    let fillD = length(toFill);
    let key = g.keyColor / (1.0 + 0.16 * keyD * keyD);
    let fill1 = g.fillColor / (1.0 + 0.16 * fillD * fillD);
    let facing = max(dot(nb, keyL), 0.0);
    var shadow = 1.0;
    if (facing > 0.0) { shadow = 0.25 + 0.75 * shade(room, p + n * 0.03, keyL, keyD); }
    let bounce = wash(room, n.xy * 0.6 + vec2f(0.0, 0.25)) * (0.3 + 0.7 * max(n.y, 0.0)) * g.bounce;
    let lit = g.ambient + bounce * open + key * facing * shadow + fill1 * max(dot(nb, toFill / fillD), 0.0);
    let shine = pow(max(dot(nb, normalize(keyL - rd)), 0.0), 40.0) * s.gloss * shadow;
    let mirror = reflect(rd, nb);
    let glance = pow(1.0 - max(dot(-rd, nb), 0.0), 3.0);
    let env = wash(room, mirror.xy / max(abs(mirror.z), 0.4)) * s.gloss * (0.05 + 0.45 * glance);

    col = s.albedo * tone * lit * open * (1.0 - 0.8 * groove)
      + s.emit * (0.9 + 0.2 * h) * (1.0 - 0.55 * groove)
      + key * shine * 0.6 + env * (1.0 - groove);
    col = mix(wash(room, sheet(rd)), col, exp(-hit.t * g.thickness));
  }
  return col + halos(room, ro, rd, reach);
}

// ------------------------------------------------------------------ The cube

fn toRoom(face: i32, v: vec3f) -> vec3f {
  switch face {
    case 0 { return vec3f(-v.z, v.y, v.x); }
    case 1 { return vec3f(v.z, v.y, -v.x); }
    case 2 { return vec3f(v.x, -v.z, v.y); }
    case 3 { return vec3f(v.x, v.z, -v.y); }
    case 4 { return v; }
    default { return vec3f(-v.x, v.y, -v.z); }
  }
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

// The stage the cube turns on: night, with the palette's gradient drifting
// through a band of squares behind it.
fn backdrop(sp: vec2f) -> vec3f {
  let t = params.time;
  let r = length(sp);
  var col = mix(vec3f(0.02, 0.022, 0.034), vec3f(0.005, 0.005, 0.008), smoothstep(0.0, 1.9, r));
  let cells = sp * 6.5;
  let id = floor(cells);
  let f = abs(fract(cells) - 0.5);
  let at = (id + 0.5) / 6.5;
  let h = hash21(id + 3.0);
  let band = (1.0 - smoothstep(0.05, 1.0, abs(at.x * 0.55 + 0.08 - at.y))) * fade(0.98, 0.55, abs(at.y));
  let body = fade(0.46, 0.43, max(f.x, f.y));
  let phase = at.x * 0.3 - at.y * 0.12 + t * 0.012;
  let lit = step(h, 0.6) * band * body;
  col += brand(phase + h * 0.07) * lit * (0.035 + 0.075 * h) * (0.75 + 0.25 * sin(t * (0.4 + h) + h * 30.0));
  col += brand(sp.x * 0.3 - sp.y * 0.12 + t * 0.012) * (1.0 - smoothstep(0.0, 0.9, abs(sp.x * 0.55 + 0.08 - sp.y))) * 0.012;
  return col;
}

fn aces(x: vec3f) -> vec3f {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3f(0.0), vec3f(1.0));
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let res = max(params.resolution, vec2f(1.0));
  let sp = vec2f((uv.x - 0.5) * 2.0 * res.x / res.y, (0.5 - uv.y) * 2.0);
  let spread = 2.0 * params.lens / res.y;

  var rd = normalize(vec3f((sp - vec2f(params.shift, 0.0)) * params.lens, -1.0));
  let yz = rot(params.look.y) * rd.yz;
  let xz = rot(params.look.x) * vec2f(rd.x, yz.y);
  rd = vec3f(xz.x, yz.x, xz.y);
  let eye = vec3f(params.look.x * 0.5, params.look.y * 0.35, params.distance);

  let inverse = vec4f(-params.rotation.xyz, params.rotation.w);
  let ro = qrot(inverse, eye);
  let dir = qrot(inverse, rd);

  let safe = select(dir, vec3f(1e-6), abs(dir) < vec3f(1e-6));
  let t1 = (vec3f(-1.0) - ro) / safe;
  let t2 = (vec3f(1.0) - ro) / safe;
  let near = min(t1, t2);
  let far = max(t1, t2);
  let enter = max(near.x, max(near.y, near.z));
  let leave = min(far.x, min(far.y, far.z));
  let within = all(abs(ro) < vec3f(1.0));

  var col = backdrop(sp);
  if (within) {
    let face = i32(params.face + 0.5);
    col = renderRoom(toRoom(face, ro), toRoom(face, dir), face, vec2f(0.0, spread));
  } else if (enter < leave && enter > 0.0) {
    var face = 4;
    if (near.x >= near.y && near.x >= near.z) {
      face = select(0, 1, dir.x > 0.0);
    } else if (near.y >= near.z) {
      face = select(2, 3, dir.y > 0.0);
    } else {
      face = select(4, 5, dir.z > 0.0);
    }
    let start = toRoom(face, ro + dir * enter);
    let local = toRoom(face, dir);
    col = renderRoom(start, local, face, vec2f(enter, spread));

    let lit = params.glow * select(0.0, 1.0, i32(params.hover + 0.5) == face && params.hover > -0.5);
    col *= 1.0 + 0.18 * lit;
    // The pane: a little of the night outside rides on the glass at a slant.
    let slant = pow(1.0 - max(-local.z, 0.0), 4.0);
    col = mix(col, vec3f(0.07, 0.085, 0.12), slant * 0.3);
    // The frame, and the light it spills onto the pane beside it.
    let edge = max(abs(start.x), abs(start.y));
    let pixel = 2.0 * params.lens * params.distance / res.y;
    let frame = smoothstep(0.962 - pixel, 0.962 + pixel, edge);
    col += PLATINUM * exp(-(1.0 - edge) * 16.0) * (0.22 + 0.3 * lit);
    col = mix(col, vec3f(1.0, 0.97, 0.84) * (1.5 + 0.8 * lit), frame);
  } else {
    let d = edgeDistance(ro, dir);
    let halo1 = 0.03 / (d + 0.03);
    col += vec3f(1.0, 0.95, 0.8) * halo1 * halo1 * (0.85 + 0.4 * params.glow);
  }

  col = pow(aces(col), vec3f(1.0 / 2.2));
  col += (hash21(uv * res) - 0.5) / 255.0;
  return vec4f(col, 1.0);
}
`
