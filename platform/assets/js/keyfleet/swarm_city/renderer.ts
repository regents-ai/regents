/**
 * Draws the swarm city with WebGPU through vgpu: a square plate of thin
 * outlined buildings in three downtowns and the low city between them, its
 * streets, the grid over the downtowns, and one disc for each agent, its swarm
 * and their tails behind them, in the page's theme. Loaded only
 * once the city is really going to be shown.
 *
 * Each frame is drawn straight to the page, multisampled so the thin lines
 * stay smooth: the sky and ground first, then the streets, then the sides and
 * roofs, so each building hides what stands behind it, then every line, then
 * the agents over the top.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, frame, geometry, init, surface, uniforms, type Draw, type Gpu} from "vgpu"
import {orbitRig, perspective, rigPose, viewMatrices, type CameraMatrices, type Pose} from "vgpu/scene"

import type {IslandRenderer} from "../canvas_island"
import {CROWNS, DISTRICTS, PLACE_ORDER, TOWERS, type Place} from "./city"
import {BEACON_FLOATS, BEACONS, SKY_FLOATS, SKY_LINES, STREET_FLOATS, STREET_LINES, TOWER_FLOATS, TOWER_RECORDS} from "./meshes"
import {CITY_LOOK, type Theme} from "./looks"
import {FOV, cityShaders, type CityShaders} from "./shaders"
import {FOLLOWERS, MAX_AGENTS, TRAIL, followerAt, parkSwarm, stepSwarm, syncSwarm, type Agent, type Node} from "./swarm"

export type CityView = {
  yaw: number
  pitch: number
  distance: number
  x: number
  y: number
  z: number
  /** How lit each district is, from 0 to 1, as the pointer finds it or its page shows it. */
  castle: number
  forge: number
  inn: number
}

/** An agent's node under the pointer, and the point just above it, both across the canvas from 0 to 1. */
export type NodeMark = {
  readonly id: string
  readonly u: number
  readonly v: number
}

/** A district under the pointer, and the point over its crown, both across the canvas from 0 to 1. */
export type DistrictMark = {
  readonly place: Place
  readonly u: number
  readonly v: number
}

export type SwarmCityRenderer = IslandRenderer & {
  /** Paints the city for the other theme, once it is ready on the GPU. */
  setTheme(theme: Theme): Promise<void>
  setAgents(agents: readonly Agent[]): void
  /** A visitor who asked for less motion gets one composed, unmoving city. */
  setCalm(calm: boolean): void
  /** The agent drawn nearest a point on the canvas (0 to 1 across, 0 to 1 down), if one is there. */
  nodeAt(u: number, v: number): NodeMark | null
  /** The district whose towers or ground are drawn under a point on the canvas, if one is there. */
  districtAt(u: number, v: number): DistrictMark | null
}

/** How far the city turns by itself, in radians a second. */
const SPIN = 0.03
/** The moment a calm city is shown at, and how long its agents fly first, so their trails are drawn. */
const STILL_TIME = 6.5
const STILL_FLIGHT = 2.4
/** Longest step the swarm takes, so a tab coming back does not jump it. */
const MAX_STEP = 1 / 20
/** How far from a node's middle a press still picks it, as a share of the canvas's height. */
const NODE_REACH = 0.045
/** Sizes of the discs, in world units. */
const LEAD_SIZE = 0.24
const FOLLOWER_SIZE = 0.075
/** Pieces in each of the swarm's tails, and how many trail points apart their ends are. */
const TAIL_PIECES = 3
const TAIL_STEP = 2
/** Floats per disc and per tail piece. */
const NODE_FLOATS = 8
const TRAIL_FLOATS = 8
const NODE_DISCS = MAX_AGENTS * (1 + FOLLOWERS)
const TRAIL_PIECES = MAX_AGENTS * (TRAIL + FOLLOWERS * TAIL_PIECES)
/** The sky and ground cover every pixel, so the colour the picture is cleared to never shows. */
const CLEAR: [number, number, number, number] = [0, 0, 0, 1]
/** Every draw of the city in one theme. */
type Painting = {
  readonly backdrop: Draw
  readonly streets: Draw
  readonly faces: Draw
  readonly edges: Draw
  readonly sky: Draw
  readonly beacons: Draw
  readonly trails: Draw
  readonly nodes: Draw
}

