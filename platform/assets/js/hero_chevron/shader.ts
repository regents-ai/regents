/**
 * Bottom-of-hero scroll cue (`HeroChevron`): a subtle double downward chevron
 * drawn on a clear premultiplied canvas in the Datascape's pixel-block and
 * chromatic-phosphor language.
 *
 * Each chevron is a symmetric 9-cell 45-degree V on a crisp CSS-pixel grid.
 * A slow light pulse sweeps from the upper chevron's tips into its apex, then
 * hands off to the lower chevron, with a restrained cyan/amber phosphor halo
 * that fades cleanly to zero before the canvas edge.
 */
export const heroChevronWgsl = /* wgsl */ `
struct Params {
  // Canvas size in device pixels, device pixels per CSS pixel, and elapsed seconds.
  size: vec4f,
  // Eased hover (0..1), eased press (0..1), unused, unused.
  motion: vec4f,
}

@group(0) @binding(0) var<uniform> params: Params;

const PITCH: f32 = 3.2;
const SPAN: f32 = 4.0;
const UPPER_APEX: f32 = 0.0;
const LOWER_APEX: f32 = 4.0;

fn sq(v: f32) -> f32 { return v * v; }
fn sat(v: f32) -> f32 { return clamp(v, 0.0, 1.0); }

fn sdBox(p: vec2f, half: vec2f, r: f32) -> f32 {
  let q = abs(p) - half + vec2f(r);
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn sdChevronDown(p: vec2f, apexY: f32, halfSpan: f32) -> f32 {
  let q = vec2f(abs(p.x), p.y);
  let a = vec2f(halfSpan, apexY - halfSpan);
  let b = vec2f(0.0, apexY);
  let pa = q - a;
  let ba = b - a;
  let h = sat(dot(pa, ba) / dot(ba, ba));
  return length(pa - ba * h);
}

fn wrapDist(a: f32, b: f32) -> f32 {
  let d = abs(fract(a - b + 0.5) - 0.5);
  return d;
}

fn chevronSample(px: vec2f, t: f32, hover: f32) -> vec2f {
  let cycle = fract(t * 0.44);
  // Subtle vertical drift as the downward wave passes through each chevron.
  let driftUpper = sin(cycle * 6.2831853) * 0.65;
  let driftLower = sin((cycle - 0.22) * 6.2831853) * 0.75;

  let upperPos = px - vec2f(0.0, driftUpper);
  let lowerPos = px - vec2f(0.0, driftLower);

  let uCell = floor(upperPos / PITCH + 0.5);
  let uLocal = upperPos - uCell * PITCH;
  let uOn = step(abs(uCell.x), SPAN + 0.1) * (1.0 - step(0.52, abs(uCell.y - (UPPER_APEX - abs(uCell.x)))));
  let uTip = (SPAN - min(abs(uCell.x), SPAN)) / SPAN;
  let uPulse = exp(-sq(wrapDist(cycle, 0.14 + uTip * 0.14) / 0.145));
  let uEnergy = sat(0.52 + 0.44 * uPulse + hover * 0.22);
  let uBlock = (1.0 - smoothstep(-0.35, 0.35, sdBox(uLocal, vec2f(PITCH * 0.40), 0.22))) * uOn;

  let lCell = floor(lowerPos / PITCH + 0.5);
  let lLocal = lowerPos - lCell * PITCH;
  let lOn = step(abs(lCell.x), SPAN + 0.1) * (1.0 - step(0.52, abs(lCell.y - (LOWER_APEX - abs(lCell.x)))));
  let lTip = (SPAN - min(abs(lCell.x), SPAN)) / SPAN;
  let lPulse = exp(-sq(wrapDist(cycle, 0.38 + lTip * 0.14) / 0.145));
  let lEnergy = sat(0.70 + 0.30 * lPulse + hover * 0.22);
  let lBlock = (1.0 - smoothstep(-0.35, 0.35, sdBox(lLocal, vec2f(PITCH * 0.40), 0.22))) * lOn;

  let blockAlpha = max(uBlock * uEnergy, lBlock * lEnergy);
  let peakPulse = max(uBlock * uPulse, lBlock * lPulse);

  // Soft phosphor halo around each chevron stroke.
  let halfSpanPx = SPAN * PITCH;
  let dUpper = sdChevronDown(upperPos, UPPER_APEX * PITCH, halfSpanPx);
  let dLower = sdChevronDown(lowerPos, LOWER_APEX * PITCH, halfSpanPx);
  let uWave = exp(-sq(wrapDist(cycle, 0.22) / 0.16));
  let lWave = exp(-sq(wrapDist(cycle, 0.46) / 0.16));
  let haloUpper = exp(-dUpper / 4.4) * (0.12 + 0.16 * uWave + 0.08 * hover);
  let haloLower = exp(-dLower / 4.4) * (0.16 + 0.18 * lWave + 0.08 * hover);
  let halo = max(haloUpper, haloLower);

  return vec2f(sat(blockAlpha + halo * (1.0 - blockAlpha * 0.65)), sat(peakPulse));
}

@fragment fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let s = max(params.size.z, 1.0);
  let t = params.size.w;
  let hover = params.motion.x;
  let press = params.motion.y;

  // Center the 9x9 chevron stack (rows -4..+4, mean row 0) inside the canvas.
  let scale = 1.0 - press * 0.07;
  let shiftY = hover * 1.75 + press * 1.0;
  let px = ((position.xy - params.size.xy * 0.5) / s - vec2f(0.0, shiftY)) / scale;

  // Restrained Datascape chromatic split along X on the phosphor edge.
  let split = 0.65 + hover * 0.3;
  let left = chevronSample(px + vec2f(split, 0.0), t, hover);
  let mid = chevronSample(px, t, hover);
  let right = chevronSample(px - vec2f(split, 0.0), t, hover);

  // Warm Platinum core (#E5E3D2), whispered cyan/amber aberration at wave crest.
  let platinum = vec3f(0.898, 0.890, 0.824);
  let coolTint = vec3f(0.682, 0.792, 0.804);
  let warmTint = vec3f(1.0, 0.694, 0.533);

  let core = mix(platinum, vec3f(0.99, 0.985, 0.95), mid.y * 0.45 + hover * 0.2);
  let splitAmt = 0.22 + 0.24 * mid.y;
  let rgb = vec3f(
    mix(core.r, warmTint.r, splitAmt * sat(left.x - mid.x + 0.15)) * mix(mid.x, left.x, 0.28),
    core.g * mid.x,
    mix(core.b, coolTint.b, splitAmt * sat(right.x - mid.x + 0.2)) * mix(mid.x, right.x, 0.32),
  );
  let alpha = sat(max(mid.x, max(left.x, right.x) * 0.65));
  let premul = min(rgb, vec3f(alpha));

  // Fade softly before the canvas boundary so phosphor glow never clips.
  let room = min(min(position.x, params.size.x - position.x), min(position.y, params.size.y - position.y));
  let edgeFade = smoothstep(0.0, 5.0 * s, room);

  return vec4f(premul * edgeFade, alpha * edgeFade);
}
`
