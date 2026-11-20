/**
 * Techtree's Results page agent-version strip (`RegentsWeb.Techtree.RunsLive.Index`):
 * the chosen version is scrolled to the middle of the strip, and keeps the focus
 * when a choice redraws the strip under it.
 */
type AgentVersionsHook = {
  el: HTMLElement
  hadFocus?: boolean
  revealSelection(this: AgentVersionsHook): void
}

export const AgentVersions = {
  mounted(this: AgentVersionsHook) { this.revealSelection() },
  beforeUpdate(this: AgentVersionsHook) { this.hadFocus = this.el.contains(document.activeElement) },
  updated(this: AgentVersionsHook) { this.revealSelection() },
  revealSelection(this: AgentVersionsHook) {
    const strip = this.el.querySelector(".agent-versions__list")
    const selected = strip?.querySelector<HTMLElement>('[aria-current="page"]')
    if (!strip || !selected) return
    if (this.hadFocus && !this.el.contains(document.activeElement)) {
      selected.focus({preventScroll: true})
    }
    this.hadFocus = false
    const stripBounds = strip.getBoundingClientRect()
    const selectedBounds = selected.getBoundingClientRect()
    strip.scrollLeft += selectedBounds.left - stripBounds.left -
      (strip.clientWidth - selectedBounds.width) / 2
  },
}
