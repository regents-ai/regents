/**
 * The colour theme. Until the visitor chooses, the page carries no theme and the
 * shared colours follow the device, dark unless it asks for light. A choice is
 * written to the cookie the server reads, so the next page is drawn in it, and
 * restated on the page at once.
 *
 * Every theme switch reads and chooses through here, and each one follows a
 * change made anywhere: by another switch, by live navigation, or by the device
 * while nothing is chosen.
 */

export type Theme = "light" | "dark"

export const THEME_COOKIE = "regent_theme"
const themeMaxAge = 60 * 60 * 24 * 365
const themeColors: Record<Theme, string> = {dark: "#161616", light: "#e5e3d2"}
const deviceLight = "(prefers-color-scheme: light)"

/** The theme the visitor chose, from cookie or localStorage; none until they choose. */
export function chosenTheme(): Theme | undefined {
  const prefix = `${THEME_COOKIE}=`
  const cookieValue = document.cookie
    .split("; ")
    .find(cookie => cookie.startsWith(prefix))
    ?.slice(prefix.length)

  if (cookieValue === "light" || cookieValue === "dark") return cookieValue

  try {
    const stored = window.localStorage.getItem(THEME_COOKIE)
    if (stored === "light" || stored === "dark") return stored
  } catch {
    // Storage may be unavailable in restricted contexts.
  }

  return undefined
}

/** The theme on screen: the page's own when it states one, otherwise the device's. */
export function showingTheme(): Theme {
  const theme = document.documentElement.dataset.theme
  if (theme === "light" || theme === "dark") return theme
  return window.matchMedia(deviceLight).matches ? "light" : "dark"
}

function writeCookie(theme: Theme): void {
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie = `${THEME_COOKIE}=${theme}; Path=/; Max-Age=${themeMaxAge}; SameSite=Lax${secure}`
}

/**
 * Live navigation keeps the document, so each page restates its theme: the
 * visitor's choice, or none so the device decides.
 */
export function syncTheme(): void {
  const root = document.documentElement
  const theme = chosenTheme()
  if (theme) {
    root.dataset.theme = theme
    writeCookie(theme)
  } else {
    delete root.dataset.theme
  }
  document.querySelector('meta[name="color-scheme"]')?.setAttribute("content", theme ?? "dark light")
  document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]').forEach(meta => {
    meta.content = themeColors[theme ?? (meta.media.includes("light") ? "light" : "dark")]
  })
}

/** Saves the visitor's choice for every later page and shows it on this one. */
export function chooseTheme(theme: Theme): void {
  writeCookie(theme)
  try {
    window.localStorage.setItem(THEME_COOKIE, theme)
  } catch {
    // Storage may be unavailable in restricted contexts.
  }
  syncTheme()
}

/**
 * Fallback for static pages or presses before the LiveView `ThemeSwitch` hook
 * mounts: pressing an unbound switch still toggles and persists the theme.
 */
export function installThemeSwitchFallback(): void {
  const syncButtons = (theme: Theme) => {
    document.querySelectorAll<HTMLButtonElement>("[data-theme-switch] [role='switch']").forEach(btn => {
      btn.setAttribute("aria-checked", String(theme === "light"))
    })
  }
  syncButtons(showingTheme())
  watchTheme(syncButtons)

  document.addEventListener("click", event => {
    const button =
      event.target instanceof Element
        ? event.target.closest<HTMLButtonElement>("[data-theme-switch] [role='switch']")
        : null
    if (!button) return
    const root = button.closest<HTMLElement>("[data-theme-switch]")
    if (!root || root.dataset.themeSwitchBound === "true") return
    chooseTheme(showingTheme() === "light" ? "dark" : "light")
  })
}

/**
 * Calls `listener` whenever the theme on screen changes, whoever changed it, and
 * returns the way to stop. It is never called for a restatement of the theme
 * already showing.
 */
export function watchTheme(listener: (theme: Theme) => void): () => void {
  let last = showingTheme()
  const check = () => {
    const next = showingTheme()
    if (next === last) return
    last = next
    listener(next)
  }
  const page = new MutationObserver(check)
  page.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
  const device = window.matchMedia(deviceLight)
  device.addEventListener("change", check)
  return () => {
    page.disconnect()
    device.removeEventListener("change", check)
  }
}
