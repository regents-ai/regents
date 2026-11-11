/**
 * The datascape's WGSL. The scene is drawn into a texture in four parts: the
 * ground behind everything, the tubes, the panels and the sparks. Three more
 * shaders then finish the picture: one keeps what is bright, one blurs it into
 * a glow, and the last lays the glow back over the scene and adds the look of
 * an old screen (colours pulled apart, a band slipping sideways now and then,
 * scan lines, grain and dark corners).
 *
 * Every place in the scene is measured from the camera, in world units: the
 * renderer takes the camera away before it writes a place, so nothing loses
 * its sharpness however far the camera has flown.
 */
import {EXPANSION} from "./field"
import {ATLAS, KIND, TUBE_STYLE} from "./world"

const f = (value: number) => value.toFixed(4)

/** The depth the ground's lines are drawn at: further back than the farthest layer. */
const GROUND_DEPTH = 0.3
/** The ground repeats every this many world units, so the camera's place on it can be kept small. */
export const GROUND_PERIOD = 1040

/** How strong each part of the finish is. */
const GLOW = 0.75
const GLOW_THRESHOLD = 0.55
const ABERRATION = 0.7
const GLITCH = 0.3
const SCAN_LINES = 0.12
const GRAIN = 0.045
const VIGNETTE = 0.55

/** What every scene shader shares: the view, and where a place in the world lands on the page. */
const view = /* wgsl */ `
struct View {
  // The picture's size in CSS pixels.
  viewport: vec2f,
  // The cosine and sine of how far the picture leans.
  lean: vec2f,
  // The camera's place on the ground, kept inside one repeat of it.
  ground: vec2f,
  zoom: f32,
  time: f32,
  // Device pixels in one CSS pixel.
  pixel: f32,
}

@group(0) @binding(0) var<uniform> view: View;

// A place measured from the camera, on a layer of this depth, as a place on the page.
fn onPage(place: vec2f, depth: f32) -> vec4f {
  let scaled = place * depth * view.zoom;
  let leaned = vec2f(scaled.x * view.lean.x - scaled.y * view.lean.y, scaled.x * view.lean.y + scaled.y * view.lean.x);
  return vec4f(leaned.x * 2.0 / view.viewport.x, -leaned.y * 2.0 / view.viewport.y, 0.0, 1.0);
}

// Device pixels in one world unit on a layer of this depth.
fn pixelsPerUnit(depth: f32) -> f32 {
  return depth * view.zoom * view.pixel;
}

// The corners of a square made of two triangles, from -1 to 1.
fn corner(vertex: u32) -> vec2f {
  var corners = array<vec2f, 6>(
    vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0),
    vec2f(-1.0, 1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0),
  );
  return corners[vertex];
}

fn hash21(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}
`

export const backdrop = /* wgsl */ `
${view}

struct BackdropOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
}

@vertex fn vs_main(@builtin(vertex_index) vertex: u32) -> BackdropOut {
  let x = f32((vertex << 1u) & 2u);
  let y = f32(vertex & 2u);
  var out: BackdropOut;
  out.position = vec4f(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
  out.uv = vec2f(x, y);
  return out;
}

const GROUND: vec3f = vec3f(0.0078, 0.0118, 0.0275);

@fragment fn fs_main(in: BackdropOut) -> @location(0) vec4f {
  let page = (in.uv - 0.5) * view.viewport;
  // The picture leans; the ground is ruled as it lies, so the lean is taken out first.
  let level = vec2f(page.x * view.lean.x + page.y * view.lean.y, -page.x * view.lean.y + page.y * view.lean.x);
  let unit = pixelsPerUnit(${f(GROUND_DEPTH)});
  let world = view.ground + level / (${f(GROUND_DEPTH)} * view.zoom);

  // Long thin guide lines, and a field of dots between them.
  let toLine = abs(fract(world / ${f(GROUND_PERIOD / 2)} + 0.5) - 0.5) * ${f(GROUND_PERIOD / 2)} * unit;
  let ruled = 1.0 - smoothstep(0.35, 1.1, min(toLine.x, toLine.y));
  let toDot = length(fract(world / ${f(GROUND_PERIOD / 16)} + 0.5) - 0.5) * ${f(GROUND_PERIOD / 16)} * unit;
  let dotted = 1.0 - smoothstep(0.5, 1.2, toDot);

  let colour = GROUND + vec3f(0.07, 0.12, 0.17) * ruled * 0.45 + vec3f(0.06, 0.08, 0.12) * dotted * 0.6;
  return vec4f(colour, 1.0);
}
`

