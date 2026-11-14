/**
 * The Overview hero's scene as the server composed it
 * (`RegentsWeb.Components.LabBlocks.Scene`), and its camera. The server projects
 * the scene the same way to place the names and lines, so a point drawn here
 * lands where the page put it.
 */

export type Vec3 = readonly [number, number, number]

export type CameraJson = {
  readonly eye: Vec3
  readonly target: Vec3
  readonly fov: number
  readonly aspect: number
}

export type Layout = {
  readonly camera: CameraJson
  readonly light: Vec3
  /** Half a product block's size, and its three axes. */
  readonly half: number
  readonly axes: readonly [Vec3, Vec3, Vec3]
  /** Each product's block's middle, in the places' order; Sign-in with Agent last. */
  readonly blocks: readonly Vec3[]
  /** The crown's blocks: half their size, how much brighter than the light alone, and each middle with its place along the gradient. */
  readonly crown: {
    readonly half: Vec3
    readonly exposure: number
    readonly cells: readonly (readonly [number, number, number, number])[]
  }
  /** Each line's two ends, by their blocks' order. */
  readonly lines: readonly (readonly [number, number])[]
  /** Half the tunnel's width and height, where it starts and ends, how deep a band is and how wide a tile. */
  readonly tunnel: {
    readonly half: readonly [number, number]
    readonly near: number
    readonly far: number
    readonly step: number
    readonly tile: number
  }
}

export type Scene = {readonly wide: Layout; readonly narrow: Layout}

export type Camera = CameraJson & {
  readonly forward: Vec3
  readonly right: Vec3
  readonly up: Vec3
  readonly tan: number
}

export const add = (a: Vec3, b: Vec3): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
export const sub = (a: Vec3, b: Vec3): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
export const scale = (a: Vec3, s: number): Vec3 => [a[0] * s, a[1] * s, a[2] * s]
export const dot = (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
export const cross = (a: Vec3, b: Vec3): Vec3 => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
]
export const normalize = (a: Vec3): Vec3 => scale(a, 1 / Math.hypot(...a))

export function camera(json: CameraJson): Camera {
  const forward = normalize(sub(json.target, json.eye))
  const right = normalize(cross(forward, [0, 1, 0]))
  return {...json, forward, right, up: cross(right, forward), tan: Math.tan((json.fov * Math.PI) / 360)}
}

/** A point as `[x %, y %, depth]` on the stage. */
export function project(view: Camera, point: Vec3): Vec3 {
  const d = sub(point, view.eye)
  const depth = dot(d, view.forward)
  const nx = dot(d, view.right) / (depth * view.tan * view.aspect)
  const ny = dot(d, view.up) / (depth * view.tan)
  return [(nx + 1) * 50, (1 - ny) * 50, depth]
}

/** The camera swung round its target: `yaw` to the side and `pitch` up, in radians. */
export function orbit(json: CameraJson, yaw: number, pitch: number): CameraJson {
  const arm = sub(json.eye, json.target)
  const reach = Math.hypot(...arm)
  const around = Math.atan2(arm[0], arm[2]) + yaw
  const up = Math.atan2(arm[1], Math.hypot(arm[0], arm[2])) + pitch
  const swung: Vec3 = [
    reach * Math.cos(up) * Math.sin(around),
    reach * Math.sin(up),
    reach * Math.cos(up) * Math.cos(around),
  ]
  return {...json, eye: add(json.target, swung)}
}

const byte = (hex: string, at: number) => parseInt(hex.slice(at, at + 2), 16) / 255

/** A `#rrggbb` colour as channels from 0 to 1. */
export const channels = (hex: string): Vec3 => [byte(hex, 1), byte(hex, 3), byte(hex, 5)]

/** A computed `rgb()` colour as channels from 0 to 1. */
export function computed(value: string): Vec3 {
  const [r, g, b] = value.match(/[\d.]+/g)!.map(Number)
  return [r! / 255, g! / 255, b! / 255]
}
