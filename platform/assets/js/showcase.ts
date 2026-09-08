import {selectConnectedEthereumWallet} from "./wallet_actions/connected_wallet"
import {PrivyShowcase} from "./hooks/privy_showcase"


import {selectors} from "../vendor/regent_ui/tokens.json"

type Palette = {
  bg: string; surface: string; fg: string; accent: string; border: string
  primaryShade: string; orange: string; blue: string; muted?: string
}
const tokens = selectors as Record<string, Record<string, string>>
const defaults: Record<string, Record<string, Palette>> = Object.fromEntries(
  ["platform", "autolaunch", "patchbay", "techtree"].map(brand => [brand, Object.fromEntries(
    ["light", "dark"].map(mode => {
      const theme = tokens[`:root[data-brand="${brand}"][data-theme="${mode}"]`]
      return [mode, {
        bg: theme["--color-bg"], surface: theme["--color-surface"],
        fg: theme["--color-fg"], accent: theme["--color-accent"],
        border: theme["--color-border"], primaryShade: theme["--color-primary-shade"],
        orange: tokens[":root"]["--palette-tangerine-tango"],
        blue: tokens[":root"]["--palette-powder-blue"], muted: theme["--color-muted"],
      }]
    })
  )])
)
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
type HookContext = {el: HTMLElement; cleanup?: () => void; refresh?: () => void}

