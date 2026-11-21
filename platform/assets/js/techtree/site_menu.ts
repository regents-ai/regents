/**
 * Techtree's Services panel, in the row under the site's bar
 * (`RegentsWeb.Techtree.Layouts`). The browser's popover opens it on Enter or Space,
 * puts focus on its first service, closes it on Escape or a press outside, hands focus
 * back to Services, and closes the site's product menu as it opens. This adds the rest:
 *
 * - Services' `aria-expanded` follows the panel.
 * - Down on Services opens it.
 * - Focus leaving Services and its panel closes it.
 * - Opened or closed from the keyboard, the panel and the caret skip their motion
 *   (`data-instant`, read by site_chrome.css).
 *
 * Listening on the document, it works after any redraw.
 */
import {lastInputByPointer} from "../hooks/motion/shared"

const PANEL = "techtree-services"
const SERVICES = `[popovertarget="${PANEL}"]`

export function installSiteMenu() {
  // Before the change is drawn, so the button and the panel's first frame change with it.
  document.addEventListener("beforetoggle", event => {
    if (!(event instanceof ToggleEvent) || !(event.target instanceof HTMLElement) || event.target.id !== PANEL) return
    const services = document.querySelector(SERVICES)
    services?.setAttribute("aria-expanded", String(event.newState === "open"))
    services?.toggleAttribute("data-instant", !lastInputByPointer())
  }, true)

  document.addEventListener("keydown", event => {
    if (event.key !== "ArrowDown" || !(event.target instanceof Element) || !event.target.matches(SERVICES)) return
    event.preventDefault()
    document.getElementById(PANEL)?.showPopover()
  })

  document.addEventListener("focusout", event => {
    const group = event.target instanceof Element ? event.target.closest(".tt-row__services") : null
    if (group && event.relatedTarget instanceof Node && !group.contains(event.relatedTarget)) {
      document.getElementById(PANEL)?.hidePopover()
    }
  })
}
