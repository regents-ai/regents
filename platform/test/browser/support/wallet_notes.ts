import type {Page} from "@playwright/test"

// The note for a press that was not sent floats over the page
// (`OnchainSteps.notes/1`): its coming and going moves nothing, and it covers no
// control.

// Every box drawn inside `root`, outside the notes, by its place in the page and
// measured from `root`, so a scroll between two readings does not count.
export async function boxes(page: Page, root: string): Promise<Record<string, number[]>> {
  return page.evaluate(root => {
    const base = document.querySelector(root)!.getBoundingClientRect()
    const found: Record<string, number[]> = {}
    const walk = (element: Element, path: string) => {
      if (element.classList.contains("onchain-notes") || !element.checkVisibility()) return
      const box = element.getBoundingClientRect()
      found[path] = [box.left - base.left, box.top - base.top, box.width, box.height].map(
        n => Math.round(n * 10) / 10,
      )
      Array.from(element.children).forEach((child, index) => walk(child, `${path}>${index}`))
    }
    walk(document.querySelector(root)!, root)
    return found
  }, root)
}

// Every control on the page that a showing note's rectangle touches.
export async function coveredControls(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const shown = (element: Element) => element.checkVisibility({visibilityProperty: true})
    const notes = [...document.querySelectorAll(".onchain-note:not([data-leaving])")].filter(shown)
    const controls = [
      ...document.querySelectorAll(
        "button, a[href], input:not([type=hidden]), select, textarea, summary, label, [role=button], [role=tab], [tabindex]:not([tabindex='-1'])",
      ),
    ].filter(control => !control.closest(".onchain-notes") && shown(control))
    const touches = (a: DOMRect, b: DOMRect) =>
      b.width > 0 &&
      Math.min(a.right, b.right) - Math.max(a.left, b.left) > 0.5 &&
      Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 0.5

    return notes.flatMap(note =>
      controls
        .filter(control => touches(note.getBoundingClientRect(), control.getBoundingClientRect()))
        .map(control => `${note.id} covers ${control.id || control.tagName.toLowerCase()}`),
    )
  })
}
