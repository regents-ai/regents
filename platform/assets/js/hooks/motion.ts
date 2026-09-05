import {animate, createScope, type AnimationParams} from "animejs"

export const APP_ENTRY_DURATION = 270
export const APP_EXIT_DURATION = 180
export const CONTENT_ENTRY_DURATION = 180
export const CONTENT_EXIT_DURATION = 120
export const SURFACE_ENTRY_DURATION = 210
export const SURFACE_EXIT_DURATION = 140
export const SURFACE_STAGGER_DELAY = 24
export const MOTION_SELECTORS = {
  region: "[data-motion-region]",
  background: "[data-motion-background]",
  headerControls: "[data-motion-header-controls]",
  surface: "[data-motion-surface]",
} as const

export type MotionAnimation = {
  cancel(): unknown
  seek(time: number): unknown
}

export type MotionDriver = {
  animate(target: HTMLElement | HTMLElement[], options: Record<string, unknown>): MotionAnimation
}

type MotionScope = {
  revert(): unknown
}

type MotionScopeFactory = (root: HTMLElement) => MotionScope

export type MotionIntent = {
  kind: "direct" | "app" | "content"
  source?: "pointer" | "keyboard"
  reducedMotion?: boolean
  outgoing?: HTMLElement[]
  incoming: HTMLElement[]
  outgoingSurfaces?: HTMLElement[]
  incomingSurfaces?: HTMLElement[]
  outgoingBackground?: HTMLElement
  incomingBackground?: HTMLElement
  outgoingHeaderControls?: HTMLElement
  incomingHeaderControls?: HTMLElement
  onSettled?: () => void
}

export type MotionController = {
  readonly active: MotionAnimation | null
  transition(intent: MotionIntent): MotionAnimation | null
  destroy(): void
}

const animeDriver: MotionDriver = {
  animate: (target, options) => animate(target, options as AnimationParams),
}

const animeScope: MotionScopeFactory = (root) => createScope({root})

const show = (target: HTMLElement | undefined) => {
  if (!target) return
  target.style.opacity = "1"
  target.style.transform = "none"
}

const hide = (target: HTMLElement | undefined) => {
  if (!target) return
  target.style.opacity = "0"
  target.style.transform = "none"
}

const renderLatest = (intent: MotionIntent) => {
  intent.outgoing?.forEach(hide)
  intent.incoming.forEach(show)
  intent.outgoingSurfaces?.forEach(hide)
  intent.incomingSurfaces?.forEach(show)
  hide(intent.outgoingBackground)
  show(intent.incomingBackground)
  hide(intent.outgoingHeaderControls)
  show(intent.incomingHeaderControls)
  intent.onSettled?.()
}

const composite = (animations: MotionAnimation[]): MotionAnimation => ({
  cancel() {
    animations.forEach((animation) => animation.cancel())
  },
  seek(time) {
    animations.forEach((animation) => animation.seek(time))
  },
})

const edgeDelay = (root: HTMLElement, target: HTMLElement) => {
  const rootBox = root.getBoundingClientRect()
  const box = target.getBoundingClientRect()
  const rootCenter = rootBox.left + rootBox.width / 2
  const distance = Math.abs(box.left + box.width / 2 - rootCenter)
  const maximum = Math.max(rootBox.width / 2, 1)
  return Math.round(20 * (1 - Math.min(distance / maximum, 1)))
}

const incomingX = (root: HTMLElement, target: HTMLElement) => {
  const rootBox = root.getBoundingClientRect()
  const box = target.getBoundingClientRect()
  return box.left + box.width / 2 < rootBox.left + rootBox.width / 2 ? -12 : 12
}

const surfaceTravel = (target: HTMLElement) =>
  target.dataset.motionSurface === "detail" ? 10 : 6

const surfaceDelay = (target: HTMLElement, index: number) =>
  target.dataset.motionSurface === "list-item"
    ? Math.min(index * SURFACE_STAGGER_DELAY, SURFACE_STAGGER_DELAY * 4)
    : 0

