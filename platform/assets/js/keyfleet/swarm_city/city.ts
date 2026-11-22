/**
 * The swarm city's ground plan: a square plate of streets and lots, three
 * downtowns rising out of it (the castle tallest, then the forge, then the
 * inn), a plaza in the middle, and avenues running out from the plaza.
 *
 * The plate is cut into blocks by streets, each block into lots, and nearly
 * every lot holds a building: thin towers downtown, low blocks between. Some
 * rise in setbacks and some carry a box on the roof, so it reads like a real
 * city. Pure numbers, no GPU: the meshes, the swarm and the picking all read
 * it. Everything comes from a fixed seed, so every visitor sees the same city.
 */

export type Place = "inn" | "forge" | "castle"

/** A downtown's middle and reach on the ground, in world units, and how tall its towers rise. */
export type District = {
  readonly x: number
  readonly z: number
  readonly radius: number
  readonly peak: number
}

export const DISTRICTS: Readonly<Record<Place, District>> = {
  castle: {x: -5.0, z: -3.0, radius: 3.7, peak: 10.5},
  forge: {x: 5.0, z: -3.4, radius: 3.4, peak: 6.4},
  inn: {x: 0.2, z: 5.4, radius: 3.3, peak: 5.6},
}

export const PLACE_ORDER: readonly Place[] = ["castle", "forge", "inn"]

/** Who a building belongs to: one of the downtowns, or the low city between them. */
export type Quarter = Place | "between"

/** Every building is a box: its footprint, and where it stands and where its roof is. */
export type Tower = {
  readonly quarter: Quarter
  readonly x: number
  readonly z: number
  readonly width: number
  readonly depth: number
  readonly base: number
  readonly top: number
}

/** A stretch of street, drawn as a blue line on the plate. */
export type Street = readonly [number, number, number, number]

/** The plate runs this far from the middle to each edge. */
export const CITY_REACH = 11
/** The grid the swarm reads roofs from, in world units. */
export const CELL = 0.5
/** How far the red grid reaches each way over the city, and its spacing. */
export const SKY_REACH = 6.6
export const SKY_SPACING = 0.6
/** The plaza's reach, and the half-width of an avenue. */
export const PLAZA = 1.5
export const AVENUE = 0.3

/** Where each downtown's landmark tower tops out, for the district's card. */
export const CROWNS: Readonly<Record<Place, readonly [number, number, number]>> = {
  castle: [DISTRICTS.castle.x, 14.2, DISTRICTS.castle.z],
  forge: [DISTRICTS.forge.x + 0.3, 8.1, DISTRICTS.forge.z - 0.2],
  inn: [DISTRICTS.inn.x, 7.0, DISTRICTS.inn.z],
}

