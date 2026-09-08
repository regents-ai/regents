import {describe, expect, it} from "vitest"

import {
  brandForShellApp,
  reconcileShellState,
  shellDestinationChanged,
  type ShellState,
} from "../js/shell_state"

const state = (overrides: Partial<ShellState> = {}): ShellState => ({
  routeId: "app",
  destination: "/app",
  menuOpen: false,
  ...overrides,
})

describe("shell brand reconciliation", () => {
  it("[U2] maps shell applications to the canonical RegentUI brands", () => {
    expect(brandForShellApp("autolaunch")).toBe("platform")
    expect(brandForShellApp("formation")).toBe("platform")
    expect(brandForShellApp(undefined)).toBe("platform")
  })
})

describe("shell state restoration", () => {
  it("closes the menu and resets local state outside its contexts", () => {
    const current = state({
      routeId: "autolaunch_auction",
      destination: "/autolaunch/auctions/one",
      menuOpen: true,
    })

    expect(reconcileShellState(current, state())).toEqual(state())
  })

  it("requests top scroll only when the actual destination changes", () => {
    const current = state({routeId: "regent_profile", destination: "/regents/one"})

    expect(
      shellDestinationChanged(current, state({routeId: "regent_profile", destination: "/regents/two"})),
    ).toBe(true)
    expect(
      shellDestinationChanged(current, state({routeId: "regent_profile", destination: "/regents/one"})),
    ).toBe(false)
  })
})
