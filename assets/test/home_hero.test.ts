import {describe, expect, it, vi} from "vitest"

import {
  HomeHero,
  createHomeHeroController,
  type HomeHeroAnimation,
  type HomeHeroDriver,
} from "../js/hooks/home_hero"

const element = () => ({style: {}, dataset: {}}) as unknown as HTMLElement

const gateway = (id: string, href: string) =>
  ({...element(), id, getAttribute: (name: string) => (name === "href" ? href : null)}) as HTMLElement

describe("homepage hero enhancement", () => {
  it("publishes the stable HomeHero hook expected by the Ash entrypoint", () => {
    expect(HomeHero).toMatchObject({
      mounted: expect.any(Function),
      destroyed: expect.any(Function),
    })
  })

  it("leaves the four server-owned OPEN gateway destinations unchanged", () => {
    const cards = [
      gateway("home-card-formation", "/formation"),
      gateway("home-card-autolaunch", "/autolaunch"),
      gateway("home-card-techtree", "/techtree"),
      gateway("home-card-regent", "/app"),
    ]
    const root = element()
    root.querySelectorAll = vi.fn((selector: string) =>
      selector === "[data-home-hero-card]" ? cards : [],
    ) as unknown as typeof root.querySelectorAll
    const driver: HomeHeroDriver = {
      animate: vi.fn(() => ({cancel: vi.fn(), seek: vi.fn()})),
    }
    const controller = createHomeHeroController(root, {
      driver,
      reducedMotion: () => false,
      requestFrame: callback => {
        callback(0)
        return 1
      },
    })

    controller.mount()

    expect(cards.map(card => [card.id, card.getAttribute("href")])).toEqual([
      ["home-card-formation", "/formation"],
      ["home-card-autolaunch", "/autolaunch"],
      ["home-card-techtree", "/techtree"],
      ["home-card-regent", "/app"],
    ])
    expect(driver.animate).toHaveBeenCalledWith(cards, expect.any(Object))
  })

  it("enhances all four already-readable cards together after first paint", () => {
    const header = element()
    const copy = element()
    const cards = [element(), element(), element(), element()]
    const voxels = [element(), element()]
    const root = element()
    root.querySelectorAll = vi.fn((selector: string) => {
      switch (selector) {
        case "[data-home-header], [data-home-hero-copy]":
          return [header, copy]
        case "[data-home-hero-card]":
          return cards
        case "[data-home-voxel]":
          return voxels
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
    expect(animations).toHaveLength(3)
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
    expect(driver.animate).toHaveBeenNthCalledWith(
      3,
      voxels,
      expect.objectContaining({duration: 400, opacity: [0.35, 0.82]}),
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
    const animations = Array.from({length: 3}, () => ({cancel: vi.fn(), seek: vi.fn()}))
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

    expect(active).toHaveLength(3)
    expect(active?.every(animation => vi.mocked(animation.cancel).mock.calls.length === 1)).toBe(true)
    expect(root.dataset.heroEnhanced).toBeUndefined()
    expect(root.dataset.heroMotion).toBeUndefined()
  })

  it("cancels an earlier enhancement before starting the latest mount", () => {
    const root = element()
    root.querySelectorAll = vi.fn(() => [element()]) as unknown as typeof root.querySelectorAll
    const first = Array.from({length: 3}, () => ({cancel: vi.fn(), seek: vi.fn()}))
    const second = Array.from({length: 3}, () => ({cancel: vi.fn(), seek: vi.fn()}))
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
