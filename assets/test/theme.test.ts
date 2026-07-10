import {describe, expect, it} from "vitest"

import {applyTheme, readTheme, resolveTheme, themeStorageKey} from "../js/theme"

describe("theme persistence", () => {
  it("resolves System from the current preference without losing the System choice", () => {
    const root = {dataset: {} as DOMStringMap}
    const stored = new Map<string, string>()
    const storage = {
      getItem: (key: string) => stored.get(key) ?? null,
      setItem: (key: string, value: string) => stored.set(key, value),
    }

    applyTheme(root, storage, "system", true)

    expect(root.dataset.theme).toBe("dark")
    expect(root.dataset.themeChoice).toBe("system")
    expect(readTheme(storage)).toBe("system")
    expect(stored.get(themeStorageKey)).toBe("system")
  })

  it("uses explicit Light and Dark choices regardless of the system preference", () => {
    expect(resolveTheme("light", true)).toBe("light")
    expect(resolveTheme("dark", false)).toBe("dark")
  })

  it("treats unknown persisted values as System", () => {
    expect(readTheme({getItem: () => "sepia"})).toBe("system")
  })
})
