/**
 * Deterministic scene graph, forked from the Vercel vgpu prism background. See
 * THIRD_PARTY_NOTICES.md.
 *
 * The CPU traces wavelength-connected sheets across the finite beam and writes them
 * into one fixed vertex buffer. Every frame resolves wall, inner glass and outer
 * glass through two full-resolution ping-pong HDR targets, then builds a four-level
 * reduced-resolution bloom pyramid before the sole tone-mapped presentation pass.
 * There is no temporal history or convergence state, so one frame is the final
 * picture for a given camera and lamp.
 */

import {draw, effect, frame, sampler, target} from "vgpu"
import type {Buffer, Draw, Effect, Geometry, Gpu, Surface, Target} from "vgpu"

import {cameraView, rotationMatrix, wallHalfHeight, type CameraView} from "./camera"
import {
  buildLightMesh,
  LIGHT_VERTEX_COUNT,
  LIGHT_VERTEX_STRIDE,
  LIGHT_WHITE_QUADS,
} from "./light-mesh"
import {prismGeometry} from "./prism-mesh"
import bloomUpsampleWgsl from "./shaders/bloom-upsample"
import bloomWgsl from "./shaders/bloom"
import copyLinearWgsl from "./shaders/copy-linear"
import glassBackWgsl from "./shaders/glass-back"
import glassWgsl from "./shaders/glass"
import lightWgsl from "./shaders/light"
import presentWgsl from "./shaders/present"
import wallWgsl from "./shaders/wall"
import {
  lampForIncidence,
  PRISM_BACK_Z,
  PRISM_BEAM_SLICES,
  PRISM_DEFAULT_ARC,
  PRISM_EDGE_FALLOFF,
  PRISM_FRONT_Z,
  PRISM_GLASS,
  PRISM_INCIDENCE_ARC,
  PRISM_LIGHT_PLANE_Z,
  PRISM_POSTPROCESS,
  PRISM_RAINBOW_FALLOFF,
  PRISM_TRIANGLE,
  type Vec2,
} from "./types"

const ENVIRONMENT_ROTATION = rotationMatrix(PRISM_GLASS.environmentRotation)
const BLOOM_LEVELS = 4
type BloomTargets = readonly [Target, Target, Target, Target]

export interface PrismScene {
  readonly gpu: Gpu
  outputSize: readonly [number, number]
  sceneTargets?: readonly [Target, Target]
  bloomTargets?: BloomTargets
  readonly light: Draw
  readonly lightBuffer: Buffer
  readonly wall: Draw
  readonly copyToBack: Effect
  readonly copyToFront: Effect
  readonly bloomDownsample: readonly [Effect, Effect, Effect, Effect]
  readonly bloomUpsample: readonly [Effect, Effect, Effect]
  readonly present: Effect
  readonly glassBack: Draw
  readonly glassFront: Draw
  readonly prism: Geometry
  readonly sceneSampler: ReturnType<typeof sampler>
  lampArc: number
  lampTarget: number
  orbit: Vec2
  aspect: number
  wallHalfExtent: Vec2
  view: CameraView
  readonly label: string
}

/** Angle of incidence, in degrees, for a normalized position along the lamp's arc. */
const incidenceAt = (position: number): number =>
  PRISM_INCIDENCE_ARC.min +
  (PRISM_INCIDENCE_ARC.max - PRISM_INCIDENCE_ARC.min) * Math.min(1, Math.max(0, position))

const wallExtent = (aspect: number): Vec2 => {
  const halfHeight = wallHalfHeight(aspect)
  return [halfHeight * aspect, halfHeight]
}

const lightMesh = (scene: PrismScene): Float32Array<ArrayBuffer> =>
  buildLightMesh({
    light: lampForIncidence(incidenceAt(scene.lampArc), scene.lampTarget),
    wallHalfExtent: scene.wallHalfExtent,
  })

