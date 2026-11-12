import type {ValuePanel} from "../../panel"

/** Cloak, Sandbox: the box panel. */
export const sandbox: ValuePanel = {
  colours: ["#1e2a38", "#8aa0b8", "#ffe14d"],
  pitch: [9, 9],
  stillAt: 3,
  body: /* wgsl */ `
  let half = vec2f(0.31, 0.29);
  let rel = (g.at - vec2f(0.5)) / half;
  let m = max(abs(rel.x), abs(rel.y));
  let unit = vec2f(1.0) / g.count / half;
  let inside = step(m, 1.0);
  let wall = (1.0 - inside) * step(max((abs(rel.x) - 1.0) / unit.x, (abs(rel.y) - 1.0) / unit.y), 1.0);
  var glow = 0.0;
  var touch = 0.0;
  for (var i = 0; i < 3; i++) {
    let fi = f32(i);
    var spot = vec2f(abs(fract(t * (0.11 + 0.04 * fi) + fi * 0.31) * 2.0 - 1.0), abs(fract(t * (0.09 + 0.05 * fi) + fi * 0.57) * 2.0 - 1.0)) * 1.7 - vec2f(0.85);
    if (i == 0) { spot = mix(spot, clamp((p.xy - vec2f(0.5)) / half, vec2f(-0.85), vec2f(0.85)), p.z); }
    let reach = length((rel - spot) * half * aspect());
    glow = max(glow, exp(-sq(reach * 9.0)));
    touch = max(touch, exp(-sq(reach * 4.5)));
  }
  let d = mix(length(g.local) - mix(0.9, 3.9, glow * inside), sdBox(g.local, vec2f(3.3, 3.3), 0.5), wall);
  let colour = mix(ramp(0.12 + 0.5 * glow), params.c.rgb, wall);
  return emit(g, d, colour, max(inside * glow, wall * (0.45 + 0.55 * touch)));
`,
}
