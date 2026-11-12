import type {ValuePanel} from "../../panel"

/** Polls: the ballot panel, two choices filling with votes. */
export const ballot: ValuePanel = {
  colours: ["#20124d", "#7b61ff", "#5ff5c0"],
  pitch: [9, 9],
  stillAt: 9,
  body: /* wgsl */ `
  let e = min(min(g.id.x, g.count.x - 1.0 - g.id.x), min(g.id.y, g.count.y - 1.0 - g.id.y));
  let border = 1.0 - step(0.5, e);
  let q = (g.at - vec2f(0.5)) * aspect();
  let clock = fract(t * 0.04);
  let spent = step(fract(atan2(q.x, q.y) / TAU + 1.0), clock);
  let left = step(x, 0.5);
  let gap = 1.0 - step(1.2 / g.count.x, abs(x - 0.5));
  let lean = p.z * (step(p.x, 0.5) * 2.0 - 1.0) * 0.12;
  let h = mix(0.16 + 0.32 * clock + 0.07 * sin(t * 0.7 + 2.0) - lean, 0.2 + 0.5 * clock + 0.07 * sin(t * 0.9) + lean, left);
  let filled = step(y, h) * step(1.5, e) * (1.0 - gap);
  let top = filled * step(h - 1.5 / g.count.y, y);
  let amount = max(border * mix(0.22, 0.9, spent), filled * (0.62 + 0.38 * top));
  return emit(g, sdBox(g.local, vec2f(3.3, 3.3), 0.5), ramp(mix(mix(0.45, 0.92, left) + 0.08 * top, 0.5, border)), amount);
`,
}
