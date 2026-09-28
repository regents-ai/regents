import "../css/app.css"
import "../vendor/regent_ui/blog.mjs"

import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/regents"

import {composeHooks, type Hook} from "./hook_composition"
import {
  browserCsrfToken,
  holdSocketDuringCookieRotation,
  installAccountAuthLazyLoader,
  installCrossTabCsrf,
  retireRefusedSession,
  type PinnedSocket,
} from "./auth_lazy"
import {
  brandForShellApp,
  reconcileShellState,
  shellDestinationChanged,
  type ShellState,
} from "./shell_state"
import {HolographicCard} from "./hooks/holographic_card"
import {HomePrism} from "./hooks/home_prism"
import {HomeTokenMenu} from "./hooks/home_token_menu"
import {InfiniteScroll} from "./hooks/infinite_scroll"
import {MotionCount, MotionList} from "./hooks/motion/moments"
import {MotionTabs, ShellViews} from "./hooks/motion/reveals"
import {FigureFlash} from "./hooks/figure_flash"
import {InfoDialog} from "./hooks/info_dialog"
import {OnchainSteps} from "./hooks/onchain_steps"
import {mountMotion} from "./motion"
import {installCopyButtons} from "./copy_buttons"
import {installPublicTools} from "./public_tools"
import {VerifiedConnections} from "./hooks/verified_connections"

type ShellHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
  shellState?: ShellState
  restoreState?: () => void
  openPopoverIds?: string[]
  destinationBeforeUpdate?: string
}

let cachedShellState: ShellState | undefined

// The colour theme. Until the visitor chooses, the page carries no theme and the
// shared colours follow the device, dark unless it asks for light. A press
// chooses the opposite of the theme showing and writes it to the cookie the
// server reads, so the next page is drawn in it. The switch names the theme
// showing by itself, so nothing here rewrites its words.
const themeCookie = "regent_theme"
const themeMaxAge = 60 * 60 * 24 * 365
type Theme = "light" | "dark"
const themeColors: Record<Theme, string> = {dark: "#161616", light: "#e5e3d2"}

function chosenTheme(): Theme | undefined {
  const prefix = `${themeCookie}=`
  const value = document.cookie
    .split("; ")
    .find(cookie => cookie.startsWith(prefix))
    ?.slice(prefix.length)

  return value === "light" || value === "dark" ? value : undefined
}

function showingTheme(): Theme {
  const theme = document.documentElement.dataset.theme
  if (theme === "light" || theme === "dark") return theme
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"
}

// The public crown is a dark-only composition, not a change to visitor preference.
const homeThemeLocked = () => window.location.pathname === "/"

// Live navigation keeps the document, so each page restates its theme: dark on
// the homepage, the visitor's choice elsewhere, or none so the device decides.
function syncTheme() {
  const root = document.documentElement
  const theme = homeThemeLocked() ? "dark" : chosenTheme()
  root.dataset.homeThemeLocked = String(homeThemeLocked())
  if (theme) root.dataset.theme = theme
  else delete root.dataset.theme
  document.querySelector('meta[name="color-scheme"]')?.setAttribute("content", theme ?? "dark light")
  document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]').forEach(meta => {
    meta.content = themeColors[theme ?? (meta.media.includes("light") ? "light" : "dark")]
  })
}

document.addEventListener("click", event => {
  if (!(event.target instanceof Element) || !event.target.closest("[data-theme-toggle]")) return
  const theme: Theme = showingTheme() === "dark" ? "light" : "dark"
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie = `${themeCookie}=${theme}; Path=/; Max-Age=${themeMaxAge}; SameSite=Lax${secure}`
  syncTheme()
})

window.addEventListener("phx:page-loading-stop", syncTheme)
window.addEventListener("popstate", syncTheme)
window.addEventListener("pageshow", syncTheme)

const shellBehavior: Hook = {
  mounted(this: ShellHook) {
    const shell = this.el
    const root = document.documentElement

    const initialState: ShellState = {
      routeId: shell.dataset.routeId ?? "",
      destination: shell.dataset.destination ?? "",
      menuOpen: shell.dataset.menuOpen === "true",
    }
    root.dataset.brand = brandForShellApp(shell.dataset.app)
    this.shellState = cachedShellState
      ? reconcileShellState(cachedShellState, initialState)
      : initialState

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
      cachedShellState = state
      menuButton()?.setAttribute("aria-expanded", String(state.menuOpen))
      syncMenuAccessibility()
    }

    const onClick = (event: Event) => {
      const target = event.target instanceof Element ? event.target : null

      if (target?.closest("#mobile-menu-button")) {
        if (this.shellState) this.shellState.menuOpen = !this.shellState.menuOpen
        this.restoreState?.()
        syncMenuAccessibility(this.shellState?.menuOpen === true, true)
      }

      if (target?.closest("[data-shell-menu-scrim], [data-shell-menu-close]")) {
        closeMenu()
      }

      if (target?.closest("#shell-sidebar a")) closeMenu()
      if (target?.closest("#account-menu a")) {
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

    const onHistoryNavigation = () => {
      scroller()?.scrollTo({top: 0})
    }

    shell.addEventListener("click", onClick)
    shell.addEventListener("keydown", onKeydown)
    window.addEventListener("popstate", onHistoryNavigation)
    this.restoreState()
    scroller()?.scrollTo({top: 0})
    shell.dataset.behaviorReady = "true"

    this.cleanup = () => {
      closeMenu(false)
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("keydown", onKeydown)
      window.removeEventListener("popstate", onHistoryNavigation)
    }
  },

  beforeUpdate(this: ShellHook) {
    this.destinationBeforeUpdate = this.el.dataset.destination ?? ""
    this.openPopoverIds = [
      ...this.el.querySelectorAll<HTMLDetailsElement>("#account-control details[open]"),
    ]
      .map(details => details.parentElement?.id)
      .filter((id): id is string => Boolean(id))
  },

  updated(this: ShellHook) {
    document.documentElement.dataset.brand = brandForShellApp(this.el.dataset.app)
    const incoming = {
      routeId: this.el.dataset.routeId ?? "",
      destination: this.el.dataset.destination ?? "",
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
const showcaseHooks = window.location.pathname.startsWith("/showcase")
  ? (await import("./showcase")).hooks : {}
const hooks = {
  ...showcaseHooks,
  ...colocatedHooks,
  FigureFlash,
  HolographicCard,
  HomePrism,
  HomeTokenMenu,
  InfiniteScroll,
  InfoDialog,
  MotionCount,
  MotionList,
  MotionTabs,
  OnchainSteps,
  ShellBehavior: composeHooks(shellBehavior, ShellViews),
  VerifiedConnections,
}
if (!browserCsrfToken()) throw new Error("Missing CSRF token")

// Sign in and refresh renew the session and rotate its CSRF state, so every
// connection and reconnection reads the token the browser holds now.
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({_csrf_token: browserCsrfToken()}),
  hooks,
})

// Installed before the first connect, so even the page's opening attempt is
// subject to the barrier. `types.d.ts` describes only the LiveSocket surface
// this application calls, so the transport entry point is named at the cast.
holdSocketDuringCookieRotation(liveSocket.getSocket() as PinnedSocket)
// Started before the first connect, so a page rendered for a refused cookie
// holds its socket until that cookie is retired.
void retireRefusedSession()
liveSocket.connect()
installAccountAuthLazyLoader()
installPublicTools()
installCrossTabCsrf()
installCopyButtons()
mountMotion(document)
window.liveSocket = liveSocket
