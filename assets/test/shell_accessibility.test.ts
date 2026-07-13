import {readFileSync} from "node:fs"
import {resolve} from "node:path"

import {beforeEach, describe, expect, it, vi} from "vitest"

type Hook = Record<string, ((...args: unknown[]) => unknown) | undefined>

const captured = vi.hoisted(() => ({hooks: {} as Record<string, Hook>}))

vi.mock("phoenix", () => ({Socket: class Socket {}}))
vi.mock("phoenix-colocated/ash_platform", () => ({hooks: {}}))
vi.mock("../js/auth_lazy", () => ({installAccountAuthLazyLoader: vi.fn()}))
vi.mock("../js/hooks/home_hero", () => ({HomeHero: {}}))
vi.mock("phoenix_live_view", () => ({
  LiveSocket: class LiveSocket {
    constructor(
      _path: string,
      _socket: unknown,
      options: {hooks: Record<string, Hook>},
    ) {
      captured.hooks = options.hooks
    }

    connect() {}
  },
}))

class FakeElement {
  dataset: Record<string, string> = {}
  disabled = false
  hidden = false
  inert = false
  open = false
  attributes = new Map<string, string>()
  focusCount = 0
  closestSelectors = new Set<string>()

  focus() {
    fakeDocument.activeElement = this
    this.focusCount += 1
  }

  closest(selector: string) {
    return selector
      .split(",")
      .some(candidate => this.closestSelectors.has(candidate.trim()))
      ? this
      : null
  }

  getAttribute(name: string) {
    return this.attributes.get(name) ?? null
  }

  setAttribute(name: string, value: string) {
    this.attributes.set(name, value)
  }

  removeAttribute(name: string) {
    this.attributes.delete(name)
  }
}

const fakeDocument = {
  activeElement: null as FakeElement | null,
  documentElement: new FakeElement(),
  querySelector(selector: string) {
    return selector === "meta[name='csrf-token']" ? {content: "csrf"} : null
  },
}

const fakeStorage = new Map<string, string>()

const fakeWindow = {
  liveSocket: undefined as unknown,
  matchMedia: () => ({
    matches: false,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  }),
  localStorage: {
    getItem: (key: string) => fakeStorage.get(key) ?? null,
    setItem: (key: string, value: string) => fakeStorage.set(key, value),
  },
}

vi.stubGlobal("Element", FakeElement)
vi.stubGlobal("HTMLElement", FakeElement)
vi.stubGlobal("document", fakeDocument)
vi.stubGlobal("window", fakeWindow)
vi.stubGlobal("localStorage", fakeWindow.localStorage)

await import("../js/app")

type Listener = (event: unknown) => void

function shellFixture() {
  const listeners = new Map<string, Listener>()
  const menuButton = new FakeElement()
  menuButton.closestSelectors.add("#mobile-menu-button")
  const firstLink = new FakeElement()
  const lastLink = new FakeElement()
  const navigationLink = new FakeElement()
  navigationLink.closestSelectors.add("#shell-sidebar a")
  const scrim = new FakeElement()
  scrim.closestSelectors.add("[data-shell-menu-scrim]")
  const appSelector = new FakeElement()
  const appSelectorLink = new FakeElement()
  appSelectorLink.closestSelectors.add("#app-selector-menu a")
  const scroller = Object.assign(new FakeElement(), {scrollTo: vi.fn()})
  const mapLink = new FakeElement()
  mapLink.dataset.treePath = "/techtree"
  mapLink.dataset.treePresentation = "map"
  mapLink.setAttribute("aria-current", "true")
  const listLink = new FakeElement()
  listLink.dataset.treePath = "/techtree"
  listLink.dataset.treePresentation = "list"
  const sidebar = Object.assign(new FakeElement(), {
    querySelectorAll: () => [firstLink, lastLink],
    contains: (element: unknown) => element === firstLink || element === lastLink,
  })
  const shell = Object.assign(new FakeElement(), {
    querySelector(selector: string) {
      if (selector === "#mobile-menu-button") return menuButton
      if (selector === "#shell-sidebar") return sidebar
      if (selector === "#app-shell-scroller") return scroller
      if (selector === "[data-shell-menu-scrim]") return scrim
      if (selector === "#app-selector") return appSelector
      return null
    },
    querySelectorAll(selector: string) {
      return selector === "[data-tree-presentation]" ? [mapLink, listLink] : []
    },
    addEventListener(type: string, listener: Listener) {
      listeners.set(type, listener)
    },
    removeEventListener(type: string) {
      listeners.delete(type)
    },
  })

  shell.dataset.routeId = "techtree"
  shell.dataset.destination = "/techtree"
  shell.dataset.menuOpen = "false"
  shell.dataset.presentation = "map"
  shell.dataset.formationPanel = "none"

  return {
    shell,
    menuButton,
    sidebar,
    scrim,
    appSelector,
    appSelectorLink,
    mapLink,
    listLink,
    scroller,
    firstLink,
    lastLink,
    navigationLink,
    click(target: FakeElement) {
      listeners.get("click")?.({target, preventDefault: vi.fn()})
    },
    keydown(key: string, options: {shiftKey?: boolean} = {}) {
      const preventDefault = vi.fn()
      listeners.get("keydown")?.({key, shiftKey: false, ...options, preventDefault})
      return preventDefault
    },
  }
}

