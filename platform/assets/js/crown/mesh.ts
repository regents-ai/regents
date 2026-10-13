/**
 * The crown's 13 glass cubes as one small mesh.
 *
 * A structural adaptation of the Vercel vgpu prism mesh (see
 * THIRD_PARTY_NOTICES.md):
 * - a rounded 2D contour is extruded along z;
 * - front and back bevel rings are generated inside an ideal optical envelope;
 * - caps are duplicated so they keep flat normals;
 * - all 13 disconnected solids are uploaded as one Geometry.
 */

import {geometry, type Geometry, type Gpu} from "vgpu"

import type {CrownShape, Vec2, Vec3} from "./look"

const CORNER_SEGMENTS = 4
const BEVEL_SEGMENTS = 4

/** position.xyz, normal.xyz, cellCenter.xy. */
const VERTEX_FLOATS = 8
const VERTEX_STRIDE = VERTEX_FLOATS * Float32Array.BYTES_PER_ELEMENT

interface ContourPoint {
  readonly position: Vec2
  readonly normal: Vec2
}

/**
 * Uploads the whole crown. The caller owns the geometry and must destroy it.
 *
 * Every triangle carries its cube's centre, which lets the glass shader intersect
 * the right ideal cube rather than treating the mark as one fused solid.
 */
export function crownGeometry(gpu: Gpu, shape: CrownShape, label: string): Geometry {
  const contour = roundedSquareContour(shape.halfSize, shape.cornerRadius, CORNER_SEGMENTS)
  const vertices: number[] = []
  const indices: number[] = []
  for (const center of shape.cellCenters) appendRoundedCell(vertices, indices, contour, center, shape)

  return geometry(gpu, {
    label,
    buffers: [
      {
        data: new Float32Array(vertices),
        stride: VERTEX_STRIDE,
        attributes: {
          position: {format: "float32x3", offset: 0, location: 0},
          normal: {format: "float32x3", offset: 12, location: 1},
          cell_center: {format: "float32x2", offset: 24, location: 2},
        },
      },
    ],
    indices: new Uint16Array(indices),
  })
}

function appendRoundedCell(
  vertices: number[],
  indices: number[],
  contour: readonly ContourPoint[],
  center: Vec2,
  shape: CrownShape,
): void {
  const rings: number[][] = []
  const zRadius = Math.min(shape.bevelRadius, (shape.frontZ - shape.backZ) * 0.45)

  const push = (position: Vec3, normal: Vec3): number => {
    const index = vertices.length / VERTEX_FLOATS
    vertices.push(...position, ...normal, ...center)
    return index
  }

  const addRing = (theta: number, z: number, zNormal: number): void => {
    const inset = zRadius * (1 - Math.cos(theta))
    const xyWeight = Math.cos(theta)
    rings.push(
      contour.map(({position, normal}) =>
        push(
          [
            center[0] + position[0] - normal[0] * inset,
            center[1] + position[1] - normal[1] * inset,
            z,
          ],
          [normal[0] * xyWeight, normal[1] * xyWeight, zNormal],
        ),
      ),
    )
  }

  const addCap = (sourceRing: readonly number[], normal: Vec3, reverse: boolean): void => {
    const cap = sourceRing.map(source => {
      const base = source * VERTEX_FLOATS
      return push([vertices[base]!, vertices[base + 1]!, vertices[base + 2]!], normal)
    })
    const z = vertices[cap[0]! * VERTEX_FLOATS + 2]!
    const centerIndex = push([center[0], center[1], z], normal)
    for (let point = 0; point < cap.length; point++) {
      const following = (point + 1) % cap.length
      if (reverse) indices.push(centerIndex, cap[following]!, cap[point]!)
      else indices.push(centerIndex, cap[point]!, cap[following]!)
    }
  }

  // Stop just short of a right angle so the cap's boundary triangles keep some area.
  const maxTheta = Math.PI / 2 - 0.06
  const maxSine = Math.sin(maxTheta)

  for (let step = BEVEL_SEGMENTS; step >= 0; step--) {
    const theta = (maxTheta * step) / BEVEL_SEGMENTS
    addRing(
      theta,
      shape.backZ + zRadius - (zRadius * Math.sin(theta)) / maxSine,
      -Math.sin(theta),
    )
  }

  for (let step = 0; step <= BEVEL_SEGMENTS; step++) {
    const theta = (maxTheta * step) / BEVEL_SEGMENTS
    addRing(
      theta,
      shape.frontZ - zRadius + (zRadius * Math.sin(theta)) / maxSine,
      Math.sin(theta),
    )
  }

  for (let band = 0; band < rings.length - 1; band++) {
    const current = rings[band]!
    const next = rings[band + 1]!
    for (let point = 0; point < contour.length; point++) {
      const following = (point + 1) % contour.length
      indices.push(
        current[point]!,
        current[following]!,
        next[following]!,
        current[point]!,
        next[following]!,
        next[point]!,
      )
    }
  }

  addCap(rings[0]!, [0, 0, -1], true)
  addCap(rings.at(-1)!, [0, 0, 1], false)
}

/**
 * Rounded square, wound counter-clockwise. Neighbouring corner arcs end on
 * matching edge normals, so the straight runs between them stay flat.
 */
function roundedSquareContour(halfSize: number, radius: number, segments: number): ContourPoint[] {
  const safeRadius = Math.min(Math.max(radius, 0), halfSize * 0.49)
  const inner = halfSize - safeRadius

  const corners = [
    {center: [inner, -inner], start: -Math.PI / 2},
    {center: [inner, inner], start: 0},
    {center: [-inner, inner], start: Math.PI / 2},
    {center: [-inner, -inner], start: Math.PI},
  ] as const

  return corners.flatMap(({center, start}) =>
    Array.from({length: segments + 1}, (_, step): ContourPoint => {
      const angle = start + (Math.PI / 2) * (step / segments)
      const normal: Vec2 = [Math.cos(angle), Math.sin(angle)]
      return {
        position: [center[0] + normal[0] * safeRadius, center[1] + normal[1] * safeRadius],
        normal,
      }
    }),
  )
}
