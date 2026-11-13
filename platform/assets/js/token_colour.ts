/**
 * Reads the page's colour tokens as red, green and blue from 0 to 1, so a GPU
 * picture paints in the theme's own colours instead of colours written into a
 * shader. Any colour CSS can state works, `color-mix()` included, because the
 * browser itself resolves it by painting one pixel.
 */

export type Rgb = readonly [number, number, number]

/** Any colour the page states, over the colour beneath it, as red, green and blue from 0 to 1. */
export function colourReader() {
  const canvas = document.createElement("canvas")
  canvas.width = 1
  canvas.height = 1
  const context = canvas.getContext("2d", {willReadFrequently: true})!
  return (css: string, under?: Rgb): Rgb => {
    context.clearRect(0, 0, 1, 1)
    context.fillStyle = "rgba(0, 0, 0, 0)"
    context.fillStyle = css
    context.fillRect(0, 0, 1, 1)
    const [r, g, b, a] = context.getImageData(0, 0, 1, 1).data
    const k = a! / 255
    const base = under ?? [0, 0, 0]
    return [r! / 255 * k + base[0] * (1 - k), g! / 255 * k + base[1] * (1 - k), b! / 255 * k + base[2] * (1 - k)]
  }
}
