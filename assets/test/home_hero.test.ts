import {afterEach, describe, expect, it, vi} from "vitest"

import {
  HERO_PALETTES,
  HERO_PALETTE_EVENT,
  heroPalette,
  setHeroPalette,
} from "../js/home_field/palette"
import {
  HomeHero,
  createHomeHeroController,
  type HomeHeroAnimation,
  type HomeHeroDriver,
} from "../js/hooks/home_hero"

const element = () =>
  ({
    style: {},
    dataset: {},
    // A plain element sits inside nothing the hero asks about.
    closest: vi.fn(() => null),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(() => true),
    querySelector: vi.fn(() => null),
  }) as unknown as HTMLElement

describe("homepage hero enhancement", () => {
  it("publishes the stable HomeHero hook expected by the Ash entrypoint", () => {
    expect(HomeHero).toMatchObject({
      mounted: expect.any(Function),
      destroyed: expect.any(Function),
    })
  })

  it("enhances the words and the three server-rendered cards together after first paint", () => {
    const header = element()
    const copy = element()
    const cards = [element(), element(), element()]
    const root = element()
    root.querySelectorAll = vi.fn((selector: string) => {
      switch (selector) {
        case "[data-home-header], [data-home-hero-copy]":
          return [header, copy]
        case "[data-home-hero-card]":
          return cards
        default:
          return []
      }
    }) as unknown as typeof root.querySelectorAll
    const animations: Array<HomeHeroAnimation & {options: Record<string, unknown>}> = []
    const driver: HomeHeroDriver = {
      animate: vi.fn((_targets, options) => {
        const animation = {options, cancel: vi.fn(), seek: vi.fn()}
        animations.push(animation)
        return animation
      }),
    }
    const requestFrame = vi.fn((callback: FrameRequestCallback) => {
      callback(0)
      return 1
    })

    const controller = createHomeHeroController(root, {
      driver,
      reducedMotion: () => false,
      requestFrame,
    })
    controller.mount()

    expect(root.dataset.heroEnhanced).toBe("true")
    expect(root.dataset.heroMotion).toBe("pending")
    expect(animations).toHaveLength(2)
    expect(driver.animate).toHaveBeenNthCalledWith(
      1,
      [header, copy],
      expect.objectContaining({opacity: [0, 1]}),
    )
    expect(driver.animate).toHaveBeenNthCalledWith(
      2,
      cards,
      expect.objectContaining({duration: 500, opacity: [0, 1], translateY: [12, 0]}),
    )
    for (const animation of animations) {
      expect(animation.options.loop).not.toBe(true)
      ;(animation.options.onComplete as () => void)()
    }
    expect(root.dataset.heroMotion).toBe("settled")
  })

  it("keeps the server-rendered hero static for reduced motion", () => {
    const root = element()
    root.querySelectorAll = vi.fn(() => []) as unknown as typeof root.querySelectorAll
    const driver: HomeHeroDriver = {
      animate: vi.fn(() => ({cancel: vi.fn(), seek: vi.fn()})),
    }

    const controller = createHomeHeroController(root, {
      driver,
      reducedMotion: () => true,
      requestFrame: callback => {
        callback(0)
        return 1
      },
    })
    controller.mount()

    expect(root.dataset.heroEnhanced).toBe("true")
    expect(root.dataset.heroMotion).toBe("settled")
    expect(driver.animate).not.toHaveBeenCalled()
  })

  it("cancels pending enhancement during teardown", () => {
    const root = element()
    const cancelFrame = vi.fn()
    const controller = createHomeHeroController(root, {
      cancelFrame,
      requestFrame: vi.fn(() => 42),
    })

    controller.mount()
    controller.destroy()

    expect(cancelFrame).toHaveBeenCalledWith(42)
    expect(root.dataset.heroEnhanced).toBeUndefined()
    expect(root.dataset.heroMotion).toBeUndefined()
  })

  it("cancels active motion and restores a clean remount boundary", () => {
    const root = element()
    root.querySelectorAll = vi.fn(() => [element()]) as unknown as typeof root.querySelectorAll
    const animations = Array.from({length: 2}, () => ({cancel: vi.fn(), seek: vi.fn()}))
    const driver: HomeHeroDriver = {animate: vi.fn(() => animations.shift()!)}
    const controller = createHomeHeroController(root, {
      driver,
      reducedMotion: () => false,
      requestFrame: callback => {
        callback(0)
        return 1
      },
    })

    controller.mount()
    const active = controller.active
    controller.destroy()

    expect(active).toHaveLength(2)
    expect(active?.every(animation => vi.mocked(animation.cancel).mock.calls.length === 1)).toBe(true)
    expect(root.dataset.heroEnhanced).toBeUndefined()
    expect(root.dataset.heroMotion).toBeUndefined()
  })

  it("cancels an earlier enhancement before starting the latest mount", () => {
    const root = element()
    root.querySelectorAll = vi.fn(() => [element()]) as unknown as typeof root.querySelectorAll
    const first = Array.from({length: 2}, () => ({cancel: vi.fn(), seek: vi.fn()}))
    const second = Array.from({length: 2}, () => ({cancel: vi.fn(), seek: vi.fn()}))
    const animations = [...first, ...second]
    const driver: HomeHeroDriver = {animate: vi.fn(() => animations.shift()!)}
    const controller = createHomeHeroController(root, {
      driver,
      reducedMotion: () => false,
      requestFrame: callback => {
        callback(0)
        return 1
      },
    })

    controller.mount()
    controller.mount()

    expect(first.every(animation => animation.cancel.mock.calls.length === 1)).toBe(true)
    expect(controller.active).toEqual(second)
  })

  it("restores readable content when animation construction fails", () => {
    const targets = Array.from({length: 3}, () => element())
    targets.forEach(target => {
      target.style.opacity = "0"
      target.style.transform = "translateY(12px)"
    })
    const root = element()
    root.querySelectorAll = vi.fn(() => targets) as unknown as typeof root.querySelectorAll
    const first = {cancel: vi.fn(), seek: vi.fn()}
    const driver: HomeHeroDriver = {
      animate: vi
        .fn()
        .mockImplementationOnce(() => first)
        .mockImplementationOnce(() => {
          throw new Error("animation construction failed")
        }),
    }
    const controller = createHomeHeroController(root, {
      driver,
      reducedMotion: () => false,
      requestFrame: callback => {
        callback(0)
        return 1
      },
    })

    expect(() => controller.mount()).not.toThrow()

    expect(first.cancel).toHaveBeenCalledOnce()
    expect(controller.active).toBeNull()
    expect(root.dataset.heroEnhanced).toBe("true")
    expect(root.dataset.heroMotion).toBe("settled")
    expect(targets.every(target => target.style.opacity === "")).toBe(true)
    expect(targets.every(target => target.style.transform === "")).toBe(true)
  })
})

