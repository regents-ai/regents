import {Heerich} from "heerich"
// The alias is resolved against the worktree's pinned regent_ui checkout by esbuild.
// @ts-ignore -- Mix owns the dependency path; it is not an npm package.
import {RegentScene} from "@regent-ui/assets/js/hooks/regent_scene"
import {selectConnectedEthereumWallet} from "./wallet_actions/connected_wallet"

Object.assign(window, {Heerich})

type Palette = {bg: string; surface: string; fg: string; accent: string}
const defaults: Record<string, Record<string, Palette>> = {
  platform: {
    dark: {bg: "#191918", surface: "#222220", fg: "#e5e3d2", accent: "#a5cce4"},
    light: {
      bg: "#f5f4ee",
      surface: "#ffffff",
      fg: "#242522",
      accent: "#315c76",
    },
  },
  autolaunch: {
    dark: {bg: "#211b17", surface: "#2d241d", fg: "#f6e6d6", accent: "#ef9c61"},
    light: {
      bg: "#f9efe3",
      surface: "#fff9f1",
      fg: "#38251a",
      accent: "#9a491f",
    },
  },
  patchbay: {
    dark: {bg: "#171a20", surface: "#202630", fg: "#e1e8f2", accent: "#93b5eb"},
    light: {
      bg: "#eef2f8",
      surface: "#ffffff",
      fg: "#202b3c",
      accent: "#375f9b",
    },
  },
  techtree: {
    dark: {bg: "#15201c", surface: "#1f2c25", fg: "#e0e9df", accent: "#a0c3a6"},
    light: {
      bg: "#edf1e8",
      surface: "#f9fcf6",
      fg: "#253429",
      accent: "#456c4c",
    },
  },
}
const colorKeys = ["bg", "surface", "fg", "accent"] as const
function luminance(hex: string): number {
  const c = [1, 3, 5]
    .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
  return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722
}
const contrast = (a: string, b: string) =>
  (Math.max(luminance(a), luminance(b)) + 0.05) /
  (Math.min(luminance(a), luminance(b)) + 0.05)
type HookContext = {el: HTMLElement; cleanup?: () => void}