const Showcase = {
  mounted(this: HookContext) {
    const root = document.documentElement
    const oldStyle = root.getAttribute("style")
    const oldBrand = root.dataset.brand
    const oldTheme = root.dataset.theme
    let brand = "platform",
      mode = "dark"
    const storageKey = (site = brand, theme = mode) => `regent-showcase:2026-09-palettes:${site}:${theme}`
    const loadPalette = (site: string, theme: string): Palette => {
      try {
        const saved = JSON.parse(localStorage.getItem(storageKey(site, theme)) || "null")
        if (saved && colorKeys.every((k) => /^#[0-9a-f]{6}$/i.test(saved[k])))
          return {...defaults[site][theme], ...Object.fromEntries(colorKeys.map((key) => [key, saved[key]]))}
      } catch {
        /* Storage may be unavailable; defaults still work. */
      }
      return {...defaults[site][theme]}
    }
    const load = () => loadPalette(brand, mode)
    let palette = load()
    let shimmerColor: string | null = null
    const apply = () => {
      root.dataset.brand = brand
      root.dataset.theme = mode
      root.style.colorScheme = mode
      this.el.removeAttribute("style")
      const themeTokens = tokens[`:root[data-brand="${brand}"][data-theme="${mode}"]`]
      Object.entries({...tokens[":root"], ...themeTokens}).forEach(([key, value]) =>
        !key.startsWith("--rg-") && this.el.style.setProperty(key, value),
      )
      colorKeys.forEach((key) => {
        root.style.setProperty(`--color-${key}`, palette[key])
        this.el.style.setProperty(`--color-${key}`, palette[key])
        const input = this.el.querySelector<HTMLInputElement>(
          `[data-sc-color="${key}"]`,
        )!
        input.value = palette[key]
        this.el.querySelector(`[data-sc-value="${key}"]`)!.textContent =
          palette[key].toUpperCase()
      })
      const accentText =
        contrast(palette.accent, "#161616") >
        contrast(palette.accent, "#E5E3D2")
          ? "#161616"
          : "#E5E3D2"
      if (shimmerColor) this.el.style.setProperty("--rg-shimmer-color", shimmerColor)
      const shimmerInput = this.el.querySelector<HTMLInputElement>("[data-sc-shimmer-color]")!
      shimmerInput.value = shimmerColor || palette.orange
      this.el.querySelector("[data-sc-shimmer-value]")!.textContent = shimmerColor?.toUpperCase() || "Automatic"
      const derived: Record<string, string> = {
        "fg-muted": "color-mix(in srgb, var(--color-fg) 65%, var(--color-bg))",
        border: palette.border,
        primary: palette.accent,
        "primary-shade": palette.primaryShade,
        orange: palette.orange,
        blue: palette.blue,
        muted: palette.muted || "color-mix(in srgb, var(--color-fg) 65%, var(--color-bg))",
        focus: mode === "dark" ? palette.blue : palette.orange,
        "fg-on-accent": accentText,
        "accent-contrast": accentText,
      }
      Object.entries(derived).forEach(([key, value]) => {
        root.style.setProperty(`--color-${key}`, value)
        this.el.style.setProperty(`--color-${key}`, value)
      })
      for (const [key, value] of Object.entries({
        bg: palette.bg,
        surface: palette.surface,
        text: palette.fg,
        accent: palette.accent,
        "accent-ink": accentText,
        line: "var(--color-border)",
      })) {
        if (brand === "patchbay") {
          root.style.setProperty(`--pb-${key}`, value)
          this.el.style.setProperty(`--pb-${key}`, value)
        } else {
          root.style.removeProperty(`--pb-${key}`)
          this.el.style.removeProperty(`--pb-${key}`)
        }
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
      this.el.querySelectorAll<HTMLButtonElement>("[data-sc-theme]").forEach((button) => {
        const selected = button.dataset.scTheme === `${brand}:${mode}`
        button.setAttribute("aria-pressed", String(selected))
        const [cardBrand, cardMode] = button.dataset.scTheme!.split(":")
        // Cards retain their own identity; the selected card reflects live edits.
        const card = selected ? palette : loadPalette(cardBrand, cardMode)
        for (const key of colorKeys) button.style.setProperty(`--sc-card-${key}`, card[key])
      })
      const tokenList = this.el.querySelector("[data-sc-tokens]")!
      tokenList.replaceChildren(...Object.entries(palette).map(([key, value]) => {
        const row = document.createElement("div")
        const label = document.createElement("dt")
        label.textContent = ({bg: "Background", surface: "Surface", fg: "Text", accent: "Primary", primaryShade: "Primary shade", orange: "Tangerine", blue: "Powder blue", border: "Border", muted: "Muted"} as Record<string, string>)[key]
        const color = document.createElement("dd")
        color.textContent = value
        row.append(label, color)
        return row
      }))
      const ratio = contrast(palette.fg, palette.bg)
      this.el.querySelector("[data-sc-contrast]")!.textContent =
        `${ratio.toFixed(1)}:1 text contrast${ratio < 4.5 ? " · below AA" : " · AA"}`
    }
    const click = async (event: Event) => {
      const button = (event.target as Element).closest<HTMLElement>("button")
      if (!button) return
      if (button.dataset.scTheme) {
        const [nextBrand, nextMode] = button.dataset.scTheme.split(":")
        if (defaults[nextBrand]?.[nextMode]) {
          brand = nextBrand
          mode = nextMode
          palette = load()
          apply()
        }
      }
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
      if (button.hasAttribute("data-sc-shimmer-reset")) {
        shimmerColor = null
        apply()
      }
      if (button.dataset.scCopy) {
        const source = document.getElementById(button.dataset.scCopy)
        const value = source?.matches("dl")
          ? Array.from(source.querySelectorAll("dt"), term =>
              `${term.textContent?.trim()}: ${term.nextElementSibling?.textContent?.trim() || ""}`,
            ).join("\n")
          : source?.textContent || ""
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
      if (el.hasAttribute("data-sc-shimmer-color") && /^#[0-9a-f]{6}$/i.test(el.value)) {
        shimmerColor = el.value
        apply()
      }
      const key = el.dataset.scColor as (typeof colorKeys)[number]
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
    this.refresh = apply
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
  updated(this: HookContext) {
    this.refresh?.()
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
export const hooks = {Showcase, ShowcaseWallet, PrivyShowcase}
