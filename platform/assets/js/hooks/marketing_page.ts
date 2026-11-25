/**
 * LiveView hook for the Regents marketing pages (`/`, `/techtree`, `/keyfleet`,
 * `/autolaunch`, `/patchbay`):
 *
 * - Stripe-style solid inverse top bar (`data-lit`) and 3-column dropdown menus
 *   (Products, Agents, Reading) with 80ms intent delay, 150ms leave grace,
 *   directional crossfade, and zero-motion keyboard opening (`data-instant`).
 * - Fixed bar ground transition on scroll (`data-scrolled`, `data-over="hero"`).
 * - Phone navigation sheet (`#sheet`) with `inert` background locking & Escape.
 * - Modal dialogs (`dialog.window`, e.g., `#tools` listing all 22 WebMCP tools).
 * - Copy prompt buttons (`[data-copy-from]`) with live region announcements.
 *
 * Note: The light/dark theme switch is the existing `Shell.theme_toggle/1`
 * component with its own `ThemeSwitch` hook — untouched here.
 */
import type {Hook} from "../hook_composition"

type MarketingPageHook = {
  el: HTMLElement
  cleanup?: () => void
}

const INTENT = 80
const GRACE = 150

export const MarketingPage: Hook = {
  mounted(this: MarketingPageHook) {
    const page = this.el
    const docRoot = document.documentElement
    const bar = page.querySelector<HTMLElement>("[data-bar]")
    const sheet = page.querySelector<HTMLElement>("#sheet")
    const announce = page.querySelector<HTMLElement>("#announce")

    if (!bar) return

    const cleanups: Array<() => void> = []
    const listen = <T extends EventTarget>(
      target: T,
      type: string,
      handler: EventListenerOrEventListenerObject,
      options?: boolean | AddEventListenerOptions,
    ) => {
      target.addEventListener(type, handler, options)
      cleanups.push(() => target.removeEventListener(type, handler, options))
    }

    const triggers = [...bar.querySelectorAll<HTMLButtonElement>("[data-menu-trigger]")]
    const menuOf = (trigger: HTMLButtonElement): HTMLElement | null => {
      const id = trigger.getAttribute("aria-controls")
      return id ? document.getElementById(id) : null
    }
    const linksOf = (trigger: HTMLButtonElement): HTMLAnchorElement[] => {
      const menu = menuOf(trigger)
      return menu ? [...menu.querySelectorAll<HTMLAnchorElement>("a")] : []
    }

    let active: HTMLButtonElement | null = null
    let openedBy: "hover" | "press" | "keys" | null = null
    let pointerIn = false
    let focusIn = false
    let returningFocus = false
    let intentTimer = 0
    let graceTimer = 0

    const light = () => bar.toggleAttribute("data-lit", pointerIn || focusIn || active !== null)

    const measure = () => {
      const heights = triggers.map(trigger => menuOf(trigger)?.offsetHeight ?? 0)
      const maxH = heights.length > 0 ? Math.max(...heights) : 0
      bar.style.setProperty("--menu-max", `${maxH}px`)
      if (active) {
        const menuH = menuOf(active)?.offsetHeight ?? 0
        bar.style.setProperty("--open-h", `${bar.offsetHeight + menuH}px`)
      }
    }

    const show = (trigger: HTMLButtonElement, how: "hover" | "press" | "keys") => {
      window.clearTimeout(intentTimer)
      window.clearTimeout(graceTimer)
      bar.toggleAttribute("data-instant", how === "keys")
      if (trigger === active) {
        if (how !== "hover") openedBy = how
        return
      }
      const menu = menuOf(trigger)
      if (!menu) return

      if (active) {
        const from = triggers.indexOf(trigger) > triggers.indexOf(active) ? "right" : "left"
        const old = menuOf(active)
        if (old) {
          old.dataset.leave = from === "right" ? "left" : "right"
          delete old.dataset.active
        }
        active.setAttribute("aria-expanded", "false")
        delete menu.dataset.leave
        menu.dataset.from = from
        menu.getBoundingClientRect()
        delete menu.dataset.from
      } else {
        delete menu.dataset.leave
      }

      menu.dataset.active = ""
      trigger.setAttribute("aria-expanded", "true")
      measure()
      bar.style.setProperty("--open-h", `${bar.offsetHeight + menu.offsetHeight}px`)
      bar.dataset.open = ""
      active = trigger
      openedBy = how
      light()
    }

    const hide = ({returnFocus = false}: {returnFocus?: boolean} = {}) => {
      window.clearTimeout(intentTimer)
      window.clearTimeout(graceTimer)
      if (!active) return
      const trigger = active
      const menu = menuOf(trigger)
      if (menu) delete menu.dataset.active
      trigger.setAttribute("aria-expanded", "false")
      bar.style.removeProperty("--open-h")
      delete bar.dataset.open
      active = null
      openedBy = null
      if (returnFocus) trigger.focus()
      light()
    }

    const closeSoon = () => {
      window.clearTimeout(intentTimer)
      window.clearTimeout(graceTimer)
      if (active) graceTimer = window.setTimeout(() => hide(), GRACE)
    }

    for (const trigger of triggers) {
      listen(trigger, "pointerenter", event => {
        if ((event as PointerEvent).pointerType !== "mouse") return
        window.clearTimeout(graceTimer)
        window.clearTimeout(intentTimer)
        if (active) show(trigger, "hover")
        else intentTimer = window.setTimeout(() => show(trigger, "hover"), INTENT)
      })

      listen(trigger, "pointerleave", () => window.clearTimeout(intentTimer))

      listen(trigger, "click", event => {
        const mouse = event as MouseEvent
        if (mouse.detail === 0) {
          if (trigger === active) hide({returnFocus: true})
          else {
            show(trigger, "keys")
            linksOf(trigger)[0]?.focus()
          }
          return
        }
        if (trigger === active && openedBy !== "hover") hide()
        else show(trigger, "press")
      })

      listen(trigger, "keydown", event => {
        const key = (event as KeyboardEvent).key
        if (key === "ArrowDown") {
          event.preventDefault()
          show(trigger, "keys")
          linksOf(trigger)[0]?.focus()
        }
      })

      const menu = menuOf(trigger)
      if (menu) {
        listen(menu, "pointerenter", () => window.clearTimeout(graceTimer))
        listen(menu, "click", event => {
          if (event.target instanceof Element && event.target.closest("a")) hide()
        })
        listen(menu, "keydown", event => {
          const kb = event as KeyboardEvent
          const links = linksOf(trigger)
          if (links.length === 0) return
          const here = links.indexOf(document.activeElement as HTMLAnchorElement)
          const map: Record<string, HTMLAnchorElement | undefined> = {
            ArrowDown: links[(here + 1) % links.length],
            ArrowUp: links[(here - 1 + links.length) % links.length],
            Home: links[0],
            End: links[links.length - 1],
          }
          const go = map[kb.key]
          if (go) {
            kb.preventDefault()
            go.focus()
          }
        })
      }
    }

    const navItems = [...bar.querySelectorAll<HTMLElement>(".bar__trigger, .bar__link")]
    for (const item of navItems) {
      listen(item, "keydown", event => {
        const kb = event as KeyboardEvent
        const step = kb.key === "ArrowRight" ? 1 : kb.key === "ArrowLeft" ? -1 : 0
        if (!step || navItems.length === 0) return
        kb.preventDefault()
        navItems[(navItems.indexOf(item) + step + navItems.length) % navItems.length]?.focus()
      })
    }

    for (const part of bar.querySelectorAll<HTMLElement>("[data-menu-off]")) {
      listen(part, "pointerenter", event => {
        if ((event as PointerEvent).pointerType === "mouse") closeSoon()
      })
    }

    listen(bar, "pointerenter", event => {
      if ((event as PointerEvent).pointerType !== "mouse") return
      pointerIn = true
      window.clearTimeout(graceTimer)
      light()
    })

    listen(bar, "pointerleave", event => {
      if ((event as PointerEvent).pointerType !== "mouse") return
      pointerIn = false
      if (active && openedBy === "hover") closeSoon()
      light()
    })

    listen(bar, "pointermove", () => delete bar.dataset.instant)

    listen(bar, "focusin", event => {
      if (returningFocus) return
      const target = event.target
      focusIn = target instanceof Element && target.matches(":focus-visible")
      light()
    })

    listen(bar, "focusout", event => {
      const related = (event as FocusEvent).relatedTarget as Node | null
      if (bar.contains(related)) {
        if (active && !active.parentElement?.contains(related)) hide()
        return
      }
      focusIn = false
      hide()
      light()
    })

    listen(document, "keydown", event => {
      const kb = event as KeyboardEvent
      if (kb.metaKey || kb.ctrlKey || kb.altKey) return
      bar.dataset.instant = ""
      if (kb.key === "Escape" && active) {
        const inside = active.parentElement?.contains(document.activeElement) ?? false
        pointerIn = false
        focusIn = false
        returningFocus = inside
        hide({returnFocus: inside})
        returningFocus = false
      }
    })

    listen(document, "pointerdown", event => {
      if (active && !bar.contains(event.target as Node | null)) hide()
    })

    measure()
    listen(window, "resize", measure)
    document.fonts?.ready.then(measure)

    // Scroll ground & hero overlap.
    const hero = page.querySelector<HTMLElement>("[data-hero-section]")
    const menuButton = bar.querySelector<HTMLButtonElement>(".bar__menu-button")
    const place = () => {
      bar.toggleAttribute("data-scrolled", window.scrollY > 0)
      const over =
        Boolean(hero) &&
        !sheet?.hasAttribute("data-open") &&
        (hero?.getBoundingClientRect().bottom ?? 0) > bar.offsetHeight
      if (over) bar.dataset.over = "hero"
      else delete bar.dataset.over
    }
    listen(window, "scroll", place, {passive: true})
    place()

    // Phone sheet.
    const behind = () => {
      if (!page.hasAttribute("data-public-header")) {
        return [...page.children].filter(
          element => element instanceof HTMLElement && element !== bar && element !== sheet &&
            element.tagName !== "SCRIPT",
        ) as HTMLElement[]
      }

      const siblings: HTMLElement[] = []
      for (let node = page; node.parentElement && node !== document.body; node = node.parentElement) {
        for (const sibling of node.parentElement.children) {
          if (sibling instanceof HTMLElement && sibling !== node) siblings.push(sibling)
        }
      }
      return siblings
    }

    const previousInert = new Map<HTMLElement, boolean>()

    const restoreBackground = () => {
      for (const [element, inert] of previousInert) element.inert = inert
      previousInert.clear()
    }

    const openSheet = () => {
      if (!sheet || !menuButton) return
      sheet.dataset.open = ""
      bar.dataset.sheet = ""
      docRoot.dataset.sheetOpen = ""
      menuButton.setAttribute("aria-expanded", "true")
      for (const element of behind()) {
        previousInert.set(element, element.inert)
        element.inert = true
      }
      place()
      sheet.querySelector<HTMLAnchorElement>("a")?.focus()
    }

    const closeSheet = ({returnFocus = true}: {returnFocus?: boolean} = {}) => {
      if (!sheet || !menuButton) return
      delete sheet.dataset.open
      delete bar.dataset.sheet
      delete docRoot.dataset.sheetOpen
      menuButton.setAttribute("aria-expanded", "false")
      restoreBackground()
      place()
      if (returnFocus) menuButton.focus()
    }

    if (menuButton && sheet) {
      listen(menuButton, "click", () => {
        if (sheet.hasAttribute("data-open")) closeSheet()
        else openSheet()
      })
      listen(sheet, "keydown", event => {
        if ((event as KeyboardEvent).key === "Escape") closeSheet()
      })
      listen(sheet, "click", event => {
        if (event.target instanceof Element && event.target.closest("a")) {
          closeSheet({returnFocus: false})
        }
      })
      listen(bar, "keydown", event => {
        if ((event as KeyboardEvent).key === "Escape" && sheet.hasAttribute("data-open")) {
          closeSheet()
        }
      })
      const narrow = window.matchMedia("(max-width: 64rem)")
      const onWidth = (event: MediaQueryListEvent) => {
        if (!event.matches && sheet.hasAttribute("data-open")) closeSheet({returnFocus: false})
      }
      narrow.addEventListener("change", onWidth)
      cleanups.push(() => narrow.removeEventListener("change", onWidth))
    }

    // Modal windows (e.g. #tools 22 WebMCP tools dialog).
    const openers = new Map<HTMLDialogElement, HTMLButtonElement>()
    for (const opener of page.querySelectorAll<HTMLButtonElement>("[data-window-open]")) {
      const id = opener.getAttribute("aria-controls")
      const dialog = id ? (document.getElementById(id) as HTMLDialogElement | null) : null
      if (!dialog) continue
      listen(opener, "click", event => {
        dialog.toggleAttribute("data-instant", (event as MouseEvent).detail === 0)
        openers.set(dialog, opener)
        if (!dialog.open) dialog.showModal()
        dialog.scrollTop = 0
      })
    }

    for (const dialog of page.querySelectorAll<HTMLDialogElement>("dialog.window")) {
      listen(dialog, "cancel", () => dialog.setAttribute("data-instant", ""))
      listen(dialog, "click", event => {
        const mouse = event as MouseEvent
        if (mouse.target !== dialog) return
        const box = dialog.getBoundingClientRect()
        const outside =
          mouse.clientX < box.left ||
          mouse.clientX > box.right ||
          mouse.clientY < box.top ||
          mouse.clientY > box.bottom
        if (outside) dialog.close()
      })
      for (const button of dialog.querySelectorAll<HTMLButtonElement>("[data-window-close]")) {
        listen(button, "click", event => {
          dialog.toggleAttribute("data-instant", (event as MouseEvent).detail === 0)
          dialog.close()
        })
      }
      listen(dialog, "close", () => openers.get(dialog)?.focus())
    }

    // Copy buttons.
    const copyTimers: number[] = []
    for (const button of page.querySelectorAll<HTMLButtonElement>("[data-copy-from]")) {
      listen(button, "click", async () => {
        const sourceId = button.dataset.copyFrom
        const source = sourceId ? document.getElementById(sourceId) : null
        let state: "done" | "failed" = "failed"
        if (source?.textContent) {
          try {
            await navigator.clipboard.writeText(source.textContent)
            state = "done"
          } catch {
            state = "failed"
          }
        }
        button.dataset.copyState = state
        if (announce) announce.textContent = state === "done" ? "Copied" : "Couldn't copy"
        const timer = window.setTimeout(() => {
          delete button.dataset.copyState
          if (announce) announce.textContent = ""
        }, 1600)
        copyTimers.push(timer)
      })
    }

    this.cleanup = () => {
      window.clearTimeout(intentTimer)
      window.clearTimeout(graceTimer)
      for (const timer of copyTimers) window.clearTimeout(timer)
      for (const dispose of cleanups) dispose()
      if (sheet?.hasAttribute("data-open")) closeSheet({returnFocus: false})
    }
  },

  destroyed(this: MarketingPageHook) {
    this.cleanup?.()
    this.cleanup = undefined
  },
}

// Public reading also uses controller-rendered HTML, so its header cannot depend
// on a LiveView socket. Mount again only when navigation replaces the element.
export function installPublicHeader() {
  let header: MarketingPageHook | undefined

  const mount = () => {
    const el = document.querySelector<HTMLElement>("[data-public-header]")
    if (el === (header?.el ?? null)) return

    header?.cleanup?.()
    header = el ? {el} : undefined
    if (header) MarketingPage.mounted?.call(header)
  }

  mount()
  window.addEventListener("phx:page-loading-stop", mount)
}
