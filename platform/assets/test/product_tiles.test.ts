// Each product tile on the home page wears its own product's colours, read here
// from the stylesheet that paints them. Its words must read on every colour the
// still gradient and the flow put under them.
import {readFileSync} from "node:fs"
import {describe, expect, it} from "vitest"
import {BAND, GLOW, contrast, labelRange, mix, ramp, type Rgb, type TileLook} from "../js/product_tiles/look"

const stylesheet = readFileSync(new URL("../css/pages/home.css", import.meta.url), "utf8")

const hex = (value: string): Rgb => [
  parseInt(value.slice(1, 3), 16) / 255,
  parseInt(value.slice(3, 5), 16) / 255,
  parseInt(value.slice(5, 7), 16) / 255,
]

const looks = new Map<string, TileLook>(
  [...stylesheet.matchAll(/\[data-product-tile="([a-z]+)"\]\s*\{([^}]*)\}/g)].map(([, name, rule]) => {
    const color = (part: string) => hex(rule!.match(new RegExp(`--tile-${part}:\\s*(#[0-9a-f]{6})`))![1]!)
    return [
      name!,
      {deep: color("deep"), mid: color("mid"), light: color("light"), sheen: color("sheen"), ink: color("ink")},
    ]
  }),
)

const distance = (a: Rgb, b: Rgb) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])

it("gives each of the five products a colour of its own", () => {
  expect(looks.size).toBe(5)
  const tiles = [...looks]
  for (const [index, [name, look]] of tiles.entries()) {
    for (const [other, otherLook] of tiles.slice(index + 1)) {
      expect(distance(look.mid, otherLook.mid), `${name} and ${other}`).toBeGreaterThan(0.25)
    }
  }
})

describe.each([...looks])("the %s tile", (_name, look) => {
  it("keeps its words readable across its still gradient", () => {
    for (let step = 0; step <= 100; step += 1) {
      expect(contrast(mix(look.mid, look.light, step / 100), look.ink)).toBeGreaterThanOrEqual(4.5)
    }
  })

  it("keeps its words readable wherever the flow runs under them, lit or not", () => {
    const [low, high] = labelRange(look)
    for (let step = 0; step <= 64; step += 1) {
      const ground = ramp(look, low + ((high - low) * step) / 64)
      for (let light = 0; light <= 8; light += 1) {
        const lit = mix(ground, look.sheen, ((BAND + GLOW) * light) / 8)
        expect(contrast(lit, look.ink)).toBeGreaterThanOrEqual(4.5)
      }
    }
  })

  it("still lets the flow move round its words", () => {
    const [low, high] = labelRange(look)
    expect(high - low).toBeGreaterThanOrEqual(0.5)
  })
})
