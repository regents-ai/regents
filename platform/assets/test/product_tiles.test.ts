// The home page's product tiles are one charcoal set, each with a dot in its
// product's colour, read here from the stylesheet that paints them. The words must
// read on every colour the still gradient and the flow put under them, and each
// dot must stand out from the tile and from the other dots.
import {readFileSync} from "node:fs"
import {expect, it} from "vitest"
import {BAND, GLOW, contrast, labelRange, mix, ramp, type Rgb, type TileLook} from "../js/product_tiles/look"

const stylesheet = readFileSync(new URL("../css/pages/home.css", import.meta.url), "utf8")

const hex = (value: string): Rgb => [
  parseInt(value.slice(1, 3), 16) / 255,
  parseInt(value.slice(3, 5), 16) / 255,
  parseInt(value.slice(5, 7), 16) / 255,
]

const row = stylesheet.match(/\.rl-product-tabs\s*\{([^}]*--tile-deep[^}]*)\}/)![1]!
const color = (part: string) => hex(row.match(new RegExp(`--tile-${part}:\\s*(#[0-9a-f]{6})`))![1]!)
const look: TileLook = {deep: color("deep"), mid: color("mid"), light: color("light"), sheen: color("sheen"), ink: color("ink")}

const dots = new Map<string, Rgb>(
  [...stylesheet.matchAll(/\[data-product-tile="([a-z]+)"\]\s*\{\s*--tile-dot:\s*(#[0-9a-f]{6})/g)].map(
    ([, name, value]) => [name!, hex(value!)],
  ),
)

/** The lightest colour a tile can show: the top of its ramp under all the light there is. */
const brightest = mix(ramp(look, 1), look.sheen, BAND + GLOW)
const distance = (a: Rgb, b: Rgb) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])

it("keeps the words readable across the still gradient", () => {
  for (let step = 0; step <= 100; step += 1) {
    expect(contrast(mix(look.mid, look.light, step / 100), look.ink)).toBeGreaterThanOrEqual(4.5)
  }
})

it("keeps the words readable wherever the flow runs under them, lit or not", () => {
  const [low, high] = labelRange(look)
  expect(high - low).toBeGreaterThanOrEqual(0.5)
  for (let step = 0; step <= 64; step += 1) {
    const ground = ramp(look, low + ((high - low) * step) / 64)
    for (let light = 0; light <= 8; light += 1) {
      const lit = mix(ground, look.sheen, ((BAND + GLOW) * light) / 8)
      expect(contrast(lit, look.ink)).toBeGreaterThanOrEqual(4.5)
    }
  }
})

it("gives each of the six tiles a dot that stands out from the tile and from the others", () => {
  expect([...dots.keys()]).toEqual(["patchbay", "autolaunch", "techtree", "keyfleet", "protocol", "cloak"])
  const all = [...dots]
  for (const [index, [name, dot]] of all.entries()) {
    expect(contrast(dot, brightest), name).toBeGreaterThanOrEqual(3)
    for (const [other, otherDot] of all.slice(index + 1)) {
      expect(distance(dot, otherDot), `${name} and ${other}`).toBeGreaterThan(0.2)
    }
  }
})
