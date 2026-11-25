type DocsHook = {el: HTMLElement; controller?: AbortController; observer?: IntersectionObserver}

// The docs heading indicator and Ask AI menu.
export const Docs = {
  mounted(this: DocsHook) {
    this.controller = new AbortController()
    const {signal} = this.controller
    this.observer = installSpy(this.el)
    installAskMenu(this.el, signal)
  },

  destroyed(this: DocsHook) {
    this.controller?.abort()
    this.observer?.disconnect()
  },
}

// The heading the reader is in, marked in the "On this page" list beside the page.
// The reading band starts under the docs bar, which stays in view as the page scrolls.
function installSpy(root: HTMLElement): IntersectionObserver | undefined {
  const list = root.querySelector<HTMLElement>("[data-docs-spy]")
  if (!list) return

  const links = new Map<string, HTMLAnchorElement>()
  list.querySelectorAll<HTMLAnchorElement>("a[href^='#']").forEach(link => {
    links.set(decodeURIComponent(link.hash.slice(1)), link)
  })
  const headings = [...links.keys()]
    .map(id => document.getElementById(id))
    .filter((heading): heading is HTMLElement => heading !== null)
  if (!headings.length) return

  const scroller = root.closest<HTMLElement>("#app-shell-scroller")
  const scrollerTop = scroller ? scroller.getBoundingClientRect().top : 0
  const barBottom = root.querySelector(".docs-bar")?.getBoundingClientRect().bottom ?? scrollerTop + 120
  const band = Math.max(0, Math.round(barBottom - scrollerTop))
  const visible = new Set<Element>()
  const mark = () => {
    const current = headings.find(heading => visible.has(heading)) ?? above(headings, barBottom)
    links.forEach((link, id) => {
      if (current && id === current.id) link.setAttribute("aria-current", "true")
      else link.removeAttribute("aria-current")
    })
  }

  const observer = new IntersectionObserver(
    entries => {
      entries.forEach(entry => (entry.isIntersecting ? visible.add(entry.target) : visible.delete(entry.target)))
      mark()
    },
    {root: scroller, rootMargin: `-${band}px 0px -60% 0px`},
  )
  headings.forEach(heading => observer.observe(heading))
  return observer
}

// With no heading in the reading band, the last one scrolled past.
function above(headings: HTMLElement[], band: number): HTMLElement | undefined {
  return headings.filter(heading => heading.getBoundingClientRect().top < band).at(-1)
}

// Keeps Ask AI's aria-expanded state in sync and positions the popover under its
// trigger in browsers without CSS Anchor Positioning.
function installAskMenu(root: HTMLElement, signal: AbortSignal) {
  const trigger = root.querySelector<HTMLButtonElement>("#docs-ask-trigger")
  const menu = root.querySelector<HTMLElement>("#docs-ask-menu")
  if (!trigger || !menu) return

  const anchored = typeof CSS !== "undefined" && CSS.supports("position-anchor: --docs-ask")
  const place = () => {
    if (anchored) return
    const box = trigger.getBoundingClientRect()
    menu.style.top = `${Math.round(box.bottom + 8)}px`
    menu.style.right = `${Math.max(8, Math.round(window.innerWidth - box.right))}px`
    menu.style.left = "auto"
    menu.style.bottom = "auto"
  }

  menu.addEventListener("beforetoggle", event => {
    const open = (event as ToggleEvent).newState === "open"
    trigger.setAttribute("aria-expanded", String(open))
    if (open) place()
  }, {signal})

  menu.addEventListener("click", event => {
    if (event.target instanceof Element && event.target.closest("a") && menu.matches(":popover-open")) {
      menu.hidePopover()
    }
  }, {signal})
}
