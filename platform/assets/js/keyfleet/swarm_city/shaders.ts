/**
 * The swarm city's WGSL. Both themes draw the same parts the same way: the sky
 * and ground behind everything, the streets, each building's sides and roof
 * and its outline, the sky grid, the beacons, and the agents with their tails.
 * What changes is the colour of each part, which each theme writes as a few
 * WGSL functions (see looks.ts). Each shader is prepared on its own, so the
 * part they all share is placed at the head of each.
 */
import {CITY_REACH, DISTRICTS} from "./city"
import type {Look} from "./looks"

const f = (value: number) => value.toFixed(3)

/** The lens, top to bottom, in degrees. */
export const FOV = 38

/** One shader for each part of the city, in the order they are drawn. */
export type CityShaders = {
  readonly backdrop: string
  readonly streets: string
  readonly faces: string
  readonly edges: string
  readonly sky: string
  readonly beacons: string
  readonly trails: string
  readonly nodes: string
}

/**
 * What every scene shader shares. WGSL lets module-level names be used before
 * they are written, so the helpers here read the look's colours, such as
 * HAZE, and each look's functions can call these helpers.
 *
 * A look provides:
 * - `HAZE`, the colour far things sink into;
 * - `quarterColour(quarter)`, each quarter's own colour;
 * - `sky(direction)`, above the horizon, and `groundColour(p, onPlate)`, below it;
 * - `faceColour(face)`, a building's sides and roof, and `edgeColour(edge)`, its outline;
 * - `streetColour(kind, p)`, where an alpha under 0.5 leaves a gap in the line;
 * - `skyColour(down, kind)` and `beaconColour(glow)` with `BEACON_SIZE`;
 * - `discColour(agent, lead, ring)` and `trailColour(glow)` for the agents.
 */