const Showcase = {
  mounted(this: HookContext) {
    const root = document.documentElement
    const oldStyle = root.getAttribute("style")
    const oldBrand = root.dataset.brand
    const oldTheme = root.dataset.theme
    let brand = "platform",
      mode = "dark"
    const storageKey = () => `regent-showcase:${brand}:${mode}`
    const load = (): Palette => {
      try {
        const saved = JSON.parse(localStorage.getItem(storageKey()) || "null")
        if (saved && colorKeys.every((k) => /^#[0-9a-f]{6}$/i.test(saved[k])))
          return saved
      } catch {
        /* Storage may be unavailable; defaults still work. */
      }
      return {...defaults[brand][mode]}
    }
    let palette = load()
    const apply = () => {
      root.dataset.brand = brand
      root.dataset.theme = mode
      root.style.colorScheme = mode
      colorKeys.forEach((key) => {
        root.style.setProperty(`--color-${key}`, palette[key])
        const input = this.el.querySelector<HTMLInputElement>(
          `[data-sc-color="${key}"]`,
        )!
        input.value = palette[key]
        this.el.querySelector(`[data-sc-value="${key}"]`)!.textContent =
          palette[key].toUpperCase()
      })
      const accentText =
        contrast(palette.accent, "#111111") >
        contrast(palette.accent, "#ffffff")
          ? "#111111"
          : "#ffffff"
      const derived: Record<string, string> = {
        "fg-muted": "color-mix(in srgb, var(--color-fg) 65%, var(--color-bg))",
        border: "color-mix(in srgb, var(--color-fg) 18%, var(--color-bg))",
        "fg-on-accent": accentText,
        "accent-contrast": accentText,
      }
      Object.entries(derived).forEach(([key, value]) =>
        root.style.setProperty(`--color-${key}`, value),
      )
      for (const [key, value] of Object.entries({
        bg: palette.bg,
        surface: palette.surface,
        text: palette.fg,
        accent: palette.accent,
        "accent-ink": accentText,
        line: "var(--color-border)",
      })) {
        if (brand === "patchbay") root.style.setProperty(`--pb-${key}`, value)
        else root.style.removeProperty(`--pb-${key}`)
      }
      this.el
        .querySelectorAll<HTMLElement>("[data-sc-brand]")
        .forEach((el) =>
          el.setAttribute("aria-pressed", String(el.dataset.scBrand === brand)),
        )
      this.el
        .querySelectorAll<HTMLElement>("[data-sc-mode]")
        .forEach((el) =>
          el.setAttribute("aria-pressed", String(el.dataset.scMode === mode)),
        )
      const ratio = contrast(palette.fg, palette.bg)
      this.el.querySelector("[data-sc-contrast]")!.textContent =
        `${ratio.toFixed(1)}:1 text contrast${ratio < 4.5 ? " · below AA" : " · AA"}`
    }
    const click = async (event: Event) => {
      const button = (event.target as Element).closest<HTMLElement>("button")
      if (!button) return
      if (button.dataset.scBrand && defaults[button.dataset.scBrand]) {
        brand = button.dataset.scBrand
        palette = load()
        apply()
      }
      if (
        button.dataset.scMode &&
        ["light", "dark"].includes(button.dataset.scMode)
      ) {
        mode = button.dataset.scMode
        palette = load()
        apply()
      }
      if (button.hasAttribute("data-sc-reset")) {
        palette = {...defaults[brand][mode]}
        try {
          localStorage.removeItem(storageKey())
        } catch {}
        apply()
      }
      if (button.dataset.scCopy) {
        const value =
          document.getElementById(button.dataset.scCopy)?.textContent || ""
        try {
          await navigator.clipboard.writeText(value)
          button.textContent = "Copied"
        } catch {
          button.textContent = "Copy unavailable"
        }
      }
    }
    const input = (event: Event) => {
      const el = event.target as HTMLInputElement
      const key = el.dataset.scColor as keyof Palette
      if (colorKeys.includes(key) && /^#[0-9a-f]{6}$/i.test(el.value)) {
        palette[key] = el.value
        try {
          localStorage.setItem(storageKey(), JSON.stringify(palette))
        } catch {}
        apply()
      }
    }
    this.el.addEventListener("click", click)
    this.el.addEventListener("input", input)
    apply()
    this.cleanup = () => {
      this.el.removeEventListener("click", click)
      this.el.removeEventListener("input", input)
      if (oldStyle === null) root.removeAttribute("style")
      else root.setAttribute("style", oldStyle)
      if (oldBrand === undefined) delete root.dataset.brand
      else root.dataset.brand = oldBrand
      if (oldTheme === undefined) delete root.dataset.theme
      else root.dataset.theme = oldTheme
    }
  },
  destroyed(this: HookContext) {
    this.cleanup?.()
  },
}

const ShowcaseWallet = {
  mounted(this: HookContext) {
    let connected = false,
      sequence = 0
    const timers = new Set<ReturnType<typeof setTimeout>>()
    const address = "0x1111111111111111111111111111111111111111"
    // Local provider only. Never registered with the application's wallet store.
    const provider = {request: async () => "fixture-request"}
    const click = (event: Event) => {
      const button = (event.target as Element).closest("button")
      if (!button) return
      const status = this.el.querySelector("[data-demo-wallet]")!
      if (button.hasAttribute("data-demo-connect")) {
        connected = true
        status.textContent = `Fixture connected · ${address}`
      }
      if (button.hasAttribute("data-demo-disconnect")) {
        connected = false
        status.textContent = "Disconnected"
      }
      if (button.hasAttribute("data-demo-send")) {
        const row = document.createElement("li")
        const id = ++sequence
        this.el.querySelector("[data-demo-results]")!.prepend(row)
        const wallet = selectConnectedEthereumWallet(
          connected
            ? [
                [
                  address,
                  {
                    provider,
                    disconnect: () => {
                      connected = false
                    },
                  },
                ],
              ]
            : [],
          address,
        )
        if (!wallet) {
          row.textContent = `#${id} · Connect the fixture first`
          return
        }
        const outcome = this.el.querySelector<HTMLSelectElement>(
          "[data-demo-outcome]",
        )!.value
        void wallet.provider.request({
          method: "eth_sendTransaction",
          params: [],
        })
        row.textContent = `#${id} · Wallet received · pending`
        const timer = setTimeout(() => {
          row.textContent = `#${id} · ${outcome}`
          timers.delete(timer)
        }, 1800)
        timers.add(timer)
      }
    }
    this.el.addEventListener("click", click)
    this.cleanup = () => {
      this.el.removeEventListener("click", click)
      timers.forEach(clearTimeout)
    }
  },
  destroyed(this: HookContext) {
    this.cleanup?.()
  },
}
export const hooks = {Showcase, ShowcaseWallet, RegentScene}
