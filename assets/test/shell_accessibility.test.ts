import {readFileSync} from "node:fs"

import {beforeEach, describe, expect, it, vi} from "vitest"

type Hook = Record<string, ((...args: unknown[]) => unknown) | undefined>

const captured = vi.hoisted(() => ({hooks: {} as Record<string, Hook>}))

vi.mock("phoenix", () => ({Socket: class Socket {}}))
vi.mock("phoenix-colocated/ash_platform", () => ({hooks: {}}))
vi.mock("../js/auth_lazy", () => ({installAccountAuthLazyLoader: vi.fn()}))
vi.mock("../js/hooks/home_hero", () => ({HomeHero: {}}))
vi.mock("../js/hooks/motion", () => ({ShellMotion: {}}))
vi.mock("../js/hooks/techtree_camera", () => ({TechtreeCamera: {}}))
vi.mock("../js/hooks/voxel", () => ({VoxelDelight: {}}))
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
  parentElement: {id?: string} | null = null
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
    if (name === "open") this.open = true
  }

  removeAttribute(name: string) {
    this.attributes.delete(name)
    if (name === "open") this.open = false
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
  addEventListener: vi.fn(),
  removeEventListener: vi.fn(),
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
vi.stubGlobal("MouseEvent", class MouseEvent {})
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
  firstLink.closestSelectors.add("[data-shell-menu-close]")
  const lastLink = new FakeElement()
  const navigationLink = new FakeElement()
  navigationLink.closestSelectors.add("#shell-sidebar a")
  const scrim = new FakeElement()
  scrim.closestSelectors.add("[data-shell-menu-scrim]")
  const appSelector = new FakeElement()
  appSelector.parentElement = {id: "app-selector"}
  const appSelectorLink = new FakeElement()
  appSelectorLink.closestSelectors.add("#app-selector a")
  appSelectorLink.closest = (selector: string) => {
    if (selector === "details") return appSelector
    return selector
      .split(",")
      .some(candidate => appSelectorLink.closestSelectors.has(candidate.trim()))
      ? appSelectorLink
      : null
  }
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
      if (selector === "#app-selector > details") return appSelector
      return null
    },
    querySelectorAll(selector: string) {
      if (selector === "[data-tree-presentation]") return [mapLink, listLink]
      if (selector.includes("details[open]")) return appSelector.open ? [appSelector] : []
      return []
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
    fakeDocument.documentElement.dataset = {}
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
    expect(page.scrim.hidden).toBe(true)
    expect(page.shell.dataset.menuOpen).toBe("false")
  })

  it.each(["Escape", "scrim", "navigation", "explicit close"])(
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
      if (reason === "explicit close") page.click(page.firstLink)

      expect(page.shell.dataset.menuOpen).toBe("false")
      expect(page.menuButton.getAttribute("aria-expanded")).toBe("false")
      expect(page.scroller.inert).toBe(false)
      expect(page.scrim.hidden).toBe(true)
      expect(page.menuButton.focusCount).toBeGreaterThan(0)
    },
  )

  it("closes the app selector after a selection", () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    hook.mounted?.call(context)
    page.appSelector.open = true
    page.appSelector.setAttribute("open", "")
    page.click(page.appSelectorLink)
    expect(page.appSelector.open).toBe(false)
    expect(page.appSelector.getAttribute("open")).toBeNull()
  })

  it("preserves an open app selector across a same-destination route patch", () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    hook.mounted?.call(context)
    page.appSelector.setAttribute("open", "")
    hook.beforeUpdate?.call(context)
    page.appSelector.removeAttribute("open")
    hook.updated?.call(context)

    expect(page.appSelector.open).toBe(true)
    expect(page.appSelector.getAttribute("open")).toBe("")
  })

  it("closes the drawer and app selector when the destination updates", async () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    hook.mounted?.call(context)
    page.click(page.menuButton)
    await Promise.resolve()
    page.appSelector.setAttribute("open", "")
    hook.beforeUpdate?.call(context)
    page.appSelector.removeAttribute("open")
    page.shell.dataset.destination = "/formation"
    hook.updated?.call(context)

    expect(page.shell.dataset.menuOpen).toBe("false")
    expect(page.scroller.inert).toBe(false)
    expect(page.scrim.hidden).toBe(true)
    expect(page.menuButton.focusCount).toBeGreaterThan(0)
    expect(page.appSelector.open).toBe(false)
    expect(page.appSelector.getAttribute("open")).toBeNull()
  })

  it("restores one selected Techtree presentation with aria-pressed", () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    hook.mounted?.call(context)
    expect(page.mapLink.getAttribute("aria-current")).toBe("true")
    expect(page.listLink.getAttribute("aria-current")).toBeNull()
    expect(page.mapLink.getAttribute("aria-pressed")).toBe("true")
    expect(page.listLink.getAttribute("aria-pressed")).toBe("false")
  })

  it("[U2] reconciles RegentUI brand from authoritative shell app patches", () => {
    const page = shellFixture()
    const hook = captured.hooks.ShellBehavior
    const context = {el: page.shell} as never

    page.shell.dataset.app = "techtree"
    hook.mounted?.call(context)
    expect(fakeDocument.documentElement.dataset.brand).toBe("techtree")

    page.shell.dataset.app = "autolaunch"
    hook.updated?.call(context)
    expect(fakeDocument.documentElement.dataset.brand).toBe("autolaunch")

    page.shell.dataset.app = "formation"
    hook.updated?.call(context)
    expect(fakeDocument.documentElement.dataset.brand).toBe("platform")
  })
})

describe("shell material contract", () => {
  const readCss = (path: string) =>
    new TextDecoder().decode(readFileSync(new URL(path, import.meta.url)))

  it("[U1][U4] loads RegentUI before shell and preserves existing page/status imports", () => {
    const appCss = readCss("../css/app.css")
    expect(appCss).toMatch(
      /^@import "\.\.\/\.\.\/\.\.\/design-system\/regent_ui\/assets\/css\/regent\.css";\n@import "\.\/tokens\/material\.css";\n@import "\.\/components\/shell\.css";\n@import "\.\/components\/comment_ledger\.css";\n@import "\.\/pages\/home\.css";[\s\S]*@import "\.\/pages\/techtree\.css";/,
    )
  })

  it("[U4][U6] keeps structural material square, responsive, and free of fabricated artwork", () => {
    const material = readCss("../css/tokens/material.css")
    const shell = readCss("../css/components/shell.css")

    expect(material).toContain("--material-radius: 4px")
    expect(material).toContain("--material-fill: var(--glass-panel-bg)")
    expect(material).toContain("--material-fill-strong: var(--glass-shell-bg)")
    expect(material).toContain("--material-stroke: var(--glass-panel-border)")
    expect(material).toContain("--material-blur: var(--glass-blur)")
    expect(material).toContain("--material-shadow: var(--glass-panel-shadow)")
    expect(shell).toContain("min-height: 2.75rem")
    expect(shell).toContain("100dvh")
    expect(shell).toContain("prefers-reduced-transparency: reduce")
    expect(shell).toContain('#shell-sidebar [aria-pressed="true"]')
    expect(shell).toContain(".shell-menu-scrim")
    expect(shell).toMatch(/\.shell-material[\s\S]*var\(--material-fill\) padding-box/)
    expect(shell).not.toMatch(/url\([^)]*backgrounds\//)
    expect(shell).not.toMatch(/border-radius:\s*(?:[5-9]|\d{2,})px/)
  })
})