const shared = (look: Look) => /* wgsl */ `
struct City {
  viewProjection: mat4x4f,
  // Where the camera is, and the time the city is drawn at.
  eye: vec3f,
  time: f32,
  // The camera's right and up, for things that always face it.
  right: vec3f,
  // Device pixels in one CSS pixel, so marks keep their size on the page.
  pixel: f32,
  up: vec3f,
  // How lit each district is: castle, forge, inn, from 0 to 1.
  lit: vec4f,
  resolution: vec2f,
  // How far the camera stands from what it looks at, so the haze starts just short of the city.
  reach: f32,
}

@group(0) @binding(0) var<uniform> city: City;

// How far the lens reaches: 1 / tan(half the field of view).
const FOCAL: f32 = ${f(1 / Math.tan((FOV * Math.PI) / 360))};

// Each district's middle and reach on the ground, and the plate's edge.
const DISTRICT_AT = array<vec3f, 3>(
  vec3f(${f(DISTRICTS.castle.x)}, ${f(DISTRICTS.castle.z)}, ${f(DISTRICTS.castle.radius)}),
  vec3f(${f(DISTRICTS.forge.x)}, ${f(DISTRICTS.forge.z)}, ${f(DISTRICTS.forge.radius)}),
  vec3f(${f(DISTRICTS.inn.x)}, ${f(DISTRICTS.inn.z)}, ${f(DISTRICTS.inn.radius)}),
);
const REACH: f32 = ${f(CITY_REACH + 0.06)};

// A point on one of a building's faces.
struct Face {
  world: vec3f,
  // Which way the face looks: one of the four sides, or up for the roof.
  normal: vec3f,
  // How far across the face, from its left edge, in world units.
  along: f32,
  // Whose building it is: castle, forge, inn, or 3 for the city between them.
  quarter: u32,
  // A shade of the building's own, from 0 to 1.
  shade: f32,
  // How lit its district is, from 0 to 1.
  lit: f32,
  // The building's base and roof.
  base: f32,
  top: f32,
}

// A point on one of a building's edges.
struct Edge {
  world: vec3f,
  quarter: u32,
  shade: f32,
  lit: f32,
  base: f32,
  top: f32,
}

fn quarterLit(quarter: u32) -> f32 {
  switch quarter {
    case 0u: { return city.lit.x; }
    case 1u: { return city.lit.y; }
    case 2u: { return city.lit.z; }
    default: { return 0.0; }
  }
}

// Far things sink into the look's haze, so the city has depth.
fn distanceFade(p: vec3f) -> f32 {
  return 1.0 - smoothstep(city.reach - 6.0, city.reach + 24.0, length(p - city.eye));
}

fn hazed(colour: vec3f, p: vec3f) -> vec3f {
  return mix(HAZE, colour, distanceFade(p));
}


// Every colour of the rainbow in turn as t runs from 0 to 1.
fn rainbow(t: f32) -> vec3f {
  return 0.5 + 0.5 * cos(6.2832 * (t + vec3f(0.0, 0.33, 0.67)));
}

// How far each district's light reaches a point on the ground: castle, forge, inn.
fn districtLight(p: vec2f) -> vec3f {
  var light = vec3f(0.0);
  for (var i = 0u; i < 3u; i++) {
    let reach = length(p - DISTRICT_AT[i].xy) / DISTRICT_AT[i].z;
    light[i] = city.lit[i] * (1.0 - smoothstep(0.4, 1.1, reach));
  }
  return light;
}

// 1 on a grid's lines and 0 between them, each line about 'width' pixels wide at any distance.
fn gridLine(p: vec2f, spacing: f32, width: f32) -> f32 {
  let cell = p / spacing;
  let gap = abs(fract(cell - 0.5) - 0.5) / max(fwidth(cell), vec2f(1e-5));
  return 1.0 - min(min(gap.x, gap.y) / width, 1.0);
}

// A fixed hash of a point, from 0 to 1.
fn hash(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(12.9898, 78.233))) * 43758.5453);
}

// A quad of six corners round a point, for things drawn as flat cards: x and y from -1 to 1.
fn corner(index: u32) -> vec2f {
  let corners = array<vec2f, 6>(
    vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0),
    vec2f(-1.0, -1.0), vec2f(1.0, 1.0), vec2f(-1.0, 1.0),
  );
  return corners[index];
}

// The look.
${look.wgsl}
`

/** A building's record, as each of its two draws reads it. */
const buildingInput = /* wgsl */ `
struct Building {
  // Middle x and z, then width and depth.
  @location(0) footprint: vec4f,
  // Base and roof.
  @location(1) span: vec2f,
  @location(2) quarter: f32,
  @location(3) shade: f32,
}

// A corner of the building's box, from a corner of the unit box: x, y and z from 0 to 1, pulled in by 'inset'.
fn boxPoint(building: Building, unit: vec3f, inset: f32) -> vec3f {
  let half = building.footprint.zw * 0.5 - vec2f(inset);
  let low = building.footprint.xy - half;
  let ground = low + unit.xz * half * 2.0;
  return vec3f(ground.x, mix(building.span.x, building.span.y - inset, unit.y), ground.y);
}
`

/**
 * Everything behind the city, drawn first over the whole picture: the sky
 * above the horizon and, below it, the ground where the camera's ray meets it,
 * the plate and the land round it running on into the haze.
 */
const backdropWgsl = (look: Look) => /* wgsl */ `${shared(look)}
struct BackdropVarying {
  @builtin(position) clip: vec4f,
  @location(0) ndc: vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex: u32) -> BackdropVarying {
  // One triangle that covers the whole picture.
  let corners = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  var output: BackdropVarying;
  output.clip = vec4f(corners[vertex], 0.0, 1.0);
  output.ndc = corners[vertex];
  return output;
}

@fragment
fn fs_main(input: BackdropVarying) -> @location(0) vec4f {
  let aspect = city.resolution.x / city.resolution.y;
  let forward = cross(city.up, city.right);
  let direction = normalize(forward + (city.right * input.ndc.x * aspect + city.up * input.ndc.y) / FOCAL);
  let along = city.eye.y / max(-direction.y, 1e-4);
  let ground = city.eye + direction * along;
  let onPlate = step(max(abs(ground.x), abs(ground.z)), REACH);
  let below = hazed(groundColour(ground.xz, onPlate), ground);
  return vec4f(select(sky(direction), below, direction.y < 0.0), 1.0);
}
`

