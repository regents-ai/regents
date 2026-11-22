import type {Hook} from "../../hook_composition"
import type {LayoutKind} from "./key_map/layouts"

type FleetPreviewHook = {
  el: HTMLElement
  draw?: () => void
}

/**
 * A still picture of a fleet's map, on its homepage card and on the page of
 * a fleet not yet on sale. The drawing loads as its own chunk and is drawn
 * again whenever the page changes `data-minted`. Mount it on a
 * `phx-update="ignore"` element carrying `data-layout` and `data-minted`.
 */
export const FleetPreview: Hook = {
  mounted(this: FleetPreviewHook) {
    void import("./key_map/preview").then(({drawPreview}) => {
      this.draw = () => drawPreview(this.el, this.el.dataset.layout as LayoutKind, Number(this.el.dataset.minted))
      this.draw()
    })
  },

  updated(this: FleetPreviewHook) {
    this.draw?.()
  },
}
