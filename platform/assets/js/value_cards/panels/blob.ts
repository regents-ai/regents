import type {ValuePanel} from "../panel"

/** Patchbay, Known fixes: the lens panel, in Patchbay's blue. */
export const blob: ValuePanel = {
  colours: ["#18265f", "#6f8fff", "#dde5ff"],
  pitch: [9, 13],
  stillAt: 2,
  body: /* wgsl */ `
  let home = vec2f(0.42 + 0.16 * sin(t * 0.5), 0.46 + 0.13 * cos(t * 0.37));
  let q = (g.at - mix(home, p.xy, p.z)) * aspect();
  let wob = (noise(g.at * 4.0 + vec2f(t * 0.3, 0.0)) - 0.5) * 0.14;
  let body = 1.0 - smoothstep(0.2, 0.3, length(q) + wob);
  let bite = smoothstep(0.1, 0.2, length(q - vec2f(0.12, 0.06)) + wob);
  let f = body * mix(1.0, bite, 0.92);
  let halfW = mix(1.5, 3.5, f);
  return emit(g, sdBox(g.local, vec2f(halfW, 5.0), halfW), ramp(0.16 + 0.84 * f), 0.26 + 0.74 * f);
`,
}
