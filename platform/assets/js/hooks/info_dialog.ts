import type {Hook} from "../hook_composition"

interface InfoDialogHook {
  el: HTMLDialogElement
  js(): {ignoreAttributes(el: HTMLElement, attrs: string[]): void}
  pushEventTo(target: HTMLElement, event: string, payload: object): void
}

// A server-rendered <dialog> of figures that opens when something on the page
// asks it to, and stays open while the reading behind its figures is replaced:
// redraws keep its `open` and the inline style its rise is drawn with, so it
// neither closes nor rises again under them. One rendered only while it has
// something to show opens as it arrives (`data-open`) and tells whatever
// rendered it, the page or a part of it, when the reader closes it
// (`data-close-event`).
export const InfoDialog: Hook = {
  mounted(this: InfoDialogHook) {
    this.js().ignoreAttributes(this.el, ["open", "style"])

    this.el.addEventListener("regents:open", () => {
      if (!this.el.open) this.el.showModal()
    })

    const closeEvent = this.el.dataset.closeEvent
    if (closeEvent) this.el.addEventListener("close", () => this.pushEventTo(this.el, closeEvent, {}))

    if (this.el.hasAttribute("data-open")) this.el.showModal()
  },
}
