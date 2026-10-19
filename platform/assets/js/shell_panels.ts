// The side panel, which the browser alone opens and closes, as the template's
// shell does. Its state lives on <html data-aside>, which the server first draws
// from the cookie written here (RegentsWeb.Plugs.Panels), so LiveView never
// patches it away. Where the side panel covers the page, it opens only when the
// person opens it on that page (<html data-aside-here>), never from the
// remembered state.

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
// How long the agents to choose from stay marked after Pair New Agent is pressed.
const flashMs = 1200
export const asideOpen = () =>
  root().dataset.aside === "open" && (!covering.matches || root().dataset.asideHere !== undefined)

/** Wires the side panel inside `scope`. Returns `sync`, to run after every page update, and `cleanup`. */
export function installShellPanels(scope: Document | HTMLElement = document) {
  const aside = () => scope.querySelector<HTMLElement>("#shell-aside")
  const asideButton = () => scope.querySelector<HTMLButtonElement>("#shell-aside-button")
  const phone = () => window.matchMedia("(max-width: 47.99rem)").matches
  let flashTimer: number | undefined

  // The side panel's own button and the account name in the header both open it.
  const sync = () => {
    scope.querySelectorAll("[data-aside-toggle]").forEach(toggle =>
      toggle.setAttribute("aria-expanded", String(asideOpen())))
  }

  const setAside = (open: boolean) => {
    const value = open ? "open" : "closed"
    root().dataset.aside = value
    if (open) root().dataset.asideHere = ""
    else delete root().dataset.asideHere
    remember(value)
    sync()

    // Opened, focus moves into it, so Escape closes it and returns focus to the
    // button that opened it, and what it shows is read again.
    if (!open) return
    aside()?.focus()
    aside()
      ?.querySelectorAll("[data-read-on-open]")
      .forEach(reader => reader.dispatchEvent(new CustomEvent("regents:aside-opened")))
  }

  // A page's own Pair New Agent button points to the agents to choose from in
  // the panel: they come into view and their box flashes, again on every press.
  const pointToAgents = () => {
    const panel = aside()
    const choices = panel?.querySelector<HTMLElement>("#shell-pairing .rg-account__choices")
    if (!panel || !choices) return

    const box = choices.getBoundingClientRect()
    const view = panel.getBoundingClientRect()
    if (box.bottom > view.bottom) panel.scrollTop += box.bottom - view.bottom + 16
    else if (box.top < view.top) panel.scrollTop -= view.top - box.top + 16

    delete choices.dataset.flash
    void choices.offsetWidth
    choices.dataset.flash = ""
    window.clearTimeout(flashTimer)
    flashTimer = window.setTimeout(() => delete choices.dataset.flash, flashMs)
  }

  const onClick = (event: Event) => {
    const target = event.target instanceof Element ? event.target : null
    if (!target) return

    if (target.closest("[data-aside-toggle]")) return setAside(!asideOpen())
    // A page's own Pair New Agent button opens the panel, leaves it open, and
    // points to the agents to choose from.
    if (target.closest("[data-aside-open]")) {
      setAside(true)
      return pointToAgents()
    }
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

  scope.addEventListener("click", onClick)
  document.addEventListener("keydown", onKeydown)
  covering.addEventListener("change", sync)

  sync()

  return {
    sync,
    cleanup: () => {
      window.clearTimeout(flashTimer)
      scope.removeEventListener("click", onClick)
      document.removeEventListener("keydown", onKeydown)
      covering.removeEventListener("change", sync)
    },
  }
}
