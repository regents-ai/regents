// Autolaunch's phone menu: the template's drawer (ash-template `shellBehavior` in
// platform/assets/js/app.ts), on the pages in Autolaunch's frame
// (`RegentsWeb.Autolaunch.Layouts`), the only pages with `#shell-drawer`. Menu, on
// its strip under the site's bar, opens it; its Close navigation bar, the dimmed
// page beside it, Escape, a link inside it and a move to another page close it, and
// focus goes back to Menu. While it is open, Tab stays inside it and the page and
// its footer behind it (marked `data-shell-behind-menu`) are inert.
//
// Its state lives on <html data-menu>, outside what LiveView draws, so a page
// update never shuts it. The server always draws it closed.

// The site's bar hides Autolaunch's links at 48rem and below, where Menu shows.
const phone = window.matchMedia("(max-width: 48rem)")
const focusable =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'

export function installShellMenu() {
  if (!document.getElementById("shell-drawer")) return

  const root = document.documentElement
  const menuButton = () => document.querySelector<HTMLButtonElement>("#mobile-menu-button")
  const drawer = () => document.querySelector<HTMLElement>("#shell-drawer")
  const menuOpen = () => root.dataset.menu === "open"
  const menuFocusables = () =>
    Array.from(drawer()?.querySelectorAll<HTMLElement>(focusable) ?? []).filter(
      element => !element.hidden && !element.inert,
    )

  // The button and the page behind follow the state, on every page drawn.
  const sync = () => {
    const open = menuOpen()
    menuButton()?.setAttribute("aria-expanded", String(open))
    document.querySelectorAll<HTMLElement>("[data-shell-behind-menu]").forEach(behind => {
      behind.inert = open
    })
  }

  const setMenu = (open: boolean, restoreFocus: boolean) => {
    if (open) root.dataset.menu = "open"
    else delete root.dataset.menu
    sync()

    if (open) {
      const [first] = menuFocusables()
      ;(first ?? drawer())?.focus()
    } else if (restoreFocus) {
      menuButton()?.focus()
    }
  }

  const onClick = (event: MouseEvent) => {
    const target = event.target instanceof Element ? event.target : null
    if (!target) return

    if (target.closest("#mobile-menu-button")) return setMenu(!menuOpen(), false)
    if (target.closest("[data-shell-menu-scrim], [data-shell-menu-close]")) return setMenu(false, true)
    if (menuOpen() && target.closest("#shell-drawer a")) return setMenu(false, true)
    // The bar stays usable above the menu; anything pressed there (the product
    // menu, the theme, the account) takes over from it.
    if (menuOpen() && target.closest("#site-bar")) setMenu(false, false)
  }

  const onKeydown = (event: KeyboardEvent) => {
    // A window opened from the menu handles its own keys.
    if (!menuOpen() || document.querySelector("dialog:modal")) return

    if (event.key === "Escape") {
      event.preventDefault()
      setMenu(false, true)
      return
    }

    if (event.key !== "Tab") return
    const focusables = menuFocusables()
    const first = focusables.at(0)
    const last = focusables.at(-1)
    const currentDrawer = drawer()

    if (!first || !last) {
      event.preventDefault()
      currentDrawer?.focus()
    } else if (!currentDrawer?.contains(document.activeElement)) {
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

  // Moving to another page, coming back to one the browser kept, or widening
  // past a phone, where there is no drawer, closes it.
  const closeQuietly = () => {
    if (menuOpen()) setMenu(false, false)
  }

  document.addEventListener("click", onClick)
  document.addEventListener("keydown", onKeydown)
  window.addEventListener("phx:page-loading-start", closeQuietly)
  window.addEventListener("phx:page-loading-stop", sync)
  window.addEventListener("pageshow", closeQuietly)
  phone.addEventListener("change", closeQuietly)
  sync()
}