/** The buildings' sides and roofs, pulled in a hair from the outline so each building never hides its own edges. */
const faceWgsl = (look: Look) => /* wgsl */ `${shared(look)}
${buildingInput}

// Five faces of the unit box, two triangles each: four sides and the roof.
const FACES = array<vec3f, 30>(
  vec3f(0.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(0.0, 0.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(0.0, 1.0, 0.0),
  vec3f(1.0, 0.0, 0.0), vec3f(1.0, 0.0, 1.0), vec3f(1.0, 1.0, 1.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 1.0, 1.0), vec3f(1.0, 1.0, 0.0),
  vec3f(1.0, 0.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(1.0, 0.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(1.0, 1.0, 1.0),
  vec3f(0.0, 0.0, 1.0), vec3f(0.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 1.0, 0.0), vec3f(0.0, 1.0, 1.0),
  vec3f(0.0, 1.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(1.0, 1.0, 1.0), vec3f(0.0, 1.0, 0.0), vec3f(1.0, 1.0, 1.0), vec3f(0.0, 1.0, 1.0),
);
const NORMALS = array<vec3f, 5>(
  vec3f(0.0, 0.0, -1.0), vec3f(1.0, 0.0, 0.0), vec3f(0.0, 0.0, 1.0), vec3f(-1.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0),
);

struct FaceVarying {
  @builtin(position) clip: vec4f,
  @location(0) world: vec3f,
  @location(1) normal: vec3f,
  @location(2) along: f32,
  @location(3) @interpolate(flat) quarter: u32,
  @location(4) shade: f32,
  @location(5) lit: f32,
  @location(6) span: vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex: u32, building: Building) -> FaceVarying {
  var output: FaceVarying;
  let unit = FACES[vertex];
  let face = vertex / 6u;
  let size = building.footprint.zw;
  // Across each side from its left edge, as someone facing it sees it.
  let across = array<f32, 5>(unit.x * size.x, unit.z * size.y, (1.0 - unit.x) * size.x, (1.0 - unit.z) * size.y, unit.x * size.x);
  output.world = boxPoint(building, unit, 0.004);
  output.normal = NORMALS[face];
  output.along = across[face];
  output.quarter = u32(building.quarter + 0.5);
  output.shade = building.shade;
  output.lit = quarterLit(output.quarter);
  output.span = building.span;
  output.clip = city.viewProjection * vec4f(output.world, 1.0);
  return output;
}

@fragment
fn fs_main(input: FaceVarying) -> @location(0) vec4f {
  let colour = faceColour(Face(input.world, input.normal, input.along, input.quarter, input.shade, input.lit, input.span.x, input.span.y));
  return vec4f(hazed(colour.rgb, input.world), colour.a);
}
`

