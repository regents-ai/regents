import type {Hook} from "../../hook_composition"
import type {TreeStage} from "./tree_canvas/stage"

type TreeCanvasHook = {
  el: HTMLElement
  stage?: TreeStage
  alive?: boolean
}

/**
 * A tree canvas (`./tree_canvas/stage`), which loads as its own chunk. Mount
 * it on an element carrying the cards and links as JSON in `data-tree` and
 * the arrangement in `data-arrange` and `data-every`, around a
 * `phx-update="ignore"` stage holding the surface the cards are drawn on.
 * The page changes the data attributes; the canvas lays itself out again
 * when they change.
 */
export const TreeCanvas: Hook = {
  mounted(this: TreeCanvasHook) {
    this.alive = true
    void import("./tree_canvas/stage").then(({createTreeStage}) => {
      if (this.alive) this.stage = createTreeStage(this.el)
    })
  },
  updated(this: TreeCanvasHook) {
    this.stage?.update()
  },
  disconnected(this: TreeCanvasHook) {
    this.stage?.pause()
  },
  reconnected(this: TreeCanvasHook) {
    this.stage?.resume()
  },
  destroyed(this: TreeCanvasHook) {
    this.alive = false
    this.stage?.destroy()
  },
}
