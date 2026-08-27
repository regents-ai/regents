// Outer/front glass interface for one of the 13 disconnected crown cells.
// Adapted from Vercel's MIT-licensed prism-background/glass.wgsl.

import {
  Glass,
  dielectricFresnel,
  glassEnvironment,
  projectToUv,
  sampleScene,
} from "./crown-glass-common.wgsl";

const NO_EXIT: f32 = 100000.0;
const SURFACE_EPSILON: f32 = 0.0002;

@group(0) @binding(0) var<uniform> params: Glass;
@group(0) @binding(1) var sceneTexture: texture_2d<f32>;
@group(0) @binding(2) var sceneSampler: sampler;

struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) worldPosition: vec3f,
  @location(1) worldNormal: vec3f,
  @location(2) @interpolate(flat) cellCenter: vec2f,
};

@vertex
fn vs_main(
  @location(0) position: vec3f,
  @location(1) normal: vec3f,
  @location(2) cell_center: vec2f,
) -> VertexOut {
  var out: VertexOut;
  out.position = params.viewProjection * vec4f(position, 1.0);
  out.worldPosition = position;
  out.worldNormal = normal;
  out.cellCenter = cell_center;
  return out;
}

fn axisExitDistance(origin: f32, direction: f32, low: f32, high: f32) -> f32 {
  if (direction > 0.00001) {
    let distance = (high - origin) / direction;
    return select(NO_EXIT, distance, distance > SURFACE_EPSILON);
  }
  if (direction < -0.00001) {
    let distance = (low - origin) / direction;
    return select(NO_EXIT, distance, distance > SURFACE_EPSILON);
  }
  return NO_EXIT;
}

/** Nearest exit from the current cell's ideal axis-aligned optical cube. */
fn cellExitDistance(origin: vec3f, direction: vec3f, center: vec2f) -> f32 {
  let low = center - params.cellHalfSize;
  let high = center + params.cellHalfSize;
  return min(
    axisExitDistance(origin.x, direction.x, low.x, high.x),
    min(
      axisExitDistance(origin.y, direction.y, low.y, high.y),
      axisExitDistance(origin.z, direction.z, params.backZ, params.frontZ),
    ),
  );
}

fn sampleInterior(uv: vec2f, halfTexel: vec2f) -> vec3f {
  return sampleScene(sceneTexture, sceneSampler, uv, halfTexel);
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4f {
  let normal = normalize(in.worldNormal);
  let view = normalize(params.cameraPosition - in.worldPosition);
  let incident = -view;
  let facing = clamp(dot(view, normal), 0.0, 1.0);
  let reflectedEnvironment = glassEnvironment(reflect(incident, normal), params);
  let fresnel = dielectricFresnel(params.ior, facing);
  let refracted = normalize(refract(incident, normal, 1.0 / params.ior));
  let exitDistance = cellExitDistance(
    in.worldPosition + refracted * SURFACE_EPSILON,
    refracted,
    in.cellCenter,
  );

  let originalUv = in.position.xy / max(params.resolution, vec2f(1.0));
  let validExit = exitDistance < 10.0;
  let sampleDistance = select(0.0, exitDistance, validExit);
  let samplePoint = in.worldPosition + refracted * sampleDistance;
  let refractedUv = select(
    originalUv,
    projectToUv(samplePoint, params.viewProjection),
    validExit,
  );
  let safeResolution = max(params.resolution, vec2f(1.0));
  let halfTexel = 0.5 / safeResolution;

  let frostOffset = max(params.frostRadius, 0.0) / safeResolution;
  let frosted = (
    sampleInterior(refractedUv + vec2f(frostOffset.x, 0.0), halfTexel)
    + sampleInterior(refractedUv - vec2f(frostOffset.x, 0.0), halfTexel)
    + sampleInterior(refractedUv + vec2f(0.0, frostOffset.y), halfTexel)
    + sampleInterior(refractedUv - vec2f(0.0, frostOffset.y), halfTexel)
  ) * 0.25;

  let refractionDeltaPixels = (refractedUv - originalUv) * safeResolution;
  let refractionDeltaLength = length(refractionDeltaPixels);
  let refractionAxis = select(
    vec2f(1.0, 0.0),
    refractionDeltaPixels / max(refractionDeltaLength, 0.0001),
    refractionDeltaLength > 0.0001,
  );
  let dispersionOffset = refractionAxis
    * (max(params.dispersion, 0.0) * 72.0)
    / safeResolution;
  let towardRefraction = sampleInterior(refractedUv + dispersionOffset, halfTexel);
  let awayFromRefraction = sampleInterior(refractedUv - dispersionOffset, halfTexel);
  let dispersionMix = clamp(params.dispersion * 48.0, 0.0, 1.0);
  let sceneColor = vec3f(
    mix(frosted.r, towardRefraction.r, dispersionMix),
    frosted.g,
    mix(frosted.b, awayFromRefraction.b, dispersionMix),
  );

  let transmittance = exp(-params.absorption * sampleDistance);
  let transmitted = sceneColor * transmittance;
  let reflected = reflectedEnvironment * params.reflectionStrength;

  let iridescencePhase =
    (1.0 - facing) * params.iridescenceFrequency * 6.28318530718;
  let spectralResponse = 0.5 + 0.5 * cos(vec3f(
    iridescencePhase,
    iridescencePhase + 2.09439510239,
    iridescencePhase + 4.18879020479,
  ));
  let grazingWeight = pow(1.0 - facing, 1.5);
  let filmAmount = clamp(params.iridescenceStrength, 0.0, 1.0)
    * (0.25 + 0.75 * grazingWeight);
  let filmReflectance = filmAmount * mix(vec3f(0.15), spectralResponse, 0.85);
  let fresnelRgb = clamp(
    vec3f(fresnel) + (1.0 - fresnel) * filmReflectance,
    vec3f(0.0),
    vec3f(1.0),
  );

  let environmentLuminance = dot(
    reflectedEnvironment,
    vec3f(0.2126, 0.7152, 0.0722),
  );
  let studioPanelMask = smoothstep(0.5, 0.82, environmentLuminance);
  let physicalGlass = transmitted * (1.0 - fresnelRgb) + reflected * fresnelRgb;
  let studioPanelStrength = studioPanelMask
    * clamp(params.reflectionStrength * 0.4, 0.0, 0.7)
    * (0.65 + 0.35 * grazingWeight);
  let studioPanelHighlight = max(
    reflected * studioPanelStrength,
    vec3f(0.0),
  );
  let finalGlass = max(physicalGlass, vec3f(0.0)) + studioPanelHighlight;
  return vec4f(finalGlass, 1.0);
}
