/**
 * The last pass: adds the bloom, tone-maps and encodes for the screen.
 *
 * Derived from the Vercel vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */
export const presentWgsl = `
// vgsl-module: apps/docs/app/[lang]/(home)/components/prism-background/present.wgsl
// Final linear-HDR presentation. The bloom pyramid is already rebuilt
// additively from 1/16 back to 1/2 resolution, so this pass only normalizes the
// accumulated energy, adds it to the untouched HDR scene, and performs the one
// ACES tone mapping plus sRGB conversion.

      

@group(0) @binding(0) var sceneTexture: texture_2d<f32>;
@group(0) @binding(1) var bloomTexture: texture_2d<f32>;
@group(0) @binding(2) var bloomSampler: sampler;

struct _vgsl_cb7fa732__PresentParams {
  bloomStrength: f32,
}

@group(0) @binding(3) var<uniform> params: _vgsl_cb7fa732__PresentParams;

// scatter = 0.65 at all three upsample steps. This is the reciprocal of
// 1 + scatter + scatter^2 + scatter^3, keeping brightness stable as levels are
// added while their progressively wider footprints shape the halo.
const _vgsl_cb7fa732__BLOOM_ENERGY_NORMALIZATION = 0.426394;

@fragment
fn fs_main(
  @location(0) uv: vec2f,
  @builtin(position) position: vec4f,
) -> @location(0) vec4f {
  let scene = textureLoad(sceneTexture, vec2i(position.xy), 0).rgb;
  let bloom = textureSampleLevel(bloomTexture, bloomSampler, uv, 0.0).rgb
    * _vgsl_cb7fa732__BLOOM_ENERGY_NORMALIZATION;
  let linear = max(scene + bloom * max(params.bloomStrength, 0.0), vec3f(0.0));
  return vec4f(_vgsl_4c2c8948__linearToSrgb3(_vgsl_4c2c8948__tonemapAces(linear)), 1.0);
}

// vgsl-module: @vgpu/wgsl-std/src/color/index.wgsl

fn _vgsl_4c2c8948__linearToSrgb(value: f32) -> f32 {
  if (value <= 0.0031308) {
    return value * 12.92;
  }
  return 1.055 * pow(value, 1.0 / 2.4) - 0.055;
}

fn _vgsl_4c2c8948__linearToSrgb3(value: vec3f) -> vec3f {
  return vec3f(_vgsl_4c2c8948__linearToSrgb(value.r), _vgsl_4c2c8948__linearToSrgb(value.g), _vgsl_4c2c8948__linearToSrgb(value.b));
}

fn _vgsl_4c2c8948__tonemapAces(value: vec3f) -> vec3f {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((value * (a * value + b)) / (value * (c * value + d) + e), vec3f(0.0), vec3f(1.0));
}
`
