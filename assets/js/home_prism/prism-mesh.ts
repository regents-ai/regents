/**
 * Procedural, subtly filleted prism geometry. Forked from the Vercel vgpu prism
 * background. See THIRD_PARTY_NOTICES.md.
 *
 * `types.ts` owns the ideal triangular solid used by the CPU ray tracer and by
 * `shaders/glass.ts` when it measures the optical path. This file only rounds the
 * visible mesh inward, so the bevel can catch the environment without ever moving
 * the light-producing faces outside their analytically traced planes.
 *
 * The construction is an equilateral triangle with a small fillet on all nine edges.
 * The triangular cross-section is replaced by tangent circular arcs, then
 * quarter-round rings blend that outline into inset front and back caps.
 */

import {geometry, type Geometry, type Gpu} from "vgpu"

import {PRISM_BACK_Z, PRISM_FRONT_Z, PRISM_TRIANGLE, type Triangle, type Vec2} from "./types"

type Vec3 = readonly [number, number, number]

interface ContourPoint {
  readonly position: Vec2
  readonly normal: Vec2
}

interface PrismMeshData {
  /** Interleaved position (xyz) then normal (xyz), 6 floats per vertex. */
  readonly vertices: Float32Array<ArrayBuffer>
  readonly indices: Uint16Array<ArrayBuffer>
}

/** Bytes between two vertices of `PrismMeshData.vertices`. */
const PRISM_VERTEX_STRIDE = 24
/** 1.125 mm fillet on the 57 mm text-to-cad reference scale. */
const PRISM_BEVEL_RADIUS = 0.01125
/** Arc subdivisions around each triangular corner. */
const PRISM_CORNER_SEGMENTS = 4
/** Quarter-round subdivisions between each broad side and cap. */
const PRISM_BEVEL_SEGMENTS = 4
/** Longitudinal subdivisions along each straight run of the rounded contour. */
const PRISM_EDGE_SEGMENTS = 16

/**
 * Vertices and indices for the rounded prism, wound counter-clockwise from outside
 * so `cull: 'back'` keeps the faces that face the camera.
 */
