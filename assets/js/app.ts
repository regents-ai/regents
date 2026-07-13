import "../css/app.css"

import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ash_platform"

import {composeHooks, type Hook} from "./hook_composition"
import {installAccountAuthLazyLoader} from "./auth_lazy"
import {
  reconcileShellState,
  shellDestinationChanged,
  type ShellState,
} from "./shell_state"
import {applyTheme, isThemeChoice, readTheme, type ThemeChoice} from "./theme"
import {HomeHero} from "./hooks/home_hero"

type ShellHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
  shellState?: ShellState
  restoreState?: () => void
}

let cachedShellState: ShellState | undefined

function closeAppSelector(shell: HTMLElement): void {
  const appSelector = shell.querySelector<HTMLDetailsElement>("#app-selector")
  if (!appSelector) return
  appSelector.open = false
  appSelector.removeAttribute("open")
}

const shellBehavior: Hook = {
  mounted(this: ShellHook) {
    const shell = this.el
    const root = document.documentElement
    const scroller = shell.querySelector<HTMLElement>("#app-shell-scroller")
    const menuButton = shell.querySelector<HTMLButtonElement>("#mobile-menu-button")
    const sidebar = shell.querySelector<HTMLElement>("#shell-sidebar")
    const menuScrim = shell.querySelector<HTMLElement>("[data-shell-menu-scrim]")
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

    const menuFocusables = () =>
      Array.from(
        sidebar?.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ) ?? [],
      ).filter(element => !element.hidden && !element.inert)

    const syncMenuAccessibility = (focusMenu = false, restoreFocus = false) => {
      const menuOpen = this.shellState?.menuOpen === true
      if (scroller) scroller.inert = menuOpen
      if (menuScrim) menuScrim.hidden = !menuOpen

      if (focusMenu && menuOpen) {
        const [first] = menuFocusables()
        ;(first ?? sidebar)?.focus()
      }

      if (restoreFocus && !menuOpen) menuButton?.focus()
    }

    const closeMenu = (restoreFocus = true) => {
      if (this.shellState) this.shellState.menuOpen = false
      this.restoreState?.()
      syncMenuAccessibility(false, restoreFocus)
    }

    this.restoreState = () => {
      const state = this.shellState
      if (!state) return

      shell.dataset.menuOpen = String(state.menuOpen)
      shell.dataset.presentation = state.presentation
      shell.dataset.formationPanel = state.formationPanel
      cachedShellState = state
      menuButton?.setAttribute("aria-expanded", String(state.menuOpen))
      syncMenuAccessibility()
      shell.querySelectorAll<HTMLAnchorElement>("[data-tree-presentation]").forEach(link => {
        const selected =
          link.dataset.treePath === state.destination &&
          link.dataset.treePresentation === state.presentation
        if (selected) link.setAttribute("aria-current", "true")
        else link.removeAttribute("aria-current")
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
        syncMenuAccessibility(this.shellState?.menuOpen === true, true)
      }

      if (target?.closest("[data-shell-menu-scrim], [data-shell-menu-close]")) closeMenu()
      if (target?.closest("#app-selector-menu a")) closeAppSelector(shell)

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
        return
      }

      if (event.key === "Tab" && shell.dataset.menuOpen === "true") {
        const focusables = menuFocusables()
        const first = focusables.at(0)
        const last = focusables.at(-1)
        if (!first || !last) return

        if (!sidebar?.contains(document.activeElement)) {
          event.preventDefault()
          ;(event.shiftKey ? last : first).focus()
        } else if (event.shiftKey && document.activeElement === first) {
          event.preventDefault()
          last.focus()
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault()
          first.focus()
        }
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
      if (scroller) scroller.inert = false
      if (menuScrim) menuScrim.hidden = true
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
    closeAppSelector(this.el)
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
const hooks = {
  ...colocatedHooks,
  HomeHero,
  ShellBehavior: composeHooks(shellBehavior, designShellHook),
}
const csrfToken = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content

if (!csrfToken) throw new Error("Missing CSRF token")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

liveSocket.connect()
installAccountAuthLazyLoader()
window.liveSocket = liveSocket
