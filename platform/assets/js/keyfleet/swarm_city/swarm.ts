/**
 * Where the agents fly. Each agent is a disc with a small swarm on its
 * tail: it circles the district of its last action, rising and dipping between
 * the towers, and when it does something somewhere else it climbs over the
 * roofs and crosses the city to the new district.
 *
 * Pure numbers, no GPU: the renderer asks for a step and reads the nodes back.
 */
import {DISTRICTS, roofAt, type Place} from "./city"

/** One agent as the page hands it over: who, where its last action was, and its colour. */
export type Agent = {
  readonly id: string
  readonly place: Place
  readonly color: string
}

/** Agents the city will ever draw, the swarm each one leads, and the points its trail keeps. */
export const MAX_AGENTS = 24
export const FOLLOWERS = 9
export const TRAIL = 84
/** Seconds between two points of a trail. */
const TRAIL_STEP = 1 / 30

export type Node = {
  readonly id: string
  place: Place
  color: string
  /** Where it is and where it is heading, in world units and world units a second. */
  x: number
  y: number
  z: number
  vx: number
  vy: number
  vz: number
  /** Which ring round its district it keeps to, and how high that ring flies. */
  lane: number
  /** A turn of its own, so no two agents rise and dip together. */
  phase: number
  /** Its last positions, newest first: x, y, z for each point. */
  readonly trail: Float32Array
  trailLength: number
  trailClock: number
}

const CRUISE = 2.3
const CIRCLE = 1.55
const STEER = 2.6
/** How far ahead on its ring a node aims, in radians. */
const LEAD = 0.5
/** Height kept above the roof under a node and the one ahead of it. */
const CLEARANCE = 0.75
/** The height a node crosses the city at. */
const COMMUTE = 9.2
const PERSONAL_SPACE = 0.7

/** How far from its district's middle a node circles, and how high. */
const ringOf = (node: Node) => {
  const district = DISTRICTS[node.place]
  return {
    radius: district.radius * (0.62 + 0.24 * (node.lane % 3) / 2),
    height: 2.2 + (node.lane % 4) * (district.peak - 2.2) / 4,
  }
}

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value))

/** Agents at one district take turns between the rings, in page order. */
const assignLanes = (nodes: readonly Node[]) => {
  const seen: Record<Place, number> = {inn: 0, forge: 0, castle: 0}
  for (const node of nodes) node.lane = seen[node.place]++
}

/** The point a node aims for on its ring: a little way ahead, rising and dipping as it goes. */
const aimOf = (node: Node, angle: number) => {
  const district = DISTRICTS[node.place]
  const ring = ringOf(node)
  const around = angle + LEAD
  const x = district.x + Math.cos(around) * ring.radius
  const z = district.z + Math.sin(around) * ring.radius
  const swell = Math.sin(around * 2 + node.phase) * 1.3
  return {x, z, y: Math.max(ring.height + swell, roofAt(x, z) + CLEARANCE)}
}

/** Puts every node on its ring, spread evenly round its district, flying along it, with no trail yet. */
export const parkSwarm = (nodes: readonly Node[]) => {
  const counts: Record<Place, number> = {inn: 0, forge: 0, castle: 0}
  for (const node of nodes) counts[node.place] += 1
  const placed: Record<Place, number> = {inn: 0, forge: 0, castle: 0}
  for (const node of nodes) {
    const angle = 0.7 + (placed[node.place]++ / counts[node.place]) * Math.PI * 2
    const aim = aimOf(node, angle - LEAD)
    node.x = aim.x
    node.y = aim.y
    node.z = aim.z
    node.vx = -Math.sin(angle) * CIRCLE
    node.vy = 0
    node.vz = Math.cos(angle) * CIRCLE
    node.trailLength = 0
    node.trailClock = 0
  }
}

/**
 * Brings the swarm in line with the agents: a new agent gets a node already
 * circling its district, a node whose agent is gone leaves, and a node whose
 * agent acted somewhere new sets off for that district.
 */
