/**
 * The workspace's places chart, one fullscreen pass over a clear canvas with
 * premultiplied alpha, so the page's own ground shows through: a few contour
 * lines, one behind another, each lifting into a ridge over the tab of every
 * place as far as that place has risen. A nearer ridge hides the lines behind
 * it, and the body under the highest one carries a faint wash of its place's
 * colour. The lines take their place's colour where they rise.
 */
export const chartWgsl = /* wgsl */ `
struct Params {
  // Width and height in device pixels, device pixels per CSS pixel, and a
  // tab's width, 0..1 across the canvas.
  size: vec4f,
  // How far each place's ridge has risen, 0..1: the Project, Docs, Code and
  // Public.
  rise: vec4f,
  // The centre of each place's tab, 0..1 across the canvas.
  centers: vec4f,
  // The resting lines' colour and strength, then each place's colour.
  line: vec4f,
  project: vec4f,
  docs: vec4f,
  code: vec4f,
  everyone: vec4f,
}
@group(0) @binding(0) var<uniform> params: Params;

// How many lines run across, from the furthest (0) to the nearest.
const LINES = 7;

fn bump(x: f32, center: f32, width: f32) -> f32 {
  let t = (x - center) / max(width * 0.42, 0.001);
  return exp(-t * t);
}

// How far each place lifts line k at x (0..1 across). Each line's ridge
// drifts a little from the next, so they read as hills rather than copies.
fn lifts(x: f32, k: f32) -> vec4f {
  let width = params.size.w;
  let drift = 0.06 * width;
  return vec4f(
    params.rise.x * bump(x, params.centers.x + drift * sin(k * 1.3), width),
    params.rise.y * bump(x, params.centers.y + drift * sin(k * 1.3 + 2.0), width),
    params.rise.z * bump(x, params.centers.z + drift * sin(k * 1.3 + 4.0), width),
    params.rise.w * bump(x, params.centers.w + drift * sin(k * 1.3 + 6.0), width),
  );
}

// Where line k runs at x, in device pixels from the top.
fn ridge(x: f32, k: f32) -> f32 {
  let h = params.size.y;
  let depth = k / f32(LINES - 1);
  let base = h * (0.3 + 0.66 * depth);
  let reach = h * (0.18 + 0.12 * depth);
  let lift = lifts(x, k);
  let wobble = h * 0.025 * sin(x * 23.0 + k * 2.1) * sin(x * 7.0 + k * 0.7);
  return base - reach * dot(lift, vec4f(1.0)) + wobble;
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let px = uv * params.size.xy;
  let pixel = 1.0 / max(params.size.x, 1.0);
  let stroke = params.size.z;
  var color = vec3f(0.0);
  var alpha = 0.0;

  // From the nearest line back: below a line is the body of its ridge, which
  // hides every line behind it.
  for (var i = LINES - 1; i >= 0; i = i - 1) {
    let k = f32(i);
    let y = ridge(uv.x, k);
    let slope = (ridge(uv.x + pixel, k) - ridge(uv.x - pixel, k)) * 0.5;
    let gap = abs(px.y - y) / sqrt(1.0 + slope * slope);
    let lift = lifts(uv.x, k);
    let total = dot(lift, vec4f(1.0));
    let risen = min(1.0, total * 1.3);
    let tint = (params.project.rgb * lift.x + params.docs.rgb * lift.y + params.code.rgb * lift.z
      + params.everyone.rgb * lift.w) / max(total, 0.0001);
    let ink = mix(params.line.rgb, tint, risen);
    let a = (1.0 - smoothstep(stroke * 0.5 - 0.5, stroke * 0.5 + 0.75, gap))
      * mix(params.line.a, 1.0, risen);
    color = color + ink * a * (1.0 - alpha);
    alpha = alpha + a * (1.0 - alpha);

    if (px.y > y + stroke) {
      let wash = 0.12 * risen * (1.0 - clamp((px.y - y) / (params.size.y * 0.45), 0.0, 1.0));
      color = color + tint * wash * (1.0 - alpha);
      alpha = alpha + wash * (1.0 - alpha);
      break;
    }
  }

  return vec4f(color, alpha);
}
`
