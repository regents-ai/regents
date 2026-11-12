import type {ValuePanel} from "../panel"

/** Protocol, Staking: the pro rata panel, from charcoal to the platform's platinum. */
export const prorata: ValuePanel = {
  colours: ["#2a2a27", "#8a887e", "#e5e3d2"],
  pitch: [8, 8],
  stillAt: 6,
  body: /* wgsl */ `
  var edges = array<f32, 6>(0.0, 0.12, 0.36, 0.52, 0.8, 1.0);
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 5; i++) {
    if (x >= edges[i] && x < edges[i + 1]) { lo = edges[i]; hi = edges[i + 1]; }
  }
  let gap = 1.0 - step(0.9 / g.count.x, x - lo);
  let level = 0.08 + 0.8 * fract(t * 0.07);
  let rowH = 1.0 / g.count.y;
  let filled = step(y, level);
  let top = filled * step(level - rowH * 1.5, y);
  let mine = p.z * step(lo, p.x) * step(p.x, hi);
  let drip = step(level, y) * step(0.86, hash(vec2f(g.id.x, g.id.y - floor(t * 9.0))));
  let colour = mix(ramp(0.12 + 0.36 * y / level + 0.52 * top), params.c.rgb, max(mine * filled * 0.6, drip));
  return emit(g, sdBox(g.local, vec2f(3.1, 3.1), 0.6), colour, (1.0 - gap) * max(filled * (0.66 + 0.34 * max(top, mine)), drip * 0.55));
`,
}