export const panels = /* wgsl */ `
${view}

@group(0) @binding(1) var atlas: texture_2d<f32>;
@group(0) @binding(2) var atlasSampler: sampler;

struct PanelIn {
  @builtin(vertex_index) vertex: u32,
  // The middle, measured from the camera, and half the width and height.
  @location(0) box: vec4f,
  // Depth, kind, the panel's own number, and how solid it is.
  @location(1) place: vec4f,
  // The first colour, and how lit the layer is.
  @location(2) first: vec4f,
  // The second colour, or for words, where they are in the atlas.
  @location(3) second: vec4f,
  // How far it has grown in, how white it is, how much of it is put together, how far it has grown under the pointer.
  @location(4) motion: vec4f,
  // The panel's clock and the way it arrives.
  @location(5) extra: vec4f,
}

struct PanelOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) @interpolate(flat) size: vec2f,
  @location(2) @interpolate(flat) place: vec4f,
  @location(3) @interpolate(flat) first: vec4f,
  @location(4) @interpolate(flat) second: vec4f,
  @location(5) @interpolate(flat) motion: vec4f,
  // The panel's clock, and device pixels in one of its world units.
  @location(6) @interpolate(flat) extra: vec2f,
}

// How wide and tall a panel is on its way in. Growing may pass 1 before it settles.
fn arrival(grow: f32, entrance: f32) -> vec2f {
  if (entrance < 0.5) {
    return vec2f(grow);
  }
  // It opens as a thin line first, then the line opens out.
  let line = clamp(grow * 2.0, 0.0, 1.0);
  let opened = 0.04 + 0.96 * clamp(grow * 2.0 - 1.0, 0.0, 1.0) + max(grow - 1.0, 0.0);
  if (entrance < 1.5) {
    return vec2f(line, opened);
  }
  return vec2f(opened, line);
}

@vertex fn vs_main(in: PanelIn) -> PanelOut {
  let at = corner(in.vertex);
  let half = in.box.zw * arrival(in.motion.x, in.extra.y) * (1.0 + in.motion.w * ${f(EXPANSION)});
  var out: PanelOut;
  out.position = onPage(in.box.xy + at * half, in.place.x);
  out.uv = at * 0.5 + 0.5;
  out.size = in.box.zw * 2.0;
  out.place = in.place;
  out.first = in.first;
  out.second = in.second;
  out.motion = in.motion;
  out.extra = vec2f(in.extra.x, pixelsPerUnit(in.place.x));
  return out;
}

const PAPER: vec3f = vec3f(0.93, 0.95, 1.0);
const PAGE: vec2f = vec2f(${f(ATLAS.pageWidth / ATLAS.span)}, ${f(ATLAS.pageHeight / ATLAS.span)});

fn valueNoise(p: vec2f) -> f32 {
  let cell = floor(p);
  let part = fract(p);
  let ease = part * part * (3.0 - 2.0 * part);
  return mix(
    mix(hash21(cell), hash21(cell + vec2f(1.0, 0.0)), ease.x),
    mix(hash21(cell + vec2f(0.0, 1.0)), hash21(cell + vec2f(1.0, 1.0)), ease.x),
    ease.y,
  );
}

fn cloud(p: vec2f) -> f32 {
  return valueNoise(p) * 0.55 + valueNoise(p * 2.1 + 7.3) * 0.3 + valueNoise(p * 4.3 + 19.1) * 0.15;
}

fn barColour(bar: u32) -> vec3f {
  switch bar % 6u {
    case 0u: { return vec3f(1.0, 0.6, 0.18); }
    case 1u: { return vec3f(0.23, 0.36, 1.0); }
    case 2u: { return vec3f(1.0, 0.22, 0.78); }
    case 3u: { return vec3f(0.64, 0.36, 1.0); }
    case 4u: { return vec3f(0.16, 0.85, 1.0); }
    default: { return vec3f(1.0, 0.82, 0.24); }
  }
}

@fragment fn fs_main(in: PanelOut) -> @location(0) vec4f {
  let kind = u32(in.place.y + 0.5);
  let seed = in.place.z;
  let a = in.first.rgb;
  let b = in.second.rgb;
  let assemble = in.motion.z;
  let clock = in.extra.x;
  // One device pixel, in world units, so thin lines never fall between pixels.
  let thin = max(0.75, 0.75 / in.extra.y);
  let at = in.uv * in.size;
  var colour = a;
  var cover = 1.0;

  switch kind {
    case ${KIND.mosaic}u: {
      let side = in.size.x / (5.0 + floor(seed * 9.0));
      let cell = floor(at / side);
      // One square in eight changes colour now and then.
      let changes = step(0.875, hash21(cell * 1.7 + seed * 13.1));
      let beat = floor(clock * 1.5 + hash21(cell + seed * 5.3) * 9.0) * changes;
      let shade = hash21(cell + seed * 91.7 + beat * 0.37);
      if (shade < 0.34) {
        colour = a;
      } else if (shade < 0.6) {
        colour = b;
      } else if (shade < 0.76) {
        colour = a * 0.42;
      } else if (shade < 0.86) {
        colour = PAPER;
      } else {
        colour = b * 0.18;
      }
      cover = step(hash21(cell * 3.3 + seed * 7.0), assemble * 1.02);
    }
    case ${KIND.text}u: {
      let down = fract(in.second.w + in.uv.y * in.second.z + clock * 0.012);
      let spot = vec2f((in.second.x + in.uv.x * in.second.y) * PAGE.x, down * PAGE.y);
      let ink = textureSampleLevel(atlas, atlasSampler, spot, 0.0).r;
      // Half the text stands on a dim sheet; the other half floats.
      let sheet = step(0.5, seed) * 0.16;
      colour = mix(vec3f(0.45, 0.5, 0.6), a, ink);
      cover = max(ink * step(in.uv.y, assemble), sheet);
    }
    case ${KIND.bars}u: {
      let count = 4.0 + floor(seed * 3.0);
      let bar = floor(in.uv.x * count);
      if (in.uv.y < 0.72) {
        colour = barColour(u32(bar + floor(seed * 60.0)));
        cover = step(bar / count, assemble);
      } else {
        colour = vec3f(step(0.5, fract(bar * 0.5 + 0.25)));
        cover = step(0.6, assemble);
      }
    }
    case ${KIND.gradient}u: {
      // It comes in as coarse blocks that sharpen.
      let grain = mix(5.0, 600.0, assemble * assemble);
      let fine = floor(in.uv * grain) / grain;
      let mist = cloud(fine * vec2f(in.size.x / in.size.y, 1.0) * 2.2 + seed * 31.0 + vec2f(clock * 0.03, 0.0));
      colour = mix(a, b, smoothstep(0.0, 1.0, fine.y));
      colour = mix(colour, PAPER, smoothstep(0.5, 0.82, mist) * 0.6);
    }
    case ${KIND.meter}u: {
      let count = 9.0 + floor(seed * 8.0);
      let bar = floor(in.uv.x * count);
      let pace = 1.2 + hash21(vec2f(bar, seed)) * 2.0;
      let level = (0.25 + 0.75 * abs(sin(clock * pace + bar * 1.7))) * (0.4 + 0.6 * hash21(vec2f(bar * 3.1, seed * 5.0)));
      let up = 1.0 - in.uv.y;
      colour = mix(a, b, up);
      cover = step(0.18, fract(in.uv.x * count)) * step(0.25, fract(up * 12.0)) * step(up, level * assemble);
    }
    case ${KIND.bands}u: {
      let rows = 5.0 + floor(seed * 12.0);
      let row = floor(in.uv.y * rows);
      let pace = (hash21(vec2f(row, seed * 9.0)) - 0.5) * 1.6;
      let run = floor(in.uv.x * (6.0 + hash21(vec2f(row * 2.3, seed)) * 30.0) + clock * pace);
      let shade = hash21(vec2f(run, row + seed * 17.0));
      if (shade < 0.3) {
        colour = a;
      } else if (shade < 0.55) {
        colour = b;
      } else if (shade < 0.7) {
        colour = PAPER;
      } else {
        colour = a * 0.3;
      }
      cover = step(0.22, hash21(vec2f(run * 1.3, row * 7.7 + seed))) * step(row / rows, assemble);
    }
    case ${KIND.lattice}u: {
      let pitch = 8.0 + floor(seed * 3.0) * 4.0;
      let toLine = abs(fract(at / pitch + 0.5) - 0.5) * pitch;
      let ruled = 1.0 - smoothstep(thin * 0.7, thin * 1.5, min(toLine.x, toLine.y));
      let knot = 1.0 - smoothstep(thin * 1.6, thin * 2.6, length(toLine));
      colour = mix(a, b, knot);
      cover = max(max(ruled * 0.8, knot), 0.06) * step(in.uv.x + in.uv.y, assemble * 2.02);
    }
    case ${KIND.dust}u: {
      cover = 0.65 + 0.35 * sin(clock * 3.0 + seed * 50.0);
    }
    case ${KIND.label}u: {
      let ink = textureSampleLevel(atlas, atlasSampler, mix(in.second.xy, in.second.zw, in.uv), 0.0).r;
      cover = ink * step(in.uv.x, assemble);
    }
    default: {
      let edge = min(min(at.x, in.size.x - at.x), min(at.y, in.size.y - at.y));
      let middle = abs(at - in.size * 0.5);
      let plus = step(middle.x, thin) * step(middle.y, in.size.y * 0.22) + step(middle.y, thin) * step(middle.x, in.size.x * 0.22);
      cover = clamp(1.0 - step(thin * 2.0, edge) + plus, 0.0, 1.0);
    }
  }

  let lit = colour * in.first.a * (1.0 + in.motion.w * 0.3);
  let alpha = mix(cover * in.place.w, 1.0, in.motion.y) * clamp(in.motion.x * 4.0, 0.0, 1.0);
  return vec4f(mix(lit, vec3f(1.0), in.motion.y), alpha);
}
`

