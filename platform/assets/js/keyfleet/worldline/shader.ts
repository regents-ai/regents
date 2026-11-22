/**
 * The Worldline's shaders, all drawn by vgpu. Into one picture, with
 * premultiplied alpha so the page's own ground shows through: the stars, then
 * the paths (the gold line, each planet's helix around it, and each planet's
 * circle in the plane of the present), then the marks (every event, and the
 * sun and planets at now). The paths and marks place every point by the same
 * sums as scene.ts, through the same camera matrix. Then a bloom: what is
 * bright in the picture is taken at half size, blurred across and down, and
 * laid back under the picture as a glow.
 *
 * The paths and marks are drawn more than once, told which part by `SIDE`:
 * the helices' far halves and the marks behind the line first, then the line,
 * veiled in the page's ground so what passes behind it is hidden, then the
 * near halves and the marks in front of it, and the heads last of all.
 */
import {DISTANCE, FORM, PLANETS, RING_PIECES, SEGMENTS, TONES} from "./scene"

const float = (value: number) => (Number.isInteger(value) ? `${value}.0` : `${value}`)

const planets = PLANETS.map((planet, index) => {
  const values = [planet.radius, planet.period, planet.offset, planet.width, planet.strength, planet.tone].map(float)
  const label = index === PLANETS.length - 1 ? "default" : `case ${index}u`
  return `    ${label}: { return Planet(${values.join(", ")}); }`
}).join("\n")

const shared = /* wgsl */ `
struct Params {
  // The picture's width and height in CSS pixels, device pixels per CSS
  // pixel, and its width against its height.
  size: vec4f,
  // The middle's time in two parts (\`split\` in scene.ts), and the seconds
  // in one unit of space.
  time: vec4f,
  // vgpu's projection times view for the camera (\`lens\` in scene.ts).
  viewProjection: mat4x4f,
  // Which way the camera faces.
  forward: vec4f,
  // The line's run: from and to, in seconds from the middle, the seconds
  // between its samples, and its instances.
  line: vec4f,
  // Each planet's run: from, to and the seconds between samples, and how far
  // into its turn it stands at the middle's time, as the picture has flown
  // on, 0..1.
  orbits: array<vec4f, ${PLANETS.length}>,
  // How many instances each planet's helix takes, and where now stands, in
  // seconds from the middle.
  pieces: vec4f,
  // The latest time shown yet as the picture reveals, and the earliest that
  // just arrived, in seconds from the middle; the mark in focus by its index
  // (-1 for none) and how far it stands out, 0..1.
  focus: vec4f,
  // How near its arrival each head still is, 1 to 0: the sun, then the
  // planets innermost first.
  flare: vec4f,
  // How far each head stands out while its link is pointed at or has the
  // keyboard, 0..1, in the same order.
  lift: vec4f,
  // How strong the glow, and how faint the far side.
  mood: vec4f,
  // The clock in seconds, and 1 while things shimmer.
  pulse: vec4f,
  // How far the planets have come out onto their orbits, and how far a
  // change of filter has gone, 0..1.
  entrance: vec4f,
  ground: vec4f,
  tones: array<vec4f, ${TONES.length}>,
}
@group(0) @binding(0) var<uniform> params: Params;

const DISTANCE = ${float(DISTANCE)};
const TAU = 6.2831853;

struct Planet {
  radius: f32,
  period: f32,
  offset: f32,
  width: f32,
  strength: f32,
  tone: f32,
}

fn planet(index: u32) -> Planet {
  switch index {
${planets}
  }
}

fn tone(index: f32) -> vec3f {
  return params.tones[u32(index + 0.5)].rgb;
}

// A point \`rel\` seconds from the middle, \`radius\` out from the line and
// \`angle\` around it.
fn point(rel: f32, radius: f32, angle: f32) -> vec3f {
  return vec3f(rel / params.time.z, radius * cos(angle), radius * sin(angle));
}

// Where a point stands in the picture, in CSS pixels, and how far in front
// of the camera, in units.
fn project(p: vec3f) -> vec3f {
  let at = params.viewProjection * vec4f(p, 1.0);
  let w = max(at.w, 0.001);
  return vec3f((at.x / w + 1.0) * 0.5 * params.size.x, (1.0 - at.y / w) * 0.5 * params.size.y, at.w);
}

// A point moved \`shift\` CSS pixels across the picture, as the GPU takes it,
// so what comes nearer than the lens allows is cut away cleanly.
fn clip(p: vec3f, shift: vec2f) -> vec4f {
  let at = params.viewProjection * vec4f(p, 1.0);
  return vec4f(at.x + 2.0 * shift.x * at.w / params.size.x, at.y - 2.0 * shift.y * at.w / params.size.y, at.z, at.w);
}

// How clearly something at \`depth\` shows, 0..1, as \`clear\` in scene.ts.
fn clear(depth: f32) -> f32 {
  let aspect = params.size.w;
  return smoothstep(0.15 * DISTANCE, 0.35 * DISTANCE, depth)
    * (1.0 - smoothstep(DISTANCE + 2.2 * aspect, DISTANCE + 5.0 * aspect, depth));
}

// How near the camera a point \`radius\` out stands against the line, -1..1,
// as \`nearness\` in scene.ts.
fn nearness(p: vec3f, radius: f32) -> f32 {
  if (radius == 0.0) {
    return 0.0;
  }
  return clamp(-(p.y * params.forward.y + p.z * params.forward.z) / radius, -1.0, 1.0);
}

// How much larger what is nearer is drawn, gently, as \`magnify\` in
// scene.ts.
fn perspective(depth: f32) -> f32 {
  return clamp(sqrt(DISTANCE / max(depth, 0.01)), 0.7, 1.4);
}

// How strongly, and how full, a point is drawn for how near it is: the far
// side faint and fine.
fn cue(near: f32) -> f32 {
  return mix(params.mood.y, 1.0, near * 0.5 + 0.5);
}

fn fullness(near: f32) -> f32 {
  return mix(0.65, 1.15, near * 0.5 + 0.5);
}

// A round point \`radius\` device pixels wide with a glow \`spread\` device
// pixels on, at \`offset\` from its middle.
fn shine(offset: vec2f, radius: f32, spread: f32, glow: f32) -> f32 {
  let distance = length(offset);
  let core = 1.0 - smoothstep(radius - 0.75, radius + 0.75, distance);
  let beyond = max(distance - radius, 0.0) / spread;
  return core + exp(-beyond * beyond) * glow * (1.0 - core);
}
`

