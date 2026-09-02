/**
 * The colours the page ground and the crown are drawn in, and the one place that
 * says which of them is showing right now.
 *
 * One field is drawn twice, so the two canvases have to be handed the same
 * colours in the two forms their pipelines expect. The page canvas writes
 * straight to the screen, so it is given the displayed values. The crown canvas
 * composes in high dynamic range and ends with one tone-mapping and encoding
 * pass, so it is given the values that come out of that pass as the displayed
 * ones. Both sets describe the same picture: the page ground carrying near-white
 * squares.
 *
 * At rest the ground is `--rl-bg` (`oklch(14.5% 0 0)`) and the three lasers are
 * white. Pointing at a product card hands both canvases that product's ground
 * and laser colour instead. The squares keep their cream in every palette.
 */

export type Rgba = readonly [number, number, number, number]
type Rgb = readonly [number, number, number]

/** The Techtree field's cream, kept as the square colour. */
const SQUARE = [0.9569, 0.9333, 0.8941, 1] as const

export const FIELD_PALETTE = {
  /** Displayed value, for a canvas that presents what the shader writes. */
  displayedSquare: SQUARE,
  /**
   * Pre-tone-mapping value, for the crown scene. It was solved against the ACES
   * curve and sRGB encode in the presentation pass, so the two canvases agree to
   * within one 8-bit step everywhere the squares are visible.
   */
  composedSquare: [0.18441, 0.17923, 0.17068, 1],
  /** How far a fully lit cell travels from the ground toward the square colour. */
  intensity: 0.2,
} as const satisfies {
  readonly displayedSquare: Rgba
  readonly composedSquare: Rgba
  readonly intensity: number
}

/** The three products a visitor can point at, named as the page names them. */
export type HeroProduct = "autolaunch" | "techtree" | "patchbay"
export type HeroPaletteName = "rest" | HeroProduct

export interface HeroPalette {
  /** Page ground, for a canvas that presents what the shader writes. */
  readonly displayedGround: Rgba
  /** The same ground, before the crown's tone-mapping and encoding pass. */
  readonly composedGround: Rgba
  /**
   * The three lasers: the white segments take this outright, and the spectral
   * fan is tinted by it. Scaled so its brightest channel is as bright as white.
   */
  readonly beam: Rgb
}

/**
 * Placeholder product colours, chosen against the page ground and kept in one
 * place so a colour is a one-line change. Each ground is the sRGB value of the
 * stylesheet's `--rl-bg` for that product, with the composed value solved back
 * through the crown's ACES curve and sRGB encode.
 */
export const HERO_PALETTES = {
  /** oklch(14.5% 0 0), white lasers. */
  rest: {
    displayedGround: [0.039388, 0.039388, 0.039388, 1],
    composedGround: [0.008589, 0.008589, 0.008589, 1],
    beam: [1, 1, 1],
  },
  /** Amber: ground oklch(16% 0.03 60), laser oklch(80% 0.16 70). */
  autolaunch: {
    displayedGround: [0.088239, 0.038507, 0.007917, 1],
    composedGround: [0.017134, 0.008449, 0.002405, 1],
    beam: [1, 0.3991, 0.0284],
  },
  /** Green: ground oklch(15% 0.03 160), laser oklch(78% 0.17 150). */
  techtree: {
    displayedGround: [0.004809, 0.058478, 0.027328, 1],
    composedGround: [0.001548, 0.011742, 0.006555, 1],
    beam: [0.1417, 1, 0.2956],
  },
  /** Violet: ground oklch(15% 0.035 300), laser oklch(72% 0.18 300). */
  patchbay: {
    displayedGround: [0.052977, 0.029145, 0.092363, 1],
    composedGround: [0.010806, 0.00688, 0.017921, 1],
    beam: [0.457, 0.2302, 1],
  },
} as const satisfies Record<HeroPaletteName, HeroPalette>

/** The name of the DOM event both canvases take their palette change from. */
export const HERO_PALETTE_EVENT = "regents:hero-palette"

let current: HeroPalette = HERO_PALETTES.rest

/** The palette both canvases are drawing right now. */
export const heroPalette = (): HeroPalette => current

/** Hands both canvases one product's colours, or the resting page back. */
export const setHeroPalette = (name: HeroPaletteName): void => {
  current = HERO_PALETTES[name]
}
