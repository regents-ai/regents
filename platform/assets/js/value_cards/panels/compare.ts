import type {ValuePanel} from "../panel"

/** Techtree, Compare Skills: the compare panel, in Techtree's green. */
export const compare: ValuePanel = {
  colours: ["#0b3a24", "#2fa866", "#d6ffe4"],
  pitch: [8, 8],
  stillAt: 2,
  body: /* wgsl */ `
  let side = step(0.5, x);
  let mi = mix(g.id.x, g.count.x - 1.0 - g.id.x, side);
  let field = noise(vec2f(mi * 0.3, g.id.y * 0.3 - t * 0.35));
  let band = mix(0.5 + 0.3 * sin(t * 0.5), p.y, p.z);
  let inBand = 1.0 - step(0.09, abs(y - band));
  let other = noise(vec2f(mi * 0.55 + 31.0, g.id.y * 0.55 + t * 0.9));
  let shown = mix(field, other, inBand * side);
  let on = dith(vec2f(mi, g.id.y), shown * 0.9 + 0.05);
  let gap = 1.0 - step(1.0 / g.count.x, abs(x - 0.5));
  var colour = ramp(0.06 + 0.44 * shown);
  colour = mix(colour, params.c.rgb, inBand * side);
  colour = mix(colour, ramp(0.5), inBand * (1.0 - side) * 0.7);
  return emit(g, sdBox(g.local, vec2f(3.0, 3.0), 0.6), colour, on * (0.62 + 0.38 * inBand) * (1.0 - gap));
`,
}