/**
 * The line, the helices and the circles in the plane of the present, each a
 * ribbon of `SEGMENTS` pieces an instance. With `SIDE` 0 the instances are
 * the line's; otherwise the first planet's helix comes first, then the
 * second's, then the third's, then `RING_PIECES` for each planet's circle,
 * and only the half of each on that side of the line is kept. A helix is
 * worked out here from time alone: one per planet, however many events.
 */
export const pathsWgsl = /* wgsl */ `
${shared}

override SIDE: f32 = 0.0;
const SEGMENTS = ${SEGMENTS}u;
const RING_PIECES = ${RING_PIECES}u;
// How strongly the ground around the line hides what passes behind it.
const VEIL = 0.85;
// Turns nearer each other on the screen than this many of their widths fade
// together into a soft band.
const DENSE = 3.0;
// How strongly a circle in the plane of the present is drawn, of its helix.
const RING = 0.3;

struct Path {
  @builtin(position) position: vec4f,
  // Distance from the middle of the path, in device pixels, either side.
  @location(0) @interpolate(linear) across: f32,
  // Half the solid path's width, in device pixels.
  @location(1) half: f32,
  @location(2) color: vec3f,
  @location(3) strength: f32,
  @location(4) near: f32,
  // How strong its glow is against the picture's own.
  @location(5) glow: f32,
}

// A point of a path: the line's \`u\` seconds from the middle for 0; for 1 to
// 3 the planet's, \`u\` seconds from the middle on its helix, where
// \`orbitAngle\` in scene.ts has it then, or \`u\` radians around its circle
// in the plane of the present.
fn on(path: u32, ring: bool, u: f32) -> vec3f {
  if (path == 0u) {
    return point(u, 0.0, 0.0);
  }
  let orbit = planet(path - 1u);
  if (ring) {
    return point(params.pieces.w, orbit.radius * params.entrance.x, u);
  }
  return point(u, orbit.radius, TAU * (params.orbits[path - 1u].w + u / orbit.period) + orbit.offset);
}

@vertex fn vs_main(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Path {
  var path = 0u;
  var piece = instance;
  var run = params.line;
  var ring = false;
  if (SIDE != 0.0) {
    let first = u32(params.pieces.x);
    let second = first + u32(params.pieces.y);
    let third = second + u32(params.pieces.z);
    if (instance >= third) {
      ring = true;
      path = 1u + (instance - third) / RING_PIECES;
      piece = (instance - third) % RING_PIECES;
      run = vec4f(0.0, TAU, TAU / f32(RING_PIECES * SEGMENTS), 0.0);
    } else {
      path = select(select(3u, 2u, instance < second), 1u, instance < first);
      piece = instance - select(select(second, first, instance < second), 0u, instance < first);
      run = params.orbits[path - 1u];
    }
  }
  let u = min(run.x + f32(piece * SEGMENTS + vertex / 2u) * run.z, run.y);
  let p = on(path, ring, u);
  let here = project(p);
  let ahead = project(on(path, ring, min(u + 0.5 * run.z, run.y)));
  let behind = project(on(path, ring, max(u - 0.5 * run.z, run.x)));
  var direction = ahead.xy - behind.xy;
  if (length(direction) < 0.0001) {
    direction = vec2f(1.0, 0.0);
  }
  let normal = normalize(vec2f(-direction.y, direction.x));
  let side = select(-1.0, 1.0, (vertex & 1u) == 1u);

  var width = 2.0;
  var strength = 1.0;
  var color = tone(0.0);
  var near = 0.0;
  var glow = 1.0;
  if (path > 0u) {
    let orbit = planet(path - 1u);
    near = nearness(p, orbit.radius * select(1.0, params.entrance.x, ring));
    width = orbit.width * fullness(near);
    strength = orbit.strength * cue(near);
    color = tone(orbit.tone);
    glow = mix(0.4, 1.25, near * 0.5 + 0.5);
    if (ring) {
      width = 1.0;
      strength = strength * RING;
      glow = 0.0;
    } else {
      // The same turn one period earlier: how far apart the turns stand here.
      let before = project(on(path, false, u - orbit.period));
      strength = strength * clamp(length(here.xy - before.xy) / (DENSE * width), 0.0, 1.0);
    }
  }
  let half = 0.5 * width * perspective(here.z);
  // Room either side for the glow, and around the line for its veil. Where a
  // turn seen edge-on doubles back on the screen, its sides swap within a
  // step, so there the room closes in on the path, or the swap would draw a
  // stub across it.
  let back = here.xy - project(on(path, ring, max(u - run.z, run.x))).xy;
  let forth = project(on(path, ring, min(u + run.z, run.y))).xy - here.xy;
  var bend = 1.0;
  if (length(back) > 0.0001 && length(forth) > 0.0001) {
    bend = dot(normalize(back), normalize(forth));
  }
  let room = half + 1.0 + select(1.5 + width, 5.0, path == 0u) * smoothstep(0.0, 0.7, bend);
  let scale = params.size.z;

  var ribbon: Path;
  ribbon.position = clip(p, normal * side * room);
  ribbon.across = side * room * scale;
  ribbon.half = half * scale;
  ribbon.color = color;
  ribbon.strength = strength * clear(here.z);
  ribbon.near = near;
  ribbon.glow = glow;
  return ribbon;
}

@fragment fn fs_main(path: Path) -> @location(0) vec4f {
  if ((SIDE < 0.0 && path.near >= 0.0) || (SIDE > 0.0 && path.near < 0.0)) {
    discard;
  }
  let scale = params.size.z;
  let distance = abs(path.across);
  let solid = 1.0 - smoothstep(path.half - 0.5, path.half + 0.75, distance);
  let spread = max(distance - path.half, 0.0) / (1.6 * scale);
  let glow = exp(-spread * spread) * params.mood.x * path.glow;
  let alpha = clamp((solid + glow * (1.0 - solid)) * path.strength, 0.0, 1.0);
  var color = path.color * alpha;
  var cover = alpha;
  if (SIDE == 0.0) {
    let veil = (1.0 - smoothstep(path.half + 1.5 * scale, path.half + 4.5 * scale, distance)) * VEIL * path.strength;
    color = color + params.ground.rgb * veil * (1.0 - alpha);
    cover = alpha + veil * (1.0 - alpha);
  }
  return vec4f(color, cover);
}
`

