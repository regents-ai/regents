/**
 * The swarm city's colours: Neon in Autolaunch's palette. While the page is dark the
 * outlines glow on the night; while it is light the city is a line drawing in the
 * same colours on the page. Each theme is written as the WGSL functions
 * shaders.ts asks for.
 */

/** Light or dark, as the page's theme switch shows it. */
export type Theme = "light" | "dark"

export type Look = {
  readonly theme: Theme
  readonly wgsl: string
}

/** A colour from 0 to 1 in each channel. */
type Colour = readonly [number, number, number]

/** A design-system colour, written as `#FF5B19`. */
const hex = (code: string): Colour => {
  const channel = (at: number) => parseInt(code.slice(at, at + 2), 16) / 255
  return [channel(1), channel(3), channel(5)]
}

/** A mix of exactly two colours, `share` of the way from the first to the second. */
const blend = ([r, g, b]: Colour, [r2, g2, b2]: Colour, share: number): Colour => [
  r + (r2 - r) * share,
  g + (g2 - g) * share,
  b + (b2 - b) * share,
]

const wgsl = ([r, g, b]: Colour) => `vec3f(${r.toFixed(3)}, ${g.toFixed(3)}, ${b.toFixed(3)})`

// The design system's colours in Autolaunch's palette.
const TANGERINE = hex("#FF5B19")
const TANGERINE_GLOW = hex("#FF8A4D")
const TANGERINE_DEEP = hex("#E6450E")
const CHARCOAL = hex("#161616")
const PLATINUM = hex("#E5E3D2")
const POWDER = hex("#AECACD")
const PAGE_LIGHT = hex("#F6F4EA")

/** The city's colours in one theme. */
type NeonColours = {
  /** The page beyond the city, the city's plate and the buildings' walls. */
  readonly page: Colour
  readonly plate: Colour
  /** Each quarter's outlines: castle, forge, inn, and the low city between them. */
  readonly quarters: readonly [Colour, Colour, Colour, Colour]
  readonly street: Colour
  /** The grid over the downtowns and the lines it drops, and the beacons. */
  readonly sky: Colour
  readonly beacon: Colour
  /** The swarm, and the ring round each agent's own disc, which keeps the agent's colour. */
  readonly swarm: Colour
}

/** Neon in the city's colours: outlines in the quarters' colours, the street plan, the sky grid, and the swarm. */
const neonIn = (theme: Theme, colours: NeonColours): Look => ({
  theme,
  wgsl: /* wgsl */ `
const NIGHT: vec3f = ${wgsl(colours.page)};
const HAZE: vec3f = NIGHT;
const PLATE: vec3f = ${wgsl(colours.plate)};
const STREET: vec3f = ${wgsl(colours.street)};
const SKY: vec3f = ${wgsl(colours.sky)};
const BEACON: vec3f = ${wgsl(colours.beacon)};
const SWARM: vec3f = ${wgsl(colours.swarm)};
const BEACON_SIZE: f32 = 1.4;

fn quarterColour(quarter: u32) -> vec3f {
  switch quarter {
    case 0u: { return ${wgsl(colours.quarters[0])}; }
    case 1u: { return ${wgsl(colours.quarters[1])}; }
    case 2u: { return ${wgsl(colours.quarters[2])}; }
    default: { return ${wgsl(colours.quarters[3])}; }
  }
}

fn sky(direction: vec3f) -> vec3f {
  return NIGHT;
}

// A faint wash of colour over a district that is lit.
fn groundColour(p: vec2f, onPlate: f32) -> vec3f {
  let light = districtLight(p);
  var colour = PLATE;
  for (var i = 0u; i < 3u; i++) {
    colour = mix(colour, quarterColour(i), light[i] * ${theme === "dark" ? "0.06" : "0.1"});
  }
  return mix(NIGHT, colour, onPlate);
}

fn faceColour(face: Face) -> vec4f {
  return vec4f(PLATE, 1.0);
}

// Each building keeps a strength of its own, so the city is never one flat colour.
fn edgeColour(edge: Edge) -> vec3f {
  let tint = mix(PLATE, quarterColour(edge.quarter), ${theme === "dark" ? "0.55 + 0.45" : "0.75 + 0.25"} * edge.shade);
${
  theme === "dark"
    ? "  return mix(tint, vec3f(1.0), edge.lit * 0.2) * (1.0 + edge.lit * 0.6);"
    : "  return mix(tint, quarterColour(edge.quarter) * 0.8, edge.lit);"
}
}

fn streetColour(kind: u32, p: vec3f) -> vec4f {
  let strength = array<f32, 3>(0.6, 0.95, 1.0);
  return vec4f(mix(PLATE, STREET, strength[kind]), 1.0);
}

fn skyColour(down: f32, kind: u32) -> vec3f {
  return mix(NIGHT, SKY, select(0.85, 0.7 - 0.45 * down, kind == 1u));
}

fn beaconColour(glow: f32) -> vec3f {
  return mix(NIGHT, BEACON, glow);
}

// The swarm is one colour; an agent's own disc is ringed in its own colour.
fn discColour(agent: vec3f, lead: f32, ring: f32) -> vec3f {
  return mix(agent, SWARM, select(1.0, ring, lead > 0.5));
}

fn trailColour(glow: f32) -> vec4f {
  return vec4f(SWARM, glow);
}
`,
})

/** Tangerine in three strengths with a powder blue downtown and a deep orange sky. */
export const CITY_LOOK: Readonly<Record<Theme, Look>> = {
  light: neonIn("light", {
    page: PLATINUM,
    plate: PAGE_LIGHT,
    quarters: [TANGERINE_DEEP, blend(POWDER, CHARCOAL, 0.4), TANGERINE, hex("#B8B6A6")],
    street: TANGERINE_GLOW,
    sky: blend(TANGERINE_DEEP, PLATINUM, 0.3),
    beacon: TANGERINE_DEEP,
    swarm: CHARCOAL,
  }),
  dark: neonIn("dark", {
    page: hex("#0E0E0E"),
    plate: CHARCOAL,
    quarters: [TANGERINE, POWDER, TANGERINE_GLOW, hex("#A1A19A")],
    street: blend(TANGERINE_DEEP, CHARCOAL, 0.35),
    sky: blend(TANGERINE_DEEP, CHARCOAL, 0.25),
    beacon: TANGERINE_GLOW,
    swarm: PLATINUM,
  }),
}
