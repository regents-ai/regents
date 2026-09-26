import type {Hook} from "../hook_composition"

interface InfoDialogHook {
  el: HTMLDialogElement
  wasOpen?: boolean
  pushEvent(event: string, payload: object): void
}

// A server-rendered <dialog> of figures that opens when something on the page
// asks it to, and stays open while the reading behind its figures is replaced.
// One rendered only while it has something to show opens as it arrives
// (`data-open`) and tells the page when the reader closes it (`data-close-event`).
export const InfoDialog: Hook = {
  mounted(this: InfoDialogHook) {
    this.el.addEventListener("regents:open", () => {
      if (!this.el.open) this.el.showModal()
    })

    const closeEvent = this.el.dataset.closeEvent
    if (closeEvent) this.el.addEventListener("close", () => this.pushEvent(closeEvent, {}))

    if (this.el.hasAttribute("data-open")) this.el.showModal()
  },

  beforeUpdate(this: InfoDialogHook) {
    this.wasOpen = this.el.open
  },

  updated(this: InfoDialogHook) {
    if (this.wasOpen && !this.el.open) this.el.showModal()
  },
}