export function createScene(gpu: Gpu, output: readonly [number, number], label: string): PrismScene {
  const aspect = output[0] / Math.max(1, output[1])
  // `prepareScene` fills this before the first frame, from the size it is given.
  const lightBuffer = gpu.device.createBuffer({
    size: LIGHT_VERTEX_COUNT * LIGHT_VERTEX_STRIDE,
    usage: ["vertex", "copy_dst"],
    label: `${label}.light-vertices`,
  })
  const bloomEffect = (name: string) => effect(gpu, bloomWgsl, {label: `${label}.bloom-${name}`})
  const bloomUpsampleEffect = (name: string) =>
    effect(gpu, bloomUpsampleWgsl, {label: `${label}.bloom-upsample-${name}`, blend: "additive"})
  const prism = prismGeometry(gpu, `${label}.prism`)

  return {
    gpu,
    outputSize: output,
    light: draw(gpu, {
      shader: lightWgsl,
      geometry: {
        vertexBuffers: [lightBuffer.gpu],
        vertexBufferLayouts: [
          {
            arrayStride: LIGHT_VERTEX_STRIDE,
            attributes: [
              {shaderLocation: 0, offset: 0, format: "float32x2" as const},
              {shaderLocation: 1, offset: 8, format: "float32" as const},
              {shaderLocation: 2, offset: 12, format: "float32" as const},
              {shaderLocation: 3, offset: 16, format: "float32" as const},
              {shaderLocation: 4, offset: 20, format: "float32" as const},
            ],
          },
        ],
        vertexCount: LIGHT_VERTEX_COUNT,
      },
      blend: "additive",
      cull: "none",
      depth: false,
      label: `${label}.light`,
    }),
    lightBuffer,
    wall: draw(gpu, {
      shader: wallWgsl,
      vertices: 6,
      cull: "back",
      depth: false,
      label: `${label}.wall`,
    }),
    copyToBack: effect(gpu, copyLinearWgsl, {label: `${label}.copy-to-back`}),
    copyToFront: effect(gpu, copyLinearWgsl, {label: `${label}.copy-to-front`}),
    bloomDownsample: [
      bloomEffect("half"),
      bloomEffect("quarter"),
      bloomEffect("eighth"),
      bloomEffect("sixteenth"),
    ],
    bloomUpsample: [
      bloomUpsampleEffect("eighth"),
      bloomUpsampleEffect("quarter"),
      bloomUpsampleEffect("half"),
    ],
    present: effect(gpu, presentWgsl, {label: `${label}.present`}),
    glassBack: draw(gpu, {
      shader: glassBackWgsl,
      geometry: prism,
      cull: "front",
      depth: false,
      label: `${label}.glass-back`,
    }),
    glassFront: draw(gpu, {
      shader: glassWgsl,
      geometry: prism,
      cull: "back",
      depth: false,
      label: `${label}.glass-front`,
    }),
    prism,
    sceneSampler: sampler(gpu, {
      minFilter: "linear",
      magFilter: "linear",
      addressModeU: "clamp-to-edge",
      addressModeV: "clamp-to-edge",
    }),
    lampArc: PRISM_DEFAULT_ARC,
    lampTarget: 0.5,
    orbit: [0, 0],
    aspect,
    wallHalfExtent: wallExtent(aspect),
    view: cameraView(aspect),
    label,
  }
}

/** Swings the source along its arc and moves its point of impact on the entry face. */
export function setLampAim(scene: PrismScene, arcPosition: number, targetPosition: number): void {
  scene.lampArc = Math.min(1, Math.max(0, arcPosition))
  scene.lampTarget = Math.min(1, Math.max(0, targetPosition))
  scene.lightBuffer.write(lightMesh(scene))
}

/**
 * Tilts the camera. The light mesh already lives on a world-space plane inside the
 * prism, so only its projection changes.
 */
