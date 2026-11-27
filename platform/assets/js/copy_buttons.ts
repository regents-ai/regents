import {deny} from "./hooks/motion/press"
import {copyStatusMessage, copyWithFallback, type CopyOutcome} from "./copy_fallback"

type Outcome = CopyOutcome

const SHOWN_MS = 1600

const timers = new WeakMap<HTMLElement, number>()

/**
 * Every `Regent.Primitives.copy_button` on every page, LiveView or not, from one
 * listener on the document. A press copies the button's `data-copy-text`, the
 * text of the element `data-copy-target` names, or the page at `data-copy-url`,
 * fetched only when pressed because it is long. Then for a moment the button
 * says "Copied", or "Couldn't copy" with a shake when the browser refuses, and
 * its polite status says the same for screen readers. When the browser refuses,
 * the target's text (or an inline selectable fallback field) is selected for
 * the person to copy themselves and the button says "Selected". The button tells
 * LiveView to leave `data-copy-state` alone, so a redraw meanwhile keeps the
 * answer on screen.
 */
export function installCopyButtons() {
  document.addEventListener("click", event => {
    const button = event.target instanceof Element ? event.target.closest("button.rg-copy") : null
    if (button instanceof HTMLButtonElement) void copy(button)
  })
}

async function copy(button: HTMLButtonElement) {
  const targetId = button.dataset.copyTarget
  const target = targetId ? document.getElementById(targetId) : null
  const url = button.dataset.copyUrl
  const text = target ? textOf(target) : (button.dataset.copyText ?? "")
  let outcome: Outcome = "copied"
  if (url) {
    try {
      await navigator.clipboard.write([new ClipboardItem({"text/plain": fetched(url)})])
    } catch {
      try {
        const fetchedText = await (await fetched(url)).text()
        outcome = await copyWithFallback(fetchedText, {
          anchor: button,
          label: button.getAttribute("aria-label") ?? "Copy text",
        })
      } catch {
        outcome = "failed"
      }
    }
  } else {
    outcome = await copyWithFallback(text, {
      target,
      anchor: button,
      label: button.getAttribute("aria-label") ?? "Copy text",
    })
  }
  if (!button.isConnected) return

  answer(button, outcome)
  if (outcome === "failed") deny(button)
  window.clearTimeout(timers.get(button))
  timers.set(button, window.setTimeout(() => answer(button, undefined), outcome === "selected" ? 3200 : SHOWN_MS))
}

// Handed to the clipboard unfinished: a browser only allows a write begun by the
// press itself, and the fetch finishes after it.
async function fetched(url: string): Promise<Blob> {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url} answered ${response.status}`)
  return new Blob([await response.text()], {type: "text/plain"})
}

function textOf(target: HTMLElement): string {
  return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement
    ? target.value
    : (target.textContent ?? "")
}

function answer(button: HTMLButtonElement, outcome: Outcome | undefined) {
  if (outcome) {
    if (!("copyOriginalTitle" in button.dataset)) button.dataset.copyOriginalTitle = button.title
    button.dataset.copyState = outcome
    button.title = copyStatusMessage(outcome)
  } else {
    delete button.dataset.copyState
    if ("copyOriginalTitle" in button.dataset) {
      button.title = button.dataset.copyOriginalTitle ?? ""
      delete button.dataset.copyOriginalTitle
    }
  }
  const status = document.getElementById(button.dataset.copyStatus ?? "")
  if (status) status.textContent = outcome ? copyStatusMessage(outcome) : ""
}
