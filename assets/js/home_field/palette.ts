/**
 * One field, drawn twice, so the two canvases have to be handed the same colours
 * in the two forms their pipelines expect.
 *
 * The page canvas writes straight to the screen, so it is given the displayed
 * values. The crown canvas composes in high dynamic range and ends with one
 * tone-mapping and encoding pass, so it is given the values that come out of
 * that pass as the displayed ones. Both sets describe the same picture: the page
 * ground `--rl-bg` (`oklch(14.5% 0 0)`) carrying near-white squares.
 */

/** The Techtree field's cream, kept as the square colour. */
const SQUARE = [0.9569, 0.9333, 0.8941, 1] as const

export const FIELD_PALETTE = {
  /** Displayed values, for a canvas that presents what the shader writes. */
  displayedGround: [0.039388, 0.039388, 0.039388, 1],
  displayedSquare: SQUARE,
  /**
   * Pre-tone-mapping values, for the crown scene. Both were solved against the
   * ACES curve and sRGB encode in the presentation pass, so the two canvases
   * agree to within one 8-bit step everywhere the squares are visible.
   */
  composedGround: [0.008589, 0.008589, 0.008589, 1],
  composedSquare: [0.18441, 0.17923, 0.17068, 1],
  /** How far a fully lit cell travels from the ground toward the square colour. */
  intensity: 0.2,
} as const
