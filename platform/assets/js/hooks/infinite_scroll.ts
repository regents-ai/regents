import type {Hook} from "../hook_composition"

type InfiniteScrollHook = Hook & {
  el: HTMLElement
  pushEvent(event: string, payload: unknown): void
  observer?: IntersectionObserver
  requested?: string
}

/**
 * A marker at the end of a list that asks the page for the next rows when it
 * scrolls into view. The page names the event in `data-event` and marks each
 * batch it has shown with a new `data-cursor`, so one batch is asked for once
 * and the next only after the previous one has landed.
 */
export const InfiniteScroll: Hook = {
  mounted(this: InfiniteScrollHook) {
    this.observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) request(this)
    })
    this.observer.observe(this.el)
  },

  // A landed batch may leave the marker still in view; observing it again
  // reports where it stands now.
  updated(this: InfiniteScrollHook) {
    this.observer?.unobserve(this.el)
    this.observer?.observe(this.el)
  },

  destroyed(this: InfiniteScrollHook) {
    this.observer?.disconnect()
  },
}

function request(hook: InfiniteScrollHook) {
  const cursor = hook.el.dataset.cursor ?? ""
  if (hook.requested === cursor) return
  hook.requested = cursor
  hook.pushEvent(hook.el.dataset.event ?? "load_more", {})
}
