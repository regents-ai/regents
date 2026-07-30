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
import {AutolaunchBidWallet} from "./hooks/autolaunch_bid_wallet"
import {ShellMotion} from "./hooks/motion"
import {StakeWallet} from "./hooks/stake_wallet"
import {RedemptionWallet} from "./hooks/redemption_wallet"
import {TechtreeCamera} from "./hooks/techtree_camera"
import {VoxelDelight} from "./hooks/voxel"

type ShellHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
  shellState?: ShellState
  restoreState?: () => void
  openPopoverIds?: string[]
  destinationBeforeUpdate?: string
}

let cachedShellState: ShellState | undefined

const shellBehavior: Hook = {
  mounted(this: ShellHook) {
    const shell = this.el
    const root = document.documentElement
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
      shell.dataset.reducedMotion = motionPreference.matches ? "true" : "false"
    }

    const menuButton = () =>
      shell.querySelector<HTMLButtonElement>("#mobile-menu-button")
    const sidebar = () => shell.querySelector<HTMLElement>("#shell-sidebar")
    const scroller = () => shell.querySelector<HTMLElement>("#app-shell-scroller")
    const menuScrim = () =>
      shell.querySelector<HTMLButtonElement>("[data-shell-menu-scrim]")
    const menuFocusables = () =>
      Array.from(
        sidebar()?.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ) ?? [],
      ).filter(element => !element.hidden && !element.inert)

    const syncMenuAccessibility = (focusMenu = false, restoreFocus = false) => {
      const menuOpen = this.shellState?.menuOpen === true
      const currentScroller = scroller()
      const currentScrim = menuScrim()
      if (currentScroller) currentScroller.inert = menuOpen
      if (currentScrim) currentScrim.hidden = !menuOpen

      if (focusMenu && menuOpen) {
        const [first] = menuFocusables()
        ;(first ?? sidebar())?.focus()
      }

      if (restoreFocus && !menuOpen) menuButton()?.focus()
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
      menuButton()?.setAttribute("aria-expanded", String(state.menuOpen))
      syncMenuAccessibility()
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
      shell.dataset.motionSource =
        event instanceof MouseEvent && event.detail === 0 ? "keyboard" : "pointer"
      const themeButton = target?.closest<HTMLElement>("[data-theme-choice]")
      const presentationLink = target?.closest<HTMLAnchorElement>("[data-tree-presentation]")
      const formationPanelButton = target?.closest<HTMLButtonElement>(
        "[data-formation-panel-choice]",
      )
      const themeChoice = themeButton?.dataset.themeChoice ?? null

      if (isThemeChoice(themeChoice)) {
        setTheme(themeChoice)
        themeButton?.closest("details")?.removeAttribute("open")
      }

      if (target?.closest("#mobile-menu-button")) {
        if (this.shellState) this.shellState.menuOpen = !this.shellState.menuOpen
        this.restoreState?.()
        syncMenuAccessibility(this.shellState?.menuOpen === true, true)
      }

      if (target?.closest("[data-shell-menu-scrim], [data-shell-menu-close]")) {
        closeMenu()
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
      if (target?.closest("#app-selector a, #account-menu a")) {
        target.closest("details")?.removeAttribute("open")
      }
    }

    const onKeydown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && shell.dataset.menuOpen === "true") {
        event.preventDefault()
        closeMenu()
        return
      }

      if (event.key === "Tab" && shell.dataset.menuOpen === "true") {
        const focusables = menuFocusables()
        const first = focusables.at(0)
        const last = focusables.at(-1)
        const currentSidebar = sidebar()

        if (!first || !last) {
          event.preventDefault()
          currentSidebar?.focus()
        } else if (!currentSidebar?.contains(document.activeElement)) {
          event.preventDefault()
          ;(event.shiftKey ? last : first).focus()
        } else if (event.shiftKey && document.activeElement === first) {
          event.preventDefault()
          last.focus()
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault()
          first.focus()
        }
        return
      }

      if (event.key === "Escape") {
        const openDetails = [...shell.querySelectorAll<HTMLDetailsElement>("details[open]")].at(-1)

        if (openDetails) {
          openDetails.removeAttribute("open")
          openDetails.querySelector<HTMLElement>("summary")?.focus()
          event.preventDefault()
          return
        }
      }

    }

    const onColorChange = () => {
      if (readTheme(localStorage) === "system") setTheme("system")
    }

    const onHistoryNavigation = () => {
      shell.dataset.motionSource = "keyboard"
      scroller()?.scrollTo({top: 0})
    }

    shell.addEventListener("click", onClick)
    shell.addEventListener("keydown", onKeydown)
    colorPreference.addEventListener("change", onColorChange)
    motionPreference.addEventListener("change", setMotion)
    window.addEventListener("popstate", onHistoryNavigation)
    setTheme(readTheme(localStorage))
    setMotion()
    this.restoreState()
    scroller()?.scrollTo({top: 0})
    shell.dataset.behaviorReady = "true"

    this.cleanup = () => {
      closeMenu(false)
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("keydown", onKeydown)
      colorPreference.removeEventListener("change", onColorChange)
      motionPreference.removeEventListener("change", setMotion)
      window.removeEventListener("popstate", onHistoryNavigation)
    }
  },

  beforeUpdate(this: ShellHook) {
    this.destinationBeforeUpdate = this.el.dataset.destination ?? ""
    this.openPopoverIds = [
      ...this.el.querySelectorAll<HTMLDetailsElement>(
        "#app-selector details[open], #account-control details[open], #theme-control details[open]",
      ),
    ]
      .map(details => details.parentElement?.id)
      .filter((id): id is string => Boolean(id))
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

    const menuWasOpen = this.shellState?.menuOpen === true
    const shouldScroll = this.shellState
      ? shellDestinationChanged(this.shellState, incoming)
      : false
    if (this.shellState) {
      this.shellState = reconcileShellState(this.shellState, incoming)
    }
    this.restoreState?.()
    if (menuWasOpen && this.shellState?.menuOpen === false) {
      this.el.querySelector<HTMLButtonElement>("#mobile-menu-button")?.focus()
    }
    if (this.destinationBeforeUpdate === incoming.destination) {
      this.openPopoverIds?.forEach(id => {
        this.el.querySelector<HTMLDetailsElement>(`#${id} > details`)?.setAttribute("open", "")
      })
    }
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
const designShellHook: Hook = composeHooks(ShellMotion, VoxelDelight)
const hooks = {
  ...colocatedHooks,
  AutolaunchBidWallet,
  HomeHero,
  ShellBehavior: composeHooks(shellBehavior, designShellHook),
  RedemptionWallet,
  StakeWallet,
  TechtreeCamera,
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
