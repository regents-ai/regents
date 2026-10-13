/**
 * The crown's passes, in the order they are drawn. Derived from the Vercel vgpu
 * prism background. See THIRD_PARTY_NOTICES.md.
 *
 * Every frame lays down the site's backdrop and the three beams, resolves the
 * crown's inner and outer glass through two full-size targets, then builds a
 * four-level bloom pyramid before the one pass that presents the picture. Nothing
 * is carried from one frame to the next, so one frame is the final picture for a
 * given camera and aim.
 */

import {prepareShader} from "@vgpu/wgsl/prepare"
import {draw, effect, frame, sampler, target, type Gpu, type Surface, type Target} from "vgpu"

import {cameraView, rotationMatrix} from "./camera"
import {crownLightGeometry, updateCrownLightGeometry, type CrownLighting} from "./light"
import {
  CROWN_LIGHT,
  crownShape,
  type CrownLook,
  type CrownStyle,
  type Vec2,
} from "./look"
import {crownGeometry} from "./mesh"
import {bloomWgsl} from "./shaders/bloom"
import {bloomUpsampleWgsl} from "./shaders/bloom_upsample"
import {copyLinearWgsl} from "./shaders/copy_linear"
import {glassBackWgsl} from "./shaders/glass_back"
import {glassFrontWgsl} from "./shaders/glass_front"
import {lightWgsl} from "./shaders/light"
import {presentWgsl} from "./shaders/present"

const BLOOM_LEVELS = 4
/** How much of each coarser bloom level is spread into the finer one above it. */
const BLOOM_SCATTER = 0.65

export interface CrownScene {
  /** Tilts the camera; both components in [-1, 1] with 0 at rest. */
  orbit(x: number, y: number): void
  /** Swings the three beams, which means retracing them on the processor. */
  aim(x: number, y: number): void
  /** Changes glass, bloom and beams. The beams are retraced once. */
  restyle(style: CrownStyle): void
  /** Follows the surface to its current size. */
  resize(): void
  present(): void
}

const clampSigned = (value: number): number => Math.min(1, Math.max(-1, value))

const bloomLevelSize = (size: Vec2, level: number): Vec2 => {
  const divisor = 2 ** (level + 1)
  return [Math.max(1, Math.ceil(size[0] / divisor)), Math.max(1, Math.ceil(size[1] / divisor))]
}