describe("homepage hero palette", () => {
  const HERO = ".rl-hero"
  const COLUMN = "[data-home-hero-cards]"
  const CARD = "[data-home-hero-card]"

  const pointAt = (target: unknown) => ({target}) as unknown as Event
  const leaveFor = (relatedTarget: unknown) => ({relatedTarget}) as unknown as Event

  const heroPage = () => {
    const hero = element()
    const column = element()
    const root = element()
    // The column contains itself as far as closest() is concerned, and a card really
    // does sit inside it, so both fakes answer that question the way the DOM would.
    Object.assign(column, {
      closest: (selector: string) => (selector === COLUMN ? column : null),
    })
    const card = (name: string) => {
      const node = {dataset: {homeHeroCard: name}} as unknown as HTMLElement
      Object.assign(node, {
        closest: (selector: string) =>
          selector === CARD ? node : selector === COLUMN ? column : null,
      })
      return node
    }
    root.querySelector = vi.fn((selector: string) =>
      selector === HERO ? hero : selector === COLUMN ? column : null,
    ) as unknown as typeof root.querySelector
    root.querySelectorAll = vi.fn(() => []) as unknown as typeof root.querySelectorAll
    return {card, column, hero, root}
  }

  const start = (fine: boolean) => {
    const nodes = heroPage()
    const controller = createHomeHeroController(nodes.root, {
      finePointer: () => fine,
      requestFrame: vi.fn(() => 1),
    })
    controller.mount()
    const on = (type: string) =>
      vi.mocked(nodes.column.addEventListener).mock.calls.find(([name]) => name === type)?.[1] as
        | EventListener
        | undefined
    return {...nodes, controller, on}
  }

  afterEach(() => {
    setHeroPalette("rest")
  })

  it("colours the hero for the card being pointed at and clears it on the way out", () => {
    const page = start(true)

    page.on("pointerover")!(pointAt(page.card("techtree")))

    expect(page.hero.dataset.heroProduct).toBe("techtree")
    expect(heroPalette()).toBe(HERO_PALETTES.techtree)

    page.on("pointerout")!(leaveFor(null))

    expect(page.hero.dataset.heroProduct).toBeUndefined()
    expect(heroPalette()).toBe(HERO_PALETTES.rest)
  })

  it("gives a keyboard reader the same colours as the pointer", () => {
    const page = start(true)

    page.on("focusin")!(pointAt(page.card("autolaunch")))

    expect(page.hero.dataset.heroProduct).toBe("autolaunch")
    expect(heroPalette()).toBe(HERO_PALETTES.autolaunch)

    page.on("focusout")!(leaveFor(null))

    expect(page.hero.dataset.heroProduct).toBeUndefined()
  })

  // The hairline between two cards belongs to the column, so crossing it is not
  // leaving the products: the hero goes straight from one colour to the next.
  it("changes colour once when the pointer crosses the gap between two cards", () => {
    const page = start(true)

    page.on("pointerover")!(pointAt(page.card("autolaunch")))
    page.on("pointerout")!(leaveFor(page.column))
    page.on("pointerover")!(pointAt(page.card("techtree")))

    expect(page.hero.dataset.heroProduct).toBe("techtree")
    expect(heroPalette()).toBe(HERO_PALETTES.techtree)
    expect(page.hero.dispatchEvent).toHaveBeenCalledTimes(2)
  })

  // Moving from a card's words to its own buttons is not leaving the card.
  it("holds the colour while the pointer stays inside one card", () => {
    const page = start(true)
    const patchbay = page.card("patchbay")

    page.on("pointerover")!(pointAt(patchbay))
    page.on("pointerout")!(leaveFor(patchbay))

    expect(page.hero.dataset.heroProduct).toBe("patchbay")
    expect(heroPalette()).toBe(HERO_PALETTES.patchbay)
  })

  // The two ways in are held apart, so a pointer passing through cannot take the
  // page out from under a keyboard reader standing on a card.
  it("gives the pointer the lead and hands the page back to the keyboard after it", () => {
    const page = start(true)

    page.on("focusin")!(pointAt(page.card("techtree")))
    expect(page.hero.dataset.heroProduct).toBe("techtree")

    page.on("pointerover")!(pointAt(page.card("autolaunch")))
    expect(page.hero.dataset.heroProduct).toBe("autolaunch")
    expect(heroPalette()).toBe(HERO_PALETTES.autolaunch)

    page.on("pointerout")!(leaveFor(null))
    expect(page.hero.dataset.heroProduct).toBe("techtree")
    expect(heroPalette()).toBe(HERO_PALETTES.techtree)

    page.on("focusout")!(leaveFor(null))
    expect(page.hero.dataset.heroProduct).toBeUndefined()
    expect(heroPalette()).toBe(HERO_PALETTES.rest)
  })

  // Both canvases follow one announcement, so the crown and the ground cannot disagree.
  it("announces the change once, on the hero, for the whole page to hear", () => {
    const page = start(true)

    page.on("pointerover")!(pointAt(page.card("techtree")))

    expect(page.hero.dispatchEvent).toHaveBeenCalledTimes(1)
    const announced = vi.mocked(page.hero.dispatchEvent).mock.calls[0]![0]
    expect(announced.type).toBe(HERO_PALETTE_EVENT)
    expect(announced.bubbles).toBe(true)
  })

  it("says nothing when the pointer has not really moved to another card", () => {
    const page = start(true)

    page.on("pointerover")!(pointAt(page.card("techtree")))
    page.on("pointerover")!(pointAt(page.card("techtree")))

    expect(page.hero.dispatchEvent).toHaveBeenCalledTimes(1)
  })

  // A touch is not a hover, so a phone is left with the resting page.
  it("installs nothing for a coarse pointer", () => {
    const page = start(false)

    expect(page.column.addEventListener).not.toHaveBeenCalled()
    expect(page.hero.dataset.heroProduct).toBeUndefined()
    expect(heroPalette()).toBe(HERO_PALETTES.rest)
  })

  it("returns the page to rest and lets the card column go when the hook is destroyed", () => {
    const page = start(true)
    page.on("pointerover")!(pointAt(page.card("autolaunch")))

    page.controller.destroy()

    expect(page.hero.dataset.heroProduct).toBeUndefined()
    expect(heroPalette()).toBe(HERO_PALETTES.rest)
    expect(vi.mocked(page.column.removeEventListener).mock.calls.map(([type]) => type)).toEqual([
      "pointerover",
      "pointerout",
      "focusin",
      "focusout",
    ])
  })
})