export const syncSwarm = (nodes: Node[], agents: readonly Agent[]): Node[] => {
  const byId = new Map(nodes.map(node => [node.id, node]))
  const arriving: Node[] = []
  const next = agents.slice(0, MAX_AGENTS).map((agent, index) => {
    const node = byId.get(agent.id)
    if (node) {
      node.place = agent.place
      node.color = agent.color
      return node
    }
    const fresh: Node = {
      id: agent.id,
      place: agent.place,
      color: agent.color,
      x: 0,
      y: 0,
      z: 0,
      vx: 0,
      vy: 0,
      vz: 0,
      lane: 0,
      phase: index * 2.39,
      trail: new Float32Array(TRAIL * 3),
      trailLength: 0,
      trailClock: 0,
    }
    arriving.push(fresh)
    return fresh
  })
  assignLanes(next)
  parkSwarm(arriving)
  return next
}

/** Moves every node on by `dt` seconds and lays down its trail. */
export const stepSwarm = (nodes: readonly Node[], dt: number) => {
  for (const node of nodes) {
    const district = DISTRICTS[node.place]
    const away = Math.hypot(node.x - district.x, node.z - district.z)
    const ring = ringOf(node)
    const travelling = away > ring.radius + 2.2

    let aimX: number
    let aimY: number
    let aimZ: number
    if (travelling) {
      // Crossing the city: head for the district high over the roofs, coming down as it nears.
      aimX = district.x
      aimZ = district.z
      aimY = Math.max(ring.height, COMMUTE * clamp((away - ring.radius) / 5, 0, 1))
    } else {
      const aim = aimOf(node, Math.atan2(node.z - district.z, node.x - district.x))
      aimX = aim.x
      aimY = aim.y
      aimZ = aim.z
    }

    const speed = travelling ? CRUISE : CIRCLE
    let wantX = aimX - node.x
    let wantY = aimY - node.y
    let wantZ = aimZ - node.z
    const reach = Math.hypot(wantX, wantY, wantZ) || 1
    wantX = (wantX / reach) * speed
    wantY = (wantY / reach) * speed
    wantZ = (wantZ / reach) * speed

    for (const other of nodes) {
      if (other === node) continue
      const ax = node.x - other.x
      const ay = node.y - other.y
      const az = node.z - other.z
      const apart = Math.hypot(ax, ay, az)
      if (apart >= PERSONAL_SPACE || apart === 0) continue
      const push = (PERSONAL_SPACE - apart) * 3
      wantX += (ax / apart) * push
      wantY += (ay / apart) * push
      wantZ += (az / apart) * push
    }

    // Never into a roof: climb when the roof under the node, or the one ahead, is close.
    const aheadX = node.x + node.vx * 0.6
    const aheadZ = node.z + node.vz * 0.6
    const floor = Math.max(roofAt(node.x, node.z), roofAt(aheadX, aheadZ)) + CLEARANCE
    if (node.y < floor + 0.4) wantY = Math.max(wantY, (floor + 0.4 - node.y) * 4)

    const turn = Math.min(1, dt * STEER)
    node.vx += (wantX - node.vx) * turn
    node.vy += (wantY - node.vy) * turn
    node.vz += (wantZ - node.vz) * turn
    node.x += node.vx * dt
    node.y = Math.max(node.y + node.vy * dt, floor - 0.35)
    node.z += node.vz * dt

    node.trailClock += dt
    while (node.trailClock >= TRAIL_STEP) {
      node.trailClock -= TRAIL_STEP
      node.trail.copyWithin(3, 0, (TRAIL - 1) * 3)
      node.trail[0] = node.x
      node.trail[1] = node.y
      node.trail[2] = node.z
      node.trailLength = Math.min(TRAIL, node.trailLength + 1)
    }
  }
}

/**
 * Where one of a node's swarm is: strung out along the trail behind it, each
 * one circling the trail at its own pace, so the swarm twists as it flies.
 * `back` asks where it was that many trail points ago, for drawing its tail.
 */
export const followerAt = (node: Node, index: number, time: number, out: Float32Array, at: number, back = 0) => {
  const behind = Math.min(node.trailLength - 1, 2 + index * 4 + back)
  const from = Math.max(0, behind) * 3
  const baseX = node.trailLength > 0 ? node.trail[from]! : node.x
  const baseY = node.trailLength > 0 ? node.trail[from + 1]! : node.y
  const baseZ = node.trailLength > 0 ? node.trail[from + 2]! : node.z
  const spin = (time - back * TRAIL_STEP) * (2.2 + index * 0.37) + index * 1.7 + node.phase
  const radius = 0.16 + 0.05 * index
  out[at] = baseX + Math.cos(spin) * radius
  out[at + 1] = baseY + Math.sin(spin * 1.3) * radius * 0.8
  out[at + 2] = baseZ + Math.sin(spin) * radius
}