/**
 * Every mark, one square of four vertices each, drawn as instances of one
 * buffer: a bead, a room's pixel, a ring, a tick across the line, a planet or
 * the sun. With `SIDE` -1 only the marks behind the line are drawn, with 1
 * the rest; with 2 these are the heads, all drawn. The mark in focus grows
 * and takes a ring, and so does what just arrived while its head flares,
 * and a planet whose link is pointed at or has the keyboard.
 * While the filter changes, the marks that no longer match shrink away and
 * the ones that now do come in. Every mark stands at its own time; as the
 * picture flies, a planet's bead turns about the line with its helix.
 */
export const marksWgsl = /* wgsl */ `
${shared}

override SIDE: f32 = 1.0;

struct Mark {
  @builtin(position) position: vec4f,
  // Where in the square, from its middle, in device pixels.
  @location(0) @interpolate(linear) offset: vec2f,
  // The mark's own radius, or half its side, in device pixels.
  @location(1) radius: f32,
  @location(2) color: vec3f,
  @location(3) strength: f32,
  @location(4) form: f32,
  // How far the ring of focus shows, 0..1.
  @location(5) ring: f32,
  // How far a head flares, 0..1.
  @location(6) flare: f32,
}

// a: its time in two parts, how far out from the line and how far around (a
// head's, or a room's line's);
// b: its colour, width in CSS pixels, index and strength; c: its form, how
// far across its room's line, its lane, and how it takes part in a change of
// filter (\`CHANGE\` in scene.ts).
@vertex fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @location(0) a: vec4f,
  @location(1) b: vec4f,
  @location(2) c: vec4f,
) -> Mark {
  // When it happened, from the middle, where it always stands; a head
  // stands at now.
  let rel = (a.x - params.time.x) + (a.y - params.time.y);
  let lane = u32(c.z + 0.5);
  let head = SIDE > 1.5;
  // A planet's bead stands on its helix at its own time, as \`on\` places
  // the helix in the paths' shader, and \`markAngle\` in scene.ts.
  var angle = a.w;
  if (!head && lane >= 1u && lane <= 3u) {
    let orbit = planet(lane - 1u);
    angle = TAU * (params.orbits[lane - 1u].w + rel / orbit.period) + orbit.offset;
  }
  // The planets come out from the sun onto their orbits as the picture opens.
  let out = select(a.z, a.z * params.entrance.x, head && lane >= 1u);
  let p = point(rel, out, angle);
  let here = project(p);
  let near = nearness(p, out);
  let form = u32(c.x + 0.5);
  var shown = 1.0;
  if (!head && (rel > params.focus.x || (near < 0.0) != (SIDE < 0.0))) {
    shown = 0.0;
  }

  // Which way its path runs on the screen there, for a post's row and a
  // tick standing across the line.
  let ahead = project(point(rel + 0.05 * params.time.z, a.z, angle));
  let run = ahead.xy - here.xy;
  let runs = length(run);
  var along = vec2f(1.0, 0.0);
  var square = vec2f(0.0, 1.0);
  if (runs >= 0.000001) {
    along = run / runs;
    square = vec2f(-along.y, along.x);
  }

  let flare = params.flare[select(0u, lane, lane >= 1u && lane <= 3u)];
  let focused = select(0.0, params.focus.w, params.focus.z >= 0.0 && abs(b.z - params.focus.z) < 0.5);
  let arrived = select(0.0, flare, !head && rel >= params.focus.y);
  let flaring = select(0.0, flare, head);
  let lifted = select(0.0, params.lift[min(lane, 3u)], head);
  let lit = max(max(focused, arrived), lifted);
  let scale = params.size.z;

  // A change of filter: what leaves shrinks and fades, what arrives grows in.
  let change = u32(c.w + 0.5);
  var stays = 1.0;
  if (change == 1u) {
    stays = 1.0 - params.entrance.y;
  } else if (change == 2u) {
    stays = params.entrance.y;
  }

  var grow = 1.0;
  if (form != ${FORM.pixel}u) {
    grow = perspective(here.z) * select(1.0, fullness(near), a.z > 0.0);
  }
  let radius = b.y * 0.5 * scale * grow * (0.5 + 0.5 * stays) * (1.0 + 0.8 * focused + 0.8 * arrived + 0.45 * flaring + 0.3 * lifted);
  var room = radius + 4.0 * scale;
  if (form == ${FORM.pixel}u) {
    room = radius + 0.75 * scale;
  } else if (form == ${FORM.tick}u) {
    room = radius + scale;
  } else if (form == ${FORM.planet}u) {
    room = radius + 12.0 * scale * (1.0 + flaring);
  } else if (form == ${FORM.sun}u) {
    room = radius + 32.0 * scale * (1.0 + flaring);
  }
  room = (room + 9.0 * scale * lit) * shown * select(1.0, 0.0, stays <= 0.0);
  let corner = vec2f(select(-1.0, 1.0, (vertex & 1u) == 1u), select(-1.0, 1.0, (vertex & 2u) == 2u));
  // A tick stands square to the line; everything else square to the screen.
  var shift = corner * room / scale;
  if (form == ${FORM.tick}u) {
    shift = (along * corner.x + square * corner.y) * room / scale;
  }

  var strength = b.w * clear(here.z) * stays;
  if (!head) {
    strength = strength * cue(near);
  }
  if (lane >= 1u && lane <= 3u && !head) {
    strength = strength * (1.0 - 0.22 * params.pulse.y * (0.5 + 0.5 * sin(params.pulse.x * 1.7 + b.z * 2.39996)));
  }

  var mark: Mark;
  mark.position = clip(p, square * c.y + shift);
  mark.offset = corner * room;
  mark.radius = radius;
  mark.color = tone(b.x);
  mark.strength = mix(strength, clear(here.z), lit);
  mark.form = c.x;
  mark.ring = lit;
  mark.flare = flaring;
  return mark;
}

@fragment fn fs_main(mark: Mark) -> @location(0) vec4f {
  let scale = params.size.z;
  let distance = length(mark.offset);
  let glow = params.mood.x;
  // The page's ground just around a bead, a ring or a planet, so it stands
  // out on its own path.
  let edge = 1.0 - smoothstep(mark.radius + 0.75 * scale, mark.radius + 1.75 * scale, distance);
  var core = 0.0;
  var veil = 0.0;
  switch u32(mark.form + 0.5) {
    case ${FORM.pixel}u: {
      let side = max(abs(mark.offset.x), abs(mark.offset.y));
      core = 1.0 - smoothstep(mark.radius - 0.5, mark.radius + 0.5, side);
    }
    case ${FORM.ring}u: {
      let stroke = 0.8 * scale;
      core = 1.0 - smoothstep(stroke - 0.5, stroke + 0.5, abs(distance - (mark.radius - stroke)));
      veil = edge;
    }
    case ${FORM.tick}u: {
      let outside = abs(mark.offset) - vec2f(0.9 * scale, mark.radius);
      core = 1.0 - smoothstep(-0.5, 0.5, max(outside.x, outside.y));
    }
    case ${FORM.planet}u: {
      core = shine(mark.offset, mark.radius, (6.0 + 6.0 * mark.flare) * scale, glow * (2.2 + 2.0 * mark.flare));
      veil = edge;
    }
    case ${FORM.sun}u: {
      let breath = 1.0 + 0.18 * params.pulse.y * sin(params.pulse.x * 1.3);
      core = shine(mark.offset, mark.radius, (12.0 + 14.0 * mark.flare) * scale, glow * (2.4 + 2.5 * mark.flare) * breath);
    }
    default: {
      core = shine(mark.offset, mark.radius, 3.0 * scale, glow * 1.6);
      veil = edge;
    }
  }
  let ringAt = abs(distance - (mark.radius + 6.0 * scale));
  let ring = (1.0 - smoothstep(0.6 * scale, 1.4 * scale, ringAt)) * mark.ring;
  let lit = clamp(max(core * mark.strength, ring * 0.9), 0.0, 1.0);
  let hidden = clamp(veil * mark.strength, 0.0, 1.0) * (1.0 - lit);
  return vec4f(mark.color * lit + params.ground.rgb * hidden, lit + hidden);
}
`