describe("mobile shell navigation", () => {
  beforeEach(() => {
    fakeDocument.activeElement = null
    fakeStorage.clear()
  })

  it("focuses and contains the temporary menu while keeping the content inert", async () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    hook.mounted?.call(context)
    page.click(page.menuButton)
    await Promise.resolve()

    expect(page.shell.dataset.menuOpen).toBe("true")
    expect(page.menuButton.getAttribute("aria-expanded")).toBe("true")
    expect(page.scroller.inert).toBe(true)
    expect(page.scrim.hidden).toBe(false)
    expect(page.firstLink.focusCount).toBe(1)

    page.lastLink.focus()
    expect(page.keydown("Tab")).toHaveBeenCalledOnce()
    expect(fakeDocument.activeElement).toBe(page.firstLink)

    page.firstLink.focus()
    expect(page.keydown("Tab", {shiftKey: true})).toHaveBeenCalledOnce()
    expect(fakeDocument.activeElement).toBe(page.lastLink)

    hook.destroyed?.call(context)
    expect(page.scroller.inert).toBe(false)
  })

  it.each(["Escape", "scrim", "navigation"])(
    "closes on %s and restores the menu trigger",
    async reason => {
      const page = shellFixture()
      const hook = captured.hooks.ShellBehavior
      const context = {el: page.shell} as never

      hook.mounted?.call(context)
      page.click(page.menuButton)
      await Promise.resolve()

      if (reason === "Escape") page.keydown("Escape")
      if (reason === "scrim") page.click(page.scrim)
      if (reason === "navigation") page.click(page.navigationLink)

      expect(page.shell.dataset.menuOpen).toBe("false")
      expect(page.menuButton.getAttribute("aria-expanded")).toBe("false")
      expect(page.scroller.inert).toBe(false)
      expect(page.scrim.hidden).toBe(true)
      expect(page.menuButton.focusCount).toBeGreaterThan(0)
    },
  )

  it("closes the app selector after a selection and after a route patch", () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    hook.mounted?.call(context)
    page.appSelector.open = true
    page.appSelector.setAttribute("open", "")
    page.click(page.appSelectorLink)
    expect(page.appSelector.open).toBe(false)
    expect(page.appSelector.getAttribute("open")).toBeNull()

    page.appSelector.open = true
    page.appSelector.setAttribute("open", "")
    hook.updated?.call(context)
    expect(page.appSelector.open).toBe(false)
    expect(page.appSelector.getAttribute("open")).toBeNull()
  })

  it("restores one selected Techtree presentation with aria-current", () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    hook.mounted?.call(context)
    expect(page.mapLink.getAttribute("aria-current")).toBe("true")
    expect(page.listLink.getAttribute("aria-current")).toBeNull()
    expect(page.mapLink.getAttribute("aria-pressed")).toBeNull()
    expect(page.listLink.getAttribute("aria-pressed")).toBeNull()
  })
})

describe("shell material contract", () => {
  const cssRoot = resolve(import.meta.dirname, "../css")

  it("loads canonical material before shell and preserves existing page/status imports", () => {
    const appCss = readFileSync(resolve(cssRoot, "app.css"), "utf8")
    expect(appCss).toMatch(
      /^@import "\.\/tokens\/material\.css";\n@import "\.\/components\/shell\.css";\n@import "\.\/pages\/home\.css";\n@import "\.\/pages\/settings\.css";\n@import "\.\/components\/account_auth_status\.css";/,
    )
  })

  it("keeps structural material square, responsive, and free of fabricated artwork", () => {
    const material = readFileSync(resolve(cssRoot, "tokens/material.css"), "utf8")
    const shell = readFileSync(resolve(cssRoot, "components/shell.css"), "utf8")

    expect(material).toContain("--radius-shell: var(--radius-sm)")
    expect(material).toContain(":root:not([data-theme])")
    expect(shell).toContain("min-height: 2.75rem")
    expect(shell).toContain("100dvh")
    expect(shell).toContain("prefers-reduced-transparency: reduce")
    expect(shell).toContain("prefers-contrast: more")
    expect(shell).toContain('a[data-tree-presentation][aria-current="true"]')
    expect(shell).toMatch(/body #route-content[\s\S]*var\(--material-fill\) padding-box/)
    expect(shell).not.toMatch(/url\([^)]*backgrounds\//)
    expect(shell).not.toMatch(/border-radius:\s*(?:[5-9]|\d{2,})px/)
  })
})
