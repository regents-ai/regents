/**
 * Where the world cube's camera stands, and which face a point on the canvas
 * falls on. The shader draws from these numbers and the page steers by them,
 * so both agree about what the visitor is pointing at.
 */

/** A rotation, as x, y, z, w. */
export type Quat = [number, number, number, number]
type Vec3 = [number, number, number]

/** Everything the shader needs to draw one frame. */
export type WorldCubeView = {
  rotation: Quat
  /** Camera distance from the cube's centre; under 1 it is inside. */
  distance: number
  /** Tangent of half the vertical field of view. */
  lens: number
  /** Yaw and pitch of the visitor's head once inside a room. */
  look: [number, number]
  /** The room the camera is flying into or standing in. */
  face: number
  /** The face under a resting pointer, or -1. */
  hover: number
  /** How strongly the hovered face is lit, 0 to 1. */
  glow: number
  /** How far right of the canvas middle the cube is drawn, where half the canvas height is 1. */
  shift: number
  /** Seconds since the cube appeared. */
  time: number
}

export const multiply = (a: Quat, b: Quat): Quat => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
  a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
  a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
]

export const aboutAxis = (axis: Vec3, angle: number): Quat => {
  const length = Math.hypot(axis[0], axis[1], axis[2]) || 1
  const s = Math.sin(angle / 2) / length
  return [axis[0] * s, axis[1] * s, axis[2] * s, Math.cos(angle / 2)]
}

export const normalize = (q: Quat): Quat => {
  const length = Math.hypot(q[0], q[1], q[2], q[3]) || 1
  return [q[0] / length, q[1] / length, q[2] / length, q[3] / length]
}

/** The shortest turn from one rotation to another, t of the way along. */
export const slerp = (from: Quat, to: Quat, t: number): Quat => {
  let dot = from[0] * to[0] + from[1] * to[1] + from[2] * to[2] + from[3] * to[3]
  const sign = dot < 0 ? -1 : 1
  dot *= sign
  if (dot > 0.9995) {
    return normalize(from.map((value, i) => value + (to[i]! * sign - value) * t) as Quat)
  }
  const angle = Math.acos(dot)
  const a = Math.sin((1 - t) * angle) / Math.sin(angle)
  const b = (Math.sin(t * angle) / Math.sin(angle)) * sign
  return from.map((value, i) => value * a + to[i]! * b) as Quat
}

const rotate = (q: Quat, v: Vec3): Vec3 => {
  const [x, y, z, w] = q
  const tx = 2 * (y * v[2] - z * v[1])
  const ty = 2 * (z * v[0] - x * v[2])
  const tz = 2 * (x * v[1] - y * v[0])
  return [
    v[0] + w * tx + (y * tz - z * ty),
    v[1] + w * ty + (z * tx - x * tz),
    v[2] + w * tz + (x * ty - y * tx),
  ]
}

const QUARTER = Math.PI / 2

/**
 * The rotation that turns each face square to the camera with its room the
 * right way up. Faces are 0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z, as in the shader.
 */
export const FACE_ON: readonly Quat[] = [
  aboutAxis([0, 1, 0], -QUARTER),
  aboutAxis([0, 1, 0], QUARTER),
  aboutAxis([1, 0, 0], QUARTER),
  aboutAxis([1, 0, 0], -QUARTER),
  [0, 0, 0, 1],
  aboutAxis([0, 1, 0], Math.PI),
]

/**
 * The face under a point on the canvas, or -1 when the point misses the cube.
 * The point is a fraction of the canvas box, measured from its top left.
 */
export const faceAt = (
  view: Pick<WorldCubeView, "rotation" | "distance" | "lens" | "shift">,
  aspect: number,
  x: number,
  y: number,
): number => {
  const sx = ((x - 0.5) * 2 * aspect - view.shift) * view.lens
  const sy = (0.5 - y) * 2 * view.lens
  const inverse: Quat = [-view.rotation[0], -view.rotation[1], -view.rotation[2], view.rotation[3]]
  const origin = rotate(inverse, [0, 0, view.distance])
  const ray = rotate(inverse, [sx, sy, -1])

  let enter = -Infinity
  let leave = Infinity
  let face = -1
  for (let axis = 0; axis < 3; axis++) {
    const direction = Math.abs(ray[axis]!) < 1e-6 ? 1e-6 : ray[axis]!
    const a = (-1 - origin[axis]!) / direction
    const b = (1 - origin[axis]!) / direction
    if (Math.min(a, b) > enter) {
      enter = Math.min(a, b)
      face = axis * 2 + (direction > 0 ? 1 : 0)
    }
    leave = Math.min(leave, Math.max(a, b))
  }
  return enter < leave && enter > 0 ? face : -1
}