/**
 * The stars, a full-screen effect drawn first: far beyond everything, so
 * they turn with the camera and stay put as the picture moves through time.
 * They lie in three layers, and as the picture flies each drifts round the
 * upright axis, the nearer faster. Each layer cuts the sky into cells by
 * which way the camera looks, a whole number of them round it, so a drift
 * all the way round meets itself; some cells hold a star, placed and lit by
 * a hash of the cell.
 */
export const starsWgsl = /* wgsl */ `
struct Sky {
  // The picture's width and height in CSS pixels, device pixels per CSS
  // pixel, and the lens's CSS pixels per unit at depth 1.
  size: vec4f,
  // Which ways the camera faces.
  right: vec4f,
  up: vec4f,
  forward: vec4f,
  // The stars' colour, and how strongly they show.
  tone: vec4f,
  // How far round each layer has drifted, in radians, the farthest first.
  drift: vec4f,
}
@group(0) @binding(0) var<uniform> sky: Sky;

const TAU = 6.2831853;

// Three numbers from 0 to 1 for a cell of a layer: Jarzynski and Olano's
// PCG3D hash.
fn hash(cell: vec2f, layer: u32) -> vec3f {
  var v = vec3u(bitcast<vec2u>(vec2i(cell)), 0x9e3779b9u + layer);
  v = v * 1664525u + 1013904223u;
  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  v ^= v >> vec3u(16u);
  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  return vec3f(v) / 4294967295.0;
}

// How much of a star of one layer covers this point of the sky: its cells
// about \`apart\` CSS pixels across, \`starry\` of them holding a star, each
// \`light\` bright at most and \`large\` times the farthest's size.
fn layer(latitude: f32, longitude: f32, index: u32, apart: f32, starry: f32, light: f32, large: f32) -> f32 {
  let scale = sky.size.z;
  let focal = sky.size.w;
  let count = max(round(TAU * focal / apart), 1.0);
  let cell = TAU / count;
  let grid = vec2f(longitude + sky.drift[index], latitude) / cell;
  let which = floor(grid);
  let seed = hash(vec2f(which.x - count * floor(which.x / count), which.y), index);
  if (seed.x > starry) {
    return 0.0;
  }
  let middle = which + 0.25 + 0.5 * seed.yz;
  let away = length((grid - middle) * cell * vec2f(cos(latitude), 1.0)) * focal * scale;
  let size = (0.45 + 0.5 * seed.z) * large * scale;
  return (1.0 - smoothstep(size, size + scale, away)) * light * (0.3 + 0.7 * pow(seed.x / starry, 2.0));
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let focal = sky.size.w;
  let offset = (uv - 0.5) * sky.size.xy / focal * vec2f(1.0, -1.0);
  let ray = normalize(sky.forward.xyz + sky.right.xyz * offset.x + sky.up.xyz * offset.y);
  let latitude = asin(clamp(ray.y, -1.0, 1.0));
  let longitude = atan2(ray.z, ray.x);
  let shine = layer(latitude, longitude, 0u, 46.0, 0.32, 0.75, 1.0)
    + layer(latitude, longitude, 1u, 95.0, 0.3, 0.9, 1.3)
    + layer(latitude, longitude, 2u, 180.0, 0.28, 1.0, 1.7);
  let alpha = min(shine, 1.0) * sky.tone.w;
  return vec4f(sky.tone.rgb * alpha, alpha);
}
`

