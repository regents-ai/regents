import {readFileSync} from "node:fs"
import {gzipSync} from "node:zlib"

import {describe, expect, it} from "vitest"

const builtAsset = (name: string) => readFileSync(new URL(`../../priv/static/assets/js/${name}`, import.meta.url))

describe("built asset budgets", () => {
  it("keeps JavaScript at or below 175 KiB gzip", () => {
    expect(gzipSync(builtAsset("app.js")).byteLength).toBeLessThanOrEqual(175 * 1024)
  })

  it("keeps CSS at or below 60 KiB gzip", () => {
    expect(gzipSync(builtAsset("app.css")).byteLength).toBeLessThanOrEqual(60 * 1024)
  })
})
