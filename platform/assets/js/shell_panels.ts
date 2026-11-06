// The account menu and the apps menu are popovers the browser opens and closes
// itself, as the template's shell does; only following a link inside one, opening
// the pairing window, and Sign out, are ours.

/**
 * Brings `target`, what an address's #fragment names, into view. When it holds a
 * choice, such as the pairing box's agents, focus goes to the chosen one, or the
 * first, so the keyboard starts there. Returns whether it holds one.
 */
export function arriveAt(target: HTMLElement) {
  target.scrollIntoView()
  const choices = [...target.querySelectorAll<HTMLInputElement>("input[type=radio]")]
  const choice = choices.find(radio => radio.checked) ?? choices[0]
  // Next frame: following the link, and LiveView's patch, each move focus first.
  if (choice) requestAnimationFrame(() => choice.focus({preventScroll: true}))
  return choice !== undefined
}

/** Wires the menus inside `scope`. Returns `cleanup`. */
export function installShellPanels(scope: Document | HTMLElement = document) {
  const pairing = () => document.getElementById("shell-pairing") as HTMLDialogElement | null

  // The window opens on the list of agents while none is chosen, with the keyboard
  // on the dropdown.
  const openPairing = () => {
    const dialog = pairing()
    if (!dialog || dialog.open) return
    dialog.showModal()
    const pick = dialog.querySelector<HTMLDetailsElement>("details.rg-pill-select")
    if (!pick) return
    if (!pick.querySelector("input:checked")) pick.open = true
    pick.querySelector<HTMLElement>(":scope > summary")?.focus()
  }

  const closePairing = () => pairing()?.close()

  const onClick = (event: MouseEvent) => {
    const target = event.target instanceof Element ? event.target : null
    if (!target) return

    // Pair New Agent, in the account menu and on the Agents page, opens the one
    // pairing window. The menu closes first, so focus goes back to the account
    // button and returns there when the window closes.
    const pairOpener = target.closest<HTMLElement>("[data-pair-open]")
    if (pairOpener) {
      pairOpener.closest<HTMLElement>("[popover]")?.hidePopover()
      return openPairing()
    }
    if (target.closest("[data-pair-close]")) return closePairing()
    // A press on the window's own backdrop lands on the window itself.
    if (target === pairing()) return closePairing()
    // Sign out closes the account menu, so a note it leaves, such as one saying it
    // couldn't finish, shows under the account button rather than behind the menu.
    const signOut = target.closest<HTMLElement>("[data-account-target='sign-out']")
    if (signOut) {
      signOut.closest<HTMLElement>("[popover]")?.hidePopover()
      return
    }
    // A page change keeps an open menu open, so a link followed from one closes it.
    // A link to a #fragment of this page changes nothing LiveView sees when the
    // address already shows it, so what it names comes into view here, every press.
    const link = target.closest<HTMLAnchorElement>("a[href]")
    if (!link) return
    link.closest<HTMLElement>("[popover]")?.hidePopover()
    const named = link.hash && link.pathname === window.location.pathname
      ? document.getElementById(decodeURIComponent(link.hash.slice(1)))
      : null
    if (named) arriveAt(named)
  }

  scope.addEventListener("click", onClick as EventListener)

  return {
    cleanup: () => scope.removeEventListener("click", onClick as EventListener),
  }
}