/** The buildings' outlines: the twelve edges of each box, a hair-thin line. */
const edgeWgsl = (look: Look) => /* wgsl */ `${shared(look)}
${buildingInput}

// The twelve edges of the unit box, two ends each.
const EDGES = array<vec3f, 24>(
  vec3f(0.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 0.0, 1.0),
  vec3f(1.0, 0.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 0.0, 0.0),
  vec3f(0.0, 1.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(1.0, 1.0, 0.0), vec3f(1.0, 1.0, 1.0),
  vec3f(1.0, 1.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(0.0, 1.0, 1.0), vec3f(0.0, 1.0, 0.0),
  vec3f(0.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), vec3f(1.0, 0.0, 0.0), vec3f(1.0, 1.0, 0.0),
  vec3f(1.0, 0.0, 1.0), vec3f(1.0, 1.0, 1.0), vec3f(0.0, 0.0, 1.0), vec3f(0.0, 1.0, 1.0),
);

struct EdgeVarying {
  @builtin(position) clip: vec4f,
  @location(0) colour: vec3f,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex: u32, building: Building) -> EdgeVarying {
  var output: EdgeVarying;
  let world = boxPoint(building, EDGES[vertex], 0.0);
  let quarter = u32(building.quarter + 0.5);
  let edge = Edge(world, quarter, building.shade, quarterLit(quarter), building.span.x, building.span.y);
  output.colour = hazed(edgeColour(edge), world);
  output.clip = city.viewProjection * vec4f(world, 1.0);
  return output;
}

@fragment
fn fs_main(input: EdgeVarying) -> @location(0) vec4f {
  return vec4f(input.colour, 1.0);
}
`

/** The streets: thin lines on the plate. 'kind' is 0 for a street, 1 for an avenue's edge and 2 for the plate's rim. */
const streetWgsl = (look: Look) => /* wgsl */ `${shared(look)}
struct StreetVarying {
  @builtin(position) clip: vec4f,
  @location(0) world: vec3f,
  @location(1) @interpolate(flat) kind: u32,
}

@vertex
fn vs_main(@location(0) position: vec3f, @location(1) kind: f32) -> StreetVarying {
  var output: StreetVarying;
  output.world = position;
  output.kind = u32(kind + 0.5);
  output.clip = city.viewProjection * vec4f(position, 1.0);
  return output;
}

@fragment
fn fs_main(input: StreetVarying) -> @location(0) vec4f {
  let colour = streetColour(input.kind, input.world);
  if (colour.a < 0.5) {
    discard;
  }
  return vec4f(hazed(colour.rgb, input.world), 1.0);
}
`

/** The grid hanging over the downtowns and the lines it drops, 'down' running from 0 at the top of a line to 1 at its foot. */
const skyWgsl = (look: Look) => /* wgsl */ `${shared(look)}
struct SkyVarying {
  @builtin(position) clip: vec4f,
  @location(0) colour: vec3f,
}

@vertex
fn vs_main(@location(0) position: vec3f, @location(1) down: f32, @location(2) kind: f32) -> SkyVarying {
  var output: SkyVarying;
  output.colour = hazed(skyColour(down, u32(kind + 0.5)), position);
  output.clip = city.viewProjection * vec4f(position, 1.0);
  return output;
}

@fragment
fn fs_main(input: SkyVarying) -> @location(0) vec4f {
  return vec4f(input.colour, 1.0);
}
`

/** The beacons: small squares round the rim, at street corners and along the avenues. */
const beaconWgsl = (look: Look) => /* wgsl */ `${shared(look)}
struct BeaconVarying {
  @builtin(position) clip: vec4f,
  @location(0) colour: vec3f,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex: u32, @location(0) position: vec3f, @location(1) phase: f32) -> BeaconVarying {
  var output: BeaconVarying;
  let clip = city.viewProjection * vec4f(position, 1.0);
  let half = BEACON_SIZE * city.pixel / city.resolution * 2.0;
  output.clip = clip + vec4f(corner(vertex) * half * clip.w, 0.0, 0.0);
  output.colour = hazed(beaconColour(0.8 + 0.2 * sin(city.time * 1.6 + phase)), position);
  return output;
}

@fragment
fn fs_main(input: BeaconVarying) -> @location(0) vec4f {
  return vec4f(input.colour, 1.0);
}
`

/**
 * The agents and their swarms: flat discs that always face the camera. An
 * agent's own disc is larger, and its look rings it.
 */
