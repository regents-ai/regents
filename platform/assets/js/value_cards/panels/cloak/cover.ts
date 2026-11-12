import type {ValuePanel} from "../../panel"

/** Cloak, Cover traffic: the cover panel. */
export const cover: ValuePanel = {
  colours: ["#12343b", "#5fa8a0", "#e6fffb"],
  pitch: [12, 9],
  stillAt: 2,
  body: /* wgsl */ `
  let row = g.id.y;
  let run = x * 5.0 - t * 0.35 + hash(vec2f(row, 2.0));
  let on = step(fract(run), 0.36);
  let real = step(0.88, hash(vec2f(floor(run), row)));
  let look = p.z * exp(-sq(length((g.at - p.xy) * aspect()) * 3.2));
  let tone = 0.32 + 0.16 * sin(row * 0.6 + t * 0.3) + real * look * 0.6;
  return emit(g, sdBox(g.local, vec2f(4.8, 2.2), 2.2), ramp(tone), on * (0.6 + 0.4 * real * look));
`,
}
