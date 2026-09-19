import type {Hook} from "../hook_composition"

type NamesViewHook = Hook & {
  el: HTMLElement
  pushEvent(event: string, payload: unknown): void
}

const STORAGE_KEY = "regents:names-view"
const VIEWS = new Set(["ens", "basename"])

/**
 * Remembers which form of a claimed name this browser last chose. The page
 * states the form it shows in `data-view`; a remembered choice that differs is
 * asked for once on mount, and every change the page makes is remembered.
 */
export const NamesView: Hook = {
  mounted(this: NamesViewHook) {
    const remembered = read()
    if (remembered && remembered !== this.el.dataset.view) {
      this.pushEvent("set_names_view", {view: remembered})
    }
  },

  updated(this: NamesViewHook) {
    const view = this.el.dataset.view
    if (view && VIEWS.has(view)) write(view)
  },
}

function read(): string | null {
  try {
    const view = window.localStorage.getItem(STORAGE_KEY)
    return view && VIEWS.has(view) ? view : null
  } catch {
    return null
  }
}

function write(view: string) {
  try {
    window.localStorage.setItem(STORAGE_KEY, view)
  } catch {
    // A browser that keeps nothing still shows the form the page chose.
  }
}
