import "../css/app.css"
import "../vendor/regent_ui/blog.mjs"
import "../vendor/regent_ui/confirm.mjs"
// An open pill menu closes on Escape or a tap outside it, iPhones included.
import "../vendor/regent_ui/pill_select.mjs"
// The arrow keys of the site bar's product menu (`Regent.Site.bar`).
import "../vendor/regent_ui/product_menu.mjs"
import "../vendor/regent_ui/tip.mjs"

import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/regents"

import {composeHooks, type Hook} from "./hook_composition"
import {
  browserCsrfToken,
  holdAdoptionWhileLeaving,
  holdSocketDuringCookieRotation,
  installAccountAuthLazyLoader,
  installCrossTabCsrf,
  installSignInLater,
  retireRefusedSession,
  signInOpensLater,
  type PinnedSocket,
} from "./auth_lazy"
import {
  reconcileShellState,
  shellDestinationChanged,
  type ShellState,
} from "./shell_state"
import {InfiniteScroll} from "./hooks/infinite_scroll"
import {DatascapeHero} from "./hooks/datascape_hero"
import {MarketingPage} from "./hooks/marketing_page"
import {MotionCount, MotionList, MotionNote, MotionRefusal, MotionTick} from "./hooks/motion/moments"
import {MotionCascade, MotionTabs, ShellViews} from "./hooks/motion/reveals"
import {InfoDialog} from "./hooks/info_dialog"
import {LabBlocks} from "./hooks/lab_blocks"
import {OnchainSteps} from "./hooks/onchain_steps"
import {PaperPicks} from "./hooks/paper_picks"
import {PublicName} from "./hooks/public_name"
import {SentList} from "./hooks/sent_list"
import {MenuAgents} from "./hooks/menu_agents"
import {ThemeSwitch} from "./hooks/theme_switch"
import {Tour} from "./hooks/tour"
import {ValueCard} from "./hooks/value_card"
import {ResearchScrollCue} from "./hooks/research_scroll_cue"
import {mountMotion} from "./motion"
import {installAgentMessage} from "./agent_message"
import {installAgentTools} from "./agent_tools"
import {installCopyButtons} from "./copy_buttons"
import {Docs} from "./docs"
import {installLiteratureChart} from "./literature_chart"
import {installPublicTools} from "./public_tools"
import {arriveAt, installShellPanels} from "./shell_panels"
import {VerifiedConnections} from "./hooks/verified_connections"
import {installVisitLog} from "./visit_log"
import {syncTheme} from "./theme"
// Techtree's pages (`RegentsWeb.Techtree`): their moving pictures, rows that rise
// in and figures that count up, the Docs' Copy page control, the Results page's
// agent-version strip, and the Services panel in Techtree's row under the bar.
import {AgentVersions} from "./techtree/agent_versions"
import {EnquiryForm} from "./techtree/enquiry_form"
import {marketingHooks, mountEntrance} from "./techtree/marketing"
import {CopyCommandPage, CopyCommandPageView} from "./techtree/page_copy"
import {installSiteMenu} from "./techtree/site_menu"
// Keyfleet's pages (`RegentsWeb.Keyfleet`): their frame, with its phone menu and the
// bar while the next page loads, and the hooks their markup names.
import {keyfleetHooks, installKeyfleet} from "./keyfleet"
import {KeyfleetShell} from "./keyfleet/shell_behavior"
// Autolaunch's pages (`RegentsWeb.Autolaunch`): the phone menu of its frame and its hooks.
import {autolaunchHooks} from "./autolaunch"
import {installShellMenu} from "./autolaunch/shell_menu"
// Patchbay's pages (`RegentsWeb.Patchbay`): Escape closing an open section, the
// home page's live list, a post's live thread and its counting times, and the
// WebMCP guide's status line.
// Their copy buttons and other motion are the site's own above.
import {installEscape} from "./patchbay/escape"
import {MotionArrivals} from "./patchbay/motion_arrivals"
import {MotionThread} from "./patchbay/motion_thread"
import {PatchbayRelativeTime} from "./patchbay/relative_time"
import {mountWebMCPStatus} from "./patchbay/webmcp_status"

// First, so an error anywhere below is reported too.
installVisitLog()

type ShellHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
  shellState?: ShellState
  restoreState?: () => void
}

let cachedShellState: ShellState | undefined

// Live navigation keeps the document, so each page restates its theme
// (theme.ts); every theme switch follows what it shows.
window.addEventListener("phx:page-loading-stop", syncTheme)
window.addEventListener("popstate", syncTheme)
window.addEventListener("pageshow", syncTheme)

// The element the address's #fragment names, such as the Agents page's pairing box.
const hashTarget = () => {
  const id = decodeURIComponent(window.location.hash.slice(1))
  return id ? document.getElementById(id) : null
}

