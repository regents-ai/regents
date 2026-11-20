/**
 * Techtree's Services menu in the site's bar and its Menu sheet on a phone
 * (`RegentsWeb.Techtree.Layouts`). Each is a popover its button opens: the browser
 * closes it on Escape or a press outside, hands focus back to its button, and puts
 * its links next in the Tab order. What is left is done here:
 *
 * - Choosing an entry closes it, and its button's `aria-expanded` follows it.
 * - Opened by a mouse or a finger it drops in and its columns follow one after
 *   another; opened from the keyboard, or with less motion asked for, it is simply
 *   there.
 * - While the sheet is open the page under the bar is inert, so Tab and a press
 *   can't land on a link behind it.
 * - A screen that crosses the bar's phone width closes whichever it no longer shows.
 */
import {stagger} from "animejs"
import {BASE, EASE_OUT, SLOW, lastInputByPointer, play, still} from "../hooks/motion/shared"

const MENUS = "#techtree-services, #techtree-menu"
// The site's bar hides its links at 48rem and below, where Menu shows.
const PHONE = "(max-width: 48rem)"

export function installSiteMenu() {
  window.matchMedia(PHONE).addEventListener("change", () => {
    for (const menu of document.querySelectorAll<HTMLElement>(`:is(${MENUS}):popover-open`)) menu.hidePopover()
  })

  document.addEventListener("click", event => {
    const entry = event.target instanceof Element ? event.target.closest(`:is(${MENUS}) a`) : null
    entry?.closest<HTMLElement>("[popover]")?.hidePopover()
  })

  // Before the change is drawn, so the button, the page and the first frame of the
  // move all change with it.
  document.addEventListener("beforetoggle", event => {
    const menu = event.target
    if (!(event instanceof ToggleEvent) || !(menu instanceof HTMLElement) || !menu.matches(MENUS)) return
    const open = event.newState === "open"
    document.querySelector(`[popovertarget="${menu.id}"]`)?.setAttribute("aria-expanded", String(open))
    if (menu.id === "techtree-menu") {
      for (const page of document.querySelectorAll<HTMLElement>(".techtree-frame")) page.inert = open
    }
    if (open && lastInputByPointer() && !still(menu)) arrive(menu)
  }, true)
}

function arrive(target: HTMLElement) {
  play(target, {opacity: {from: 0}, y: {from: -8}, duration: BASE, ease: EASE_OUT})
  const parts = [...target.querySelectorAll(".menu-columns__column, .sheet__links, .sheet__end")]
  play(parts, {opacity: {from: 0}, y: {from: 8}, delay: stagger(35, {start: 40}), duration: SLOW, ease: EASE_OUT})
}
