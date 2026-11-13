import type {Rgb} from "../product_tiles/look"

const rgb = (hex: string): Rgb => {
  const value = parseInt(hex.slice(1), 16)
  return [(value >> 16) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255]
}

/**
 * The blues Enter App moves between, in sRGB, the space its canvas and the stylesheet
 * both paint in: its own Signal Blue, a deeper blue, and a lighter one a little way
 * toward the prompt's edge blue. White words read at 4.5:1 or better on each, and so
 * on every mix of them.
 */
export const BLUE = rgb("#3361FF")
export const DEEP = rgb("#1E42DC")
export const LIGHT = rgb("#3966FF")

const vec = (color: Rgb) => `vec3f(${color.map(channel => channel.toFixed(6)).join(", ")})`

/**
 * One pass over the button. A deeper blue and a lighter one each drift slowly across
 * it on waves that bend a little as they go, measured in the button's height so a
 * wide button and a narrow one show the same soft shapes.
 */
export const wgsl = /* wgsl */ `
struct Params {
  // Canvas pixels across and down, then seconds.
  view: vec4f,
}

@group(0) @binding(0) var<uniform> params: Params;

const BLUE = ${vec(BLUE)};
const DEEP = ${vec(DEEP)};
const LIGHT = ${vec(LIGHT)};

fn grain(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(12.9898, 78.233))) * 43758.5453) - 0.5;
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let size = params.view.xy;
  let t = params.view.z;
  let p = (position.xy - 0.5 * size) / size.y;

  let bend = 0.8 * sin(p.y * 2.1 - t * 0.17);
  let deep = smoothstep(-0.3, 1.0, sin(p.x * 0.9 - p.y * 1.4 + t * 0.23 + bend));
  let light = smoothstep(0.2, 1.0, sin(p.x * 1.3 + p.y * 0.7 - t * 0.19 + 2.4));
  let color = mix(mix(BLUE, LIGHT, light), DEEP, 0.8 * deep);
  return vec4f(color + grain(position.xy) / 255.0, 1.0);
}
`
