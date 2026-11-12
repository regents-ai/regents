/**
 * Each product tile's colours, and the part of its ramp its label stays readable on.
 *
 * Everything here works in sRGB, the space the tile's canvas and stylesheet both
 * paint in, so a mix computed here is the mix the visitor sees.
 */

/** Red, green and blue, each from 0 to 1. */
export type Rgb = readonly [number, number, number]

/**
 * A tile's colours, from its product's own site: the ramp the flow runs along
 * (deep, mid, light), the light that drifts across it, and the label's ink.
 */
export type TileLook = {
  readonly deep: Rgb
  readonly mid: Rgb
  readonly light: Rgb
  readonly sheen: Rgb
  readonly ink: Rgb
}

/** How much of the sheen the drifting band and the pointer's light each add, at most. */
export const BAND = 0.3
export const GLOW = 0.24

/** WCAG's 4.5:1 for small text, with room for the grain that keeps the ramp from banding. */
export const LABEL_CONTRAST = 4.6

/** A computed `rgb(…)` colour as its three channels. */
export const channels = (color: string): Rgb => {
  const [red, green, blue] = (color.match(/[\d.]+/g) ?? []).map(Number)
  if (red === undefined || green === undefined || blue === undefined) {
    throw new Error(`product tile colour is not rgb(): ${color}`)
  }
  return [red / 255, green / 255, blue / 255]
}

export const mix = (from: Rgb, to: Rgb, amount: number): Rgb => [
  from[0] + (to[0] - from[0]) * amount,
  from[1] + (to[1] - from[1]) * amount,
  from[2] + (to[2] - from[2]) * amount,
]

const smoothstep = (edge0: number, edge1: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)))
  return t * t * (3 - 2 * t)
}

/** The colour at `v` along a tile's ramp, exactly as the shader takes it. */
export const ramp = (look: TileLook, v: number): Rgb =>
  mix(mix(look.deep, look.mid, smoothstep(0, 0.5, v)), look.light, smoothstep(0.5, 1, v))

const linear = (channel: number) =>
  channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4

const luminance = ([red, green, blue]: Rgb) =>
  0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)

/** WCAG contrast ratio between two colours. */
export const contrast = (a: Rgb, b: Rgb): number => {
  const [lighter, darker] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number]
  return (lighter + 0.05) / (darker + 0.05)
}

const SAMPLES = 256
const SHEEN_SAMPLES = 8

/** Whether the label reads at `v` under every amount of sheen the tile can show. */
const readable = (look: TileLook, v: number) => {
  const ground = ramp(look, v)
  for (let step = 0; step <= SHEEN_SAMPLES; step += 1) {
    const lit = mix(ground, look.sheen, ((BAND + GLOW) * step) / SHEEN_SAMPLES)
    if (contrast(lit, look.ink) < LABEL_CONTRAST) return false
  }
  return true
}

/**
 * The longest stretch of the ramp, from 0 to 1, that the label reads on under any
 * sheen. A tile's flow keeps to this stretch, so its words never sit on a colour
 * too close to their own.
 */
export const labelRange = (look: TileLook): readonly [number, number] => {
  let best: [number, number] | undefined
  let start: number | undefined
  for (let index = 0; index <= SAMPLES; index += 1) {
    const v = index / SAMPLES
    if (readable(look, v)) {
      start ??= v
      if (!best || v - start > best[1] - best[0]) best = [start, v]
    } else {
      start = undefined
    }
  }
  if (!best) throw new Error("a product tile's label reads nowhere on its colours")
  return best
}
