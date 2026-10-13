/**
 * The outer, near faces of the glass cubes: refraction, reflection of the studio and the thin spectral film.
 *
 * Derived from the Vercel vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */
export const glassFrontWgsl = `
// vgsl-module: /regents/home-crown/crown-glass-front.wgsl
// Outer/front glass interface for one of the 13 disconnected crown cells.
// Adapted from Vercel's MIT-licensed prism-background/glass.wgsl.

 
  
  
  
  
  
  

const _vgsl_a5b5afc1__NO_EXIT: f32 = 100000.0;
const _vgsl_a5b5afc1__SURFACE_EPSILON: f32 = 0.0002;

@group(0) @binding(0) var<uniform> params: _vgsl_371be593__Glass;
@group(0) @binding(1) var sceneTexture: texture_2d<f32>;
@group(0) @binding(2) var sceneSampler: sampler;

struct _vgsl_a5b5afc1__VertexOut {
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
) -> _vgsl_a5b5afc1__VertexOut {
  var out: _vgsl_a5b5afc1__VertexOut;
  out.position = params.viewProjection * vec4f(position, 1.0);
  out.worldPosition = position;
  out.worldNormal = normal;
  out.cellCenter = cell_center;
  return out;
}

fn _vgsl_a5b5afc1__axisExitDistance(origin: f32, direction: f32, low: f32, high: f32) -> f32 {
  if (direction > 0.00001) {
    let distance = (high - origin) / direction;
    return select(_vgsl_a5b5afc1__NO_EXIT, distance, distance > _vgsl_a5b5afc1__SURFACE_EPSILON);
  }
  if (direction < -0.00001) {
    let distance = (low - origin) / direction;
    return select(_vgsl_a5b5afc1__NO_EXIT, distance, distance > _vgsl_a5b5afc1__SURFACE_EPSILON);
  }
  return _vgsl_a5b5afc1__NO_EXIT;
}

/** Nearest exit from the current cell's ideal axis-aligned optical cube. */
fn _vgsl_a5b5afc1__cellExitDistance(origin: vec3f, direction: vec3f, center: vec2f) -> f32 {
  let low = center - params.cellHalfSize;
  let high = center + params.cellHalfSize;
  return min(
    _vgsl_a5b5afc1__axisExitDistance(origin.x, direction.x, low.x, high.x),
    min(
      _vgsl_a5b5afc1__axisExitDistance(origin.y, direction.y, low.y, high.y),
      _vgsl_a5b5afc1__axisExitDistance(origin.z, direction.z, params.backZ, params.frontZ),
    ),
  );
}

fn _vgsl_a5b5afc1__sampleInterior(uv: vec2f, halfTexel: vec2f) -> vec3f {
  return _vgsl_371be593__sampleScene(sceneTexture, sceneSampler, uv, halfTexel);
}

@fragment
fn fs_main(in: _vgsl_a5b5afc1__VertexOut) -> @location(0) vec4f {
  let normal = normalize(in.worldNormal);
  let view = normalize(params.cameraPosition - in.worldPosition);
  let incident = -view;
  let facing = clamp(dot(view, normal), 0.0, 1.0);
  let reflectedEnvironment = _vgsl_371be593__glassEnvironment(reflect(incident, normal), params);
  let fresnel = _vgsl_371be593__dielectricFresnel(params.ior, facing);
  let refracted = normalize(refract(incident, normal, 1.0 / params.ior));
  let exitDistance = _vgsl_a5b5afc1__cellExitDistance(
    in.worldPosition + refracted * _vgsl_a5b5afc1__SURFACE_EPSILON,
    refracted,
    in.cellCenter,
  );

  let originalUv = in.position.xy / max(params.resolution, vec2f(1.0));
  let validExit = exitDistance < 10.0;
  let sampleDistance = select(0.0, exitDistance, validExit);
  let samplePoint = in.worldPosition + refracted * sampleDistance;
  let refractedUv = select(
    originalUv,
    _vgsl_371be593__projectToUv(samplePoint, params.viewProjection),
    validExit,
  );
  let safeResolution = max(params.resolution, vec2f(1.0));
  let halfTexel = 0.5 / safeResolution;

  let frostOffset = max(params.frostRadius, 0.0) / safeResolution;
  let frosted = (
    _vgsl_a5b5afc1__sampleInterior(refractedUv + vec2f(frostOffset.x, 0.0), halfTexel)
    + _vgsl_a5b5afc1__sampleInterior(refractedUv - vec2f(frostOffset.x, 0.0), halfTexel)
    + _vgsl_a5b5afc1__sampleInterior(refractedUv + vec2f(0.0, frostOffset.y), halfTexel)
    + _vgsl_a5b5afc1__sampleInterior(refractedUv - vec2f(0.0, frostOffset.y), halfTexel)
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
  let towardRefraction = _vgsl_a5b5afc1__sampleInterior(refractedUv + dispersionOffset, halfTexel);
  let awayFromRefraction = _vgsl_a5b5afc1__sampleInterior(refractedUv - dispersionOffset, halfTexel);
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

// vgsl-module: /regents/home-crown/crown-glass-common.wgsl
// Adapted from Vercel's MIT-licensed prism-background glass-common.wgsl.
// The triangle-specific uniforms are replaced by one ideal square envelope per
// disconnected crown cell. 'cellCenter' is supplied as a flat vertex varying.

      

struct _vgsl_371be593__Glass {
  viewProjection: mat4x4f,
  environmentRotation: mat4x4f,
  cameraPosition: vec3f,
  /** Beer-Lambert absorption per scene unit, in linear RGB. */
  absorption: vec3f,
  /** Half width/height of one ideal optical cube in world XY. */
  cellHalfSize: vec2f,
  resolution: vec2f,
  frontZ: f32,
  backZ: f32,
  wallZ: f32,
  ior: f32,
  reflectionStrength: f32,
  frostRadius: f32,
  dispersion: f32,
  iridescenceStrength: f32,
  iridescenceFrequency: f32,
  environmentExposure: f32,
}

fn _vgsl_371be593__glassEnvironment(direction: vec3f, params: _vgsl_371be593__Glass) -> vec3f {
  return _vgsl_fdf2273e__sampleStudioEnvironment(
    _vgsl_fdf2273e__rotateEnvironmentDirection(direction, params.environmentRotation),
  ) * params.environmentExposure;
}

fn _vgsl_371be593__dielectricFresnel(ior: f32, facing: f32) -> f32 {
  let ratio = (ior - 1.0) / (ior + 1.0);
  let f0 = ratio * ratio;
  return f0 + (1.0 - f0) * pow(1.0 - clamp(facing, 0.0, 1.0), 5.0);
}

fn _vgsl_371be593__projectToUv(point: vec3f, viewProjection: mat4x4f) -> vec2f {
  let clip = viewProjection * vec4f(point, 1.0);
  let ndc = clip.xy / max(clip.w, 0.00001);
  return vec2f(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

fn _vgsl_371be593__sampleScene(
  sceneTexture: texture_2d<f32>,
  sceneSampler: sampler,
  uv: vec2f,
  halfTexel: vec2f,
) -> vec3f {
  let safeUv = clamp(uv, halfTexel, vec2f(1.0) - halfTexel);
  return textureSampleLevel(sceneTexture, sceneSampler, safeUv, 0.0).rgb;
}

// vgsl-module: /regents/home-crown/environment.wgsl
// The deliberately sparse studio the prism reflects.
//
// It started as 'glass-fractal''s nine-panel baked cubemap, but this shot only
// needs three intentional surfaces: a dark back-left wall, a cool right key and
// a neutral strip below the prism. Evaluating them directly keeps the environment
// editable in one WGSL file and available to both the glass and mirror-ball debugger.
//
// The final line replays the round trip the asset used to perform — encode to
// gamma 2.2, decode as sRGB — so the values a reflection reads here are the values
// a reflection reads there, including the small mismatch between those two curves.
//
// Sampling analytically also costs nothing in fidelity for this material: the
// baked cubemap carries a prefiltered mip chain for rough surfaces, and glass
// only ever reads its sharpest level.

     

struct _vgsl_fdf2273e__StudioPanel {
  direction: vec3f,
  /** Half-extents of the panel in tangent space, as a fraction of its distance. */
  size: vec2f,
  feather: f32,
  color: vec3f,
  intensity: f32,
}

/** A back-left wall, soft center fill and dominant right key. */
fn _vgsl_fdf2273e__studioPanels() -> array<_vgsl_fdf2273e__StudioPanel, 3> {
  return array<_vgsl_fdf2273e__StudioPanel, 3>(
    // A broad back-left wall, only a touch brighter than the dark floor.
    _vgsl_fdf2273e__StudioPanel(
      vec3f(-0.82, 0.08, 0.57), // direction
      vec2f(1.35, 1.1), // size
      0.22, // feather
      vec3f(0.82, 0.84, 0.88), // color
      0.011 // intensity
    ),
    // A broad, heavily feathered center fill that barely lifts the bottom edge.
    _vgsl_fdf2273e__StudioPanel(
      vec3f(0.0, -0.707, 0.707), // direction
      vec2f(0.38, 0.62), // size
      0.18, // feather
      vec3f(1.0, 0.97, 0.91), // color
      0.22 // intensity
    ),
    // The cool right panel is the dominant key and keeps a more defined edge.
    _vgsl_fdf2273e__StudioPanel(
      vec3f(0.612, 0.354, 0.707), // direction
      vec2f(0.5, 0.16), // size
      0.035, // feather
      vec3f(0.76, 0.88, 1.0), // color
      20.0 // intensity
    ),
  );
}

/**
 * How much of 'panel' a ray heading in 'direction' sees: a rectangle projected
 * onto the sphere, feathered at its border so its edge does not alias in a
 * mirror-smooth reflection.
 */
fn _vgsl_fdf2273e__studioPanelMask(direction: vec3f, panel: _vgsl_fdf2273e__StudioPanel) -> f32 {
  let forward = normalize(panel.direction);
  // Any helper axis works as long as it is not parallel to the panel's own; the
  // overhead panels are the ones that need the fallback.
  let helper = select(vec3f(0.0, 1.0, 0.0), vec3f(0.0, 0.0, 1.0), abs(forward.y) > 0.92);
  let right = normalize(cross(helper, forward));
  let up = cross(forward, right);
  let facing = dot(direction, forward);
  if (facing <= 0.01) {
    return 0.0;
  }
  let localX = abs(dot(direction, right) / facing);
  let localY = abs(dot(direction, up) / facing);
  let edgeX = 1.0 - smoothstep(panel.size.x, panel.size.x + panel.feather, localX);
  let edgeY = 1.0 - smoothstep(panel.size.y, panel.size.y + panel.feather, localY);
  return edgeX * edgeY;
}

/** Rotates a reflection into the studio's frame. Copied from 'glass-fractal'. */
fn _vgsl_fdf2273e__rotateEnvironmentDirection(direction: vec3f, rotation: mat4x4f) -> vec3f {
  return normalize((rotation * vec4f(direction, 0.0)).xyz);
}

/** Radiance arriving from 'direction', in linear RGB. */
fn _vgsl_fdf2273e__sampleStudioEnvironment(directionInput: vec3f) -> vec3f {
  let direction = normalize(directionInput);
  let floorBlend = 1.0 - smoothstep(-0.22, -0.02, direction.y);
  var room = mix(
    vec3f(0.00025, 0.0003, 0.0004),
    vec3f(0.006, 0.007, 0.009),
    floorBlend,
  );

  // The projection wall occupies the upper part of the -Z hemisphere. Keep the
  // floor below it, but drive the wall itself essentially to black so the prism
  // reflects the same dark surface it physically stands in front of.
  let negativeZ = 1.0 - smoothstep(-0.08, 0.08, direction.z);
  let aboveFloor = smoothstep(-0.28, -0.08, direction.y);
  let backWall = negativeZ * aboveFloor;
  room = mix(room, vec3f(0.00002), backWall);

  // A restrained seam is just bright enough to preserve the floor/wall read.
  let horizon = exp(-abs(direction.y + 0.1) * 22.0) * 0.0012;
  var color = room + vec3f(horizon, horizon * 0.96, horizon * 0.9);
  let panels = _vgsl_fdf2273e__studioPanels();
  for (var index = 0u; index < 3u; index = index + 1u) {
    let panel = panels[index];
    color = color + panel.color * (_vgsl_fdf2273e__studioPanelMask(direction, panel) * panel.intensity);
  }
  // Filmic compression, then the asset's gamma-2.2 encode and the sRGB decode a
  // sample of it performs.
  let mapped = color / (vec3f(1.0) + color);
  return _vgsl_7245ced0__srgbToLinear3(pow(max(mapped, vec3f(0.0)), vec3f(1.0 / 2.2)));
}

// vgsl-module: /vendor/@vgpu/wgsl-std/color/index.wgsl

fn _vgsl_7245ced0__srgbToLinear(value: f32) -> f32 {
  if (value <= 0.04045) {
    return value / 12.92;
  }
  return pow((value + 0.055) / 1.055, 2.4);
}

fn _vgsl_7245ced0__srgbToLinear3(value: vec3f) -> vec3f {
  return vec3f(_vgsl_7245ced0__srgbToLinear(value.r), _vgsl_7245ced0__srgbToLinear(value.g), _vgsl_7245ced0__srgbToLinear(value.b));
}
`
