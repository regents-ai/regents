import {animate, type AnimationParams} from "animejs"

import {
  HERO_PALETTE_EVENT,
  setHeroPalette,
  type HeroPaletteName,
  type HeroProduct,
} from "../home_field/palette"

type RequestFrame = (callback: FrameRequestCallback) => number
type CancelFrame = (handle: number) => void

export type HomeHeroAnimation = {
  cancel(): unknown
  seek(time: number): unknown
}

export type HomeHeroDriver = {
  animate(targets: HTMLElement[], options: Record<string, unknown>): HomeHeroAnimation
}

type HomeHeroOptions = {
  cancelFrame?: CancelFrame
  driver?: HomeHeroDriver
  finePointer?: () => boolean
  reducedMotion?: () => boolean
  requestFrame?: RequestFrame
}

export type HomeHeroController = {
  readonly active: HomeHeroAnimation[] | null
  mount(): void
  destroy(): void
}

const animeDriver: HomeHeroDriver = {
  animate: (targets, options) => animate(targets, options as AnimationParams),
}

const browserRequestFrame: RequestFrame = callback =>
  typeof window === "undefined" ? 0 : window.requestAnimationFrame(callback)

const browserCancelFrame: CancelFrame = handle => {
  if (typeof window !== "undefined") window.cancelAnimationFrame(handle)
}

const browserReducedMotion = () =>
  typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches

// A touch is not a hover, so a coarse pointer is left with the resting page.
const browserFinePointer = () =>
  typeof window !== "undefined" && window.matchMedia("(pointer: fine)").matches

const HERO = ".rl-hero"
const CARD_COLUMN = "[data-home-hero-cards]"
const CARD = "[data-home-hero-card]"

const clearAnimationStyles = (targets: HTMLElement[]) => {
  targets.forEach(target => {
    target.style.removeProperty?.("opacity")
    target.style.removeProperty?.("transform")
    target.style.removeProperty?.("translate")
    target.style.opacity = ""
    target.style.transform = ""
  })
}

