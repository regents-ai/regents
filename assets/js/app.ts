import "../css/app.css"

import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ash_platform"

import {composeHooks, type Hook} from "./hook_composition"
import {
  reconcileShellState,
  shellDestinationChanged,
  type ShellState,
} from "./shell_state"
import {applyTheme, isThemeChoice, readTheme, type ThemeChoice} from "./theme"

type ShellHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
  shellState?: ShellState
  restoreState?: () => void
}

let cachedShellState: ShellState | undefined

const shellBehavior: Hook = {
  mounted(this: ShellHook) {
    const shell = this.el
    const root = document.documentElement
    const scroller = shell.querySelector<HTMLElement>("#app-shell-scroller")
    const colorPreference = window.matchMedia("(prefers-color-scheme: dark)")
    const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)")

    const initialState: ShellState = {
      routeId: shell.dataset.routeId ?? "",
      destination: shell.dataset.destination ?? "",
      menuOpen: shell.dataset.menuOpen === "true",
      presentation: shell.dataset.presentation ?? "none",
      supportsPresentation: shell.querySelectorAll("[data-tree-presentation]").length > 0,
      formationPanel: shell.dataset.formationPanel ?? "none",
      supportsFormationPanel:
        shell.querySelectorAll("[data-formation-panel-choice]").length > 0,
    }
    this.shellState = cachedShellState
      ? reconcileShellState(cachedShellState, initialState)
      : initialState

    const setTheme = (choice: ThemeChoice) =>
      applyTheme(root, localStorage, choice, colorPreference.matches)

    const setMotion = () => {
      root.dataset.reducedMotion = motionPreference.matches ? "true" : "false"
    }

    const closeMenu = () => {
      if (this.shellState) this.shellState.menuOpen = false
      this.restoreState?.()
    }

    this.restoreState = () => {
      const state = this.shellState
      if (!state) return

      shell.dataset.menuOpen = String(state.menuOpen)
      shell.dataset.presentation = state.presentation
      shell.dataset.formationPanel = state.formationPanel
      cachedShellState = state
      shell
        .querySelector<HTMLButtonElement>("#mobile-menu-button")
        ?.setAttribute("aria-expanded", String(state.menuOpen))
      shell.querySelectorAll<HTMLAnchorElement>("[data-tree-presentation]").forEach(link => {
        link.setAttribute(
          "aria-pressed",
          String(
            link.dataset.treePath === state.destination &&
              link.dataset.treePresentation === state.presentation,
          ),
        )
      })
      shell
        .querySelectorAll<HTMLButtonElement>("[data-formation-panel-choice]")
        .forEach(button => {
          button.setAttribute(
            "aria-pressed",
            String(button.dataset.formationPanelChoice === state.formationPanel),
          )
        })
    }

    const onClick = (event: Event) => {
      const target = event.target instanceof Element ? event.target : null
      const themeButton = target?.closest<HTMLElement>("[data-theme-choice]")
      const presentationLink = target?.closest<HTMLAnchorElement>("[data-tree-presentation]")
      const formationPanelButton = target?.closest<HTMLButtonElement>(
        "[data-formation-panel-choice]",
      )
      const themeChoice = themeButton?.dataset.themeChoice ?? null

      if (isThemeChoice(themeChoice)) {
        setTheme(themeChoice)
      }

      if (target?.closest("#mobile-menu-button")) {
        if (this.shellState) this.shellState.menuOpen = !this.shellState.menuOpen
        this.restoreState?.()
      }

      if (presentationLink) {
        const presentation = presentationLink.dataset.treePresentation
        const treePath = presentationLink.dataset.treePath
        if (this.shellState && presentation) this.shellState.presentation = presentation
        this.restoreState?.()
        if (treePath === this.shellState?.destination) event.preventDefault()
      }

      if (formationPanelButton) {
        const panel = formationPanelButton.dataset.formationPanelChoice
        if (this.shellState && panel) this.shellState.formationPanel = panel
        this.restoreState?.()
      }

      if (target?.closest("#shell-sidebar a")) closeMenu()
    }

    const onKeydown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && shell.dataset.menuOpen === "true") {
        closeMenu()
        shell.querySelector<HTMLButtonElement>("#mobile-menu-button")?.focus()
      }
    }

    const onColorChange = () => {
      if (readTheme(localStorage) === "system") setTheme("system")
    }

    shell.addEventListener("click", onClick)
    shell.addEventListener("keydown", onKeydown)
    colorPreference.addEventListener("change", onColorChange)
    motionPreference.addEventListener("change", setMotion)
    setTheme(readTheme(localStorage))
    setMotion()
    this.restoreState()
    scroller?.scrollTo({top: 0})
    shell.dataset.behaviorReady = "true"

    this.cleanup = () => {
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("keydown", onKeydown)
      colorPreference.removeEventListener("change", onColorChange)
      motionPreference.removeEventListener("change", setMotion)
    }
  },

  updated(this: ShellHook) {
    const incoming = {
      routeId: this.el.dataset.routeId ?? "",
      destination: this.el.dataset.destination ?? "",
      presentation: this.el.dataset.presentation ?? "none",
      supportsPresentation: this.el.querySelectorAll("[data-tree-presentation]").length > 0,
      formationPanel: this.el.dataset.formationPanel ?? "none",
      supportsFormationPanel:
        this.el.querySelectorAll("[data-formation-panel-choice]").length > 0,
    }

    const shouldScroll = this.shellState
      ? shellDestinationChanged(this.shellState, incoming)
      : false
    if (this.shellState) {
      this.shellState = reconcileShellState(this.shellState, incoming)
    }
    this.restoreState?.()
    this.el.dataset.behaviorReady = "true"
    if (shouldScroll) {
      this.el.querySelector<HTMLElement>("#app-shell-scroller")?.scrollTo({top: 0})
    }
  },

  destroyed(this: ShellHook) {
    this.cleanup?.()
  },
}

// Design composes presentation behavior here; the Ash-owned behavior remains first.
const designShellHook: Hook = {}
const hooks = {...colocatedHooks, ShellBehavior: composeHooks(shellBehavior, designShellHook)}
const csrfToken = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content

if (!csrfToken) throw new Error("Missing CSRF token")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

liveSocket.connect()
if (document.querySelector("meta[name='privy-app-id']")) {
  void import("./privy_bridge").then(({startPrivyBridge}) => startPrivyBridge())
}
window.liveSocket = liveSocket