const nodeWgsl = (look: Look) => /* wgsl */ `${shared(look)}
struct NodeVarying {
  @builtin(position) clip: vec4f,
  @location(0) at: vec2f,
  @location(1) colour: vec3f,
  @location(2) glow: f32,
  // 1 for an agent's own disc, 0 for one of its swarm.
  @location(3) lead: f32,
  // The disc's radius on the page, in device pixels.
  @location(4) radius: f32,
}

@vertex
fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @location(0) position: vec3f,
  @location(1) size: f32,
  @location(2) colour: vec3f,
  @location(3) glow: f32,
) -> NodeVarying {
  var output: NodeVarying;
  let at = corner(vertex);
  // Never smaller than a share of the picture's shorter side, so a far agent still reads as a
  // disc and keeps the same size beside the city on a tall phone as on a wide screen.
  let centre = city.viewProjection * vec4f(position, 1.0);
  let perPixel = centre.w * 2.0 / (city.resolution.y * FOCAL);
  let lead = select(0.0, 1.0, size > 0.15);
  let least = mix(0.006, 0.016, lead) * min(city.resolution.x, city.resolution.y) * perPixel;
  let radius = max(size, least);
  let world = position + (city.right * at.x + city.up * at.y) * radius;
  output.clip = city.viewProjection * vec4f(world, 1.0);
  output.at = at;
  output.colour = colour;
  output.glow = glow * distanceFade(position);
  output.lead = lead;
  output.radius = radius / perPixel;
  return output;
}

@fragment
fn fs_main(input: NodeVarying) -> @location(0) vec4f {
  let d = length(input.at) * input.radius;
  let edge = 1.0 - smoothstep(input.radius - 1.0, input.radius, d);
  let ring = (1.0 - smoothstep(input.radius - 2.6 * city.pixel, input.radius - 1.6 * city.pixel, d)) * input.lead;
  return vec4f(discColour(input.colour, input.lead, ring), edge * input.glow);
}
`

/** The tails: hair-thin lines that always face the camera, fading toward their ends. */
const trailWgsl = (look: Look) => /* wgsl */ `${shared(look)}
struct TrailVarying {
  @builtin(position) clip: vec4f,
  @location(0) side: f32,
  @location(1) glow: f32,
}

@vertex
fn vs_main(
  @builtin(vertex_index) vertex: u32,
  @location(0) from_: vec3f,
  @location(1) to: vec3f,
  @location(2) glows: vec2f,
) -> TrailVarying {
  var output: TrailVarying;
  let at = corner(vertex);
  let ends = array<vec4f, 2>(city.viewProjection * vec4f(from_, 1.0), city.viewProjection * vec4f(to, 1.0));
  let end = select(0u, 1u, at.x > 0.0);
  let screen0 = ends[0].xy / ends[0].w * city.resolution;
  let screen1 = ends[1].xy / ends[1].w * city.resolution;
  var direction = screen1 - screen0;
  direction = select(vec2f(1.0, 0.0), normalize(direction), length(direction) > 1e-4);
  let across = vec2f(-direction.y, direction.x);
  let glow = select(glows.x, glows.y, at.x > 0.0);
  let width = (1.1 + 0.9 * glow) * city.pixel;
  let clip = ends[end];
  output.clip = clip + vec4f(across * at.y * width / city.resolution * clip.w, 0.0, 0.0);
  output.side = at.y;
  output.glow = glow * distanceFade(select(from_, to, at.x > 0.0));
  return output;
}

@fragment
fn fs_main(input: TrailVarying) -> @location(0) vec4f {
  let soft = 1.0 - input.side * input.side;
  let colour = trailColour(input.glow);
  return vec4f(colour.rgb, soft * colour.a);
}
`

export const cityShaders = (look: Look): CityShaders => ({
  backdrop: backdropWgsl(look),
  streets: streetWgsl(look),
  faces: faceWgsl(look),
  edges: edgeWgsl(look),
  sky: skyWgsl(look),
  beacons: beaconWgsl(look),
  trails: trailWgsl(look),
  nodes: nodeWgsl(look),
})