/** A small, fixed random sequence (mulberry32), so the city is the same on every load. */
function seeded(seed: number): () => number {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** How far a point is from the segment a–b, on the ground. */
function fromSegment(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number {
  const dx = bx - ax
  const dz = bz - az
  const t = Math.min(1, Math.max(0, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz)))
  return Math.hypot(px - ax - dx * t, pz - az - dz * t)
}

/**
 * The avenues, each from the plaza outward: one into each downtown, and one
 * between each pair of downtowns out to the plate's edge.
 */
export const AVENUES: readonly Street[] = [
  ...PLACE_ORDER.map((place): Street => [0, 0, DISTRICTS[place].x, DISTRICTS[place].z]),
  [0, 0, -CITY_REACH, 8.6],
  [0, 0, CITY_REACH, 9.4],
  [0, 0, 0.6, -CITY_REACH],
]

/** How far a point is from the nearest avenue. */
export function fromAvenue(x: number, z: number): number {
  return Math.min(...AVENUES.map(([ax, az, bx, bz]) => fromSegment(x, z, ax, az, bx, bz)))
}

/**
 * How far a ground point is into a downtown, from 1 at its middle to 0 at its
 * edge and below 0 beyond it. The edge wanders, so no downtown is a circle.
 */
function into(place: Place, x: number, z: number): number {
  const district = DISTRICTS[place]
  const angle = Math.atan2(z - district.z, x - district.x)
  const ragged = 1 + 0.16 * Math.sin(angle * 3 + district.x) + 0.08 * Math.sin(angle * 7 + district.z)
  return 1 - Math.hypot(x - district.x, z - district.z) / (district.radius * ragged)
}

/** The downtown a ground point lies in, if any. */
function districtUnder(x: number, z: number): Place | null {
  return PLACE_ORDER.find(place => into(place, x, z) > 0) ?? null
}

type Rect = {readonly x0: number; readonly z0: number; readonly x1: number; readonly z1: number}

/** Cuts a rectangle in two across its longer side, leaving `gap` between the halves. */
function cut(rect: Rect, at: number, gap: number): [Rect, Rect, Street] {
  const {x0, z0, x1, z1} = rect
  if (x1 - x0 >= z1 - z0) {
    const x = x0 + (x1 - x0) * at
    return [{x0, z0, x1: x - gap / 2, z1}, {x0: x + gap / 2, z0, x1, z1}, [x, z0, x, z1]]
  }
  const z = z0 + (z1 - z0) * at
  return [{x0, z0, x1, z1: z - gap / 2}, {x0, z0: z + gap / 2, x1, z1}, [x0, z, x1, z]]
}

const longest = (rect: Rect) => Math.max(rect.x1 - rect.x0, rect.z1 - rect.z0)

/** Each landmark is a stack of boxes at its downtown's middle: the castle's needle, the forge's stacks, the inn's tower. */
function landmarks(): Tower[] {
  const {castle, forge, inn} = DISTRICTS
  const box = (quarter: Place, x: number, z: number, width: number, depth: number, base: number, top: number): Tower => ({
    quarter,
    x,
    z,
    width,
    depth,
    base,
    top,
  })
  return [
    box("castle", castle.x, castle.z, 0.82, 0.82, 0, 6.4),
    box("castle", castle.x, castle.z, 0.6, 0.6, 6.4, 10.2),
    box("castle", castle.x, castle.z, 0.36, 0.36, 10.2, 12.6),
    box("castle", castle.x, castle.z, 0.1, 0.1, 12.6, 14.2),
    box("forge", forge.x, forge.z, 1.0, 0.6, 0, 3.1),
    box("forge", forge.x + 0.3, forge.z - 0.2, 0.22, 0.22, 3.1, 8.1),
    box("forge", forge.x - 0.1, forge.z + 0.1, 0.2, 0.2, 3.1, 7.2),
    box("forge", forge.x - 0.35, forge.z - 0.1, 0.18, 0.18, 3.1, 6.3),
    box("inn", inn.x, inn.z, 0.7, 0.7, 0, 4.2),
    box("inn", inn.x, inn.z, 0.5, 0.5, 4.2, 6.2),
    box("inn", inn.x, inn.z, 0.22, 0.22, 6.2, 7.0),
  ]
}

/** The tallest a building on a lot may be: towers downtown, falling away from each middle to the low city. */
function heightAt(x: number, z: number, random: () => number): {quarter: Quarter; top: number} {
  const place = districtUnder(x, z)
  if (place) {
    const district = DISTRICTS[place]
    const fall = into(place, x, z)
    const spike = random() < 0.07 ? 1.25 : 1
    return {quarter: place, top: (0.3 + (district.peak - 0.3) * fall ** 1.7 * (0.3 + 0.7 * random())) * spike}
  }
  // The low city: mostly two or three floors, a few mid-rises, and taller near the downtowns.
  const near = Math.max(...PLACE_ORDER.map(each => 1 + (into(each, x, z) * DISTRICTS[each].radius) / 3))
  const lift = Math.min(1, Math.max(0, near))
  const midRise = random() < 0.025 + 0.1 * lift
  return {quarter: "between", top: midRise ? 0.5 + random() * (0.7 + 1.5 * lift) : 0.06 + random() * (0.18 + 0.3 * lift)}
}

/** The city: its blocks cut by streets, each block cut into lots, and a building on nearly every lot. */
function build(): {towers: Tower[]; streets: Street[]; corners: [number, number][]} {
  const random = seeded(1026)
  const towers = landmarks()
  const streets: Street[] = []
  const corners: [number, number][] = []

  // Blocks: the plate cut again and again; the first cuts are the main streets, and wider.
  const blocks: Rect[] = []
  const split = (rect: Rect, depth: number) => {
    if (longest(rect) < 1.3 + random() * 1.5) {
      blocks.push(rect)
      return
    }
    const [a, b, street] = cut(rect, 0.32 + random() * 0.36, depth < 3 ? 0.34 : depth < 5 ? 0.22 : 0.1)
    if (depth < 5) streets.push(street)
    split(a, depth + 1)
    split(b, depth + 1)
  }
  split({x0: -CITY_REACH, z0: -CITY_REACH, x1: CITY_REACH, z1: CITY_REACH}, 0)

  for (const block of blocks) {
    corners.push([block.x0, block.z0], [block.x1, block.z0], [block.x1, block.z1], [block.x0, block.z1])
    const middle = [(block.x0 + block.x1) / 2, (block.z0 + block.z1) / 2] as const
    // Downtown lots are small, so the towers stand thin and close.
    const downtown = districtUnder(middle[0], middle[1]) !== null
    const lots: Rect[] = []
    const subdivide = (rect: Rect) => {
      const smallest = downtown ? 0.2 + random() * 0.22 : 0.26 + random() * 0.4
      if (longest(rect) < smallest) {
        lots.push(rect)
        return
      }
      const [a, b] = cut(rect, 0.3 + random() * 0.4, 0.035)
      subdivide(a)
      subdivide(b)
    }
    subdivide(block)

    for (const lot of lots) {
      const x = (lot.x0 + lot.x1) / 2
      const z = (lot.z0 + lot.z1) / 2
      if (Math.max(Math.abs(x), Math.abs(z)) < PLAZA || fromAvenue(x, z) < AVENUE) continue
      if (PLACE_ORDER.some(place => Math.hypot(x - DISTRICTS[place].x, z - DISTRICTS[place].z) < 0.75)) continue
      if (random() < 0.05) continue
      // Each building stands back from its lot's edges by its own amount.
      const inset = () => 0.008 + random() * 0.05
      const [x0, x1] = [lot.x0 + inset(), lot.x1 - inset()]
      const [z0, z1] = [lot.z0 + inset(), lot.z1 - inset()]
      if (x1 - x0 < 0.05 || z1 - z0 < 0.05) continue
      const {quarter, top} = heightAt(x, z, random)
      const tower = (shrink: number, base: number, roof: number) =>
        towers.push({quarter, x: (x0 + x1) / 2, z: (z0 + z1) / 2, width: (x1 - x0) * shrink, depth: (z1 - z0) * shrink, base, top: roof})
      if (top > 1.6 && random() < 0.45) {
        // A setback: the tower narrows part way up.
        const step = top * (0.5 + random() * 0.3)
        tower(1, 0, step)
        tower(0.55 + random() * 0.25, step, top)
      } else {
        tower(1, 0, top)
      }
      if (top < 1.2 && random() < 0.3) {
        // A box on the roof: a stair head or a plant room, off to one side.
        const width = (x1 - x0) * (0.25 + random() * 0.25)
        const depth = (z1 - z0) * (0.25 + random() * 0.25)
        towers.push({
          quarter,
          x: x0 + width / 2 + random() * (x1 - x0 - width),
          z: z0 + depth / 2 + random() * (z1 - z0 - depth),
          width,
          depth,
          base: top,
          top: top + 0.04 + random() * 0.1,
        })
      }
    }
  }
  return {towers, streets, corners}
}

const CITY = build()

export const TOWERS: readonly Tower[] = CITY.towers
/** The red grid's height: a clear floor above the tallest roof, so nothing rises through it. */
export const SKY_GRID = Math.max(...TOWERS.map(tower => tower.top)) + 1
/** The main streets, from the first cuts of the plate. */
export const STREETS: readonly Street[] = CITY.streets
/** Where blocks meet the streets round them. */
export const BLOCK_CORNERS: readonly (readonly [number, number])[] = CITY.corners

const cellKey = (column: number, row: number) => `${column},${row}`

/** The highest roof standing in each cell, for the swarm to fly over. */
const ROOFS: ReadonlyMap<string, number> = (() => {
  const roofs = new Map<string, number>()
  for (const tower of TOWERS) {
    const halfX = tower.width / 2
    const halfZ = tower.depth / 2
    for (let column = Math.floor((tower.x - halfX) / CELL); column <= Math.floor((tower.x + halfX) / CELL); column++) {
      for (let row = Math.floor((tower.z - halfZ) / CELL); row <= Math.floor((tower.z + halfZ) / CELL); row++) {
        const key = cellKey(column, row)
        roofs.set(key, Math.max(roofs.get(key) ?? 0, tower.top))
      }
    }
  }
  return roofs
})()

/** The highest roof in the cell under a point, or 0 over a street, the plaza or open ground. */
export function roofAt(x: number, z: number): number {
  return ROOFS.get(cellKey(Math.floor(x / CELL), Math.floor(z / CELL))) ?? 0
}
