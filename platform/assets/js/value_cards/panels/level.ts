import type {ValuePanel} from "../panel"

/** Autolaunch, Auctions: the level panel, in Autolaunch's soft orange. */
export const level: ValuePanel = {
  colours: ["#5a2416", "#ff9a66", "#fff1e6"],
  pitch: [9, 12],
  stillAt: 3.1,
  body: /* wgsl */ `
  let col = g.id.x;
  let lift = exp(-sq((x - p.x) * 5.0)) * p.z * 0.18;
  let bid = sat(0.16 + 0.8 * (noise(vec2f(col * 0.31, t * 0.22)) * 0.62 + noise(vec2f(col * 1.27 + 7.0, t * 0.55)) * 0.38) + lift);
  let level = mix(0.5 + 0.13 * sin(t * 0.45), clamp(p.y, 0.12, 0.9), p.z);
  let rowH = 1.0 / g.count.y;
  let snapped = (floor(level / rowH) + 0.5) * rowH;
  let onLine = 1.0 - step(rowH * 0.5, abs(y - snapped));
  let reaches = step(snapped, bid);
  let paid = step(y, min(bid, snapped - rowH * 0.5));
  let above = step(snapped + rowH * 0.5, y) * step(y, bid);
  var colour = ramp(0.1 + 0.5 * y / max(snapped, 0.05));
  var amount = paid * 0.94;
  colour = mix(colour, ramp(0.2), above);
  amount = max(amount, above * dith(g.id, 0.5) * 0.55);
  colour = mix(colour, params.c.rgb, onLine);
  amount = max(amount, onLine * mix(0.28, 1.0, reaches));
  return emit(g, sdBox(g.local, vec2f(2.9, 4.6), 2.9), colour, amount);
`,
}
