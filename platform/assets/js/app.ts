import "../css/app.css"
import "../vendor/regent_ui/blog.mjs"

import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ash_platform"

import {composeHooks, type Hook} from "./hook_composition"
import {
  browserCsrfToken,
  holdSocketDuringCookieRotation,
  installAccountAuthLazyLoader,
  installCrossTabCsrf,
  type PinnedSocket,
} from "./auth_lazy"
import {
  brandForShellApp,
  reconcileShellState,
  shellDestinationChanged,
  type ShellState,
} from "./shell_state"
import {HomeField} from "./hooks/home_field"
import {HomeHero} from "./hooks/home_hero"
import {HomePrism} from "./hooks/home_prism"
import {HomeTokenMenu} from "./hooks/home_token_menu"
import {ProductArtwork} from "./hooks/product_artwork"
import {AutolaunchBidWallet} from "./hooks/autolaunch_bid_wallet"
import {AutolaunchLaunchDraft} from "./hooks/autolaunch_launch_draft"
import {AutolaunchLaunchWallet} from "./hooks/autolaunch_launch_wallet"
import {AutolaunchSubjectWallet} from "./hooks/autolaunch_subject_wallet"
import {ShellMotion} from "./hooks/motion"
import {StakeWallet} from "./hooks/stake_wallet"
import {RedemptionWallet} from "./hooks/redemption_wallet"
import {RegentsClubMetadataWallet} from "./hooks/regents_club_metadata_wallet"
import {CommentMarkdown} from "./hooks/comment_markdown"
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

// The colour theme travels in a cookie so the server can render it before the
// first paint. The switch itself is client-owned: it writes the cookie, restyles
// the document, and re-announces itself after every live navigation.
const themeCookie = "regent_theme"
const themeMaxAge = 60 * 60 * 24 * 365
const themes = {
  light: {name: "Light", nextName: "Dark"},
  dark: {name: "Dark", nextName: "Light"},
}
type Theme = keyof typeof themes

const isTheme = (value: string | undefined): value is Theme =>
  value === "light" || value === "dark"

function readThemeCookie(): Theme | undefined {
  const prefix = `${themeCookie}=`
  const value = document.cookie
    .split("; ")
    .find(cookie => cookie.startsWith(prefix))
    ?.slice(prefix.length)

  return isTheme(value) ? value : undefined
}

function writeThemeCookie(theme: Theme) {
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie =
    `${themeCookie}=${theme}; Path=/; Max-Age=${themeMaxAge}; SameSite=Lax${secure}`
}

let savedTheme = readThemeCookie()

// The public crown is a dark-only composition, not a change to visitor preference.
const homeThemeLocked = () => window.location.pathname === "/"
const pageTheme = (): Theme => homeThemeLocked() ? "dark" : savedTheme ?? "dark"

function applyTheme(theme: Theme) {
  const selected = themes[theme]
  document.documentElement.dataset.theme = theme
  document.documentElement.dataset.homeThemeLocked = String(homeThemeLocked())
  if (homeThemeLocked()) document.documentElement.dataset.brand = "platform"
  document.querySelector('meta[name="color-scheme"]')?.setAttribute("content", theme)
  document.querySelector('meta[name="theme-color"]')?.setAttribute("content", theme === "dark" ? "#161616" : "#e5e3d2")

  document.querySelectorAll<HTMLElement>("[data-theme-toggle]").forEach(toggle => {
    toggle.hidden = homeThemeLocked()
    toggle.setAttribute("aria-pressed", String(theme === "light"))
    toggle.setAttribute(
      "aria-label",
      homeThemeLocked() ? "Color theme: Dark. Fixed on the homepage." : `Color theme: ${selected.name}. Activate ${selected.nextName} theme.`,
    )
    toggle.setAttribute("title", homeThemeLocked() ? "Dark homepage" : `Switch to ${selected.nextName}`)
    const state = toggle.querySelector("[data-theme-toggle-state]")
    if (state) state.textContent = `${selected.name} theme active`
  })
}

function syncTheme() {
  savedTheme = readThemeCookie()
  applyTheme(pageTheme())
}

document.addEventListener("click", event => {
  if (!(event.target instanceof Element) || !event.target.closest("[data-theme-toggle]")) return
  if (homeThemeLocked()) {
    event.preventDefault()
    return
  }

  const active = document.documentElement.dataset.theme
  const theme: Theme = (isTheme(active) ? active : pageTheme()) === "dark" ? "light" : "dark"
  savedTheme = theme
  writeThemeCookie(theme)
  applyTheme(theme)
})

window.addEventListener("phx:page-loading-stop", syncTheme)
window.addEventListener("popstate", syncTheme)
window.addEventListener("pageshow", syncTheme)
syncTheme()

const shellBehavior: Hook = {
  mounted(this: ShellHook) {
    const shell = this.el
    const root = document.documentElement
    const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)")

    const initialState: ShellState = {
      routeId: shell.dataset.routeId ?? "",
      destination: shell.dataset.destination ?? "",
      menuOpen: shell.dataset.menuOpen === "true",
    }
    root.dataset.brand = brandForShellApp(shell.dataset.app)
    this.shellState = cachedShellState
      ? reconcileShellState(cachedShellState, initialState)
      : initialState

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
      cachedShellState = state
      menuButton()?.setAttribute("aria-expanded", String(state.menuOpen))
      syncMenuAccessibility()
    }

    const onClick = (event: Event) => {
      const target = event.target instanceof Element ? event.target : null
      shell.dataset.motionSource =
        event instanceof MouseEvent && event.detail === 0 ? "keyboard" : "pointer"

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
      shell.dataset.motionSource = "keyboard"
      scroller()?.scrollTo({top: 0})
    }

    shell.addEventListener("click", onClick)
    shell.addEventListener("keydown", onKeydown)
    motionPreference.addEventListener("change", setMotion)
    window.addEventListener("popstate", onHistoryNavigation)
    setMotion()
    this.restoreState()
    scroller()?.scrollTo({top: 0})
    shell.dataset.behaviorReady = "true"

    this.cleanup = () => {
      closeMenu(false)
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("keydown", onKeydown)
      motionPreference.removeEventListener("change", setMotion)
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
  CommentMarkdown,
  ...showcaseHooks,
  ...colocatedHooks,
  AutolaunchBidWallet,
  AutolaunchLaunchDraft,
  AutolaunchLaunchWallet,
  AutolaunchSubjectWallet,
  HomeField,
  HomeHero,
  HomePrism,
  HomeTokenMenu,
  ProductArtwork,
  ShellBehavior: composeHooks(shellBehavior, ShellMotion),
  RedemptionWallet,
  RegentsClubMetadataWallet,
  StakeWallet,
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
liveSocket.connect()
installAccountAuthLazyLoader()
installCrossTabCsrf()
window.liveSocket = liveSocket
