/**
 * Deterministic geometry for the light itself, forked from the Vercel vgpu prism
 * background. See THIRD_PARTY_NOTICES.md.
 *
 * The mesh integrates two continuous dimensions. Wavelength vertices are connected
 * to their neighbours, so RGB can interpolate without visible bands. Several
 * additive spectral sheets sample the finite width of the collimated beam,
 * preserving the footprint that a single centre ray would collapse. Their XY
 * coordinates are lifted to a shared world-space depth by `shaders/light.ts`.
 */

import {intersectTriangle, iorAt, tracePrismDetailed, type DetailedPrismPath} from "./optics"
import {
  PRISM_BEAM_SLICES,
  PRISM_DISPERSION,
  PRISM_EDGE_FALLOFF,
  PRISM_LIGHT_EXPOSURE,
  PRISM_MAX_INTERNAL_BOUNCES,
  PRISM_SPECTRAL_SAMPLES,
  PRISM_TRIANGLE,
  PRISM_WAVELENGTHS,
  type CollimatedLight,
  type Vec2,
} from "./types"

/** position.xy, wavelength, transverse profile, intensity, distance from glass. */
const LIGHT_VERTEX_FLOATS = 6
export const LIGHT_VERTEX_STRIDE = LIGHT_VERTEX_FLOATS * Float32Array.BYTES_PER_ELEMENT
const VERTICES_PER_QUAD = 6
const MAX_INTERNAL_SEGMENTS = PRISM_MAX_INTERNAL_BOUNCES + 1
/** White input and internal quads, ahead of the spectral cells in the same buffer. */
export const LIGHT_WHITE_QUADS = (1 + MAX_INTERNAL_SEGMENTS) * PRISM_BEAM_SLICES
const DENSITY_MEASURE_DISTANCE = 1
/** The collimated source is deliberately emissive HDR, not painted white. */
const INPUT_BEAM_RADIANCE = 6
/** Fresnel transmission makes the light inside the glass slightly dimmer. */
const INTERNAL_BEAM_RADIANCE = 4.5

/** White input/internal quads, then one cell per wavelength interval and beam slice. */
export const LIGHT_VERTEX_COUNT =
  (LIGHT_WHITE_QUADS + (PRISM_SPECTRAL_SAMPLES - 1) * PRISM_BEAM_SLICES) * VERTICES_PER_QUAD

export interface LightMeshOptions {
  readonly light: CollimatedLight
  readonly wallHalfExtent: Vec2
}

interface SpectralNode {
  readonly wavelength: number
  readonly paths: readonly (DetailedPrismPath | undefined)[]
}

const add = (a: Vec2, b: Vec2): Vec2 => [a[0] + b[0], a[1] + b[1]]
const sub = (a: Vec2, b: Vec2): Vec2 => [a[0] - b[0], a[1] - b[1]]
const scale = (a: Vec2, amount: number): Vec2 => [a[0] * amount, a[1] * amount]
const cross = (a: Vec2, b: Vec2): number => a[0] * b[1] - a[1] * b[0]
const dot = (a: Vec2, b: Vec2): number => a[0] * b[0] + a[1] * b[1]
const normalize = (a: Vec2): Vec2 => {
  const magnitude = Math.hypot(a[0], a[1]) || 1
  return [a[0] / magnitude, a[1] / magnitude]
}

/** Origin at a normalized coordinate across the finite collimated beam. */
function beamProfileOrigin(light: CollimatedLight, profile: number): Vec2 {
  const perpendicular: Vec2 = [-light.direction[1], light.direction[0]]
  return add(
    light.center,
    scale(perpendicular, light.beamHalfWidth * Math.min(1, Math.max(-1, profile))),
  )
}

/** First point where a forward ray reaches the axis-aligned wall rectangle. */
function rayToWallBoundary(origin: Vec2, direction: Vec2, halfExtent: Vec2): Vec2 {
  let nearest = Number.POSITIVE_INFINITY
  for (let axis = 0; axis < 2; axis++) {
    const component = direction[axis]!
    if (Math.abs(component) < 1e-8) continue
    for (const side of [-halfExtent[axis]!, halfExtent[axis]!] as const) {
      const distance = (side - origin[axis]!) / component
      if (distance <= 0 || distance >= nearest) continue
      const other = 1 - axis
      const otherCoordinate = origin[other]! + direction[other]! * distance
      if (Math.abs(otherCoordinate) <= halfExtent[other]! + 1e-6) nearest = distance
    }
  }
  return Number.isFinite(nearest) ? add(origin, scale(direction, nearest)) : origin
}