export const tubes = /* wgsl */ `
${view}

struct TubeIn {
  @builtin(vertex_index) vertex: u32,
  // A run: its two ends. A turn: its circle's middle, radius and starting angle. Measured from the camera.
  @location(0) ends: vec4f,
  // Thickness, the tube's length before this piece, 1 for a turn, and which way a turn goes.
  @location(1) shape: vec4f,
  // Depth, style, the length drawn so far, and how lit the layer is.
  @location(2) place: vec4f,
  // The first colour and the tube's whole length.
  @location(3) first: vec4f,
  // The second colour and the tube's own number.
  @location(4) second: vec4f,
}

struct TubeOut {
  @builtin(position) position: vec4f,
  // A run: how far along and across. A turn: the offset from its circle's middle.
  @location(0) at: vec2f,
  @location(1) @interpolate(flat) ends: vec4f,
  @location(2) @interpolate(flat) shape: vec4f,
  @location(3) @interpolate(flat) place: vec4f,
  @location(4) @interpolate(flat) first: vec4f,
  @location(5) @interpolate(flat) second: vec4f,
}

@vertex fn vs_main(in: TubeIn) -> TubeOut {
  let at = corner(in.vertex);
  // Room for the soft edge, and for a hair-thin tube to still be one pixel wide.
  let reach = in.shape.x * 0.5 + 1.5 / pixelsPerUnit(in.place.x);
  var out: TubeOut;
  if (in.shape.z > 0.5) {
    out.at = at * (in.ends.z + reach);
    out.position = onPage(in.ends.xy + out.at, in.place.x);
  } else {
    let span = in.ends.zw - in.ends.xy;
    let run = max(length(span), 0.0001);
    let along = span / run;
    // A little past each end, so no gap shows where a run meets a turn.
    out.at = vec2f(mix(-0.3, run + 0.3, at.x * 0.5 + 0.5), at.y * reach);
    out.position = onPage(in.ends.xy + along * out.at.x + vec2f(-along.y, along.x) * out.at.y, in.place.x);
  }
  out.ends = in.ends;
  out.shape = in.shape;
  out.place = in.place;
  out.first = in.first;
  out.second = in.second;
  return out;
}

@fragment fn fs_main(in: TubeOut) -> @location(0) vec4f {
  let unit = pixelsPerUnit(in.place.x);
  var across = in.at.y;
  var along = in.shape.y + in.at.x;
  if (in.shape.z > 0.5) {
    let turned = (fract((atan2(in.at.y, in.at.x) - in.ends.w) / 6.2832 + 0.5) - 0.5) * 6.2832 * in.shape.w;
    if (turned < -0.01 || turned > 1.5808) {
      discard;
    }
    across = length(in.at) - in.ends.z;
    along = in.shape.y + turned * in.ends.z;
  }
  // Only as much of the tube as has been drawn so far.
  if (along > in.place.z) {
    discard;
  }

  let half = max(in.shape.x * 0.5, 0.6 / unit);
  var cover = clamp((half - abs(across)) * unit + 0.5, 0.0, 1.0);
  let a = in.first.rgb;
  let b = in.second.rgb;
  let style = u32(in.place.y + 0.5);
  var colour = a;
  switch style {
    case ${TUBE_STYLE.candy}u: {
      let stripe = fract((along - view.time * 90.0) / (in.shape.x * 3.0));
      colour = mix(a, b, step(0.5, stripe));
    }
    case ${TUBE_STYLE.rainbow}u: {
      colour = 0.5 + 0.5 * cos(6.2832 * (across / in.shape.x + 0.5 + vec3f(0.0, 0.33, 0.67)));
    }
    case ${TUBE_STYLE.dotted}u: {
      cover *= step(0.45, fract((along - view.time * 30.0) / 9.0));
    }
    default: {
      // A lighter core, so a thick tube reads as round.
      colour = mix(a, vec3f(1.0), (1.0 - smoothstep(0.0, 0.7, abs(across) / half)) * 0.3);
    }
  }

  // The end still being drawn is white hot.
  let growing = step(in.place.z, in.first.a - 0.5);
  let tip = (1.0 - smoothstep(0.0, 30.0, in.place.z - along)) * growing;
  return vec4f(mix(colour * in.place.w, vec3f(1.0), tip * 0.85), cover);
}
`

