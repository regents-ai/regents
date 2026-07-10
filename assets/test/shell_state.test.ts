import {describe, expect, it} from "vitest"

import {
  reconcileShellState,
  shellDestinationChanged,
  type ShellState,
} from "../js/shell_state"

const state = (overrides: Partial<ShellState> = {}): ShellState => ({
  routeId: "app",
  destination: "/app",
  menuOpen: false,
  presentation: "none",
  supportsPresentation: false,
  formationPanel: "none",
  supportsFormationPanel: false,
  ...overrides,
})

describe("shell state restoration", () => {
  it("preserves presentation from cached remount state and resets outside Techtree", () => {
    const firstTree = state({
      destination: "/techtree/genebench-pro-reference-lab",
      presentation: "list",
      supportsPresentation: true,
    })
    const remountedTree = state({
      destination: "/techtree/question-forge-metaskills",
      presentation: "map",
      supportsPresentation: true,
    })

    const afterRemount = reconcileShellState(firstTree, remountedTree)
    expect(afterRemount.presentation).toBe("list")

    const afterLeaving = reconcileShellState(afterRemount, state())
    expect(afterLeaving.presentation).toBe("none")

    const freshTree = state({
      destination: "/techtree/genebench-pro-reference-lab",
      presentation: "map",
      supportsPresentation: true,
    })
    expect(reconcileShellState(afterLeaving, freshTree).presentation).toBe("map")
  })

  it("preserves List when a tree name changes the destination", () => {
    const current = state({
      routeId: "techtree_tree",
      destination: "/techtree/genebench-pro-reference-lab",
      menuOpen: true,
      presentation: "list",
      supportsPresentation: true,
    })
    const incoming = state({
      routeId: "techtree_tree",
      destination: "/techtree/question-forge-metaskills",
      presentation: "map",
      supportsPresentation: true,
    })

    expect(reconcileShellState(current, incoming)).toEqual({
      ...incoming,
      menuOpen: false,
      presentation: "list",
    })
  })

  it("uses Map on the first visit to a tree", () => {
    const incoming = state({
      routeId: "techtree_tree",
      destination: "/techtree/genebench-pro-reference-lab",
      presentation: "map",
      supportsPresentation: true,
    })

    expect(reconcileShellState(state(), incoming).presentation).toBe("map")
  })

  it("preserves Formation panel selection across same-destination patches", () => {
    const current = state({
      routeId: "formation",
      destination: "/formation",
      formationPanel: "billing",
      supportsFormationPanel: true,
    })
    const incoming = state({
      routeId: "formation",
      destination: "/formation",
      formationPanel: "overview",
      supportsFormationPanel: true,
    })

    expect(reconcileShellState(current, incoming).formationPanel).toBe("billing")
  })

  it("closes the menu and resets local state outside its contexts", () => {
    const current = state({
      routeId: "techtree_tree",
      destination: "/techtree/genebench-pro-reference-lab",
      menuOpen: true,
      presentation: "list",
      supportsPresentation: true,
    })

    expect(reconcileShellState(current, state())).toEqual(state())
  })

  it("requests top scroll only when the actual destination changes", () => {
    const current = state({routeId: "regent_profile", destination: "/regents/one"})

    expect(shellDestinationChanged(current, state({routeId: "regent_profile", destination: "/regents/two"}))).toBe(true)
    expect(shellDestinationChanged(current, state({routeId: "regent_profile", destination: "/regents/one"}))).toBe(false)
  })
})
