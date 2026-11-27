// Keyfleet's frame (`RegentsWeb.Keyfleet.Components.Shell`): keyboard Escape
// handling for open disclosures, where each page starts, and the page progress
// bar while the next route loads. The unified one-site sidebar owns navigation.

import {composeHooks, type Hook} from "../hook_composition"
import {ShellViews} from "./hooks/motion/reveals"
import {arriveAt} from "../shell_panels"
import {reconcileShellState, shellDestinationChanged, type ShellState} from "../shell_state"
import {mountPageProgress} from "./page_progress"

type ShellHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
  shellState?: ShellState
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
      menuOpen: false,
    }
    this.shellState = cachedShellState
      ? reconcileShellState(cachedShellState, initialState)
      : initialState
    cachedShellState = this.shellState

    const scroller = () => shell.querySelector<HTMLElement>("#app-shell-scroller")

    const onKeydown = (event: KeyboardEvent) => {
      // Escape closes the last open disclosure a person can see, inside the open
      // modal dialog when one is open; a dialog with none open inside closes itself.
      if (event.key === "Escape" && !shell.querySelector(":popover-open")) {
        const layer = [...shell.querySelectorAll<HTMLDialogElement>("dialog:modal")].at(-1) ?? shell
        const openDetails = [...layer.querySelectorAll<HTMLDetailsElement>("details[open]")]
          .filter(details => details.checkVisibility())
          .at(-1)

        if (openDetails) {
          openDetails.removeAttribute("open")
          openDetails.querySelector<HTMLElement>("summary")?.focus()
          event.preventDefault()
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

    shell.addEventListener("keydown", onKeydown)
    window.addEventListener("popstate", onHistoryNavigation)
    window.addEventListener("phx:navigate", onNavigate)
    const stopPageProgress = mountPageProgress()
    // A page opened at a #fragment starts at what it names, otherwise at its top.
    const opened = hashTarget()
    if (opened) arriveAt(opened)
    else scroller()?.scrollTo({top: 0})
    shell.dataset.behaviorReady = "true"

    this.cleanup = () => {
      shell.removeEventListener("keydown", onKeydown)
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

    const shouldScroll = this.shellState
      ? shellDestinationChanged(this.shellState, incoming)
      : false
    if (this.shellState) {
      this.shellState = reconcileShellState(this.shellState, incoming)
      cachedShellState = this.shellState
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
