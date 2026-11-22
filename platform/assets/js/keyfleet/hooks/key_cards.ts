/**
 * The Key cards turning over in the "Buy Key" window. The stylesheet turns
 * them, only while this marks them `data-cards-turning`: on screen. Scrolled
 * away, they hold the card they reached and go on from it when they come
 * back. Without this hook, or for a visitor who asked for less motion, the
 * first card stays.
 */
import type {Hook} from "../../hook_composition"

type KeyCardsHook = {el: HTMLElement; watch?: IntersectionObserver}

export const KeyCards: Hook = {
  mounted(this: KeyCardsHook) {
    const deck = this.el
    // One element is watched, so the last entry is where it stands now.
    this.watch = new IntersectionObserver(entries => {
      deck.toggleAttribute("data-cards-turning", entries.at(-1)?.isIntersecting ?? false)
    })
    this.watch.observe(deck)
  },

  destroyed(this: KeyCardsHook) {
    this.watch?.disconnect()
  },
}