export const createHomeHeroController = (
  root: HTMLElement,
  options: HomeHeroOptions = {},
): HomeHeroController => {
  const cancelFrame = options.cancelFrame ?? browserCancelFrame
  const driver = options.driver ?? animeDriver
  const finePointer = options.finePointer ?? browserFinePointer
  const reducedMotion = options.reducedMotion ?? browserReducedMotion
  const requestFrame = options.requestFrame ?? browserRequestFrame
  let active: HomeHeroAnimation[] | null = null
  let frame: number | undefined
  let targets: HTMLElement[] = []
  let generation = 0
  // The hero and its card column, held from the moment hover is wired up so that
  // colouring and releasing never have to go looking for them again.
  let wired: {cards: HTMLElement; hero: HTMLElement} | undefined
  // The pointer and the keyboard each keep their own product, so moving the mouse
  // never takes away the colour a keyboard reader is standing on. The pointer leads
  // while it is on a card, and the keyboard's product comes back when it leaves.
  let pointed: HeroProduct | undefined
  let focused: HeroProduct | undefined
  let shown: HeroPaletteName = "rest"

  // Reading a card colours the whole hero: the stylesheet reads the attribute, and
  // the two canvases take the same palette from the one signal that follows it.
  const settle = () => {
    const name: HeroPaletteName = pointed ?? focused ?? "rest"
    if (!wired || name === shown) return
    shown = name
    const {hero} = wired
    if (name === "rest") delete hero.dataset.heroProduct
    else hero.dataset.heroProduct = name
    setHeroPalette(name)
    hero.dispatchEvent(new Event(HERO_PALETTE_EVENT, {bubbles: true}))
  }

  const productAt = (node: EventTarget | null) =>
    (node as Element | null)?.closest<HTMLElement>(CARD)?.dataset.homeHeroCard as
      | HeroProduct
      | undefined

  // The hairline between two cards belongs to the column, and so does the space
  // around them: only leaving the column is leaving the products.
  const staysInColumn = (event: Event) =>
    Boolean(
      ((event as PointerEvent | FocusEvent).relatedTarget as Element | null)?.closest(CARD_COLUMN),
    )

  const onPointerEnter = (event: Event) => {
    const product = productAt(event.target)
    if (!product) return
    pointed = product
    settle()
  }

  const onPointerLeave = (event: Event) => {
    if (staysInColumn(event)) return
    pointed = undefined
    settle()
  }

  const onFocusEnter = (event: Event) => {
    const product = productAt(event.target)
    if (!product) return
    focused = product
    settle()
  }

  const onFocusLeave = (event: Event) => {
    if (staysInColumn(event)) return
    focused = undefined
    settle()
  }

  const stopCurrentEnhancement = () => {
    generation += 1
    if (frame !== undefined) cancelFrame(frame)
    frame = undefined
    active?.forEach(animation => animation.cancel())
    active = null
    clearAnimationStyles(targets)
    targets = []
  }

  return {
    get active() {
      return active
    },
    mount() {
      // Two pairs of listeners on the column read every card, one for each way in.
      if (!wired && finePointer()) {
        wired = {
          cards: root.querySelector<HTMLElement>(CARD_COLUMN)!,
          hero: root.querySelector<HTMLElement>(HERO)!,
        }
        wired.cards.addEventListener("pointerover", onPointerEnter, {passive: true})
        wired.cards.addEventListener("pointerout", onPointerLeave, {passive: true})
        wired.cards.addEventListener("focusin", onFocusEnter)
        wired.cards.addEventListener("focusout", onFocusLeave)
      }

      stopCurrentEnhancement()
      let completed = false
      const handle = requestFrame(() => {
        root.dataset.heroEnhanced = "true"
        root.dataset.heroMotion = "pending"
        completed = true
        frame = undefined

        if (reducedMotion()) {
          root.dataset.heroMotion = "settled"
          return
        }

        const introduction = Array.from(
          root.querySelectorAll<HTMLElement>("[data-home-header], [data-home-hero-copy]"),
        )
        const cards = Array.from(root.querySelectorAll<HTMLElement>(CARD))
        targets = [...introduction, ...cards]
        const groups = [
          {
            targets: introduction,
            options: {
              opacity: [0, 1],
              translateY: [8, 0],
              duration: 420,
              ease: "outQuart",
              loop: false,
            },
          },
          {
            targets: cards,
            options: {
              opacity: [0, 1],
              translateY: [12, 0],
              duration: 500,
              ease: "outQuart",
              loop: false,
            },
          },
        ].filter(group => group.targets.length > 0)
        const mountGeneration = generation
        let remaining = groups.length

        const finish = () => {
          if (generation !== mountGeneration) return
          remaining -= 1
          if (remaining > 0) return

          clearAnimationStyles(targets)
          targets = []
          active = null
          root.dataset.heroMotion = "settled"
        }

        if (remaining === 0) {
          root.dataset.heroMotion = "settled"
          return
        }

        active = []
        try {
          for (const group of groups) {
            active.push(driver.animate(group.targets, {...group.options, onComplete: finish}))
          }
        } catch {
          stopCurrentEnhancement()
          root.dataset.heroMotion = "settled"
        }
      })
      frame = completed ? undefined : handle
    },
    destroy() {
      stopCurrentEnhancement()
      if (wired) {
        // The listeners go first: they are released against the column this hook
        // held, not against whatever the page looks like by now.
        wired.cards.removeEventListener("pointerover", onPointerEnter)
        wired.cards.removeEventListener("pointerout", onPointerLeave)
        wired.cards.removeEventListener("focusin", onFocusEnter)
        wired.cards.removeEventListener("focusout", onFocusLeave)
        pointed = undefined
        focused = undefined
        settle()
        wired = undefined
      }
      delete root.dataset.heroEnhanced
      delete root.dataset.heroMotion
    },
  }
}

type HomeHeroHook = {
  el: HTMLElement
  controller?: HomeHeroController
}

export const HomeHero = {
  mounted(this: HomeHeroHook) {
    this.controller = createHomeHeroController(this.el)
    this.controller.mount()
  },
  destroyed(this: HomeHeroHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