/** The bloom's first pass: what is bright in the picture, taken at half size. */
export const brightWgsl = /* wgsl */ `
@group(0) @binding(0) var picture: texture_2d<f32>;
@group(0) @binding(1) var filtering: sampler;
struct Bright {
  // How bright, by luminance, a pixel begins to glow and glows fully.
  level: vec4f,
}
@group(0) @binding(2) var<uniform> bright: Bright;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let color = textureSampleLevel(picture, filtering, uv, 0.0);
  let light = dot(color.rgb, vec3f(0.2126, 0.7152, 0.0722));
  return color * smoothstep(bright.level.x, bright.level.y, light);
}
`

/** The bloom's blur, one way at a time: across, then down. */
export const blurWgsl = /* wgsl */ `
@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var filtering: sampler;
struct Blur {
  // How far apart its samples are, in uv.
  step: vec4f,
}
@group(0) @binding(2) var<uniform> blur: Blur;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  var weights = array<f32, 5>(0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
  var sum = textureSampleLevel(source, filtering, uv, 0.0) * weights[0];
  for (var i = 1u; i < 5u; i++) {
    let offset = blur.step.xy * f32(i);
    sum += (textureSampleLevel(source, filtering, uv + offset, 0.0) + textureSampleLevel(source, filtering, uv - offset, 0.0)) * weights[i];
  }
  return sum;
}
`

/** The picture to the canvas, its bloom laid under it. */
export const compositeWgsl = /* wgsl */ `
@group(0) @binding(0) var picture: texture_2d<f32>;
@group(0) @binding(1) var glow: texture_2d<f32>;
@group(0) @binding(2) var filtering: sampler;
struct Composite {
  // How strong the glow is.
  strength: vec4f,
}
@group(0) @binding(3) var<uniform> composite: Composite;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let color = textureSampleLevel(picture, filtering, uv, 0.0);
  let haze = min(textureSampleLevel(glow, filtering, uv, 0.0) * composite.strength.x, vec4f(1.0));
  return color + haze * (1.0 - color.a);
}
`
