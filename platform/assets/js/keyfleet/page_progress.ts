// A thin bar along the top of the window while the next page is on its way.
// Most pages land before anyone would notice, so the bar waits a moment
// before it shows; when the page lands it fills and fades. Keyfleet's frame
// (shell_behavior.ts) brings the bar in once its first page has landed, so a
// later "initial" load is Back or Forward, and takes it away with itself.

/** How long a page may take before the bar shows, in milliseconds. */
const SHOW_AFTER = 120

type PageLoading = CustomEvent<{kind: string}>

/** Adds the bar to the page; returns what takes it away again. */
export function mountPageProgress(): () => void {
  const bar = document.createElement("div")
  bar.className = "page-progress"
  bar.setAttribute("aria-hidden", "true")
  document.body.append(bar)
  let timer: number | undefined

  const onStart = (event: Event) => {
    const {kind} = (event as PageLoading).detail
    if (kind !== "redirect" && kind !== "patch" && kind !== "initial") return
    window.clearTimeout(timer)
    timer = window.setTimeout(() => {
      // Back to empty first, so a bar still fading from the last page starts over.
      delete bar.dataset.state
      void bar.offsetWidth
      bar.dataset.state = "running"
    }, SHOW_AFTER)
  }

  // Any page landing ends the bar, whatever started it: a redirect whose page
  // has to join again only stops when that page's own join does.
  const onStop = () => {
    window.clearTimeout(timer)
    if (bar.dataset.state === "running") bar.dataset.state = "done"
  }

  const onTransitionEnd = (event: TransitionEvent) => {
    if (event.propertyName === "opacity" && bar.dataset.state === "done") delete bar.dataset.state
  }

  window.addEventListener("phx:page-loading-start", onStart)
  window.addEventListener("phx:page-loading-stop", onStop)
  bar.addEventListener("transitionend", onTransitionEnd)

  return () => {
    window.clearTimeout(timer)
    window.removeEventListener("phx:page-loading-start", onStart)
    window.removeEventListener("phx:page-loading-stop", onStop)
    bar.remove()
  }
}
