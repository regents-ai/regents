import type {ValuePanel} from "../../panel"

/** Cloak, Rewriting: the redact panel, in Cloak's violet. */
export const rewrite: ValuePanel = {
  colours: ["#2a1457", "#a97bf0", "#d4bcff"],
  pitch: [8, 12],
  stillAt: 2,
  body: /* wgsl */ `
  let gate = mix(0.5 + 0.22 * sin(t * 0.4), clamp(p.x, 0.1, 0.9), p.z);
  let row = g.id.y;
  let pos = g.id.x - floor(t * 2.5) + floor(hash(vec2f(row, 1.0)) * 9.0);
  let word = floor(pos / 4.0);
  let ink = step(0.28, hash(vec2f(word, row))) * step(0.5, pos - word * 4.0);
  let before = step(x, gate);
  let near = exp(-sq((x - gate) * g.count.x * 0.7));
  let on = mix(dith(g.id, 0.5) * 0.5, ink, before);
  let d = mix(length(g.local) - 2.3, sdBox(g.local, vec2f(3.3, 3.0), 0.6), before);
  return emit(g, d, mix(ramp(mix(0.3, 0.95, before)), params.c.rgb, near), max(on * mix(0.75, 0.95, before), near));
`,
}
