import type {ValuePanel} from "../panel"

/** Keyfleet, Fleets: the formation panel, from a darker orange to Keyfleet's tangerine. */
export const fleet: ValuePanel = {
  colours: ["#6b2006", "#ff5b19", "#ffd2ad"],
  pitch: [10, 10],
  stillAt: 2,
  body: /* wgsl */ `
  var value = 0.0;
  for (var i = 0; i < 7; i++) {
    let rank = f32((i + 1) / 2);
    let side = f32(i % 2) * 2.0 - 1.0;
    let then = t - rank * 0.35;
    let lead = mix(vec2f(0.5 + 0.14 * sin(then * 0.5), 0.74 + 0.08 * sin(then * 0.8 + 1.0)), p.xy, p.z);
    let spot = lead + vec2f(side * rank * 0.135, -rank * 0.15);
    value = max(value, exp(-sq(length((g.at - spot) * aspect()) * 9.5)) * (1.0 - 0.08 * rank));
  }
  return emit(g, sdDiamond(g.local, mix(1.2, 5.0, value)), ramp(0.08 + 0.92 * value), value);
`,
}
