// Inner/back glass interface for one of the 13 disconnected crown cells.
// Adapted from Vercel's MIT-licensed prism-background/glass-back.wgsl.

import {
  Glass,
  dielectricFresnel,
  glassEnvironment,
  projectToUv,
  sampleScene,
} from "./crown-glass-common.wgsl";

@group(0) @binding(0) var<uniform> params: Glass;
@group(0) @binding(1) var sceneTexture: texture_2d<f32>;
@group(0) @binding(2) var sceneSampler: sampler;

struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) worldPosition: vec3f,
  @location(1) worldNormal: vec3f,
  @location(2) @interpolate(flat) cellCenter: vec2f,
};

struct SurfaceHit {
  distance: f32,
  outwardNormal: vec3f,
};

struct ExitPath {
  position: vec3f,
  direction: vec3f,
  incidentDirection: vec3f,
  inwardNormal: vec3f,
  escaped: u32,
};

const NO_HIT: f32 = 100000.0;
const SURFACE_EPSILON: f32 = 0.0002;
const MAX_INTERNAL_BOUNCES: u32 = 3u;

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

fn candidateDistance(
  origin: f32,
  direction: f32,
  plane: f32,
) -> f32 {
  if (abs(direction) <= 0.00001) { return NO_HIT; }
  let distance = (plane - origin) / direction;
  return select(NO_HIT, distance, distance > SURFACE_EPSILON);
}

/** Nearest ideal cell plane reached by a ray already inside that cell. */
fn nextSurface(origin: vec3f, direction: vec3f, center: vec2f) -> SurfaceHit {
  let low = center - params.cellHalfSize;
  let high = center + params.cellHalfSize;
  var nearest = NO_HIT;
  var normal = vec3f(0.0, 0.0, 1.0);

  let xPlane = select(low.x, high.x, direction.x > 0.0);
  let xDistance = candidateDistance(origin.x, direction.x, xPlane);
  if (xDistance < nearest) {
    nearest = xDistance;
    normal = vec3f(select(-1.0, 1.0, direction.x > 0.0), 0.0, 0.0);
  }

  let yPlane = select(low.y, high.y, direction.y > 0.0);
  let yDistance = candidateDistance(origin.y, direction.y, yPlane);
  if (yDistance < nearest) {
    nearest = yDistance;
    normal = vec3f(0.0, select(-1.0, 1.0, direction.y > 0.0), 0.0);
  }

  let zPlane = select(params.backZ, params.frontZ, direction.z > 0.0);
  let zDistance = candidateDistance(origin.z, direction.z, zPlane);
  if (zDistance < nearest) {
    nearest = zDistance;
    normal = vec3f(0.0, 0.0, select(-1.0, 1.0, direction.z > 0.0));
  }

  return SurfaceHit(nearest, normal);
}

fn traceExit(
  firstPosition: vec3f,
  firstDirection: vec3f,
  firstInwardNormal: vec3f,
  cellCenter: vec2f,
) -> ExitPath {
  var position = firstPosition;
  var direction = firstDirection;
  var inwardNormal = firstInwardNormal;

  for (var bounce = 0u; bounce <= MAX_INTERNAL_BOUNCES; bounce = bounce + 1u) {
    let transmitted = refract(direction, inwardNormal, params.ior);
    if (length(transmitted) > 0.00001) {
      return ExitPath(
        position,
        normalize(transmitted),
        direction,
        inwardNormal,
        1u,
      );
    }

    direction = normalize(reflect(direction, inwardNormal));
    let hit = nextSurface(
      position + direction * SURFACE_EPSILON,
      direction,
      cellCenter,
    );
    if (hit.distance >= 10.0) { break; }
    position = position + direction * (hit.distance + SURFACE_EPSILON);
    inwardNormal = -hit.outwardNormal;
  }

  return ExitPath(position, direction, direction, inwardNormal, 0u);
}

fn traceReflectedEnvironmentExit(
  surfacePosition: vec3f,
  incidentDirection: vec3f,
  inwardNormal: vec3f,
  cellCenter: vec2f,
) -> ExitPath {
  let direction = normalize(reflect(incidentDirection, inwardNormal));
  let shiftedPosition = surfacePosition + direction * SURFACE_EPSILON;
  let hit = nextSurface(shiftedPosition, direction, cellCenter);
  if (hit.distance >= 10.0) {
    return ExitPath(surfacePosition, direction, direction, inwardNormal, 0u);
  }
  let position = shiftedPosition + direction * hit.distance;
  return traceExit(position, direction, -hit.outwardNormal, cellCenter);
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4f {
  let view = normalize(params.cameraPosition - in.worldPosition);
  let incident = -view;
  let inwardNormal = -normalize(in.worldNormal);
  let exit = traceExit(
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
    projectToUv(wallPoint, params.viewProjection),
    validWallHit,
  );
  let halfTexel = 0.5 / max(params.resolution, vec2f(1.0));
  let wallColor = sampleScene(sceneTexture, sceneSampler, refractedUv, halfTexel);
  let exteriorColor = glassEnvironment(exit.direction, params)
    * params.reflectionStrength;
  let sceneColor = select(exteriorColor, wallColor, validWallHit);

  let reflectedExit = traceReflectedEnvironmentExit(
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
    1.0 - dielectricFresnel(params.ior, reflectedFacing),
    reflectedExit.escaped != 0u,
  );
  let reflectedEnvironment = glassEnvironment(reflectedExit.direction, params)
    * params.reflectionStrength
    * reflectedExitTransmission;
  let facing = clamp(
    -dot(exit.incidentDirection, exit.inwardNormal),
    0.0,
    1.0,
  );
  let fresnel = dielectricFresnel(params.ior, facing);
  let radiance = select(
    reflectedEnvironment,
    mix(sceneColor, reflectedEnvironment, fresnel),
    exit.escaped != 0u,
  );
  return vec4f(radiance, 1.0);
}
