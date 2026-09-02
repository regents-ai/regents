import {afterEach, describe, expect, it} from "vitest"

import {
  FIELD_PALETTE,
  HERO_PALETTES,
  HERO_PALETTE_EVENT,
  heroPalette,
  setHeroPalette,
  type HeroPaletteName,
} from "../js/home_field/palette"

// Both canvases finish a frame with the same two steps — the ACES curve and the sRGB
// encode — so the colour they are cleared to is not the colour the visitor sees. The two
// steps are written out here so the pair of grounds each palette carries can be checked
// against them rather than trusted.
const aces = (value: number) =>
  Math.min(
    1,
    Math.max(0, (value * (2.51 * value + 0.03)) / (value * (2.43 * value + 0.59) + 0.14)),
  )

const encode = (value: number) =>
  value <= 0.0031308 ? value * 12.92 : 1.055 * value ** (1 / 2.4) - 0.055

const presented = (value: number) => encode(aces(value))

// The laser colours are the stylesheet's own, so they are derived here from the same
// oklch the CSS names rather than compared against a copied-out number. A laser is that
// colour scaled until its brightest channel is as bright as white; scaling, not clamping,
// is what keeps the hue when the colour lies outside what a screen can show.
const LASER_SOURCES = {
  autolaunch: [0.8, 0.16, 70],
  techtree: [0.78, 0.17, 150],
  patchbay: [0.72, 0.18, 300],
} as const satisfies Record<string, readonly [number, number, number]>

const linearFromOklch = ([lightness, chroma, hue]: readonly [number, number, number]) => {
  const radians = (hue * Math.PI) / 180
  const a = chroma * Math.cos(radians)
  const b = chroma * Math.sin(radians)
  const cone = [
    (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3,
    (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3,
    (lightness - 0.0894841775 * a - 1.291485548 * b) ** 3,
  ] as const
  return [
    [4.0767416621, -3.3077115913, 0.2309699292],
    [-1.2684380046, 2.6097574011, -0.3413193965],
    [-0.0041960863, -0.7034186147, 1.707614701],
  ].map(row => row.reduce((total, weight, index) => total + weight * cone[index]!, 0))
}

const normalise = (channels: number[]) => {
  const brightest = Math.max(...channels)
  return channels.map(channel => channel / brightest)
}

const names = Object.keys(HERO_PALETTES) as HeroPaletteName[]

describe("the hero palette", () => {
  afterEach(() => {
    setHeroPalette("rest")
  })

  it("carries a colour for the resting page and for each product the hero shows", () => {
    expect(names).toEqual(["rest", "autolaunch", "techtree", "patchbay"])
  })

  it("hands the two canvases grounds that come out of the frame the same colour", () => {
    for (const name of names) {
      const {composedGround, displayedGround} = HERO_PALETTES[name]
      for (let channel = 0; channel < 3; channel += 1) {
        expect(presented(composedGround[channel]!)).toBeCloseTo(displayedGround[channel]!, 3)
      }
      expect(composedGround[3]).toBe(1)
      expect(displayedGround[3]).toBe(1)
    }
  })

  // Only the ground follows the hover. The squares lit on top of it, and how far a lit
  // cell travels toward them, are the field's own and were not touched.
  it("keeps the field's squares the colour they already were", () => {
    expect(FIELD_PALETTE.displayedSquare).toEqual([0.9569, 0.9333, 0.8941, 1])
    expect(FIELD_PALETTE.composedSquare).toEqual([0.18441, 0.17923, 0.17068, 1])
    expect(FIELD_PALETTE.intensity).toBe(0.2)
  })

  it("leaves the resting page exactly as it was: a white shot on a near-black ground", () => {
    expect(HERO_PALETTES.rest.beam).toEqual([1, 1, 1])
    const [red, green, blue] = HERO_PALETTES.rest.displayedGround
    expect(red).toBe(green)
    expect(green).toBe(blue)
    expect(red).toBeLessThan(0.05)
  })

  it("gives each product a ground and a shot no other product shares", () => {
    const grounds = names.map(name => HERO_PALETTES[name].displayedGround.join())
    const beams = names.map(name => HERO_PALETTES[name].beam.join())
    expect(new Set(grounds).size).toBe(names.length)
    expect(new Set(beams).size).toBe(names.length)
  })

  it("scales each laser to the stylesheet's colour instead of clamping it", () => {
    expect(HERO_PALETTES.rest.beam).toEqual([1, 1, 1])

    for (const [name, source] of Object.entries(LASER_SOURCES)) {
      const expected = normalise(linearFromOklch(source))
      const beam = HERO_PALETTES[name as HeroPaletteName].beam
      beam.forEach((channel, index) => expect(channel).toBeCloseTo(expected[index]!, 4))
      // Scaling puts the brightest channel exactly at white and the rest below it, so a
      // colour the screen cannot reach loses brightness rather than hue.
      expect(Math.max(...beam)).toBe(1)
    }
  })

  it("asks for no colour a screen cannot show", () => {
    for (const name of names) {
      const palette = HERO_PALETTES[name]
      const channels = [...palette.displayedGround, ...palette.composedGround, ...palette.beam]
      expect(channels.every(channel => channel >= 0 && channel <= 1)).toBe(true)
    }
  })

  // The two canvases never ask each other what is showing; they both read this.
  it("keeps handing out the last palette the hero chose", () => {
    expect(heroPalette()).toBe(HERO_PALETTES.rest)

    setHeroPalette("autolaunch")
    expect(heroPalette()).toBe(HERO_PALETTES.autolaunch)

    setHeroPalette("rest")
    expect(heroPalette()).toBe(HERO_PALETTES.rest)
  })

  it("names its announcement so nothing else on the page answers to it", () => {
    expect(HERO_PALETTE_EVENT).toBe("regents:hero-palette")
  })
})
