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

// The laser colours are the products' own palette values, so they are derived here from
// the same hexes the stylesheet names rather than compared against a copied-out number. A
// laser is that colour in linear light, scaled until its brightest channel is as bright as
// white; scaling, not clamping, is what keeps the hue when the colour lies outside what a
// screen can show.
const LASER_SOURCES = {
  autolaunch: "#FF5B19",
  techtree: "#AECACD",
  patchbay: "#B9B7A6",
} as const satisfies Record<string, string>

const decode = (channel: number) =>
  channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4

const linearFromHex = (hex: string) =>
  [1, 3, 5].map(start => decode(Number.parseInt(hex.slice(start, start + 2), 16) / 255))

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

  // Only the ground follows the hover. The squares lit on top of it are the palette's own
  // Text, #E5E3D2, and how far a lit cell travels toward them is the field's own.
  it("lights the field's squares in the palette's cream", () => {
    expect(FIELD_PALETTE.displayedSquare).toEqual([0.898039, 0.890196, 0.823529, 1])
    expect(FIELD_PALETTE.intensity).toBe(0.2)

    // The crown composes the same picture and finishes it with the ACES curve and the sRGB
    // encode, so its square is the value that comes out of that pass as the displayed one.
    // The two are matched at a lit amount of 0.118, the field's own operating point.
    const amount = 0.118
    FIELD_PALETTE.composedSquare.slice(0, 3).forEach((composed, channel) => {
      const ground = HERO_PALETTES.rest
      const page =
        ground.displayedGround[channel]! * (1 - amount) +
        FIELD_PALETTE.displayedSquare[channel]! * amount
      const crown = presented(ground.composedGround[channel]! * (1 - amount) + composed * amount)
      expect(crown).toBeCloseTo(page, 4)
    })
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
      const expected = normalise(linearFromHex(source))
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