/** The portion of a forward ray that lies inside the wall rectangle. */
function lineThroughWall(
  origin: Vec2,
  direction: Vec2,
  halfExtent: Vec2,
): readonly [Vec2, Vec2] | undefined {
  let near = Number.NEGATIVE_INFINITY
  let far = Number.POSITIVE_INFINITY
  for (let axis = 0; axis < 2; axis++) {
    const component = direction[axis]!
    const coordinate = origin[axis]!
    const extent = halfExtent[axis]!
    if (Math.abs(component) < 1e-8) {
      if (Math.abs(coordinate) > extent) return undefined
      continue
    }
    const first = (-extent - coordinate) / component
    const second = (extent - coordinate) / component
    near = Math.max(near, Math.min(first, second))
    far = Math.min(far, Math.max(first, second))
    if (near > far) return undefined
  }
  near = Math.max(0, near)
  if (!Number.isFinite(near) || !Number.isFinite(far) || far < near) return undefined
  return [add(origin, scale(direction, near)), add(origin, scale(direction, far))]
}

/** Exact overlap test between the forward finite beam strip and the triangle. */
function beamIntersectsPrism(light: CollimatedLight): boolean {
  const perpendicular: Vec2 = [-light.direction[1], light.direction[0]]
  let polygon: Vec2[] = [PRISM_TRIANGLE.a, PRISM_TRIANGLE.b, PRISM_TRIANGLE.c].map(point => {
    const offset = sub(point, light.center)
    return [dot(offset, light.direction), dot(offset, perpendicular)]
  })
  const clip = (inside: (point: Vec2) => number): void => {
    const input = polygon
    polygon = []
    for (let index = 0; index < input.length; index++) {
      const start = input[index]!
      const end = input[(index + 1) % input.length]!
      const startDistance = inside(start)
      const endDistance = inside(end)
      const startInside = startDistance >= 0
      const endInside = endDistance >= 0
      if (startInside) polygon.push(start)
      if (startInside === endInside) continue
      const amount = startDistance / (startDistance - endDistance)
      polygon.push([
        start[0] + (end[0] - start[0]) * amount,
        start[1] + (end[1] - start[1]) * amount,
      ])
    }
  }
  clip(point => point[0])
  if (polygon.length === 0) return false
  clip(point => point[1] + light.beamHalfWidth)
  if (polygon.length === 0) return false
  clip(point => light.beamHalfWidth - point[1])
  return polygon.length > 0
}

const matchingTopology = (a: DetailedPrismPath, b: DetailedPrismPath): boolean =>
  a.edges.length === b.edges.length && a.edges.every((edge, index) => edge === b.edges[index])

function pushVertex(
  output: number[],
  point: Vec2,
  wavelength: number,
  profile: number,
  intensity: number,
  travel: number,
): void {
  output.push(point[0], point[1], wavelength, profile, intensity, travel)
}

function pushQuad(
  output: number[],
  lowerStart: Vec2,
  upperStart: Vec2,
  lowerEnd: Vec2,
  upperEnd: Vec2,
  intensity: number,
  lowerProfile = -1,
  upperProfile = 1,
): void {
  pushVertex(output, lowerStart, -1, lowerProfile, intensity, 0)
  pushVertex(output, upperStart, -1, upperProfile, intensity, 0)
  pushVertex(output, upperEnd, -1, upperProfile, intensity, 0)
  pushVertex(output, lowerStart, -1, lowerProfile, intensity, 0)
  pushVertex(output, upperEnd, -1, upperProfile, intensity, 0)
  pushVertex(output, lowerEnd, -1, lowerProfile, intensity, 0)
}

/** A cell whose two rails carry neighbouring wavelengths and intensities. */
function pushSpectralCell(
  output: number[],
  lowStart: Vec2,
  highStart: Vec2,
  lowEnd: Vec2,
  highEnd: Vec2,
  lowWavelength: number,
  highWavelength: number,
  lowIntensity: number,
  highIntensity: number,
): void {
  pushVertex(output, lowStart, lowWavelength, 0, lowIntensity, 0)
  pushVertex(output, highStart, highWavelength, 0, highIntensity, 0)
  pushVertex(output, highEnd, highWavelength, 0, highIntensity, 1)
  pushVertex(output, lowStart, lowWavelength, 0, lowIntensity, 0)
  pushVertex(output, highEnd, highWavelength, 0, highIntensity, 1)
  pushVertex(output, lowEnd, lowWavelength, 0, lowIntensity, 1)
}

