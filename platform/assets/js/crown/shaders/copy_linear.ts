/**
 * Copies the picture so far into the target the next glass pass reads behind itself.
 *
 * Derived from the Vercel vgpu prism background. See THIRD_PARTY_NOTICES.md.
 */
export const copyLinearWgsl = `
// vgsl-module: apps/docs/app/[lang]/(home)/components/prism-background/copy-linear.wgsl
// Raw ping-pong copy. The scene stays in linear HDR until the final surface pass.

@group(0) @binding(0) var sceneTexture: texture_2d<f32>;

@fragment
fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  return textureLoad(sceneTexture, vec2i(position.xy), 0);
}
`