export const sparks = /* wgsl */ `
${view}

struct SparkIn {
  @builtin(vertex_index) vertex: u32,
  // Where it starts, measured from the camera, and how far it flies.
  @location(0) flight: vec4f,
  // When it was thrown, how long it lasts, its size and its depth.
  @location(1) life: vec4f,
  // Its colour and how lit the layer is.
  @location(2) tint: vec4f,
}

struct SparkOut {
  @builtin(position) position: vec4f,
  @location(0) @interpolate(flat) tint: vec4f,
}

@vertex fn vs_main(in: SparkIn) -> SparkOut {
  let age = clamp((view.time - in.life.x) / in.life.y, 0.0, 1.0);
  // Fast at first, slowing to a stop.
  let flown = 1.0 - pow(1.0 - age, 3.0);
  let size = in.life.z * (1.0 - age * 0.7) * step(age, 0.999);
  var out: SparkOut;
  out.position = onPage(in.flight.xy + in.flight.zw * flown + corner(in.vertex) * size, in.life.w);
  out.tint = vec4f(in.tint.rgb * in.tint.a, (1.0 - age) * (1.0 - age));
  return out;
}

@fragment fn fs_main(in: SparkOut) -> @location(0) vec4f {
  return in.tint;
}
`

/** Keeps what is bright in the scene, at a quarter of its size. */
export const bright = /* wgsl */ `
@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var srcSampler: sampler;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let texel = 1.0 / vec2f(textureDimensions(src));
  let colour = (
    textureSampleLevel(src, srcSampler, uv + texel * vec2f(-1.0, -1.0), 0.0).rgb +
    textureSampleLevel(src, srcSampler, uv + texel * vec2f(1.0, -1.0), 0.0).rgb +
    textureSampleLevel(src, srcSampler, uv + texel * vec2f(-1.0, 1.0), 0.0).rgb +
    textureSampleLevel(src, srcSampler, uv + texel * vec2f(1.0, 1.0), 0.0).rgb
  ) * 0.25;
  let peak = max(colour.r, max(colour.g, colour.b));
  return vec4f(colour * smoothstep(${f(GLOW_THRESHOLD - 0.2)}, ${f(GLOW_THRESHOLD + 0.25)}, peak), 1.0);
}
`