const pushEmptyQuad = (output: number[]): void =>
  pushQuad(output, [0, 0], [0, 0], [0, 0], [0, 0], 0)

/** Gaussian scattering profile with a zero-energy rim at the beam boundary. */
function normalizedProfileWeights(profiles: readonly number[]): readonly number[] {
  const weights = profiles.map(profile => {
    const edge = Math.min(1, Math.max(0, (Math.abs(profile) - 0.55) / 0.45))
    const smooth = edge * edge * (3 - 2 * edge)
    return Math.exp(-PRISM_EDGE_FALLOFF * profile * profile) * (1 - smooth)
  })
  const sum = weights.reduce((total, weight) => total + weight, 0) || 1
  return weights.map(weight => weight / sum)
}

const canConnect = (
  a: SpectralNode | undefined,
  b: SpectralNode | undefined,
  profileIndex: number,
): boolean => {
  const aPath = a?.paths[profileIndex]
  const bPath = b?.paths[profileIndex]
  return Boolean(aPath && bPath && matchingTopology(aPath, bPath))
}

const densityReference = (path: DetailedPrismPath): Vec2 =>
  add(path.origin, scale(path.direction, DENSITY_MEASURE_DISTANCE))

/**
 * Spectral energy density at one wavelength vertex.
 *
 * The finite difference estimates how much screen-space width a normalized
 * wavelength interval occupies. Dividing flux by that Jacobian keeps total energy
 * stable when the mesh is subdivided more finely.
 */
function spectralDensity(
  nodes: readonly (SpectralNode | undefined)[],
  nodeIndex: number,
  profileIndex: number,
  inputWidth: number,
  profileWeight: number,
): number {
  const path = nodes[nodeIndex]?.paths[profileIndex]
  if (!path) return 0

  let left = nodeIndex - 1
  while (left >= 0 && !nodes[left]?.paths[profileIndex]) left--
  let right = nodeIndex + 1
  while (right < nodes.length && !nodes[right]?.paths[profileIndex]) right++
  if (left < 0) left = nodeIndex
  if (right >= nodes.length) right = nodeIndex
  if (left === right) return 0

  const leftPath = nodes[left]!.paths[profileIndex]!
  const rightPath = nodes[right]!.paths[profileIndex]!
  if (!matchingTopology(leftPath, rightPath)) return 0
  const direction = normalize(add(leftPath.direction, rightPath.direction))
  const spectralWidth = Math.abs(
    cross(sub(densityReference(rightPath), densityReference(leftPath)), direction),
  )
  const jacobian = spectralWidth / ((right - left) / (nodes.length - 1))
  return (
    (PRISM_LIGHT_EXPOSURE * inputWidth * profileWeight * path.transmission) /
    Math.max(jacobian, 1e-4)
  )
}