function prismMeshData(triangle: Triangle = PRISM_TRIANGLE): PrismMeshData {
  const radius = Math.min(PRISM_BEVEL_RADIUS, (PRISM_FRONT_Z - PRISM_BACK_Z) * 0.45)
  const contour = roundedTriangleContour(triangle, radius)
  const vertices: number[] = []
  const indices: number[] = []
  const rings: number[][] = []

  const push = (position: Vec3, normal: Vec3): number => {
    const index = vertices.length / 6
    vertices.push(...position, ...normal)
    return index
  }
  const addRing = (theta: number, z: number, zNormal: number): void => {
    const inset = radius * (1 - Math.cos(theta))
    const xyWeight = Math.cos(theta)
    rings.push(
      contour.map(({position, normal}) =>
        push(
          [position[0] - normal[0] * inset, position[1] - normal[1] * inset, z],
          [normal[0] * xyWeight, normal[1] * xyWeight, zNormal],
        ),
      ),
    )
  }

  // Stop a fraction short of pi/2 so the tiny cap corner arcs retain positive area
  // instead of collapsing every sample at a corner onto the same point.
  const maxTheta = Math.PI / 2 - 0.06
  const maxSine = Math.sin(maxTheta)
  for (let step = PRISM_BEVEL_SEGMENTS; step >= 0; step--) {
    const theta = (maxTheta * step) / PRISM_BEVEL_SEGMENTS
    addRing(theta, PRISM_BACK_Z + radius - (radius * Math.sin(theta)) / maxSine, -Math.sin(theta))
  }
  for (let step = 0; step <= PRISM_BEVEL_SEGMENTS; step++) {
    const theta = (maxTheta * step) / PRISM_BEVEL_SEGMENTS
    addRing(theta, PRISM_FRONT_Z - radius + (radius * Math.sin(theta)) / maxSine, Math.sin(theta))
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
  addCap(rings[rings.length - 1]!, [0, 0, 1], false)

  return {vertices: new Float32Array(vertices), indices: new Uint16Array(indices)}

  function addCap(sourceRing: readonly number[], normal: Vec3, reverse: boolean): void {
    const cap = sourceRing.map(source => {
      const base = source * 6
      return push([vertices[base]!, vertices[base + 1]!, vertices[base + 2]!], normal)
    })
    const center = [0, 1, 2].map(
      axis => cap.reduce((sum, index) => sum + vertices[index * 6 + axis]!, 0) / cap.length,
    ) as unknown as Vec3
    const centerIndex = push(center, normal)
    for (let point = 0; point < cap.length; point++) {
      const following = (point + 1) % cap.length
      if (reverse) indices.push(centerIndex, cap[following]!, cap[point]!)
      else indices.push(centerIndex, cap[point]!, cap[following]!)
    }
  }
}

/** Uploads the solid triangle mesh. The caller owns it and must `destroy()` it. */
export function prismGeometry(gpu: Gpu, label: string): Geometry {
  const {vertices, indices} = prismMeshData()
  return geometry(gpu, {
    label,
    buffers: [
      {
        data: vertices,
        stride: PRISM_VERTEX_STRIDE,
        attributes: {position: "float32x3", normal: "float32x3"},
      },
    ],
    indices,
  })
}

/** Outward normal of one edge of a counter-clockwise triangle. */
function outwardNormal(start: Vec2, end: Vec2): Vec2 {
  const edge: Vec2 = [end[0] - start[0], end[1] - start[1]]
  const length = Math.hypot(edge[0], edge[1]) || 1
  return [edge[1] / length, -edge[0] / length]
}

function normalize2(value: Vec2): Vec2 {
  const length = Math.hypot(value[0], value[1]) || 1
  return [value[0] / length, value[1] / length]
}

function roundedTriangleContour(triangle: Triangle, radius: number): ContourPoint[] {
  const corners = [triangle.a, triangle.b, triangle.c]
  const arcs = corners.map((corner, index) => {
    const previous = corners[(index + 2) % 3]!
    const next = corners[(index + 1) % 3]!
    const towardPrevious = normalize2([previous[0] - corner[0], previous[1] - corner[1]])
    const towardNext = normalize2([next[0] - corner[0], next[1] - corner[1]])
    const cosine = towardPrevious[0] * towardNext[0] + towardPrevious[1] * towardNext[1]
    const halfAngle = Math.acos(Math.min(1, Math.max(-1, cosine))) / 2
    const tangentDistance = radius / Math.max(Math.tan(halfAngle), 1e-6)
    const centerDistance = radius / Math.max(Math.sin(halfAngle), 1e-6)
    const bisector = normalize2([
      towardPrevious[0] + towardNext[0],
      towardPrevious[1] + towardNext[1],
    ])
    const center: Vec2 = [
      corner[0] + bisector[0] * centerDistance,
      corner[1] + bisector[1] * centerDistance,
    ]
    const angleAt = (toward: Vec2): number =>
      Math.atan2(
        corner[1] + toward[1] * tangentDistance - center[1],
        corner[0] + toward[0] * tangentDistance - center[0],
      )
    const startAngle = angleAt(towardPrevious)
    let endAngle = angleAt(towardNext)
    while (endAngle <= startAngle) endAngle += Math.PI * 2
    return Array.from({length: PRISM_CORNER_SEGMENTS + 1}, (_, step): ContourPoint => {
      const angle = startAngle + ((endAngle - startAngle) * step) / PRISM_CORNER_SEGMENTS
      const normal: Vec2 = [Math.cos(angle), Math.sin(angle)]
      return {
        position: [center[0] + normal[0] * radius, center[1] + normal[1] * radius],
        normal,
      }
    })
  })

  return arcs.flatMap((arc, index) => {
    const end = arc[arc.length - 1]!
    const nextStart = arcs[(index + 1) % 3]![0]!
    const edgeNormal = outwardNormal(corners[index]!, corners[(index + 1) % 3]!)
    const straight = Array.from({length: PRISM_EDGE_SEGMENTS - 1}, (_, step): ContourPoint => {
      const amount = (step + 1) / PRISM_EDGE_SEGMENTS
      return {
        position: [
          end.position[0] + (nextStart.position[0] - end.position[0]) * amount,
          end.position[1] + (nextStart.position[1] - end.position[1]) * amount,
        ],
        normal: edgeNormal,
      }
    })
    return [...arc, ...straight]
  })
}
