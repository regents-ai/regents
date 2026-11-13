/**
 * Reads the server's drawing of an icon or a mark (an inline SVG inside the
 * field) into a raster fitted into the shape's box, for `pictureShape` to put
 * grains on. Each element is painted the way the SVG paints it, stroke or fill,
 * so any Lucide icon and any flat mark works without code of its own.
 */
import type {Picture} from "./shapes"

/** Cells across the box's longer side. */
const CELLS = 360

const DRAWN = "path, circle, ellipse, line, polyline, polygon, rect"

const number = (el: Element, name: string) => Number(el.getAttribute(name) ?? 0)

/** The paint an element takes: its own attribute, or the nearest one round it. */
const paint = (el: Element, name: string) => el.closest(`[${name}]`)?.getAttribute(name) ?? undefined

const points = (el: Element) =>
  (el.getAttribute("points") ?? "")
    .trim()
    .split(/[\s,]+/)
    .map(Number)

function pathOf(el: Element): Path2D {
  const path = new Path2D()
  switch (el.localName) {
    case "path":
      path.addPath(new Path2D(el.getAttribute("d") ?? ""))
      break
    case "circle":
      path.arc(number(el, "cx"), number(el, "cy"), number(el, "r"), 0, 2 * Math.PI)
      break
    case "ellipse":
      path.ellipse(number(el, "cx"), number(el, "cy"), number(el, "rx"), number(el, "ry"), 0, 0, 2 * Math.PI)
      break
    case "line":
      path.moveTo(number(el, "x1"), number(el, "y1"))
      path.lineTo(number(el, "x2"), number(el, "y2"))
      break
    case "polyline":
    case "polygon": {
      const xy = points(el)
      for (let k = 0; k + 1 < xy.length; k += 2) path.lineTo(xy[k]!, xy[k + 1]!)
      if (el.localName === "polygon") path.closePath()
      break
    }
    case "rect":
      path.roundRect(number(el, "x"), number(el, "y"), number(el, "width"), number(el, "height"), number(el, "rx"))
      break
  }
  return path
}

/** The drawing, contained in a box `aspect` wide and one tall, as one cell per raster pixel. */
export function pictureOf(svg: SVGSVGElement, aspect: number): Picture {
  const [vx, vy, vw, vh] = svg.getAttribute("viewBox")!.trim().split(/[\s,]+/).map(Number) as [number, number, number, number]
  const cell = Math.max(aspect, 1) / CELLS
  const width = Math.ceil(aspect / cell)
  const height = Math.ceil(1 / cell)
  // Units per drawing unit: the drawing fits the box and sits in its middle.
  const fit = Math.min(aspect / vw, 1 / vh)
  const scale = fit / cell
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext("2d", {willReadFrequently: true})!
  context.setTransform(scale, 0, 0, scale, (aspect / 2 - (vx + vw / 2) * fit) / cell, (0.5 - (vy + vh / 2) * fit) / cell)
  context.fillStyle = "#fff"
  context.strokeStyle = "#fff"
  for (const el of svg.querySelectorAll(DRAWN)) {
    const path = pathOf(el)
    // SVG fills black unless told otherwise, and strokes nothing.
    if ((paint(el, "fill") ?? "black") !== "none") context.fill(path)
    if ((paint(el, "stroke") ?? "none") !== "none") {
      context.lineWidth = Number(paint(el, "stroke-width") ?? 1)
      context.lineCap = (paint(el, "stroke-linecap") ?? "butt") as CanvasLineCap
      context.lineJoin = (paint(el, "stroke-linejoin") ?? "miter") as CanvasLineJoin
      context.stroke(path)
    }
  }
  const pixels = context.getImageData(0, 0, width, height).data
  const mask = new Uint8Array(width * height)
  for (let c = 0; c < mask.length; c++) mask[c] = pixels[c * 4 + 3]! >= 128 ? 1 : 0
  return {mask, width, height, cell, left: -aspect / 2, top: -0.5}
}
