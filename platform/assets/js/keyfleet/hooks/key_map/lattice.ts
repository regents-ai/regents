/**
 * Pointy-top hex lattice maths for the key map.
 *
 * Cells are axial `(q, r)`. Row layouts are authored in odd-r offset
 * coordinates `(col, row)`, where odd rows sit half a cell to the right.
 * Pixel conversion takes the hexagon's circumradius; a tile is `√3·size` wide
 * and `2·size` tall, and rows are `1.5·size` apart.
 */

export type Cell = readonly [q: number, r: number]
export type Point = readonly [x: number, y: number]

export const SQRT3 = Math.sqrt(3)

export const mod = (value: number, modulus: number) => ((value % modulus) + modulus) % modulus

export const offsetToAxial = (col: number, row: number): Cell => [col - Math.floor(row / 2), row]

export const axialToOffset = (q: number, r: number): Cell => [q + Math.floor(r / 2), r]

export const axialToPixel = (q: number, r: number, size: number): Point => [
  size * SQRT3 * (q + r / 2),
  size * 1.5 * r,
]

/** The cell under a pixel, by cube rounding. */
export function pixelToAxial(x: number, y: number, size: number): Cell {
  const fq = ((SQRT3 / 3) * x - y / 3) / size
  const fr = ((2 / 3) * y) / size
  const fs = -fq - fr
  let q = Math.round(fq)
  let r = Math.round(fr)
  const s = Math.round(fs)
  const dq = Math.abs(q - fq)
  const dr = Math.abs(r - fr)
  const ds = Math.abs(s - fs)
  if (dq > dr && dq > ds) q = -r - s
  else if (dr > ds) r = -q - s
  return [q + 0, r + 0]
}

export const hexDistance = (dq: number, dr: number) =>
  (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2

/**
 * The copy of `home` nearest `target` among `home + i·a + j·b` for integer
 * `i, j`. Solves for real `i, j` with the 2×2 inverse, then keeps the closest
 * of the integer pairs around the rounded answer.
 */
export function nearestCopy(home: Point, target: Point, a: Point, b: Point): Point {
  const dx = target[0] - home[0]
  const dy = target[1] - home[1]
  const det = a[0] * b[1] - a[1] * b[0]
  const i0 = Math.round((dx * b[1] - dy * b[0]) / det)
  const j0 = Math.round((a[0] * dy - a[1] * dx) / det)
  let best: Point = home
  let bestDistance = Infinity
  for (let i = i0 - 1; i <= i0 + 1; i++) {
    for (let j = j0 - 1; j <= j0 + 1; j++) {
      const x = home[0] + i * a[0] + j * b[0]
      const y = home[1] + i * a[1] + j * b[1]
      const distance = (x - target[0]) ** 2 + (y - target[1]) ** 2
      if (distance < bestDistance) {
        best = [x, y]
        bestDistance = distance
      }
    }
  }
  return best
}
