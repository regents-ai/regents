/**
 * The swarm city's fixed shapes: one record per building, drawn as a dark box
 * and its outline; the streets on the plate; the red sky grid and the lines it
 * drops; and the beacons along the edges and streets. None of them move, so
 * each is built once into a buffer.
 */
import {
  AVENUE,
  AVENUES,
  BLOCK_CORNERS,
  CITY_REACH,
  PLAZA,
  SKY_GRID,
  SKY_REACH,
  SKY_SPACING,
  STREETS,
  TOWERS,
  type Quarter,
} from "./city"

/** A building: its middle and footprint on the ground, its base and roof, whose it is, and a shade of its own. */
export const TOWER_FLOATS = 8

/** A street line vertex: where it is, and what it is (0 a street, 1 an avenue's edge, 2 the plate's rim). */
export const STREET_FLOATS = 4

/** A sky line vertex: where it is, how far down the line it is from 0 to 1, and what it is (0 the grid, 1 a drop). */
export const SKY_FLOATS = 5

/** A beacon: where it stands, and a phase so no two twinkle together. */
export const BEACON_FLOATS = 4

/** Whose building it is, as the shaders number it. */
export const QUARTER_INDEX: Readonly<Record<Quarter, number>> = {castle: 0, forge: 1, inn: 2, between: 3}

/** A small, fixed hash, so each building keeps its shade on every load. */
const shadeOf = (index: number) => {
  const value = Math.sin(index * 12.9898) * 43758.5453
  return value - Math.floor(value)
}

function towerRecords(): Float32Array<ArrayBuffer> {
  const data = new Float32Array(TOWERS.length * TOWER_FLOATS)
  TOWERS.forEach((tower, index) => {
    data.set(
      [tower.x, tower.z, tower.width, tower.depth, tower.base, tower.top, QUARTER_INDEX[tower.quarter], shadeOf(index)],
      index * TOWER_FLOATS,
    )
  })
  return data
}

/** Where a line from the plaza's middle toward (x, z) leaves the plaza's square, as a share of the way. */
const leavingPlaza = (x: number, z: number) => PLAZA / Math.max(Math.abs(x), Math.abs(z))

function streetLines(): Float32Array<ArrayBuffer> {
  const data: number[] = []
  const line = (ax: number, az: number, bx: number, bz: number, kind: number) => data.push(ax, 0.004, az, kind, bx, 0.004, bz, kind)
  for (const [ax, az, bx, bz] of STREETS) line(ax, az, bx, bz, 0)
  // Each avenue is a pair of lines either side of it, from the plaza's edge out.
  for (const [, , bx, bz] of AVENUES) {
    const length = Math.hypot(bx, bz)
    const [dx, dz] = [bx / length, bz / length]
    const from = leavingPlaza(bx, bz) * length
    const to = Math.max(Math.abs(bx), Math.abs(bz)) >= CITY_REACH ? length : length - 0.8
    for (const side of [-AVENUE, AVENUE]) line(dx * from - dz * side, dz * from + dx * side, dx * to - dz * side, dz * to + dx * side, 1)
  }
  const square = (reach: number, kind: number) => {
    line(-reach, -reach, reach, -reach, kind)
    line(reach, -reach, reach, reach, kind)
    line(reach, reach, -reach, reach, kind)
    line(-reach, reach, -reach, -reach, kind)
  }
  square(PLAZA, 1)
  square(PLAZA * 0.55, 1)
  square(CITY_REACH + 0.06, 2)
  return new Float32Array(data)
}

/**
 * The red grid hanging over the downtowns, a curtain of lines from its rim to
 * the plate, and a line from it onto each of the tallest roofs beneath it.
 */
function skyLines(): Float32Array<ArrayBuffer> {
  const data: number[] = []
  const line = (ax: number, ay: number, az: number, bx: number, by: number, bz: number, kind: number) =>
    data.push(ax, ay, az, 0, kind, bx, by, bz, 1, kind)
  const steps = Math.round((SKY_REACH * 2) / SKY_SPACING)
  for (let index = 0; index <= steps; index++) {
    const at = -SKY_REACH + index * SKY_SPACING
    line(at, SKY_GRID, -SKY_REACH, at, SKY_GRID, SKY_REACH, 0)
    line(-SKY_REACH, SKY_GRID, at, SKY_REACH, SKY_GRID, at, 0)
  }
  for (let index = 0; index <= steps; index += 2) {
    const at = -SKY_REACH + index * SKY_SPACING
    for (const [x, z] of [[at, -SKY_REACH], [at, SKY_REACH], [-SKY_REACH, at], [SKY_REACH, at]] as const) line(x, SKY_GRID, z, x, 0, z, 1)
  }
  const roofs = new Set<string>()
  const tallest = TOWERS.filter(tower => Math.max(Math.abs(tower.x), Math.abs(tower.z)) < SKY_REACH)
    .sort((a, b) => b.top - a.top)
  for (const tower of tallest) {
    const key = `${Math.round(tower.x * 2)},${Math.round(tower.z * 2)}`
    if (roofs.has(key)) continue
    roofs.add(key)
    line(tower.x, SKY_GRID, tower.z, tower.x, tower.top, tower.z, 1)
    if (roofs.size >= 64) break
  }
  return new Float32Array(data)
}

/** Beacons round the plate's rim, at street corners, and along the avenues. */
function beaconPoints(): Float32Array<ArrayBuffer> {
  const data: number[] = []
  let phase = 0
  const beacon = (x: number, z: number) => data.push(x, 0.03, z, (phase += 1.618) % (Math.PI * 2))
  const rim = CITY_REACH + 0.06
  for (let along = -rim; along < rim; along += 0.55) {
    beacon(along, -rim)
    beacon(rim, along)
    beacon(-along, rim)
    beacon(-rim, -along)
  }
  BLOCK_CORNERS.forEach(([x, z], index) => {
    if (index % 5 === 0 && Math.max(Math.abs(x), Math.abs(z)) < CITY_REACH - 0.3) beacon(x, z)
  })
  for (const [, , bx, bz] of AVENUES) {
    const length = Math.hypot(bx, bz)
    const [dx, dz] = [bx / length, bz / length]
    for (let along = leavingPlaza(bx, bz) * length + 0.3; along < length - 0.9; along += 0.9) {
      for (const side of [-AVENUE, AVENUE]) beacon(dx * along - dz * side, dz * along + dx * side)
    }
  }
  return new Float32Array(data)
}

export const TOWER_RECORDS = towerRecords()
export const STREET_LINES = streetLines()
export const SKY_LINES = skyLines()
export const BEACONS = beaconPoints()
