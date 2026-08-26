import {animate, type AnimationParams} from "animejs"

type RequestFrame = (callback: FrameRequestCallback) => number
type CancelFrame = (handle: number) => void

export type HomeHeroAnimation = {
  cancel(): unknown
  seek(time: number): unknown
}

export type HomeHeroDriver = {
  animate(targets: HTMLElement[], options: Record<string, unknown>): HomeHeroAnimation
}

type WriteClipboard = (text: string) => Promise<void>

type HomeHeroOptions = {
  cancelFrame?: CancelFrame
  driver?: HomeHeroDriver
  reducedMotion?: () => boolean
  requestFrame?: RequestFrame
  writeClipboard?: WriteClipboard
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

const browserWriteClipboard: WriteClipboard = text => navigator.clipboard.writeText(text)

const COPY_TRIGGER = "[data-copy-hermes-instructions]"

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
  const reducedMotion = options.reducedMotion ?? browserReducedMotion
  const requestFrame = options.requestFrame ?? browserRequestFrame
  const writeClipboard = options.writeClipboard ?? browserWriteClipboard
  let active: HomeHeroAnimation[] | null = null
  let frame: number | undefined
  let targets: HTMLElement[] = []
  let generation = 0
  let clipboardAttached = false

  const announce = (message: string) => {
    root.querySelector<HTMLElement>("#regent-copy-status")!.textContent = message
  }

  const onClipboardClick = (event: Event) => {
    const trigger = (event.target as Element).closest<HTMLElement>(COPY_TRIGGER)
    if (!trigger) return

    void writeClipboard(trigger.dataset.copyHermesInstructions!).then(
      () => announce("Instructions copied."),
      () => announce("Couldn’t copy. Try again."),
    )
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
      // Copying is plain enhancement: it attaches ahead of, and independently of, any motion.
      if (!clipboardAttached) {
        root.addEventListener("click", onClipboardClick)
        clipboardAttached = true
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
        const cards = Array.from(root.querySelectorAll<HTMLElement>("[data-home-hero-card]"))
        const voxels = Array.from(root.querySelectorAll<HTMLElement>("[data-home-voxel]"))
        targets = [...introduction, ...cards, ...voxels]
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
          {
            targets: voxels,
            options: {
              opacity: [0.35, 0.82],
              translateX: [-4, 0],
              duration: 400,
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
      root.removeEventListener("click", onClipboardClick)
      clipboardAttached = false
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
