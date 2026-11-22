/**
 * The page's own colours, for the pictures drawn beside it: any colour the
 * stylesheet states, as a shader takes it. A picture hears the page turn light
 * or dark through `watchTheme` (theme.ts).
 */
let swatch: CanvasRenderingContext2D | undefined

/** Any colour the page can state, as the three 0..1 sRGB channels a shader takes. */
export const tone = (root: HTMLElement, property: string): readonly [number, number, number] => {
  swatch ??= document.createElement("canvas").getContext("2d", {willReadFrequently: true})!
  const probe = root.ownerDocument.createElement("span")
  probe.hidden = true
  probe.style.color = `var(${property})`
  root.append(probe)
  const color = getComputedStyle(probe).color
  probe.remove()
  swatch.clearRect(0, 0, 1, 1)
  swatch.fillStyle = color
  swatch.fillRect(0, 0, 1, 1)
  const [red = 0, green = 0, blue = 0] = swatch.getImageData(0, 0, 1, 1).data
  return [red / 255, green / 255, blue / 255]
}