export async function createCrownScene(
  gpu: Gpu,
  output: Surface,
  look: CrownLook,
  label: string,
): Promise<CrownScene> {
  const {framing, backdrop} = look
  const shape = crownShape(framing.scale)

  let style: CrownStyle = look
  let environment = rotationMatrix(style.glass.environmentRotation)
  let size: Vec2 = output.size
  let aspect = size[0] / Math.max(1, size[1])
  let orbit: Vec2 = [0, 0]
  let aim: Vec2 = [0, 0]
  let view = cameraView(shape, framing, aspect)

  const lighting = (): CrownLighting => ({
    shape,
    beams: style.beams,
    colors: style.colors,
    ior: style.glass.ior,
    aim,
    aspect,
  })

  const hdrTarget = (name: string, targetSize: Vec2): Target =>
    target(gpu, {size: targetSize, format: "rgba16float", label: `${label}.${name}`})
  const sceneA = hdrTarget("scene-a", size)
  const sceneB = hdrTarget("scene-b", size)
  const blooms = Array.from({length: BLOOM_LEVELS}, (_, level) =>
    hdrTarget(`bloom-${level}`, bloomLevelSize(size, level)),
  )

  const crown = crownGeometry(gpu, shape, `${label}.crown`)
  const lightSheet = crownLightGeometry(gpu, lighting(), `${label}.light-sheet`)
  const linear = sampler(gpu, {
    minFilter: "linear",
    magFilter: "linear",
    addressModeU: "clamp-to-edge",
    addressModeV: "clamp-to-edge",
  })

  const copyShader = prepareShader(copyLinearWgsl, "crown_copy_linear.wgsl")
  const bloomShader = prepareShader(bloomWgsl, "crown_bloom.wgsl")
  const bloomUpsampleShader = prepareShader(bloomUpsampleWgsl, "crown_bloom_upsample.wgsl")

  const backdropPass = effect(gpu, prepareShader(backdrop.wgsl, "crown_backdrop.wgsl"), {
    label: `${label}.backdrop`,
  })
  const light = draw(gpu, {
    shader: prepareShader(lightWgsl, "crown_light.wgsl"),
    geometry: lightSheet,
    blend: "additive",
    cull: "none",
    depth: false,
    label: `${label}.light`,
  })
  const copyToBack = effect(gpu, copyShader, {label: `${label}.copy-to-back`})
  const glassBack = draw(gpu, {
    shader: prepareShader(glassBackWgsl, "crown_glass_back.wgsl"),
    geometry: crown,
    cull: "front",
    depth: false,
    label: `${label}.glass-back`,
  })
  const copyToFront = effect(gpu, copyShader, {label: `${label}.copy-to-front`})
  const glassFront = draw(gpu, {
    shader: prepareShader(glassFrontWgsl, "crown_glass_front.wgsl"),
    geometry: crown,
    cull: "back",
    depth: false,
    label: `${label}.glass-front`,
  })
  // Each level reads the one above it; the first reads the scene and keeps only
  // what is bright enough to glow.
  const bloomDown = blooms.map((_, level) =>
    effect(gpu, bloomShader, {label: `${label}.bloom-down-${level}`}),
  )
  // Then each coarser level is added back into the finer one, ending at the first.
  const bloomUp = blooms.slice(1).map((_, step) =>
    effect(gpu, bloomUpsampleShader, {label: `${label}.bloom-up-${step}`, blend: "additive"}),
  )
  const presentPass = effect(gpu, prepareShader(presentWgsl, "crown_present.wgsl"), {
    label: `${label}.present`,
  })

  const bloomUpTarget = (step: number): Target => blooms[BLOOM_LEVELS - 2 - step]!
  const bloomUpSource = (step: number): Target => blooms[BLOOM_LEVELS - 1 - step]!
  const texel = (source: Target): Vec2 => [1 / source.size[0], 1 / source.size[1]]

  /** Hands every pass its values for this frame, and returns what the scene clears to. */
  const bind = () => {
    const {glass, bloom} = style
    const {clear, set} = backdrop.frame(size)
    const glassParams = {
      viewProjection: view.viewProjection,
      environmentRotation: environment,
      cameraPosition: view.position,
      absorption: glass.absorption,
      cellHalfSize: [shape.halfSize, shape.halfSize],
      resolution: size,
      frontZ: shape.frontZ,
      backZ: shape.backZ,
      wallZ: 0,
      ior: glass.ior,
      reflectionStrength: glass.reflectionStrength,
      frostRadius: glass.frostRadius,
      dispersion: glass.dispersion,
      iridescenceStrength: glass.iridescenceStrength,
      iridescenceFrequency: glass.iridescenceFrequency,
      environmentExposure: glass.environmentExposure,
    }

    backdropPass.set(set)
    light.set({
      params: {
        viewProjection: view.viewProjection,
        lightPlaneZ: shape.lightPlaneZ,
        edgeFalloff: CROWN_LIGHT.edgeFalloff,
        rainbowFalloffRate: CROWN_LIGHT.rainbowFalloffRate,
        rainbowFalloffPower: CROWN_LIGHT.rainbowFalloffPower,
        opacity: CROWN_LIGHT.opacity,
      },
    })
    copyToBack.set({sceneTexture: sceneA})
    glassBack.set({params: glassParams, sceneTexture: sceneA, sceneSampler: linear})
    copyToFront.set({sceneTexture: sceneB})
    glassFront.set({params: glassParams, sceneTexture: sceneB, sceneSampler: linear})
    bloomDown.forEach((pass, level) => {
      const source = level === 0 ? sceneA : blooms[level - 1]!
      pass.set({
        sourceTexture: source,
        sourceSampler: linear,
        params: {
          sourceTexelSize: texel(source),
          threshold: bloom.threshold,
          extractHighlights: level === 0 ? 1 : 0,
        },
      })
    })
    bloomUp.forEach((pass, step) => {
      const source = bloomUpSource(step)
      pass.set({
        sourceTexture: source,
        sourceSampler: linear,
        params: {sourceTexelSize: texel(source), radius: bloom.radius, scatter: BLOOM_SCATTER},
      })
    })
    presentPass.set({
      sceneTexture: sceneA,
      bloomTexture: blooms[0]!,
      bloomSampler: linear,
      params: {bloomStrength: bloom.strength},
    })
    return clear
  }

  bind()
  await Promise.all([
    backdropPass.compile(sceneA),
    light.compile(sceneA),
    copyToBack.compile(sceneB),
    glassBack.compile(sceneB),
    copyToFront.compile(sceneA),
    glassFront.compile(sceneA),
    ...bloomDown.map((pass, level) => pass.compile(blooms[level]!)),
    ...bloomUp.map((pass, step) => pass.compile(bloomUpTarget(step))),
    presentPass.compile({colors: [output.format]}),
  ])

  return {
    orbit(x, y) {
      orbit = [clampSigned(x), clampSigned(y)]
      view = cameraView(shape, framing, aspect, orbit[0], orbit[1])
    },
    aim(x, y) {
      aim = [clampSigned(x), clampSigned(y)]
      updateCrownLightGeometry(lightSheet, lighting())
    },
    restyle(next) {
      style = next
      environment = rotationMatrix(next.glass.environmentRotation)
      updateCrownLightGeometry(lightSheet, lighting())
    },
    resize() {
      size = output.size
      aspect = size[0] / Math.max(1, size[1])
      sceneA.resize(size)
      sceneB.resize(size)
      blooms.forEach((bloom, level) => bloom.resize(bloomLevelSize(size, level)))
      view = cameraView(shape, framing, aspect, orbit[0], orbit[1])
      updateCrownLightGeometry(lightSheet, lighting())
    },
    present() {
      const clear = bind()
      frame(gpu, current => {
        current.pass({target: sceneA, clear}, pass => {
          pass.draw(backdropPass)
          pass.draw(light)
        })
        current.pass({target: sceneB, clear}, pass => {
          pass.draw(copyToBack)
          pass.draw(glassBack)
        })
        current.pass({target: sceneA, clear}, pass => {
          pass.draw(copyToFront)
          pass.draw(glassFront)
        })
        bloomDown.forEach((pass, level) => {
          current.pass({target: blooms[level]!, clear: [0, 0, 0, 1]}, bloomPass => bloomPass.draw(pass))
        })
        bloomUp.forEach((pass, step) => {
          current.pass({target: bloomUpTarget(step), clear: false}, bloomPass => bloomPass.draw(pass))
        })
        current.pass({target: output}, pass => pass.draw(presentPass))
      })
    },
  }
}