export const createMotionController = (
  root: HTMLElement,
  driver: MotionDriver = animeDriver,
  scopeFactory: MotionScopeFactory = animeScope,
): MotionController => {
  const scope = scopeFactory(root)
  let active: MotionAnimation | null = null
  let generation = 0

  const cancelActive = () => {
    active?.cancel()
    active = null
  }

  return {
    get active() {
      return active
    },
    transition(intent) {
      cancelActive()
      const intentGeneration = ++generation

      if (intent.kind === "direct" || intent.reducedMotion || intent.source === "keyboard") {
        renderLatest(intent)
        return null
      }

      const animations: MotionAnimation[] = []
      let remaining =
        (intent.outgoing?.length ?? 0) +
        intent.incoming.length +
        (intent.outgoingSurfaces?.length ?? 0) +
        (intent.incomingSurfaces?.length ?? 0) +
        (intent.kind === "app"
          ? Number(Boolean(intent.outgoingBackground)) +
            Number(Boolean(intent.incomingBackground)) +
            Number(Boolean(intent.outgoingHeaderControls)) +
            Number(Boolean(intent.incomingHeaderControls))
          : 0)
      if (remaining === 0) {
        renderLatest(intent)
        return null
      }
      const complete = () => {
        remaining -= 1
        if (remaining === 0 && generation === intentGeneration) {
          renderLatest(intent)
          active = null
        }
      }

      if (intent.kind === "content") {
        intent.outgoing?.forEach((target) =>
          animations.push(
            driver.animate(target, {
              opacity: 0,
              duration: CONTENT_EXIT_DURATION,
              ease: "inQuad",
              onComplete: complete,
            }),
          ),
        )
        intent.incoming.forEach((target) =>
          animations.push(
            driver.animate(target, {
              opacity: 1,
              duration: CONTENT_ENTRY_DURATION,
              ease: "outQuad",
              onComplete: complete,
            }),
          ),
        )
      } else {
        intent.outgoing?.forEach((target) =>
          animations.push(
            driver.animate(target, {
              opacity: 0,
              translateY: 8,
              duration: APP_EXIT_DURATION,
              ease: "inQuart",
              onComplete: complete,
            }),
          ),
        )
        intent.incoming.forEach((target) => {
          if (!target.style.opacity) target.style.opacity = "0"
          if (!target.style.transform) target.style.transform = `translateX(${incomingX(root, target)}px)`
          const delay = edgeDelay(root, target)
          animations.push(
            driver.animate(target, {
              opacity: 1,
              translateX: 0,
              delay,
              duration: APP_ENTRY_DURATION - delay,
              ease: "outQuart",
              onComplete: complete,
            }),
          )
        })
        const crossfade = (
          target: HTMLElement | undefined,
          opacity: number,
          duration: number,
          ease: "inQuart" | "outQuart",
        ) => {
          if (!target) return
          animations.push(
            driver.animate(target, {
              opacity,
              duration,
              ease,
              onComplete: complete,
            }),
          )
        }
        crossfade(intent.outgoingBackground, 0, APP_EXIT_DURATION, "inQuart")
        crossfade(intent.incomingBackground, 1, APP_ENTRY_DURATION, "outQuart")
        crossfade(intent.outgoingHeaderControls, 0, APP_EXIT_DURATION, "inQuart")
        crossfade(intent.incomingHeaderControls, 1, APP_ENTRY_DURATION, "outQuart")
      }

      intent.outgoingSurfaces?.forEach((target) =>
        animations.push(
          driver.animate(target, {
            opacity: 0,
            translateY: surfaceTravel(target),
            duration: SURFACE_EXIT_DURATION,
            ease: "inQuart",
            onComplete: complete,
          }),
        ),
      )
      intent.incomingSurfaces?.forEach((target, index) => {
        if (!target.style.opacity) target.style.opacity = "0"
        if (!target.style.transform) {
          target.style.transform = `translateY(${surfaceTravel(target)}px)`
        }
        animations.push(
          driver.animate(target, {
            opacity: 1,
            translateY: 0,
            delay: surfaceDelay(target, index),
            duration: SURFACE_ENTRY_DURATION,
            ease: "outQuart",
            onComplete: complete,
          }),
        )
      })

      if (animations.length === 0) {
        renderLatest(intent)
        return null
      }

      active = composite(animations)
      return active
    },
    destroy() {
      cancelActive()
      scope.revert()
    },
  }
}

type ShellMotionHookState = {
  el: HTMLElement
  motion?: MotionController
  motionFactory?: (root: HTMLElement) => MotionController
  motionApp?: string
  motionSnapshot?: MotionSnapshot
  motionCopies?: HTMLElement[]
}

type MotionSnapshot = {
  app?: string
  destination?: string
  regions: HTMLElement[]
  surfaces: HTMLElement[]
  background?: HTMLElement
  headerControls?: HTMLElement
}

