import type {Hook} from "../hook_composition"

interface InfoDialogHook {
  el: HTMLDialogElement
  wasOpen?: boolean
}

// A server-rendered <dialog> of figures that opens when something on the page
// asks it to, and stays open while the reading behind its figures is replaced.
export const InfoDialog: Hook = {
  mounted(this: InfoDialogHook) {
    this.el.addEventListener("regents:open", () => {
      if (!this.el.open) this.el.showModal()
    })
  },

  beforeUpdate(this: InfoDialogHook) {
    this.wasOpen = this.el.open
  },

  updated(this: InfoDialogHook) {
    if (this.wasOpen && !this.el.open) this.el.showModal()
  },
}
