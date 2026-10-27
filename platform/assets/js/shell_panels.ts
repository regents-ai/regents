// The side panel, which the browser alone opens and closes, as the template's
// shell does. Its state lives on <html data-aside>, which the server first draws
// from the cookie written here (RegentsWeb.Plugs.Panels), so LiveView never
// patches it away. Where the side panel covers the page, it opens only when the
// person opens it on that page (<html data-aside-here>), never from the
// remembered state.

import {beckon} from "./hooks/motion/press"
import {byPointer, still} from "./hooks/motion/shared"

const yearInSeconds = 60 * 60 * 24 * 365
const cookie = "regents_aside"

// The server's value, closed, is the default; only open is kept.
function remember(value: string) {
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  const age = value === "open" ? yearInSeconds : 0
  document.cookie = `${cookie}=${value}; Path=/; Max-Age=${age}; SameSite=Lax${secure}`
}

const root = () => document.documentElement
const covering = window.matchMedia("(max-width: 63.99rem)")
// How the agents to choose from are marked after Pair New Agent is pressed:
// at once, for 1.2 s, then a 0.6 s fade; from the keyboard or with less motion
// asked for, the mark simply goes at the same moment.
const markHeld = 1200
const markFade = 600
export const asideOpen = () =>
  root().dataset.aside === "open" && (!covering.matches || root().dataset.asideHere !== undefined)

/** Wires the side panel inside `scope`. Returns `sync`, to run after every page update, and `cleanup`. */
export function installShellPanels(scope: Document | HTMLElement = document) {
  const aside = () => scope.querySelector<HTMLElement>("#shell-aside")
  const asideButton = () => scope.querySelector<HTMLButtonElement>("#shell-aside-button")
  const phone = () => window.matchMedia("(max-width: 47.99rem)").matches
  let marking: Animation | undefined
  // A press on Pair New Agent as a link to another page, until that page arrives.
  let arriving: {href: string; pointer: boolean} | undefined

  // The side panel's own button and the account name in the header both open it.
  const sync = () => {
    scope.querySelectorAll("[data-aside-toggle]").forEach(toggle =>
      toggle.setAttribute("aria-expanded", String(asideOpen())))
  }

  // Opened, focus moves into it (to the panel itself, or to what a press
  // points to there), so Escape closes it and returns focus to the button that
  // opened it, and what it shows is read again.
  const setAside = (open: boolean, focus: () => HTMLElement | null | undefined = aside) => {
    const value = open ? "open" : "closed"
    root().dataset.aside = value
    if (open) root().dataset.asideHere = ""
    else delete root().dataset.asideHere
    remember(value)
    sync()

    if (!open) {
      arriving = undefined
      return
    }
    focus()?.focus({preventScroll: true})
    aside()
      ?.querySelectorAll("[data-read-on-open]")
      .forEach(reader => reader.dispatchEvent(new CustomEvent("regents:aside-opened")))
  }

  const choices = () => aside()?.querySelector<HTMLElement>("#shell-pairing .rg-account__choices")
  // The agent already chosen, or else the first, so a screen reader hears the
  // box's question and that agent.
  const firstChoice = () =>
    choices()?.querySelector<HTMLInputElement>("input:checked") ?? choices()?.querySelector<HTMLInputElement>("input")

  // A page's own Pair New Agent button points to the agents to choose from in
  // the panel: focus lands on them, their box glides into view and is marked
  // for a moment while the agents settle in turn, again on every press. Pressed
  // from the keyboard, or with less motion asked for, the box is simply there
  // and marked. The mark is the browser's own animation of the box's `::after`,
  // so a redraw of the box by the server leaves it alone.
  const pointToAgents = (pointer: boolean) => {
    setAside(true, firstChoice)
    const box = choices()
    if (!box) return

    const moving = pointer && !still(box)
    box.scrollIntoView({block: "nearest", behavior: moving ? "smooth" : "instant"})
    marking?.cancel()
    marking = box.animate(
      moving
        ? [{opacity: 1}, {opacity: 1, offset: markHeld / (markHeld + markFade), easing: "cubic-bezier(0.23, 1, 0.32, 1)"}, {opacity: 0}]
        : [{opacity: 1}, {opacity: 1}],
      {duration: moving ? markHeld + markFade : markHeld, pseudoElement: "::after"},
    )
    if (moving) beckon([...box.querySelectorAll(".rg-account__choice")])
  }

  // Pair New Agent as a link to another page opens the panel now and points
  // to the agents once that page has drawn itself, panel included: the first
  // drawing of the page the link named. Closing the panel before then calls
  // it off. A press that opens the link in another tab is the browser's own.
  const onArrival = (event: Event) => {
    const {to, kind} = (event as CustomEvent<{to?: string; kind?: string}>).detail ?? {}
    if (kind !== "initial" || !arriving) return
    const {href, pointer} = arriving
    arriving = undefined
    if (to === href) pointToAgents(pointer)
  }

  const onClick = (event: MouseEvent) => {
    const target = event.target instanceof Element ? event.target : null
    if (!target) return

    if (target.closest("[data-aside-toggle]")) return setAside(!asideOpen())
    // A page's own Pair New Agent button opens the panel, leaves it open, and
    // points to the agents to choose from.
    const pairNew = target.closest("[data-aside-open]")
    if (pairNew instanceof HTMLAnchorElement) {
      if (event.ctrlKey || event.metaKey || event.shiftKey) return
      setAside(true)
      arriving = {href: pairNew.href, pointer: byPointer(event)}
      return
    }
    if (pairNew) return pointToAgents(byPointer(event))
    // On a phone the side bar covers the page, so a page link inside it closes it.
    if (phone() && target.closest("#shell-aside a")) setAside(false)
  }

  const onKeydown = (event: KeyboardEvent) => {
    if (event.key === "Escape" && asideOpen() && aside()?.contains(document.activeElement)) {
      event.preventDefault()
      setAside(false)
      asideButton()?.focus()
    }
  }

  scope.addEventListener("click", onClick as EventListener)
  window.addEventListener("phx:page-loading-stop", onArrival)
  document.addEventListener("keydown", onKeydown)
  covering.addEventListener("change", sync)

  sync()

  return {
    sync,
    cleanup: () => {
      marking?.cancel()
      scope.removeEventListener("click", onClick as EventListener)
      window.removeEventListener("phx:page-loading-stop", onArrival)
      document.removeEventListener("keydown", onKeydown)
      covering.removeEventListener("change", sync)
    },
  }
}
