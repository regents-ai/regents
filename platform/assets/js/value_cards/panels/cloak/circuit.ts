import type {ValuePanel} from "../../panel"

/** Cloak, Tor circuits: the circuit panel. */
export const circuit: ValuePanel = {
  colours: ["#2d1457", "#9b5de5", "#c9ffd9"],
  pitch: [9, 9],
  stillAt: 2.6,
  body: /* wgsl */ `
  let rowH = 1.0 / g.count.y;
  let colW = 1.0 / g.count.x;
  let s = floor(x * 4.0);
  var value = 0.0;
  var hop = 0.0;
  for (var i = 0; i < 3; i++) {
    let fi = f32(i);
    let home = (fi + 0.5) / 3.0;
    let epoch = floor(t * 0.12 + fi * 0.37);
    let ya = home + (hash(vec2f(fi * 7.0 + s, epoch)) - 0.5) * 0.22;
    let yb = home + (hash(vec2f(fi * 7.0 + s - 1.0, epoch)) - 0.5) * 0.22;
    let onRun = 1.0 - step(rowH * 0.6, abs(y - ya));
    let atHop = (1.0 - step(colW * 0.6, abs(x - s / 4.0))) * step(0.5, s);
    let onRise = atHop * step(min(ya, yb) - rowH * 0.5, y) * step(y, max(ya, yb) + rowH * 0.5);
    let line = max(onRun, onRise);
    let pulse = exp(-sq((x - fract(t * (0.2 + 0.07 * fi) + fi * 0.3)) * 7.0));
    let pick = p.z * exp(-sq((p.y - home) * 5.0));
    value = max(value, line * (0.38 + 0.62 * max(pulse, pick)));
    hop = max(hop, atHop * step(abs(y - ya), rowH * 0.6));
  }
  value = max(value, hop);
  return emit(g, length(g.local) - mix(1.0, 3.8, value), ramp(0.08 + 0.92 * value), value);
`,
}
