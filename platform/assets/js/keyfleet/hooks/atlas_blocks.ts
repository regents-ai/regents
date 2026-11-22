import type {Hook} from "../../hook_composition"
import type {Ask, BlocksStage} from "../atlas/blocks/stage"

type AtlasBlocksHook = {
  el: HTMLElement
  stage?: BlocksStage
  alive?: boolean
  pushEvent<Reply>(event: string, payload: object, onReply?: (reply: Reply) => void): void
  handleEvent<Payload>(event: string, callback: (payload: Payload) => void): void
}

/**
 * The Atlas as blocks (`../atlas/blocks/stage`), which loads as its own
 * chunk. Mount it on an element carrying the projects as JSON in
 * `data-rows`, the kinds of work in `data-kinds`, the window in
 * `data-window`, `data-from` and `data-to`, and the kind shown in
 * `data-kind`, around a `phx-update="ignore"` stage. The blocks ask the page
 * for the window's counts and for each kind's things as the reader opens
 * them, and read them again when the page says the fleet's work was counted
 * again (`atlas:changed`).
 */
export const AtlasBlocks: Hook = {
  mounted(this: AtlasBlocksHook) {
    this.alive = true
    const ask: Ask = (event, payload, reply) => this.pushEvent(event, payload, reply)
    this.handleEvent("atlas:changed", () => this.stage?.changed())
    void import("../atlas/blocks/stage").then(({createBlocksStage}) => {
      if (this.alive) this.stage = createBlocksStage(this.el, ask)
    })
  },
  updated(this: AtlasBlocksHook) {
    this.stage?.update()
  },
  disconnected(this: AtlasBlocksHook) {
    this.stage?.pause()
  },
  reconnected(this: AtlasBlocksHook) {
    this.stage?.resume()
  },
  destroyed(this: AtlasBlocksHook) {
    this.alive = false
    this.stage?.destroy()
  },
}
