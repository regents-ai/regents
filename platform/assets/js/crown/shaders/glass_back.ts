/**
 * The inner, far faces of the glass cubes, refracting the picture behind them.
 *
 * Derived from the Vercel vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */
export const glassBackWgsl = `
// vgsl-module: /regents/home-crown/crown-glass-back.wgsl
// Inner/back glass interface for one of the 13 disconnected crown cells.
// Adapted from Vercel's MIT-licensed prism-background/glass-back.wgsl.

 
  
  
  
  
  
  

@group(0) @binding(0) var<uniform> params: _vgsl_371be593__Glass;
@group(0) @binding(1) var sceneTexture: texture_2d<f32>;
@group(0) @binding(2) var sceneSampler: sampler;

struct _vgsl_840e9247__VertexOut {
  @builtin(position) position: vec4f,
  @location(0) worldPosition: vec3f,
  @location(1) worldNormal: vec3f,
  @location(2) @interpolate(flat) cellCenter: vec2f,
};

struct _vgsl_840e9247__SurfaceHit {
  distance: f32,
  outwardNormal: vec3f,
};

struct _vgsl_840e9247__ExitPath {
  position: vec3f,
  direction: vec3f,
  incidentDirection: vec3f,
  inwardNormal: vec3f,
  escaped: u32,
};

const _vgsl_840e9247__NO_HIT: f32 = 100000.0;
const _vgsl_840e9247__SURFACE_EPSILON: f32 = 0.0002;
const _vgsl_840e9247__MAX_INTERNAL_BOUNCES: u32 = 3u;

@vertex
fn vs_main(
  @location(0) position: vec3f,
  @location(1) normal: vec3f,
  @location(2) cell_center: vec2f,
) -> _vgsl_840e9247__VertexOut {
  var out: _vgsl_840e9247__VertexOut;
  out.position = params.viewProjection * vec4f(position, 1.0);
  out.worldPosition = position;
  out.worldNormal = normal;
  out.cellCenter = cell_center;
  return out;
}

fn _vgsl_840e9247__candidateDistance(
  origin: f32,
  direction: f32,
  plane: f32,
) -> f32 {
  if (abs(direction) <= 0.00001) { return _vgsl_840e9247__NO_HIT; }
  let distance = (plane - origin) / direction;
  return select(_vgsl_840e9247__NO_HIT, distance, distance > _vgsl_840e9247__SURFACE_EPSILON);
}

/** Nearest ideal cell plane reached by a ray already inside that cell. */
fn _vgsl_840e9247__nextSurface(origin: vec3f, direction: vec3f, center: vec2f) -> _vgsl_840e9247__SurfaceHit {
  let low = center - params.cellHalfSize;
  let high = center + params.cellHalfSize;
  var nearest = _vgsl_840e9247__NO_HIT;
  var normal = vec3f(0.0, 0.0, 1.0);

  let xPlane = select(low.x, high.x, direction.x > 0.0);
  let xDistance = _vgsl_840e9247__candidateDistance(origin.x, direction.x, xPlane);
  if (xDistance < nearest) {
    nearest = xDistance;
    normal = vec3f(select(-1.0, 1.0, direction.x > 0.0), 0.0, 0.0);
  }

  let yPlane = select(low.y, high.y, direction.y > 0.0);
  let yDistance = _vgsl_840e9247__candidateDistance(origin.y, direction.y, yPlane);
  if (yDistance < nearest) {
    nearest = yDistance;
    normal = vec3f(0.0, select(-1.0, 1.0, direction.y > 0.0), 0.0);
  }

  let zPlane = select(params.backZ, params.frontZ, direction.z > 0.0);
  let zDistance = _vgsl_840e9247__candidateDistance(origin.z, direction.z, zPlane);
  if (zDistance < nearest) {
    nearest = zDistance;
    normal = vec3f(0.0, 0.0, select(-1.0, 1.0, direction.z > 0.0));
  }

  return _vgsl_840e9247__SurfaceHit(nearest, normal);
}

fn _vgsl_840e9247__traceExit(
  firstPosition: vec3f,
  firstDirection: vec3f,
  firstInwardNormal: vec3f,
  cellCenter: vec2f,
) -> _vgsl_840e9247__ExitPath {
  var position = firstPosition;
  var direction = firstDirection;
  var inwardNormal = firstInwardNormal;

  for (var bounce = 0u; bounce <= _vgsl_840e9247__MAX_INTERNAL_BOUNCES; bounce = bounce + 1u) {
    let transmitted = refract(direction, inwardNormal, params.ior);
    if (length(transmitted) > 0.00001) {
      return _vgsl_840e9247__ExitPath(
        position,
        normalize(transmitted),
        direction,
        inwardNormal,
        1u,
      );
    }

    direction = normalize(reflect(direction, inwardNormal));
    let hit = _vgsl_840e9247__nextSurface(
      position + direction * _vgsl_840e9247__SURFACE_EPSILON,
      direction,
      cellCenter,
    );
    if (hit.distance >= 10.0) { break; }
    position = position + direction * (hit.distance + _vgsl_840e9247__SURFACE_EPSILON);
    inwardNormal = -hit.outwardNormal;
  }

  return _vgsl_840e9247__ExitPath(position, direction, direction, inwardNormal, 0u);
}

fn _vgsl_840e9247__traceReflectedEnvironmentExit(
  surfacePosition: vec3f,
  incidentDirection: vec3f,
  inwardNormal: vec3f,
  cellCenter: vec2f,
) -> _vgsl_840e9247__ExitPath {
  let direction = normalize(reflect(incidentDirection, inwardNormal));
  let shiftedPosition = surfacePosition + direction * _vgsl_840e9247__SURFACE_EPSILON;
  let hit = _vgsl_840e9247__nextSurface(shiftedPosition, direction, cellCenter);
  if (hit.distance >= 10.0) {
    return _vgsl_840e9247__ExitPath(surfacePosition, direction, direction, inwardNormal, 0u);
  }
  let position = shiftedPosition + direction * hit.distance;
  return _vgsl_840e9247__traceExit(position, direction, -hit.outwardNormal, cellCenter);
}

@fragment
fn fs_main(in: _vgsl_840e9247__VertexOut) -> @location(0) vec4f {
  let view = normalize(params.cameraPosition - in.worldPosition);
  let incident = -view;
  let inwardNormal = -normalize(in.worldNormal);
  let exit = _vgsl_840e9247__traceExit(
    in.worldPosition,
    incident,
    inwardNormal,
    in.cellCenter,
  );
  let wallDenominator = exit.direction.z;
  let wallDistance = (params.wallZ - exit.position.z) / select(
    0.00001,
    wallDenominator,
    abs(wallDenominator) > 0.00001,
  );
  let validWallHit = exit.escaped != 0u && wallDistance > 0.00001;

  let originalUv = in.position.xy / max(params.resolution, vec2f(1.0));
  let wallPoint = exit.position + exit.direction * max(wallDistance, 0.0);
  let refractedUv = select(
    originalUv,
    _vgsl_371be593__projectToUv(wallPoint, params.viewProjection),
    validWallHit,
  );
  let halfTexel = 0.5 / max(params.resolution, vec2f(1.0));
  let wallColor = _vgsl_371be593__sampleScene(sceneTexture, sceneSampler, refractedUv, halfTexel);
  let exteriorColor = _vgsl_371be593__glassEnvironment(exit.direction, params)
    * params.reflectionStrength;
  let sceneColor = select(exteriorColor, wallColor, validWallHit);

  let reflectedExit = _vgsl_840e9247__traceReflectedEnvironmentExit(
    exit.position,
    exit.incidentDirection,
    exit.inwardNormal,
    in.cellCenter,
  );
  let reflectedFacing = clamp(
    -dot(reflectedExit.incidentDirection, reflectedExit.inwardNormal),
    0.0,
    1.0,
  );
  let reflectedExitTransmission = select(
    0.0,
    1.0 - _vgsl_371be593__dielectricFresnel(params.ior, reflectedFacing),
    reflectedExit.escaped != 0u,
  );
  let reflectedEnvironment = _vgsl_371be593__glassEnvironment(reflectedExit.direction, params)
    * params.reflectionStrength
    * reflectedExitTransmission;
  let facing = clamp(
    -dot(exit.incidentDirection, exit.inwardNormal),
    0.0,
    1.0,
  );
  let fresnel = _vgsl_371be593__dielectricFresnel(params.ior, facing);
  let radiance = select(
    reflectedEnvironment,
    mix(sceneColor, reflectedEnvironment, fresnel),
    exit.escaped != 0u,
  );
  return vec4f(radiance, 1.0);
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
