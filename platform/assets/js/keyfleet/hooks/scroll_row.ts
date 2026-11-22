import type {Hook} from "../../hook_composition"

type ScrollRowHook = {
  el: HTMLElement
  shown?: HTMLElement | null
  frame?: number
  watch?: ResizeObserver
  onClick?: (event: Event) => void
  onFocus?: (event: Event) => void
  onScroll?: () => void
}

const items = (row: HTMLElement) => [...row.querySelectorAll<HTMLElement>("a, button")]

/** The open tab or room (`aria-current="page"`), else the pressed item. */
const selected = (row: HTMLElement) =>
  row.querySelector<HTMLElement>('[aria-current="page"]') ?? row.querySelector<HTMLElement>('[aria-pressed="true"]')

/** How far in from each edge an item stands whole and clear: the row's scroll padding. */
function reach(row: HTMLElement) {
  const style = getComputedStyle(row)
  return {start: parseFloat(style.scrollPaddingInlineStart) || 0, end: parseFloat(style.scrollPaddingInlineEnd) || 0}
}

/**
 * Fades the row out at an edge while part of an item lies past that edge,
 * over whole items only: an item that reaches within the scroll padding of
 * such an edge fades entirely, and every other item stands clear, so no word
 * is cut part way by the edge. A row that fits, or an edge it has reached,
 * has no fade.
 */
function fade(row: HTMLElement) {
  const box = row.getBoundingClientRect()
  const {start, end} = reach(row)
  const rects = items(row).map(item => item.getBoundingClientRect())
  const hiddenBefore = rects.some(rect => rect.left < box.left - 1)
  const hiddenAfter = rects.some(rect => rect.right > box.right + 1)
  const before = rects.filter(rect => rect.left < box.left + start - 1).pop()
  const after = rects.find(rect => rect.right > box.right - end + 1)
  const fadeStart = hiddenBefore && before ? before.right - box.left : 0
  const fadeEnd = hiddenAfter && after ? box.right - after.left : 0
  row.style.setProperty("--fleet-fade-start", `${fadeStart}px`)
  row.style.setProperty("--fleet-fade-end", `${fadeEnd}px`)
}

/**
 * Scrolls the row, never the page, until `item` stands whole inside it, its
 * start on the row's scroll padding, where the row's snapping rests an item.
 * An item already whole and clear stays put.
 */
function reveal(row: HTMLElement, item: HTMLElement | null, smooth: boolean) {
  if (!item) return
  const {start, end} = reach(row)
  const from = item.getBoundingClientRect().left - row.getBoundingClientRect().left - row.clientLeft
  if (from >= start && from + item.offsetWidth <= row.clientWidth - end) return
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches
  row.scrollTo({left: row.scrollLeft + from - start, behavior: smooth && !still ? "smooth" : "instant"})
}

/** The row's item an event happened on, if any. */
const itemOf = (row: HTMLElement, event: Event) => {
  const item = event.target instanceof Element ? event.target.closest<HTMLElement>("a, button") : null
  return item && row.contains(item) ? item : null
}

/**
 * A row of tabs or channels that scrolls sideways on a narrow screen: it
 * keeps the selected item in view when the page opens, when the selection
 * changes and when an item is pressed, brings an item reached from the
 * keyboard whole into view at once, and fades at an edge with more past it.
 */
export const ScrollRow: Hook = {
  mounted(this: ScrollRowHook) {
    const row = this.el
    const refade = () => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => {
        this.frame = undefined
        fade(row)
      })
    }

    this.shown = selected(row)
    reveal(row, this.shown, false)
    fade(row)

    this.onScroll = refade
    this.onClick = event => reveal(row, itemOf(row, event), true)
    this.onFocus = event => {
      const item = itemOf(row, event)
      if (item?.matches(":focus-visible")) reveal(row, item, false)
    }
    this.watch = new ResizeObserver(refade)
    this.watch.observe(row)
    row.addEventListener("scroll", this.onScroll, {passive: true})
    row.addEventListener("click", this.onClick)
    row.addEventListener("focusin", this.onFocus)
    void document.fonts.ready.then(refade)
  },

  updated(this: ScrollRowHook) {
    const item = selected(this.el)
    if (item !== this.shown) {
      this.shown = item
      reveal(this.el, item, true)
    }
    fade(this.el)
  },

  destroyed(this: ScrollRowHook) {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.watch?.disconnect()
    if (this.onScroll) this.el.removeEventListener("scroll", this.onScroll)
    if (this.onClick) this.el.removeEventListener("click", this.onClick)
    if (this.onFocus) this.el.removeEventListener("focusin", this.onFocus)
  },
}