/** Build the white input and wavelength-connected spectral sheets. */
export function buildLightMesh(options: LightMeshOptions): Float32Array<ArrayBuffer> {
  const {direction} = options.light
  const vertices: number[] = []
  const inputWidth = options.light.beamHalfWidth * 2
  const profiles = Array.from(
    {length: PRISM_BEAM_SLICES},
    (_, index) => -1 + (2 * (index + 0.5)) / PRISM_BEAM_SLICES,
  )
  const profileWeights = normalizedProfileWeights(profiles)

  // White light is sliced across its finite width too. This lets neighbouring parts
  // of a grazing beam enter different faces — or miss the prism — without
  // invalidating the rest of the beam.
  const middleIor = iorAt(
    (PRISM_WAVELENGTHS.min + PRISM_WAVELENGTHS.max) * 0.5,
    PRISM_DISPERSION.base,
    PRISM_DISPERSION.strength,
  )
  const whiteBoundaries = Array.from(
    {length: PRISM_BEAM_SLICES + 1},
    (_, index) => -1 + (2 * index) / PRISM_BEAM_SLICES,
  ).map(profile => {
    const origin = beamProfileOrigin(options.light, profile)
    const hit = intersectTriangle(PRISM_TRIANGLE, origin, direction, 1e-4)
    return {
      profile,
      entry: hit && dot(direction, hit.normal) < 0 ? add(origin, scale(direction, hit.t)) : undefined,
      wall: lineThroughWall(origin, direction, options.wallHalfExtent),
      path: tracePrismDetailed(PRISM_TRIANGLE, origin, direction, middleIor),
    }
  })
  const backwards: Vec2 = [-direction[0], -direction[1]]
  for (let slice = 0; slice < PRISM_BEAM_SLICES; slice++) {
    const lower = whiteBoundaries[slice]!
    const upper = whiteBoundaries[slice + 1]!
    if (lower.entry && upper.entry) {
      pushQuad(
        vertices,
        rayToWallBoundary(lower.entry, backwards, options.wallHalfExtent),
        rayToWallBoundary(upper.entry, backwards, options.wallHalfExtent),
        lower.entry,
        upper.entry,
        INPUT_BEAM_RADIANCE,
        lower.profile,
        upper.profile,
      )
    } else {
      const cellLight: CollimatedLight = {
        center: beamProfileOrigin(options.light, (lower.profile + upper.profile) * 0.5),
        direction,
        beamHalfWidth: options.light.beamHalfWidth * (upper.profile - lower.profile) * 0.5,
      }
      if (!beamIntersectsPrism(cellLight) && lower.wall && upper.wall) {
        pushQuad(
          vertices,
          lower.wall[0],
          upper.wall[0],
          lower.wall[1],
          upper.wall[1],
          INPUT_BEAM_RADIANCE,
          lower.profile,
          upper.profile,
        )
      } else {
        pushEmptyQuad(vertices)
      }
    }

    const connectedInternal = Boolean(
      lower.path && upper.path && matchingTopology(lower.path, upper.path),
    )
    for (let segment = 0; segment < MAX_INTERNAL_SEGMENTS; segment++) {
      const lowerStart = lower.path?.points[segment]
      const lowerEnd = lower.path?.points[segment + 1]
      const upperStart = upper.path?.points[segment]
      const upperEnd = upper.path?.points[segment + 1]
      if (connectedInternal && lowerStart && lowerEnd && upperStart && upperEnd) {
        pushQuad(
          vertices,
          lowerStart,
          upperStart,
          lowerEnd,
          upperEnd,
          INTERNAL_BEAM_RADIANCE,
          lower.profile,
          upper.profile,
        )
      } else {
        pushEmptyQuad(vertices)
      }
    }
  }

  const nodes: (SpectralNode | undefined)[] = []
  for (let index = 0; index < PRISM_SPECTRAL_SAMPLES; index++) {
    const wavelength =
      PRISM_WAVELENGTHS.min +
      (PRISM_WAVELENGTHS.max - PRISM_WAVELENGTHS.min) *
        (index / (PRISM_SPECTRAL_SAMPLES - 1))
    const ior = iorAt(wavelength, PRISM_DISPERSION.base, PRISM_DISPERSION.strength)
    const paths = profiles.map(profile =>
      tracePrismDetailed(PRISM_TRIANGLE, beamProfileOrigin(options.light, profile), direction, ior),
    )
    nodes.push(paths.some(Boolean) ? {wavelength, paths} : undefined)
  }

  const densities = nodes.map((node, nodeIndex) =>
    profiles.map((_, profileIndex) =>
      node
        ? spectralDensity(nodes, nodeIndex, profileIndex, inputWidth, profileWeights[profileIndex]!)
        : 0,
    ),
  )

  for (let interval = 0; interval < PRISM_SPECTRAL_SAMPLES - 1; interval++) {
    const low = nodes[interval]
    const high = nodes[interval + 1]

    for (let profileIndex = 0; profileIndex < PRISM_BEAM_SLICES; profileIndex++) {
      if (!canConnect(low, high, profileIndex)) {
        pushEmptyQuad(vertices)
        continue
      }
      const lowPath = low!.paths[profileIndex]!
      const highPath = high!.paths[profileIndex]!
      pushSpectralCell(
        vertices,
        lowPath.origin,
        highPath.origin,
        rayToWallBoundary(lowPath.origin, lowPath.direction, options.wallHalfExtent),
        rayToWallBoundary(highPath.origin, highPath.direction, options.wallHalfExtent),
        low!.wavelength,
        high!.wavelength,
        densities[interval]![profileIndex]!,
        densities[interval + 1]![profileIndex]!,
      )
    }
  }

  return new Float32Array(vertices)
}