/** Blurs along one direction; run across and then down, it blurs evenly. */
export const blur = /* wgsl */ `
struct Blur {
  // One step of the blur, as a share of the picture.
  stride: vec2f,
}

@group(0) @binding(0) var<uniform> blur: Blur;
@group(0) @binding(1) var src: texture_2d<f32>;
@group(0) @binding(2) var srcSampler: sampler;

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  var sum = textureSampleLevel(src, srcSampler, uv, 0.0).rgb * 0.227;
  sum += (textureSampleLevel(src, srcSampler, uv + blur.stride, 0.0).rgb + textureSampleLevel(src, srcSampler, uv - blur.stride, 0.0).rgb) * 0.1946;
  sum += (textureSampleLevel(src, srcSampler, uv + blur.stride * 2.0, 0.0).rgb + textureSampleLevel(src, srcSampler, uv - blur.stride * 2.0, 0.0).rgb) * 0.1216;
  sum += (textureSampleLevel(src, srcSampler, uv + blur.stride * 3.0, 0.0).rgb + textureSampleLevel(src, srcSampler, uv - blur.stride * 3.0, 0.0).rgb) * 0.0541;
  sum += (textureSampleLevel(src, srcSampler, uv + blur.stride * 4.0, 0.0).rgb + textureSampleLevel(src, srcSampler, uv - blur.stride * 4.0, 0.0).rgb) * 0.0162;
  return vec4f(sum, 1.0);
}
`

