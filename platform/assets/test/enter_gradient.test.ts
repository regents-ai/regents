// Enter App's white words sit on a gradient that drifts between three blues. They
// must read at 4.5:1 or better on every colour the shader can put under them, grain
// included, and every one of those colours must stay blue: never violet, teal or
// orange. The flat blue the stylesheet shows before the first frame, and for less
// motion, must read as well.
import {readFileSync} from "node:fs"
import {expect, it} from "vitest"
import {BLUE, DEEP, LIGHT} from "../js/enter_gradient/shader"
import {contrast, mix, type Rgb} from "../js/product_tiles/look"

const WHITE: Rgb = [1, 1, 1]
const GRAIN = 0.5 / 255

const nudge = ([red, green, blue]: Rgb, by: number): Rgb => [red + by, green + by, blue + by]

/** Every colour the shader's two mixes reach, nudged by the grain both ways. */
const reachable = (): Rgb[] => {
  const colours: Rgb[] = []
  for (let light = 0; light <= 1; light += 1 / 64)
    for (let deep = 0; deep <= 0.8; deep += 0.8 / 64) {
      const color = mix(mix(BLUE, LIGHT, light), DEEP, deep)
      colours.push(nudge(color, -GRAIN), nudge(color, GRAIN))
    }
  return colours
}

const hue = ([red, green, blue]: Rgb) => {
  const max = Math.max(red, green, blue)
  const spread = max - Math.min(red, green, blue)
  const sector = max === red ? ((green - blue) / spread) % 6 : max === green ? (blue - red) / spread + 2 : (red - green) / spread + 4
  return (sector * 60 + 360) % 360
}

it("keeps white words at 4.5:1 or better on every colour of the gradient", () => {
  const worst = Math.min(...reachable().map(color => contrast(WHITE, color)))
  expect(worst).toBeGreaterThanOrEqual(4.5)
})

it("keeps every colour of the gradient blue", () => {
  for (const color of reachable()) {
    expect(hue(color)).toBeGreaterThan(215)
    expect(hue(color)).toBeLessThan(240)
  }
})

it("keeps white words readable on the flat blue shown before drawing and for less motion", () => {
  const stylesheet = readFileSync(new URL("../css/pages/home.css", import.meta.url), "utf8")
  const flat = stylesheet.match(/\.rl-hero-cta__stage\s*\{[^}]*background:\s*#([0-9a-f]{6})/i)![1]!
  const value = parseInt(flat, 16)
  const color: Rgb = [(value >> 16) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255]
  expect(contrast(WHITE, color)).toBeGreaterThanOrEqual(4.5)
  expect(color.map(channel => Math.round(channel * 255))).toEqual(BLUE.map(channel => Math.round(channel * 255)))
})