export function setOrbit(scene: PrismScene, x: number, y: number): void {
  scene.orbit = [Math.min(1, Math.max(-1, x)), Math.min(1, Math.max(-1, y))]
  scene.view = cameraView(scene.aspect, scene.orbit[0], scene.orbit[1])
}

export function resizeScene(scene: PrismScene, output: readonly [number, number]): void {
  scene.outputSize = output
  scene.aspect = output[0] / Math.max(1, output[1])
  scene.wallHalfExtent = wallExtent(scene.aspect)
  scene.sceneTargets?.[0].resize(output)
  scene.sceneTargets?.[1].resize(output)
  scene.bloomTargets?.forEach((bloomTarget, level) => bloomTarget.resize(bloomLevelSize(output, level)))
  scene.view = cameraView(scene.aspect, scene.orbit[0], scene.orbit[1])
  scene.lightBuffer.write(lightMesh(scene))
}

/** Kept as one shared block so wall, ribbons and glass cannot drift apart. */
function sceneUniforms(scene: PrismScene): Record<string, unknown> {
  return {
    viewProjection: scene.view.camera.viewProjection,
    wallHalfExtent: scene.wallHalfExtent,
    wallColor: [0, 0, 0],
    causticOnly: 0,
    lightPlaneZ: PRISM_LIGHT_PLANE_Z,
    lightWhiteQuads: LIGHT_WHITE_QUADS,
    lightBeamSlices: PRISM_BEAM_SLICES,
    lightEdgeFalloff: PRISM_EDGE_FALLOFF,
    rainbowFalloff: PRISM_RAINBOW_FALLOFF,
  }
}

function glassUniforms(scene: PrismScene): Record<string, unknown> {
  return {
    viewProjection: scene.view.camera.viewProjection,
    environmentRotation: ENVIRONMENT_ROTATION,
    cameraPosition: scene.view.position,
    absorption: PRISM_GLASS.absorption,
    prismA: PRISM_TRIANGLE.a,
    prismB: PRISM_TRIANGLE.b,
    prismC: PRISM_TRIANGLE.c,
    resolution: scene.outputSize,
    frontZ: PRISM_FRONT_Z,
    backZ: PRISM_BACK_Z,
    wallZ: 0,
    ior: PRISM_GLASS.ior,
    reflectionStrength: PRISM_GLASS.reflectionStrength,
    frostRadius: PRISM_GLASS.frostRadius,
    dispersion: PRISM_GLASS.dispersion,
    iridescenceStrength: PRISM_GLASS.iridescenceStrength,
    iridescenceFrequency: PRISM_GLASS.iridescenceFrequency,
    environmentExposure: PRISM_GLASS.environmentExposure,
  }
}

export async function prepareScene(scene: PrismScene, output: Surface): Promise<void> {
  resizeScene(scene, output.size)
  const hdrTarget = (name: string, size: readonly [number, number]): Target =>
    target(scene.gpu, {size, format: "rgba16float", label: `${scene.label}.${name}`})
  scene.sceneTargets ??= [hdrTarget("scene-a", output.size), hdrTarget("scene-b", output.size)]
  scene.bloomTargets ??= (Array.from({length: BLOOM_LEVELS}, (_, level) =>
    hdrTarget(`bloom-${level}`, bloomLevelSize(output.size, level)),
  ) as unknown as BloomTargets)
  bind(scene)
  await Promise.all([
    scene.light.compile(scene.sceneTargets[0]),
    scene.wall.compile(scene.sceneTargets[0]),
    scene.copyToBack.compile(scene.sceneTargets[1]),
    scene.glassBack.compile(scene.sceneTargets[1]),
    scene.copyToFront.compile(scene.sceneTargets[0]),
    scene.glassFront.compile(scene.sceneTargets[0]),
    ...scene.bloomDownsample.map((bloom, level) => bloom.compile(scene.bloomTargets![level]!)),
    ...scene.bloomUpsample.map((bloom, index) => bloom.compile(scene.bloomTargets![2 - index]!)),
    scene.present.compile({colors: [output.format]}),
  ])
}

