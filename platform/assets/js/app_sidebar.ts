const preferenceKey = "regents:sidebar-collapsed"
const phoneQuery = "(max-width: 47.99rem)"

export function installAppSidebar() {
  let current: HTMLElement | null = null
  let cleanup: (() => void) | undefined

  const mount = () => {
    const bar = document.getElementById("workspace-bar")
    if (bar === current) return
    cleanup?.()
    current = bar
    cleanup = bar ? mountSidebar(bar) : undefined
  }

  mount()
  window.addEventListener("phx:page-loading-stop", mount)
  window.addEventListener("pageshow", mount)
}

function mountSidebar(bar: HTMLElement) {
  const toggle = bar.querySelector<HTMLButtonElement>("[data-workspace-toggle]")
  const nav = bar.querySelector<HTMLElement>(".workspace-sidebar")
  if (!toggle || !nav) return

  const phone = window.matchMedia(phoneQuery)
  const listeners = new AbortController()
  const options = {signal: listeners.signal}
  let collapsed = false
  let mobileOpen = false

  try {
    collapsed = localStorage.getItem(preferenceKey) === "true"
  } catch {
    // Navigation remains usable when storage is unavailable.
  }

  const sync = () => {
    const expanded = phone.matches ? mobileOpen : !collapsed
    const label = phone.matches
      ? (expanded ? "Close products" : "Open products")
      : (expanded ? "Collapse sidebar" : "Expand sidebar")

    bar.dataset.collapsed = String(collapsed)
    bar.dataset.mobileOpen = String(mobileOpen)
    toggle.setAttribute("aria-expanded", String(expanded))
    toggle.setAttribute("aria-label", label)
  }

  const setCollapsed = (value: boolean) => {
    collapsed = value
    try {
      localStorage.setItem(preferenceKey, String(value))
    } catch {
      // Keep the preference for this page.
    }
    sync()
  }

  const closeMobile = () => {
    mobileOpen = false
    sync()
    toggle.focus()
  }

  toggle.addEventListener("click", () => {
    if (!phone.matches) {
      setCollapsed(!collapsed)
    } else if (mobileOpen) {
      closeMobile()
    } else {
      mobileOpen = true
      sync()
      nav.querySelector<HTMLElement>("summary")?.focus()
    }
  }, options)

  nav.addEventListener("click", (event) => {
    if (phone.matches || !collapsed || !(event.target instanceof Element)) return
    const summary = event.target.closest("summary")
    if (!(summary?.parentElement instanceof HTMLDetailsElement)) return

    event.preventDefault()
    summary.parentElement.open = true
    setCollapsed(false)
  }, options)

  bar.querySelector("[data-workspace-scrim]")?.addEventListener("click", closeMobile, options)
  bar.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && mobileOpen) {
      event.preventDefault()
      closeMobile()
    }
  }, options)
  document.addEventListener("focusin", (event) => {
    if (mobileOpen && event.target instanceof Node && !bar.contains(event.target)) {
      mobileOpen = false
      sync()
    }
  }, options)
  phone.addEventListener("change", () => {
    mobileOpen = false
    sync()
  }, options)

  sync()
  return () => listeners.abort()
}
