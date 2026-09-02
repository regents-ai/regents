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