export function presentScene(scene: PrismScene, output: Surface): void {
  const [readTarget, writeTarget] = scene.sceneTargets!
  const bloomTargets = scene.bloomTargets!
  bind(scene)
  frame(scene.gpu, current => {
    current.pass({target: readTarget, clear: [0, 0, 0, 1]}, pass => pass.draw(scene.wall))
    current.pass({target: writeTarget, clear: [0, 0, 0, 1]}, pass => {
      pass.draw(scene.copyToBack)
      pass.draw(scene.glassBack)
      pass.draw(scene.light)
    })
    current.pass({target: readTarget, clear: [0, 0, 0, 1]}, pass => {
      pass.draw(scene.copyToFront)
      pass.draw(scene.glassFront)
    })
    bloomTargets.forEach((bloomTarget, level) => {
      current.pass({target: bloomTarget, clear: [0, 0, 0, 1]}, pass =>
        pass.draw(scene.bloomDownsample[level]!),
      )
    })
    scene.bloomUpsample.forEach((bloom, index) => {
      current.pass({target: bloomTargets[2 - index]!, clear: false}, pass => pass.draw(bloom))
    })
    current.pass({target: output}, pass => pass.draw(scene.present))
  })
}

function bind(scene: PrismScene): void {
  const [readTarget, writeTarget] = scene.sceneTargets!
  const bloomTargets = scene.bloomTargets!
  const values = sceneUniforms(scene)
  scene.light.set({scene: values})
  scene.wall.set({scene: values})
  scene.copyToBack.set({sceneTexture: readTarget})
  scene.glassBack.set({
    params: glassUniforms(scene),
    sceneTexture: readTarget,
    sceneSampler: scene.sceneSampler,
  })
  scene.copyToFront.set({sceneTexture: writeTarget})
  scene.glassFront.set({
    params: glassUniforms(scene),
    sceneTexture: writeTarget,
    sceneSampler: scene.sceneSampler,
  })
  scene.bloomDownsample.forEach((bloom, level) => {
    const source = level === 0 ? readTarget : bloomTargets[level - 1]!
    bloom.set({
      sourceTexture: source,
      sourceSampler: scene.sceneSampler,
      params: {
        sourceTexelSize: [1 / source.size[0], 1 / source.size[1]],
        threshold: PRISM_POSTPROCESS.bloomThreshold,
        extractHighlights: level === 0 ? 1 : 0,
      },
    })
  })
  scene.bloomUpsample.forEach((bloom, index) => {
    const source = bloomTargets[3 - index]!
    bloom.set({
      sourceTexture: source,
      sourceSampler: scene.sceneSampler,
      params: {
        sourceTexelSize: [1 / source.size[0], 1 / source.size[1]],
        radius: PRISM_POSTPROCESS.bloomRadius,
        scatter: 0.65,
      },
    })
  })
  scene.present.set({
    sceneTexture: readTarget,
    bloomTexture: bloomTargets[0],
    bloomSampler: scene.sceneSampler,
    params: {bloomStrength: PRISM_POSTPROCESS.bloomStrength},
  })
}

function bloomLevelSize(
  size: readonly [number, number],
  level: number,
): readonly [number, number] {
  const divisor = 2 ** (level + 1)
  return [Math.max(1, Math.ceil(size[0] / divisor)), Math.max(1, Math.ceil(size[1] / divisor))]
}

const destroyTarget = (value: Target | undefined): void =>
  (value as (Target & {destroy?: () => void}) | undefined)?.destroy?.()

export function destroyScene(scene: PrismScene): void {
  scene.sceneTargets?.forEach(destroyTarget)
  scene.sceneTargets = undefined
  scene.bloomTargets?.forEach(destroyTarget)
  scene.bloomTargets = undefined
  scene.lightBuffer.destroy()
  scene.prism.destroy()
}