export async function createSwarmCityRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  view: CityView,
  theme: Theme,
): Promise<SwarmCityRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a city still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })
  try {
    return await build(gpu, canvas, size, view, theme, () => disposed, () => void (disposed = true))
  } catch (error) {
    disposed = true
    gpu.dispose()
    throw error
  }
}

async function build(
  gpu: Gpu,
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  view: CityView,
  theme: Theme,
  isDisposed: () => boolean,
  markDisposed: () => void,
): Promise<SwarmCityRenderer> {
  const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", depth: true, msaa: true, label: "swarm-city"})
  stage.resize([size[0], size[1]])

  const camera: {pose: Pose; projection: Float32Array; matrices: CameraMatrices} = {
    pose: {position: new Float32Array(3), quaternion: new Float32Array(4)},
    projection: new Float32Array(16),
    matrices: {view: new Float32Array(16), viewProjection: new Float32Array(16)},
  }
  const cityValues = {
    viewProjection: camera.matrices.viewProjection,
    eye: [0, 0, 0],
    time: STILL_TIME,
    right: [1, 0, 0],
    pixel: 1,
    up: [0, 1, 0],
    lit: [0, 0, 0, 0],
    resolution: [size[0], size[1]],
    reach: view.distance,
  }
  const cityUniforms = uniforms(gpu, cityValues)
  const set = {city: cityUniforms}

  // Every building is one record; its sides and roof, and its outline, are both drawn from it.
  const buildings = (topology: GPUPrimitiveTopology, label: string) =>
    geometry(gpu, {
      buffers: [
        {
          data: TOWER_RECORDS,
          stride: TOWER_FLOATS * 4,
          stepMode: "instance",
          attributes: {
            footprint: {format: "float32x4", offset: 0, location: 0},
            span: {format: "float32x2", offset: 16, location: 1},
            quarter: {format: "float32", offset: 24, location: 2},
            shade: {format: "float32", offset: 28, location: 3},
          },
        },
      ],
      instanceCount: TOWERS.length,
      topology,
      label,
    })
  const towerFaces = buildings("triangle-list", "swarm-city.tower-faces")
  const towerEdges = buildings("line-list", "swarm-city.tower-edges")
  const streetLines = geometry(gpu, {
    buffers: [
      {
        data: STREET_LINES,
        stride: STREET_FLOATS * 4,
        attributes: {
          position: {format: "float32x3", offset: 0, location: 0},
          kind: {format: "float32", offset: 12, location: 1},
        },
      },
    ],
    vertexCount: STREET_LINES.length / STREET_FLOATS,
    topology: "line-list",
    label: "swarm-city.streets",
  })
  const skyLines = geometry(gpu, {
    buffers: [
      {
        data: SKY_LINES,
        stride: SKY_FLOATS * 4,
        attributes: {
          position: {format: "float32x3", offset: 0, location: 0},
          down: {format: "float32", offset: 12, location: 1},
          kind: {format: "float32", offset: 16, location: 2},
        },
      },
    ],
    vertexCount: SKY_LINES.length / SKY_FLOATS,
    topology: "line-list",
    label: "swarm-city.sky",
  })
  const beaconPoints = geometry(gpu, {
    buffers: [
      {
        data: BEACONS,
        stride: BEACON_FLOATS * 4,
        stepMode: "instance",
        attributes: {
          position: {format: "float32x3", offset: 0, location: 0},
          phase: {format: "float32", offset: 12, location: 1},
        },
      },
    ],
    instanceCount: BEACONS.length / BEACON_FLOATS,
    label: "swarm-city.beacons",
  })
  const nodeData = new Float32Array(NODE_DISCS * NODE_FLOATS)
  const nodeGeometry = geometry(gpu, {
    buffers: [
      {
        data: nodeData,
        stride: NODE_FLOATS * 4,
        stepMode: "instance",
        attributes: {
          position: {format: "float32x3", offset: 0, location: 0},
          size: {format: "float32", offset: 12, location: 1},
          colour: {format: "float32x3", offset: 16, location: 2},
          glow: {format: "float32", offset: 28, location: 3},
        },
      },
    ],
    instanceCount: NODE_DISCS,
    label: "swarm-city.nodes",
  })
  const trailData = new Float32Array(TRAIL_PIECES * TRAIL_FLOATS)
  const trailGeometry = geometry(gpu, {
    buffers: [
      {
        data: trailData,
        stride: TRAIL_FLOATS * 4,
        stepMode: "instance",
        attributes: {
          from_: {format: "float32x3", offset: 0, location: 0},
          to: {format: "float32x3", offset: 12, location: 1},
          glows: {format: "float32x2", offset: 24, location: 2},
        },
      },
    ],
    instanceCount: TRAIL_PIECES,
    label: "swarm-city.trails",
  })

  /** Every draw of the city in one theme, ready on the GPU. */
  const paint = async (theme: Theme): Promise<Painting> => {
    const shaders = cityShaders(CITY_LOOK[theme])
    const part = (name: keyof CityShaders) => ({
      shader: prepareShader(shaders[name], `swarm_city_${theme}_${name}.wgsl`),
      set,
      label: `swarm-city.${theme}.${name}`,
    })
    // The agents lie over the city, hidden by what stands in front of them, with soft edges.
    const flying = {blend: "alpha", depth: {write: false}} as const
    const painting: Painting = {
      backdrop: draw(gpu, {...part("backdrop"), vertices: 3, depth: false}),
      streets: draw(gpu, {...part("streets"), geometry: streetLines}),
      faces: draw(gpu, {...part("faces"), geometry: towerFaces, vertices: 30}),
      edges: draw(gpu, {...part("edges"), geometry: towerEdges, vertices: 24}),
      sky: draw(gpu, {...part("sky"), geometry: skyLines}),
      beacons: draw(gpu, {...part("beacons"), geometry: beaconPoints, vertices: 6}),
      trails: draw(gpu, {...part("trails"), geometry: trailGeometry, vertices: 6, ...flying}),
      nodes: draw(gpu, {...part("nodes"), geometry: nodeGeometry, vertices: 6, ...flying}),
    }
    await Promise.all(Object.values(painting).map(each => each.compile(stage)))
    return painting
  }
  // Each theme is made the first time it is asked for, and kept.
  const paintings = new Map<Theme, Promise<Painting>>()
  const paintingOf = (theme: Theme) => {
    const made = paintings.get(theme) ?? paint(theme)
    paintings.set(theme, made)
    return made
  }
  let wanted = theme
  let painting = await paintingOf(theme)

  let nodes: Node[] = []
  let time = STILL_TIME
  let spin = 0
  let calm = false
  let lastStep: number | undefined
  let nodeCount = 0
  let trailCount = 0
  const colours = new Map<string, [number, number, number]>()
  const tailEnd = new Float32Array(3)

  const aim = () => {
    const [width, height] = stage.size
    const aspect = width / height
    // A narrow canvas stands back further, so the whole city still fits across it.
    const fit = Math.max(1, 1.4 / aspect) ** 0.85
    cityValues.reach = view.distance * fit
    const rig = orbitRig({
      target: [view.x, view.y, view.z],
      yaw: view.yaw + spin,
      pitch: view.pitch,
      distance: cityValues.reach,
    })
    rigPose(rig, camera.pose)
    perspective({fov: FOV, near: 0.3, far: 140}, aspect, camera.projection)
    viewMatrices(camera.pose, camera.projection, camera.matrices)
    const m = camera.matrices.view
    cityValues.eye = [camera.pose.position[0]!, camera.pose.position[1]!, camera.pose.position[2]!]
    cityValues.right = [m[0]!, m[4]!, m[8]!]
    cityValues.up = [m[1]!, m[5]!, m[9]!]
  }

  /** A point in the world, across the canvas from 0 to 1, and whether it is in front of the camera. */
  const onCanvas = (x: number, y: number, z: number): [number, number, boolean] => {
    const m = camera.matrices.viewProjection
    const clipX = m[0]! * x + m[4]! * y + m[8]! * z + m[12]!
    const clipY = m[1]! * x + m[5]! * y + m[9]! * z + m[13]!
    const clipW = m[3]! * x + m[7]! * y + m[11]! * z + m[15]!
    return [(clipX / clipW + 1) / 2, (1 - clipY / clipW) / 2, clipW > 0]
  }

  /** The ray from the eye through a point on the canvas. */
  const rayThrough = (u: number, v: number) => {
    const inverse = invert(camera.matrices.viewProjection)
    const unproject = (depth: number) => {
      const x = u * 2 - 1
      const y = 1 - v * 2
      const w = inverse[3]! * x + inverse[7]! * y + inverse[11]! * depth + inverse[15]!
      return [0, 1, 2].map(row => (inverse[row]! * x + inverse[row + 4]! * y + inverse[row + 8]! * depth + inverse[row + 12]!) / w)
    }
    const near = unproject(0)
    const far = unproject(1)
    const direction = [far[0]! - near[0]!, far[1]! - near[1]!, far[2]! - near[2]!]
    return {origin: near, direction}
  }

  const writeAgents = () => {
    let disc = 0
    let piece = 0
    const tail = (fromX: number, fromY: number, fromZ: number, toX: number, toY: number, toZ: number, glowFrom: number, glowTo: number) => {
      trailData.set([fromX, fromY, fromZ, toX, toY, toZ, glowFrom, glowTo], piece * TRAIL_FLOATS)
      piece += 1
    }
    for (const node of nodes) {
      nodeData.set([node.x, node.y, node.z, LEAD_SIZE, ...colours.get(node.id)!, 1], disc * NODE_FLOATS)
      disc += 1
      for (let index = 0; index < FOLLOWERS; index++) {
        const at = disc * NODE_FLOATS
        followerAt(node, index, time, nodeData, at)
        const glow = 0.95 - index * 0.04
        nodeData.set([FOLLOWER_SIZE, 0, 0, 0, glow], at + 3)
        disc += 1
        // Its tail: back through where it was a moment ago, fading to nothing.
        let [toX, toY, toZ] = [nodeData[at]!, nodeData[at + 1]!, nodeData[at + 2]!]
        for (let step = 1; step <= TAIL_PIECES; step++) {
          followerAt(node, index, time, tailEnd, 0, step * TAIL_STEP)
          tail(tailEnd[0]!, tailEnd[1]!, tailEnd[2]!, toX, toY, toZ, glow * (1 - step / TAIL_PIECES), glow * (1 - (step - 1) / TAIL_PIECES))
          ;[toX, toY, toZ] = [tailEnd[0]!, tailEnd[1]!, tailEnd[2]!]
        }
      }
      // The agent's own tail: from the disc back through each point it kept, fading toward the end.
      let [toX, toY, toZ] = [node.x, node.y, node.z]
      for (let index = 0; index < node.trailLength; index++) {
        const at = index * 3
        const [fromX, fromY, fromZ] = [node.trail[at]!, node.trail[at + 1]!, node.trail[at + 2]!]
        tail(fromX, fromY, fromZ, toX, toY, toZ, 1 - (index + 1) / TRAIL, 1 - index / TRAIL)
        ;[toX, toY, toZ] = [fromX, fromY, fromZ]
      }
    }
    nodeCount = disc
    trailCount = piece
    if (disc > 0) nodeGeometry.write(nodeData.subarray(0, disc * NODE_FLOATS))
    if (piece > 0) trailGeometry.write(trailData.subarray(0, piece * TRAIL_FLOATS))
  }

  /** Lets a calm city's agents fly a moment, so it is shown mid-flight with its trails behind it. */
  const compose = () => {
    time = STILL_TIME
    spin = 0
    parkSwarm(nodes)
    for (let flown = 0; flown < STILL_FLIGHT; flown += 1 / 30) stepSwarm(nodes, 1 / 30)
  }

  const renderer: SwarmCityRenderer = {
    async setTheme(theme) {
      wanted = theme
      const next = await paintingOf(theme)
      // A theme asked for later, while this one was being made, wins.
      if (wanted === theme) painting = next
    },
    setAgents(agents) {
      nodes = syncSwarm(nodes, agents)
      colours.clear()
      for (const node of nodes) colours.set(node.id, displayColor(node.color))
      if (calm) compose()
    },
    setCalm(next) {
      calm = next
      if (calm) compose()
      else lastStep = undefined
    },
    nodeAt(u, v) {
      const [width, height] = stage.size
      const aspect = width / height
      let nearest: Node | undefined
      let nearestMiss = NODE_REACH
      for (const node of nodes) {
        const [nodeU, nodeV, ahead] = onCanvas(node.x, node.y, node.z)
        if (!ahead) continue
        const miss = Math.hypot((u - nodeU) * aspect, v - nodeV)
        if (miss < nearestMiss) {
          nearest = node
          nearestMiss = miss
        }
      }
      if (!nearest) return null
      const [markU, markV] = onCanvas(nearest.x, nearest.y + 0.45, nearest.z)
      return {id: nearest.id, u: markU, v: markV}
    },
    districtAt(u, v) {
      const {origin, direction} = rayThrough(u, v)
      // The nearest tower the ray meets decides; the low blocks between districts hide what is behind them.
      let nearest = Infinity
      let hit: Place | null = null
      for (const tower of TOWERS) {
        const distance = rayBox(origin, direction, tower)
        if (distance < nearest) {
          nearest = distance
          hit = tower.quarter === "between" ? null : tower.quarter
        }
      }
      if (nearest === Infinity && direction[1]! < 0) {
        const along = -origin[1]! / direction[1]!
        const x = origin[0]! + direction[0]! * along
        const z = origin[2]! + direction[2]! * along
        hit = PLACE_ORDER.find(place => Math.hypot(x - DISTRICTS[place].x, z - DISTRICTS[place].z) < DISTRICTS[place].radius) ?? null
      }
      if (!hit) return null
      const [x, y, z] = CROWNS[hit]
      const [markU, markV] = onCanvas(x, y + 0.5, z)
      return {place: hit, u: markU, v: markV}
    },
    resize(width, height) {
      stage.resize([width, height])
      cityValues.resolution = [width, height]
      // Marks keep the same size on the page at any resolution.
      cityValues.pixel = Math.max(1, height / 620)
    },
    step() {
      if (calm) return false
      const now = performance.now() / 1000
      const dt = lastStep === undefined ? 0 : Math.min(MAX_STEP, now - lastStep)
      lastStep = now
      time += dt
      spin += dt * SPIN
      stepSwarm(nodes, dt)
      return true
    },
    present() {
      aim()
      writeAgents()
      cityValues.time = time
      cityValues.lit = [view.castle, view.forge, view.inn, 0]
      cityUniforms.set(cityValues)
      frame(gpu, current => {
        current.pass({target: stage, clear: CLEAR}, pass => {
          pass.draw(painting.backdrop)
          pass.draw(painting.streets)
          pass.draw(painting.faces, {vertices: 30, instances: TOWERS.length})
          pass.draw(painting.edges, {vertices: 24, instances: TOWERS.length})
          pass.draw(painting.sky)
          pass.draw(painting.beacons, {vertices: 6})
          if (trailCount > 0) pass.draw(painting.trails, {vertices: 6, instances: trailCount})
          if (nodeCount > 0) pass.draw(painting.nodes, {vertices: 6, instances: nodeCount})
        })
      })
    },
    settled() {
      return gpu.settled()
    },
    dispose() {
      if (isDisposed()) return
      markDisposed()
      stage.dispose()
      gpu.dispose()
    },
  }

  cityValues.pixel = Math.max(1, size[1] / 620)
  return renderer
}

