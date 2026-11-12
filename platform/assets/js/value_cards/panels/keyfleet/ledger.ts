import type {ValuePanel} from "../../panel"

/** Treasury: the ledger panel, a statement's lines rising, the newest brightest. */
export const ledger: ValuePanel = {
  colours: ["#07332c", "#22c79b", "#dcfff2"],
  pitch: [8, 9],
  stillAt: 3,
  body: /* wgsl */ `
  let below = g.count.y - 1.0 - g.id.y;
  let m = floor(t * 0.7) - below;
  let entry = floor(m / 2.0);
  let line = step(m - entry * 2.0, 0.5);
  let fresh = 1.0 - below / g.count.y;
  let date = step(0.03, x) * step(x, 0.1 + 0.08 * hash(vec2f(entry, 3.0)));
  let size = 0.12 + 0.46 * hash(vec2f(entry, 7.0));
  let figure = step(0.97 - size, x) * step(x, 0.97);
  let held = p.z * (1.0 - step(1.5 / g.count.y, abs(y - p.y)));
  let shown = line * max(date, figure);
  let amount = shown * max(max(date * 0.3, figure * (0.35 + 0.55 * fresh)), held);
  return emit(g, sdBox(g.local, vec2f(3.4, 2.4), 1.2), ramp(mix(0.3, 0.45 + 0.5 * fresh, figure) + 0.1 * held), amount);
`,
}
