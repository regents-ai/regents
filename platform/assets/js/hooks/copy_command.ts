import {deny} from "./motion/press"
import type {Hook} from "../hook_composition"
import {
  copyButtonLabel,
  copyStatusMessage,
  copyWithFallback,
  dismissInlineFallback,
} from "../copy_fallback"

type CopyCommandHook = Hook & {
  el: HTMLButtonElement
  idleLabel?: string
  timer?: number
  statusEl?: HTMLElement
  onClick?: () => void
}

const RESET_MS = 2200

/**
 * Copy button hook for install and API commands (`/cloak`, `/cloak/install`,
 * `/cloak/download/mac`). Falls back cleanly to selectable text and honest
 * status text when browser policy blocks clipboard writes.
 */
export const CopyCommand: Hook = {
  mounted(this: CopyCommandHook) {
    this.idleLabel = (this.el.textContent ?? "Copy").trim() || "Copy"

    const status = document.createElement("span")
    status.className = "visually-hidden"
    status.setAttribute("role", "status")
    status.setAttribute("aria-live", "polite")
    this.el.insertAdjacentElement("afterend", status)
    this.statusEl = status

    this.onClick = async () => {
      const text = this.el.dataset.copy ?? ""
      const targetId = this.el.dataset.copyTarget
      const target = targetId ? document.getElementById(targetId) : null
      const outcome = await copyWithFallback(text, {
        target,
        anchor: this.el,
        label: this.el.getAttribute("aria-label") ?? "Copy command",
      })
      if (!this.el.isConnected) return

      this.el.dataset.copyState = outcome
      this.el.textContent = copyButtonLabel(outcome)
      this.el.title = copyStatusMessage(outcome)
      if (this.statusEl) this.statusEl.textContent = copyStatusMessage(outcome)
      if (outcome === "failed") deny(this.el)

      window.clearTimeout(this.timer)
      this.timer = window.setTimeout(() => {
        if (!this.el.isConnected) return
        delete this.el.dataset.copyState
        this.el.textContent = this.idleLabel ?? "Copy"
        this.el.removeAttribute("title")
        if (this.statusEl) this.statusEl.textContent = ""
      }, outcome === "selected" ? 4000 : RESET_MS)
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed(this: CopyCommandHook) {
    window.clearTimeout(this.timer)
    if (this.onClick) this.el.removeEventListener("click", this.onClick)
    this.statusEl?.remove()
    dismissInlineFallback(this.el)
  },
}
