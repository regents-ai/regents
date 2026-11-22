import type {Hook} from "../../hook_composition"
import type {KeyMapStage} from "./key_map/key_map_stage"
import type {LayoutKind} from "./key_map/layouts"
import type {KeyMapFound, KeyMapPatch, KeyMapPictures, KeyMapSnapshot} from "./key_map/state"

type KeyMapHook = {
  el: HTMLElement
  pushEvent<Reply>(event: string, payload: unknown, onReply: (reply: Reply) => void): void
  handleEvent<Payload>(event: string, callback: (payload: Payload) => void): void
  ready?: () => void
  cleanup?: () => void
}

/**
 * A fleet's key map. The map itself loads as its own chunk; this hook asks the
 * page for the fleet's keys on mount, after every reconnect and whenever the
 * page says too much changed to send, applies the changes the page sends in
 * between, asks for the card close-ups of the keys in view, and reports the
 * key a viewer chooses. Mount it on a
 * `phx-update="ignore"` element carrying `data-layout`, and `data-selected`
 * while the page has a key chosen.
 *
 * The page's controls reach the map as `keymap:next`, `keymap:mine`,
 * `keymap:level` and `keymap:find` events on the element; `keymap:level` comes
 * from a form whose `level` field names the level, and `keymap:find` from a
 * form whose `q` field holds what to look for and whose `found` output takes
 * the words saying what was found.
 */
export const KeyMap: Hook = {
  mounted(this: KeyMapHook) {
    let stage: KeyMapStage | undefined
    let alive = true
    // Left unanswered when the keys can't be read, the map stays as drawn
    // until it asks again.
    this.ready = () =>
      this.pushEvent<KeyMapSnapshot | undefined>("keymap_ready", {}, snapshot => snapshot && stage?.load(snapshot))
    void import("./key_map/key_map_stage").then(({createKeyMapStage}) => {
      if (!alive) return
      stage = createKeyMapStage(this.el, {
        layout: this.el.dataset.layout as LayoutKind,
        // A reply callback keeps a press made while offline from raising an error.
        select: key => this.pushEvent("select_key", {token_id: key}, () => {}),
        pictures: (keys, done) => this.pushEvent<KeyMapPictures>("keymap_pictures", {keys}, ({pictures}) => done(pictures)),
      })
      this.ready?.()
    })

    this.handleEvent<KeyMapPatch>("keymap:patch", patch => stage?.patch(patch))
    this.handleEvent<{token_id: number | null}>("keymap:select", ({token_id}) => stage?.select(token_id))
    this.handleEvent("keymap:reset", () => this.ready?.())

    const next = () => stage?.focusNext()
    const mine = () => stage?.focusMine()
    const level = (event: Event) => {
      const form = (event as CustomEvent<{dispatcher: HTMLFormElement}>).detail.dispatcher
      stage?.focusLevel(Number(new FormData(form).get("level")))
    }
    const find = (event: Event) => {
      const form = (event as CustomEvent<{dispatcher: HTMLFormElement}>).detail.dispatcher
      const note = form.elements.namedItem("found") as HTMLOutputElement
      this.pushEvent<KeyMapFound>("find_keys", {q: String(new FormData(form).get("q"))}, ({keys, words}) => {
        note.value = words
        stage?.find(keys)
      })
    }
    this.el.addEventListener("keymap:next", next)
    this.el.addEventListener("keymap:mine", mine)
    this.el.addEventListener("keymap:level", level)
    this.el.addEventListener("keymap:find", find)

    this.cleanup = () => {
      alive = false
      this.el.removeEventListener("keymap:next", next)
      this.el.removeEventListener("keymap:mine", mine)
      this.el.removeEventListener("keymap:level", level)
      this.el.removeEventListener("keymap:find", find)
      stage?.destroy()
    }
  },

  reconnected(this: KeyMapHook) {
    this.ready?.()
  },

  destroyed(this: KeyMapHook) {
    this.cleanup?.()
  },
}
