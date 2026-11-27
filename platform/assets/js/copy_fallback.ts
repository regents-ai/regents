export type CopyOutcome = "copied" | "selected" | "failed"

export type CopyFallbackOptions = {
  target?: HTMLElement | null
  anchor?: HTMLElement | null
  label?: string
}

export function copyShortcutHint(): string {
  const platform =
    typeof navigator !== "undefined"
      ? ((navigator as Navigator & {userAgentData?: {platform?: string}}).userAgentData?.platform ??
          navigator.platform ??
          navigator.userAgent ??
          "")
      : ""
  return /mac|iphone|ipad|ipod/i.test(platform) ? "⌘C" : "Ctrl+C"
}

export function copyStatusMessage(outcome: CopyOutcome): string {
  if (outcome === "copied") return "Copied"
  if (outcome === "selected") return `Selected — press ${copyShortcutHint()}`
  return "Couldn't copy"
}

export function copyButtonLabel(outcome: CopyOutcome): string {
  if (outcome === "copied") return "Copied"
  if (outcome === "selected") return `Press ${copyShortcutHint()}`
  return "Couldn't copy"
}

/**
 * Copies `text` to the clipboard with deterministic, honest fallbacks whenever
 * `navigator.clipboard.writeText` is unavailable or rejected by browser policy:
 *
 * 1. `navigator.clipboard.writeText(text)` -> `"copied"`
 * 2. Select `target` (when its exact text matches `text`) and try
 *    `document.execCommand("copy")` -> `"copied"` or `"selected"`
 * 3. Try an offscreen readonly `<textarea>` with `execCommand("copy")` -> `"copied"`
 * 4. Reveal an inline selectable readonly field near `anchor` pre-selected with
 *    `text` so the user can press ⌘C / Ctrl+C directly -> `"selected"`
 * 5. Only if selection and DOM fallback both fail -> `"failed"`
 */
export async function copyWithFallback(
  text: string,
  options: CopyFallbackOptions = {},
): Promise<CopyOutcome> {
  if (!text) return "failed"

  const {target = null, anchor = null, label = "Copy command manually"} = options

  try {
    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
      await navigator.clipboard.writeText(text)
      dismissInlineFallback(anchor)
      return "copied"
    }
  } catch {
    // Fall through to execCommand + selectable fallback below.
  }

  if (target && matchesExactText(target, text)) {
    const selected = selectElement(target)
    if (selected === "selected") {
      if (tryExecCopy()) {
        dismissInlineFallback(anchor)
        return "copied"
      }
      return "selected"
    }
  }

  if (tryOffscreenExecCopy(text)) {
    dismissInlineFallback(anchor)
    return "copied"
  }

  if (anchor && showInlineSelectableFallback(anchor, text, label)) {
    return "selected"
  }

  if (target && selectElement(target) === "selected") {
    return "selected"
  }

  return "failed"
}

export function dismissInlineFallback(anchor: HTMLElement | null) {
  const host = fallbackHostFor(anchor)
  if (!host) return
  const existing = host.querySelector<HTMLElement>("[data-copy-fallback]")
  existing?.remove()
}

function matchesExactText(target: HTMLElement, text: string): boolean {
  const current =
    target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement
      ? target.value
      : (target.textContent ?? "")
  return current.trim() === text.trim()
}

function tryExecCopy(): boolean {
  try {
    return typeof document.execCommand === "function" && document.execCommand("copy")
  } catch {
    return false
  }
}

function tryOffscreenExecCopy(text: string): boolean {
  if (!document.body) return false
  const scratch = document.createElement("textarea")
  scratch.value = text
  scratch.setAttribute("readonly", "")
  scratch.setAttribute("aria-hidden", "true")
  scratch.style.position = "fixed"
  scratch.style.top = "-9999px"
  scratch.style.opacity = "0"
  document.body.append(scratch)
  scratch.focus({preventScroll: true})
  scratch.select()
  const ok = tryExecCopy()
  scratch.remove()
  return ok
}

function selectElement(target: HTMLElement): "selected" | "failed" {
  try {
    if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) {
      target.focus()
      target.select()
      return "selected"
    }

    const selection = document.getSelection()
    if (!selection) return "failed"
    const range = document.createRange()
    range.selectNodeContents(target)
    selection.removeAllRanges()
    selection.addRange(range)
    return "selected"
  } catch {
    return "failed"
  }
}

function fallbackHostFor(anchor: HTMLElement | null): HTMLElement | null {
  if (!anchor) return null
  return (
    anchor.closest<HTMLElement>(".cloak-terminal, .cloak-verify__cmd, .cloak-closing__pill-row, .cloak-dl__verify-actions, .prompt, .pbt-copy-wrap") ??
    anchor.parentElement
  )
}

function showInlineSelectableFallback(anchor: HTMLElement, text: string, label: string): boolean {
  const host = fallbackHostFor(anchor)
  if (!host) return false

  let box = host.querySelector<HTMLElement>("[data-copy-fallback]")
  if (!box) {
    box = document.createElement("div")
    box.className = "rg-copy-fallback"
    box.dataset.copyFallback = ""
    box.setAttribute("role", "region")
    box.setAttribute("aria-label", label)

    const hint = document.createElement("div")
    hint.className = "rg-copy-fallback__head"
    const caption = document.createElement("span")
    caption.className = "rg-copy-fallback__hint"
    caption.textContent = `Clipboard blocked — press ${copyShortcutHint()} to copy:`
    const close = document.createElement("button")
    close.type = "button"
    close.className = "rg-copy-fallback__close"
    close.textContent = "Dismiss"
    close.addEventListener("click", () => box?.remove())
    hint.append(caption, close)

    const multiline = text.includes("\n")
    const field = multiline ? document.createElement("textarea") : document.createElement("input")
    field.className = "rg-copy-fallback__field"
    field.readOnly = true
    field.setAttribute("aria-label", label)
    field.spellcheck = false
    if (field instanceof HTMLInputElement) {
      field.type = "text"
    } else {
      field.rows = Math.min(6, Math.max(2, text.split("\n").length))
    }
    field.addEventListener("focus", () => field.select())
    field.addEventListener("click", () => field.select())
    field.addEventListener("keydown", event => {
      if ((event as KeyboardEvent).key === "Escape") {
        box?.remove()
        anchor.focus()
      }
    })

    box.append(hint, field)
    host.append(box)
  }

  const field = box.querySelector<HTMLInputElement | HTMLTextAreaElement>(".rg-copy-fallback__field")
  if (!field) return false
  field.value = text
  field.focus()
  field.select()
  return true
}
