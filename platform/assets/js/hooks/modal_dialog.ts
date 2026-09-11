import type {Hook} from "../hook_composition"

interface ModalDialogHook {
  el: HTMLDialogElement
  pushEvent(event: string, payload: Record<string, never>): void
}

// A server-rendered <dialog> that is modal for exactly as long as it is in the
// document: it opens on mount, and closing it by hand tells the server so the
// element leaves the page instead of lingering closed.
export const ModalDialog: Hook = {
  mounted(this: ModalDialogHook) {
    const dialog = this.el
    dialog.addEventListener("close", () => {
      const event = dialog.dataset.dismissEvent
      if (event) this.pushEvent(event, {})
    })
    if (!dialog.open) dialog.showModal()
  },
}