/** Lays the glow over the scene and gives the whole picture the look of an old screen. */
export const finish = /* wgsl */ `
struct Screen {
  // The picture's size in device pixels.
  resolution: vec2f,
  time: f32,
  // Device pixels in one CSS pixel.
  pixel: f32,
}

@group(0) @binding(0) var<uniform> screen: Screen;
@group(0) @binding(1) var scene: texture_2d<f32>;
@group(0) @binding(2) var glow: texture_2d<f32>;
@group(0) @binding(3) var screenSampler: sampler;

fn hash21(p: vec2f) -> f32 {
  var q = fract(p * vec2f(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  // Now and then a band of the picture slips sideways for a moment.
  let beat = floor(screen.time * 7.0);
  let band = floor(uv.y * 26.0);
  let struck = step(${f(1 - GLITCH * 0.08)}, hash21(vec2f(band, beat)));
  let slip = (hash21(vec2f(beat, band * 1.7)) - 0.5) * 0.05 * struck;
  let at = vec2f(uv.x + slip, uv.y);

  // Red and blue are pulled apart, more towards the sides and wherever a band slipped.
  let apart = vec2f(${f(ABERRATION)} * (0.0014 + 0.004 * abs(uv.x - 0.5)) + abs(slip) * 0.4, 0.0);
  var colour = vec3f(
    textureSampleLevel(scene, screenSampler, at + apart, 0.0).r,
    textureSampleLevel(scene, screenSampler, at, 0.0).g,
    textureSampleLevel(scene, screenSampler, at - apart, 0.0).b,
  );
  colour += vec3f(
    textureSampleLevel(glow, screenSampler, at + apart, 0.0).r,
    textureSampleLevel(glow, screenSampler, at, 0.0).g,
    textureSampleLevel(glow, screenSampler, at - apart, 0.0).b,
  ) * ${f(GLOW)};

  // Scan lines two CSS pixels apart, grain, and dark corners.
  let row = uv.y * screen.resolution.y / screen.pixel;
  colour *= 1.0 - ${f(SCAN_LINES)} * (0.5 + 0.5 * sin(row * 3.1416));
  colour += (hash21(uv * screen.resolution + fract(screen.time) * 61.0) - 0.5) * ${f(GRAIN)};
  colour *= 1.0 - ${f(VIGNETTE)} * smoothstep(0.35, 0.95, length(uv - 0.5) * 1.25);
  return vec4f(max(colour, vec3f(0.0)), 1.0);
}
`