/** How far along a ray it first meets a tower's box, or Infinity if it misses. */
function rayBox(origin: readonly number[], direction: readonly number[], tower: (typeof TOWERS)[number]): number {
  const low = [tower.x - tower.width / 2, tower.base, tower.z - tower.depth / 2]
  const high = [tower.x + tower.width / 2, tower.top, tower.z + tower.depth / 2]
  let enter = 0
  let leave = Infinity
  for (let axis = 0; axis < 3; axis++) {
    const d = direction[axis]!
    const o = origin[axis]!
    if (Math.abs(d) < 1e-9) {
      if (o < low[axis]! || o > high[axis]!) return Infinity
      continue
    }
    const a = (low[axis]! - o) / d
    const b = (high[axis]! - o) / d
    enter = Math.max(enter, Math.min(a, b))
    leave = Math.min(leave, Math.max(a, b))
    if (enter > leave) return Infinity
  }
  return enter
}

/** The inverse of a 4×4 matrix stored column by column. */
function invert(m: Float32Array): Float64Array {
  const out = new Float64Array(16)
  const [a00, a01, a02, a03, a10, a11, a12, a13, a20, a21, a22, a23, a30, a31, a32, a33] = Array.from(m)
  const b00 = a00! * a11! - a01! * a10!
  const b01 = a00! * a12! - a02! * a10!
  const b02 = a00! * a13! - a03! * a10!
  const b03 = a01! * a12! - a02! * a11!
  const b04 = a01! * a13! - a03! * a11!
  const b05 = a02! * a13! - a03! * a12!
  const b06 = a20! * a31! - a21! * a30!
  const b07 = a20! * a32! - a22! * a30!
  const b08 = a20! * a33! - a23! * a30!
  const b09 = a21! * a32! - a22! * a31!
  const b10 = a21! * a33! - a23! * a31!
  const b11 = a22! * a33! - a23! * a32!
  const det = 1 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06)
  out[0] = (a11! * b11 - a12! * b10 + a13! * b09) * det
  out[1] = (a02! * b10 - a01! * b11 - a03! * b09) * det
  out[2] = (a31! * b05 - a32! * b04 + a33! * b03) * det
  out[3] = (a22! * b04 - a21! * b05 - a23! * b03) * det
  out[4] = (a12! * b08 - a10! * b11 - a13! * b07) * det
  out[5] = (a00! * b11 - a02! * b08 + a03! * b07) * det
  out[6] = (a32! * b02 - a30! * b05 - a33! * b01) * det
  out[7] = (a20! * b05 - a22! * b02 + a23! * b01) * det
  out[8] = (a10! * b10 - a11! * b08 + a13! * b06) * det
  out[9] = (a01! * b08 - a00! * b10 - a03! * b06) * det
  out[10] = (a30! * b04 - a31! * b02 + a33! * b00) * det
  out[11] = (a21! * b02 - a20! * b04 - a23! * b00) * det
  out[12] = (a11! * b07 - a10! * b09 - a12! * b06) * det
  out[13] = (a00! * b09 - a01! * b07 + a02! * b06) * det
  out[14] = (a31! * b01 - a30! * b03 - a32! * b00) * det
  out[15] = (a20! * b03 - a21! * b01 + a22! * b00) * det
  return out
}

/** #rrggbb as the page shows it. */
function displayColor(hex: string): [number, number, number] {
  const value = Number.parseInt(hex.slice(1), 16)
  return [((value >> 16) & 255) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255]
}