const cloneForMotion = (target: HTMLElement) => {
  const copy = target.cloneNode(true) as HTMLElement
  const box = target.getBoundingClientRect()
  copy.dataset.motionCopy = "true"
  copy.removeAttribute("id")
  copy.querySelectorAll<HTMLElement>("[id]").forEach((descendant) => descendant.removeAttribute("id"))
  copy.setAttribute("aria-hidden", "true")
  copy.inert = true
  Object.assign(copy.style, {
    position: "fixed",
    left: `${box.left}px`,
    top: `${box.top}px`,
    width: `${box.width}px`,
    height: `${box.height}px`,
    margin: "0",
    pointerEvents: "none",
  })
  return copy
}

const current = <T extends HTMLElement>(root: HTMLElement, selector: string) =>
  Array.from(root.querySelectorAll<T>(selector)).filter((target) => target.dataset.motionCopy !== "true")

const capture = (root: HTMLElement): MotionSnapshot => {
  const regions = current<HTMLElement>(root, MOTION_SELECTORS.region).map(cloneForMotion)
  const surfaces = regions.flatMap((region) =>
    [...region.querySelectorAll<HTMLElement>(MOTION_SELECTORS.surface)],
  )
  const background = current<HTMLElement>(root, MOTION_SELECTORS.background)[0]
  const headerControls = current<HTMLElement>(root, MOTION_SELECTORS.headerControls)[0]

  return {
    app: root.dataset.motionApp,
    destination: root.dataset.destination,
    regions,
    surfaces,
    background: background ? cloneForMotion(background) : undefined,
    headerControls: headerControls ? cloneForMotion(headerControls) : undefined,
  }
}

const clearCopies = (hook: ShellMotionHookState) => {
  hook.motionCopies?.forEach((copy) => copy.remove())
  hook.motionCopies = []
}

export const ShellMotion = {
  mounted(this: ShellMotionHookState) {
    this.motion = (this.motionFactory ?? createMotionController)(this.el)
    this.motionApp = this.el.dataset.motionApp
    this.motionCopies = []
    const incomingSurfaces = current<HTMLElement>(this.el, MOTION_SELECTORS.surface)
    if (incomingSurfaces.length > 0) {
      this.motion.transition({
        kind: "content",
        source: this.el.dataset.motionSource === "keyboard" ? "keyboard" : "pointer",
        reducedMotion: this.el.dataset.reducedMotion === "true",
        incoming: [],
        incomingSurfaces,
      })
    }
  },
  beforeUpdate(this: ShellMotionHookState) {
    clearCopies(this)
    this.motionSnapshot = capture(this.el)
  },
  updated(this: ShellMotionHookState) {
    const snapshot = this.motionSnapshot
    if (!snapshot || !this.motion) return

    clearCopies(this)
    const nextDestination = this.el.dataset.destination
    const incoming = current<HTMLElement>(this.el, MOTION_SELECTORS.region)
    const incomingSurfaces = current<HTMLElement>(this.el, MOTION_SELECTORS.surface)
    const incomingBackground = current<HTMLElement>(this.el, MOTION_SELECTORS.background)[0]
    const incomingHeaderControls = current<HTMLElement>(this.el, MOTION_SELECTORS.headerControls)[0]

    if (!snapshot.destination || !nextDestination || snapshot.destination === nextDestination) {
      this.motion.transition({
        kind: "direct",
        incoming,
        incomingSurfaces,
        incomingBackground,
        incomingHeaderControls,
      })
      this.motionSnapshot = undefined
      return
    }

    const copies = [snapshot.background, ...snapshot.regions, snapshot.headerControls].filter(
      (target): target is HTMLElement => Boolean(target),
    )
    this.motionCopies = copies
    this.el.append(...copies)

    const nextApp = this.el.dataset.motionApp
    const source = this.el.dataset.motionSource === "keyboard" ? "keyboard" : "pointer"
    const reducedMotion = this.el.dataset.reducedMotion === "true"
    this.motion.transition({
      kind: snapshot.app && nextApp && snapshot.app !== nextApp ? "app" : "content",
      source,
      reducedMotion,
      outgoing: snapshot.regions,
      incoming,
      outgoingSurfaces: snapshot.surfaces,
      incomingSurfaces,
      outgoingBackground: snapshot.background,
      incomingBackground,
      outgoingHeaderControls: snapshot.headerControls,
      incomingHeaderControls,
      onSettled: () => clearCopies(this),
    })
    this.motionApp = nextApp
    this.motionSnapshot = undefined
  },
  destroyed(this: ShellMotionHookState) {
    clearCopies(this)
    this.motion?.destroy()
    this.motion = undefined
    this.motionSnapshot = undefined
  },
}
