/**
 * The one camera in the scene. Derived from the Vercel vgpu prism background.
 * See THIRD_PARTY_NOTICES.md.
 *
 * Its distance comes from the box the whole crown fits in: every canvas shape
 * gets one distance that keeps all eight corners inside the margin at every
 * swing the pointer can give it, so the crown keeps the same breathing room
 * through pointer motion and resize.
 */

import {group, perspective, viewMatrices} from "vgpu/scene"

import {
  CAMERA_FOV_DEGREES,
  CAMERA_ORBIT_DEGREES,
  type CrownFraming,
  type CrownRoom,
  type CrownShape,
  type Vec3,
} from "./look"

const CAMERA_FIT_SAFETY = 1.005

export interface CameraView {
  /** Projection moved across the canvas without changing the physical view ray. */
  readonly viewProjection: Float32Array
  readonly position: Vec3
}

const radians = (degrees: number): number => (degrees * Math.PI) / 180
const clamp = (value: number, low: number, high: number): number =>
  Math.min(high, Math.max(low, value))
const dot = (a: Vec3, b: Vec3): number => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

const cross = (a: Vec3, b: Vec3): Vec3 => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
]

const normalize = (value: Vec3): Vec3 => {
  const length = Math.hypot(value[0], value[1], value[2]) || 1
  return [value[0] / length, value[1] / length, value[2] / length]
}

/**
 * The camera for a pointer position, both components in [-1, 1] with 0 at rest.
 *
 * It swings on a sphere around the crown and keeps looking at it. The site's
 * placement then moves the picture across the canvas, which leaves the view ray,
 * and so every reflection in the glass, as it was.
 */
export function cameraView(
  shape: CrownShape,
  framing: CrownFraming,
  aspect: number,
  orbitX = 0,
  orbitY = 0,
): CameraView {
  const distance = crownCameraDistance(shape, framing, aspect)
  const yaw = radians(clamp(orbitX, -1, 1) * CAMERA_ORBIT_DEGREES)
  const pitch = radians(-clamp(orbitY, -1, 1) * CAMERA_ORBIT_DEGREES)
  const cosPitch = Math.cos(pitch)
  const position: Vec3 = [
    Math.sin(yaw) * cosPitch * distance,
    Math.sin(pitch) * distance,
    Math.cos(yaw) * cosPitch * distance,
  ]
  const eye = group({position}).lookAt([0, 0, 0], [0, 1, 0])
  // The whole scene sits between the wall at z = 0 and the glass in front of it,
  // so the depth range only has to bracket a couple of units.
  const projection = perspective(
    {fov: CAMERA_FOV_DEGREES, near: 0.05, far: 4 * distance},
    aspect,
    new Float32Array(16),
  )
  const matrices = {view: new Float32Array(16), viewProjection: new Float32Array(16)}
  viewMatrices({position: eye.worldPosition, quaternion: eye.quaternion}, projection, matrices)

  const centred = matrices.viewProjection
  return {
    viewProjection: moved(centred, framing.place(aspect, room(shape, framing, centred))),
    position,
  }
}

/**
 * Camera distance that fits every corner of the crown at every swing.
 *
 * For a point projected onto one camera axis, the share of the screen it takes is
 * `axis / ((distance + forwardDepth) * tanHalfFov)`. Rearranged, that gives the
 * least distance directly.
 */
function crownCameraDistance(shape: CrownShape, framing: CrownFraming, aspect: number): number {
  const safeAspect = Math.max(0.01, aspect)
  const tanHalfFov = Math.tan(radians(CAMERA_FOV_DEGREES) / 2)
  const usable = 1 - framing.margin * 2
  let required = 0

  for (const orbitX of [-1, 0, 1]) {
    for (const orbitY of [-1, 0, 1]) {
      const yaw = radians(orbitX * CAMERA_ORBIT_DEGREES)
      const pitch = radians(-orbitY * CAMERA_ORBIT_DEGREES)
      const cosPitch = Math.cos(pitch)
      const forward = normalize([
        -Math.sin(yaw) * cosPitch,
        -Math.sin(pitch),
        -Math.cos(yaw) * cosPitch,
      ])
      const right = normalize(cross(forward, [0, 1, 0]))
      const up = cross(right, forward)

      for (const corner of shape.corners) {
        const forwardDepth = dot(corner, forward)
        required = Math.max(
          required,
          Math.abs(dot(corner, right)) / (usable * tanHalfFov * safeAspect) - forwardDepth,
          Math.abs(dot(corner, up)) / (usable * tanHalfFov) - forwardDepth,
        )
      }
    }
  }

  return Math.max(framing.distance, required * CAMERA_FIT_SAFETY)
}

/** How far the crown, as this camera sees it, can move before crossing the margin. */
function room(shape: CrownShape, framing: CrownFraming, matrix: Float32Array): CrownRoom {
  let minX = Number.POSITIVE_INFINITY
  let maxX = Number.NEGATIVE_INFINITY
  let minY = Number.POSITIVE_INFINITY
  let maxY = Number.NEGATIVE_INFINITY
  for (const [x, y, z] of shape.corners) {
    const clipX = matrix[0]! * x + matrix[4]! * y + matrix[8]! * z + matrix[12]!
    const clipY = matrix[1]! * x + matrix[5]! * y + matrix[9]! * z + matrix[13]!
    const clipW = matrix[3]! * x + matrix[7]! * y + matrix[11]! * z + matrix[15]!
    minX = Math.min(minX, clipX / clipW)
    maxX = Math.max(maxX, clipX / clipW)
    minY = Math.min(minY, clipY / clipW)
    maxY = Math.max(maxY, clipY / clipW)
  }
  const usable = 1 - framing.margin * 2
  return {left: -usable - minX, right: usable - maxX, down: -usable - minY, up: usable - maxY}
}

function moved(matrix: Float32Array, [offsetX, offsetY]: readonly [number, number]): Float32Array {
  const shifted = new Float32Array(matrix)
  for (let column = 0; column < 4; column++) {
    shifted[column * 4] = shifted[column * 4]! + offsetX * matrix[column * 4 + 3]!
    shifted[column * 4 + 1] = shifted[column * 4 + 1]! + offsetY * matrix[column * 4 + 3]!
  }
  return shifted
}

/** Column-major XYZ rotation, used to turn the studio the glass reflects. */
export function rotationMatrix(degrees: Vec3): Float32Array {
  const [x, y, z] = degrees.map(radians) as [number, number, number]
  const [sx, cx] = [Math.sin(x), Math.cos(x)]
  const [sy, cy] = [Math.sin(y), Math.cos(y)]
  const [sz, cz] = [Math.sin(z), Math.cos(z)]
  return new Float32Array([
    cy * cz, cy * sz, -sy, 0,
    sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy, 0,
    cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy, 0,
    0, 0, 0, 1,
  ])
}
