/**
 * Motion for moving between views and for a page arriving: the app's page
 * gliding in when another is chosen, a headline that rises in word by word
 * and a grid of cards that settles into place.
 */
import {
  animate,
  createScope,
  stagger,
  utils,
  type AnimationParams,
  type JSAnimation,
  type Scope,
  type TextSplitter,
} from "animejs"
import {EASE_OUT, SLOW, byPointer, lastInputByPointer, still} from "./shared"
import type {Hook} from "../../hook_composition"

const tidy = (animation: JSAnimation) => utils.cleanInlineStyles(animation)

// How the new view arrives. `step` is 1 when the chosen view comes after the
// last one in the navigation and -1 when it comes before.
const TABS: Record<string, (step: number) => AnimationParams> = {
  glide: step => ({x: {from: step * 24}, opacity: {from: 0}, duration: SLOW, ease: EASE_OUT}),
}

type ViewsHook = {
  el: HTMLElement
  scope?: Scope
  destination?: string
  pointer: boolean
}

/**
 * The app's pages, switched by the server as the reader moves through the
 * navigation. The page names where it is in `data-destination` and the
 * version in `data-variant`; a page chosen with a mouse or finger glides in,
 * one reached from the keyboard or the browser's back button is simply there.
 */
export const ShellViews: Hook = {
  mounted(this: ViewsHook) {
    const scope = createScope({root: this.el})
    this.destination = this.el.dataset.destination
    this.pointer = false

    this.scope = scope.add(() => {
      const place = (path?: string) =>
        [...this.el.querySelectorAll("#shell-sidebar a[href]")].findIndex(
          link => link.getAttribute("href") === path,
        )

      scope.add("glide", (from: string, to: string) => {
        const view = this.el.querySelector("#route-content")
        const step = place(to) < place(from) ? -1 : 1
        if (view) animate(view, {...TABS[this.el.dataset.variant ?? ""](step), onComplete: tidy})
      })

      const onClick = (event: MouseEvent) => {
        if (event.target instanceof Element && event.target.closest("a[href]")) {
          this.pointer = byPointer(event)
        }
      }

      this.el.addEventListener("click", onClick, true)
      return () => this.el.removeEventListener("click", onClick, true)
    })
  },

  updated(this: ViewsHook) {
    const from = this.destination
    const to = this.el.dataset.destination
    this.destination = to
    if (from === to || from === undefined || to === undefined) return

    if (this.pointer && !still()) this.scope?.methods.glide(from, to)
    this.pointer = false
  },

  destroyed(this: ViewsHook) {
    this.scope?.revert()
  },
}

type TabsHook = {el: HTMLElement; scope?: Scope; active?: string}

/**
 * A panel whose tabs the server switches, such as Stake's stake and unstake
 * form. The panel names the chosen tab in `data-active`, every tab in order in
 * `data-tabs` and the version in `data-variant`; it glides in from the side of
 * the chosen tab when that was picked with a mouse or finger.
 */
export const MotionTabs: Hook = {
  mounted(this: TabsHook) {
    const scope = createScope({root: this.el})
    this.active = this.el.dataset.active

    this.scope = scope.add(() => {
      scope.add("glide", (step: number) => {
        animate(this.el, {...TABS[this.el.dataset.variant ?? ""](step), onComplete: tidy})
      })
    })
  },

  updated(this: TabsHook) {
    const from = this.active
    const to = this.el.dataset.active
    this.active = to
    if (from === to || from === undefined || to === undefined) return
    if (!lastInputByPointer() || still()) return

    const tabs = (this.el.dataset.tabs ?? "").split(" ")
    this.scope?.methods.glide(tabs.indexOf(to) < tabs.indexOf(from) ? -1 : 1)
  },

  destroyed(this: TabsHook) {
    this.scope?.revert()
  },
}

// Moves in percent name both ends, so they stay a share of each word's own
// height instead of being converted to pixels from its width.
export const riseHeadline = (split: TextSplitter) =>
  animate(split.words, {y: ["100%", "0%"], delay: stagger(50), duration: SLOW, ease: EASE_OUT})

export const cascadeCards = (cards: Element[]) =>
  animate(cards, {
    y: {from: 16},
    opacity: {from: 0},
    delay: stagger(45),
    duration: SLOW,
    ease: EASE_OUT,
    onComplete: tidy,
  })
