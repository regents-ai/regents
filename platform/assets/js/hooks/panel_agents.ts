import type {Hook} from "../hook_composition"
import {asideOpen} from "../shell_panels"

interface PanelAgentsHook {
  el: HTMLElement
  read?: () => void
  pushEventTo(target: HTMLElement, event: string, payload: object): void
}

// The side panel's agents read what each one last did only while someone can
// see them: when the page arrives with the panel open, and each time it opens
// (`regents:aside-opened`, from `installShellPanels`).
export const PanelAgents: Hook = {
  mounted(this: PanelAgentsHook) {
    this.read = () => this.pushEventTo(this.el, "read_last_actions", {})
    this.el.addEventListener("regents:aside-opened", this.read)
    if (asideOpen()) this.read()
  },

  destroyed(this: PanelAgentsHook) {
    if (this.read) this.el.removeEventListener("regents:aside-opened", this.read)
  },
}
