// Keyfleet's frame (`RegentsWeb.Keyfleet.Components.Shell`): its phone menu, its
// keyboard, where each page starts and the bar while the next one loads. The page
// stays Keyfleet's (`data-product="keyfleet"`), which its stylesheets are scoped to.

import {composeHooks, type Hook} from "../hook_composition"
import {ShellViews} from "../hooks/motion/reveals"
import {arriveAt} from "../shell_panels"
import {reconcileShellState, shellDestinationChanged, type ShellState} from "../shell_state"
import {mountPageProgress} from "./page_progress"

type ShellHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
  shellState?: ShellState
  restoreState?: () => void
}

let cachedShellState: ShellState | undefined

/**
 * The id a #fragment names, or "" for none. A fragment whose %-escapes spell no
 * text, such as #%E0, names nothing.
 */
function fragmentId(hash: string) {
  try {
    return decodeURIComponent(hash.slice(1))
  } catch {
    return ""
  }
}

/** The element the address's #fragment names. */
const hashTarget = () => {
  const id = fragmentId(window.location.hash)
  return id ? document.getElementById(id) : null
}

const keyfleetShell: Hook = {
  mounted(this: ShellHook) {
    const shell = this.el

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

      // An open menu takes Escape itself, before any section behind it.
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

    // LiveView records a new address only once its page is drawn, so what a
    // #fragment names is reached here, after the page has started at its top.
    const onNavigate = () => {
      const named = hashTarget()
      if (named) arriveAt(named)
    }

    // The sidebar stands beside the page rather than in it, so a scroll over a
    // sidebar with no more of its own to scroll that way moves the page, down
    // to its footer. The open phone menu keeps its scroll to itself.
    const onWheel = (event: WheelEvent) => {
      const target = event.target instanceof Element ? event.target : null
      const overSidebar = target?.closest<HTMLElement>("#shell-sidebar")
      if (!overSidebar || event.ctrlKey || shell.dataset.menuOpen === "true") return
      const {scrollTop, scrollHeight, clientHeight} = overSidebar
      const room = event.deltaY > 0 ? scrollHeight - clientHeight - scrollTop : scrollTop
      if (room > 1) return
      const lines = event.deltaMode === WheelEvent.DOM_DELTA_LINE
      scroller()?.scrollBy({top: lines ? event.deltaY * 16 : event.deltaY})
    }

    shell.addEventListener("click", onClick)
    shell.addEventListener("keydown", onKeydown)
    shell.addEventListener("wheel", onWheel, {passive: true})
    window.addEventListener("popstate", onHistoryNavigation)
    window.addEventListener("phx:navigate", onNavigate)
    const stopPageProgress = mountPageProgress()
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
      shell.removeEventListener("wheel", onWheel)
      window.removeEventListener("popstate", onHistoryNavigation)
      window.removeEventListener("phx:navigate", onNavigate)
      stopPageProgress()
    }
  },

  updated(this: ShellHook) {
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
    this.el.dataset.behaviorReady = "true"
    // A new page starts at its top, with focus on its heading, so a screen
    // reader announces where the person has arrived.
    if (shouldScroll) {
      this.el.querySelector<HTMLElement>("#app-shell-scroller")?.scrollTo({top: 0})
      this.el.querySelector<HTMLElement>("#route-content h1")?.focus({preventScroll: true})
    }
  },

  destroyed(this: ShellHook) {
    this.cleanup?.()
  },
}

export const KeyfleetShell = composeHooks(keyfleetShell, ShellViews)