const shellBehavior: Hook = {
  mounted(this: ShellHook) {
    const shell = this.el
    const root = document.documentElement

    const initialState: ShellState = {
      routeId: shell.dataset.routeId ?? "",
      destination: shell.dataset.destination ?? "",
      menuOpen: shell.dataset.menuOpen === "true",
    }
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

      // An open account or apps menu takes Escape itself, before any section behind it.
      // Otherwise Escape closes the last open section a person can see, inside the open
      // window when one is open; a window with none open inside closes itself.
      if (event.key === "Escape" && !shell.querySelector(":popover-open")) {
        const layer = [...shell.querySelectorAll<HTMLDialogElement>("dialog:modal")].at(-1) ?? shell
        const openDetails = [...layer.querySelectorAll<HTMLDetailsElement>("details[open]")]
          .filter(details => details.checkVisibility())
          .at(-1)

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

    // A link to another page's #fragment: what the #fragment names is reached
    // here, after the page has started at its top.
    const onNavigate = () => {
      const named = hashTarget()
      if (named) arriveAt(named)
    }

    shell.addEventListener("click", onClick)
    shell.addEventListener("keydown", onKeydown)
    window.addEventListener("popstate", onHistoryNavigation)
    window.addEventListener("phx:navigate", onNavigate)
    this.restoreState()
    // A page opened at a #fragment starts at what it names, otherwise at its top.
    const opened = hashTarget()
    if (opened) arriveAt(opened)
    else scroller()?.scrollTo({top: 0})
    shell.dataset.behaviorReady = "true"

    this.cleanup = () => {
      closeMenu(false)
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("keydown", onKeydown)
      window.removeEventListener("popstate", onHistoryNavigation)
      window.removeEventListener("phx:navigate", onNavigate)
    }
  },

  // A page reached from another starts at its top. This runs as the new page is
  // drawn, before its own parts start, so a part one of them brings into view as
  // it starts (the Stake page's guided tour) stays in view. LiveView hands it the
  // shell as the server has just drawn it.
  beforeUpdate(this: ShellHook, next: unknown) {
    const destination = (next as HTMLElement).dataset.destination ?? ""
    if (this.shellState && shellDestinationChanged(this.shellState, {destination})) {
      this.el.querySelector<HTMLElement>("#app-shell-scroller")?.scrollTo({top: 0})
    }
  },

  updated(this: ShellHook) {
    const incoming = {
      routeId: this.el.dataset.routeId ?? "",
      destination: this.el.dataset.destination ?? "",
    }

    const menuWasOpen = this.shellState?.menuOpen === true
    if (this.shellState) {
      this.shellState = reconcileShellState(this.shellState, incoming)
    }
    this.restoreState?.()
    if (menuWasOpen && this.shellState?.menuOpen === false) {
      this.el.querySelector<HTMLButtonElement>("#mobile-menu-button")?.focus()
    }
    this.el.dataset.behaviorReady = "true"
  },

  destroyed(this: ShellHook) {
    this.cleanup?.()
  },
}

// Design composes presentation behavior here; the Ash-owned behavior remains first.
const showcaseHooks = window.location.pathname.startsWith("/showcase")
  ? (await import("./showcase")).hooks : {}
const labHooks = window.location.pathname === "/animations"
  ? (await import("./motion_lab")).hooks : {}
const hooks = {
  ...showcaseHooks,
  ...labHooks,
  ...colocatedHooks,
  ...marketingHooks,
  ...keyfleetHooks,
  ...autolaunchHooks,
  AgentVersions,
  CopyCommandPage,
  CopyCommandPageView,
  DatascapeHero,
  Docs,
  EnquiryForm,
  InfiniteScroll,
  InfoDialog,
  KeyfleetShell,
  LabBlocks,
  MarketingPage,
  MotionArrivals,
  MotionCascade,
  MotionCount,
  MotionList,
  MotionNote,
  MotionRefusal,
  MotionTabs,
  MotionTick,
  MotionThread,
  MenuAgents,
  OnchainSteps,
  PaperPicks,
  PatchbayRelativeTime,
  PublicName,
  ResearchScrollCue,
  SentList,
  ShellBehavior: composeHooks(shellBehavior, ShellViews),
  ThemeSwitch,
  Tour,
  ValueCard,
  VerifiedConnections,
  WatchdogSites: MotionList,
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
holdAdoptionWhileLeaving()
// Started before the first connect, so a page rendered for a refused cookie
// holds its socket until that cookie is retired.
void retireRefusedSession()
liveSocket.connect()
// Where the site only reads, nobody signs in: Sign in says so, and Privy never loads.
if (signInOpensLater()) installSignInLater()
else installAccountAuthLazyLoader()
installPublicTools()
installCrossTabCsrf()
installCopyButtons()
installAgentMessage()
installAgentTools()
installLiteratureChart()
installShellPanels()
installShellMenu()
installSiteMenu()
installEscape()
installKeyfleet()
mountWebMCPStatus()
mountMotion(document)
mountEntrance(document)
window.liveSocket = liveSocket
