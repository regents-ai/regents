import type {PrismRenderer} from "../home_prism"

type RequestFrame = (callback: FrameRequestCallback) => number
type CancelFrame = (handle: number) => void

type MediaQuery = {
  readonly matches: boolean
  addEventListener(type: "change", listener: () => void): void
  removeEventListener(type: "change", listener: () => void): void
}

type LoadRenderer = (
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
) => Promise<PrismRenderer>

export type HomePrismOptions = {
  cancelFrame?: CancelFrame
  devicePixelRatio?: () => number
  loadRenderer?: LoadRenderer
  motionQuery?: () => MediaQuery
  pointerQuery?: () => MediaQuery
  requestFrame?: RequestFrame
  supportsWebGpu?: () => boolean
}

export type HomePrismController = {
  mount(): void
  pause(): void
  resume(): void
  destroy(): void
}

/** Resolution ceilings. The picture is decorative; a 4K backing store is not. */
export const MAX_DEVICE_PIXEL_RATIO = 1.5
export const MAX_DRAWING_BUFFER_PIXELS = 1_500_000

/** Frames the easing may spend settling after the pointer stops moving. */
export const EASING_FRAME_LIMIT = 24

/**
 * Backing-store size for a CSS box, capped on both device pixel ratio and total
 * pixels. Both axes take the same scale, so the picture never stretches.
 */
export function drawingBufferSize(
  width: number,
  height: number,
  devicePixelRatio: number,
): readonly [number, number] {
  const ratio = Math.min(MAX_DEVICE_PIXEL_RATIO, Math.max(1, devicePixelRatio))
  const requested = width * height * ratio * ratio
  const fit =
    requested > MAX_DRAWING_BUFFER_PIXELS ? Math.sqrt(MAX_DRAWING_BUFFER_PIXELS / requested) : 1
  return [
    Math.max(1, Math.floor(width * ratio * fit)),
    Math.max(1, Math.floor(height * ratio * fit)),
  ]
}

const browserRequestFrame: RequestFrame = callback => window.requestAnimationFrame(callback)
const browserCancelFrame: CancelFrame = handle => window.cancelAnimationFrame(handle)
const browserLoadRenderer: LoadRenderer = (canvas, size, onDeviceLost) =>
  import("../home_prism").then(({createPrismRenderer}) =>
    createPrismRenderer(canvas, size, onDeviceLost),
  )

export const createHomePrismController = (
  root: HTMLElement,
  options: HomePrismOptions = {},
): HomePrismController => {
  const cancelFrame = options.cancelFrame ?? browserCancelFrame
  const devicePixelRatio = options.devicePixelRatio ?? (() => window.devicePixelRatio || 1)
  const loadRenderer = options.loadRenderer ?? browserLoadRenderer
  const motionQuery =
    options.motionQuery ?? (() => window.matchMedia("(prefers-reduced-motion: reduce)"))
  const pointerQuery = options.pointerQuery ?? (() => window.matchMedia("(pointer: fine)"))
  const requestFrame = options.requestFrame ?? browserRequestFrame
  const supportsWebGpu = options.supportsWebGpu ?? (() => Boolean(navigator.gpu))

  const canvas = () => root.querySelector<HTMLCanvasElement>("[data-home-prism-canvas]")!
  // The island itself takes no pointer events, so hover is read from the hero it
  // decorates — the element the server renders it inside.
  const hero = () => root.parentElement!

  const motion = motionQuery()

  let generation = 0
  let renderer: PrismRenderer | undefined
  let release: (() => void) | undefined
  let startFrame: number | undefined
  let startingGeneration: number | undefined
  let renderFrame: number | undefined
  let pendingSize: readonly [number, number] | undefined
  let pendingPresent = false
  let confirming = false
  let easingFrames = 0

  // Every reason the island may work is tracked apart from every other one, because
  // they come back independently: a hero scrolling into view while the tab is hidden
  // is worth exactly as much as a tab returning while the hero is still offscreen.
  let mounted = false
  let retired = false
  let awake = true
  let onscreen = false
  let visible = true
  let motionAllowed = true

  /** Nothing is scheduled, imported or drawn unless all of these hold. */
  const active = () => mounted && !retired && awake && visible && onscreen && motionAllowed

  const measure = (): readonly [number, number] => {
    const {width, height} = canvas().getBoundingClientRect()
    return drawingBufferSize(width, height, devicePixelRatio())
  }

  const stopFrame = () => {
    if (renderFrame !== undefined) cancelFrame(renderFrame)
    renderFrame = undefined
  }

  const stopStart = () => {
    if (startFrame !== undefined) cancelFrame(startFrame)
    startFrame = undefined
  }

  const schedule = () => {
    if (renderFrame !== undefined || !renderer || !active()) return
    renderFrame = requestFrame(tick)
  }

  const invalidate = () => {
    pendingPresent = true
    schedule()
  }

  /**
   * Two frames of headroom before the renderer chunk is even asked for. The first
   * callback still runs before the server hero paints; the second runs after it.
   *
   * A start still waiting on the chunk has no renderer to point at yet, so the generation
   * it belongs to is what says one is already coming. Only a newer one may ask again.
   */
  const scheduleStart = () => {
    if (startFrame !== undefined || startingGeneration === generation || renderer) return
    const started = generation
    startFrame = requestFrame(() => {
      startFrame = requestFrame(() => {
        startFrame = undefined
        startingGeneration = started
        void start(started)
      })
    })
  }

  /**
   * The one place the island decides whether it should be doing anything at all. Every
   * condition is read fresh, so a return on one axis while another still says no
   * queues no work of any kind.
   */
  const sync = () => {
    if (!active()) {
      stopStart()
      stopFrame()
      // A start that was in flight belongs to a generation that no longer wants it;
      // whatever it produces is disposed when it lands.
      if (!renderer) generation += 1
      return
    }
    if (renderer) invalidate()
    else scheduleStart()
  }

  /**
   * Back to the server's hero art: the renderer is dropped and the reveal undone.
   * Bumping the generation is what makes an import or a frame confirmation still in
   * flight land on the floor instead of on a disposed renderer.
   */
  const retreat = () => {
    generation += 1
    confirming = false
    pendingPresent = false
    easingFrames = 0
    delete root.dataset.prismReady
    stopStart()
    stopFrame()
    renderer?.dispose()
    renderer = undefined
  }

  /** A retreat the island does not come back from: the GPU is not going to draw this. */
  const retire = () => {
    retired = true
    retreat()
  }

  /** The fallback stays until real GPU work for the first frame has finished. */
  const confirmFirstFrame = () => {
    confirming = true
    const drawn = generation
    void renderer!.settled().then(
      () => {
        if (drawn === generation) root.dataset.prismReady = "true"
      },
      () => {
        if (drawn === generation) retire()
      },
    )
  }

  function tick(): void {
    renderFrame = undefined
    if (!renderer) return
    if (pendingSize) {
      renderer.resize(pendingSize[0], pendingSize[1])
      pendingSize = undefined
      pendingPresent = true
    }
    easingFrames += 1
    // The last frame the easing is allowed snaps home, so there is never a frame after
    // it with nothing left to do.
    const last = easingFrames >= EASING_FRAME_LIMIT
    const moved = renderer.step(last)
    if (!moved && !pendingPresent) return
    pendingPresent = false
    renderer.present()
    if (!confirming) confirmFirstFrame()
    if (moved && !last) schedule()
  }

  const attach = (): (() => void) => {
    const resizeObserver = new ResizeObserver(() => {
      pendingSize = measure()
      invalidate()
    })
    // One element is observed, so the last entry is the island's current standing.
    const intersectionObserver = new IntersectionObserver(entries => {
      onscreen = entries.at(-1)?.isIntersecting ?? onscreen
      sync()
    })
    const onVisibilityChange = () => {
      visible = !document.hidden
      sync()
    }
    const onPointerMove = (event: PointerEvent) => {
      if (event.isPrimary === false) return
      const {left, top, width, height} = hero().getBoundingClientRect()
      renderer?.aim((event.clientX - left) / width, (event.clientY - top) / height)
      easingFrames = 0
      invalidate()
    }
    const onPointerLeave = () => {
      renderer?.rest()
      easingFrames = 0
      invalidate()
    }

    resizeObserver.observe(canvas())
    intersectionObserver.observe(root)
    document.addEventListener("visibilitychange", onVisibilityChange)
    // Coarse pointers get the composed shot: a tap is not a hover, and chasing one
    // would wake the GPU for every scroll gesture.
    const fine = pointerQuery().matches
    if (fine) {
      hero().addEventListener("pointermove", onPointerMove, {passive: true})
      hero().addEventListener("pointerleave", onPointerLeave, {passive: true})
    }

    return () => {
      resizeObserver.disconnect()
      intersectionObserver.disconnect()
      document.removeEventListener("visibilitychange", onVisibilityChange)
      if (fine) {
        hero().removeEventListener("pointermove", onPointerMove)
        hero().removeEventListener("pointerleave", onPointerLeave)
      }
    }
  }

  const start = async (started: number) => {
    const loaded = await loadRenderer(canvas(), measure(), () => {
      if (started === generation) retire()
    }).catch(() => undefined)
    if (started !== generation) {
      loaded?.dispose()
      return
    }
    if (!loaded) {
      // The chunk or the device is not coming. The server's art is the picture.
      retire()
      return
    }
    renderer = loaded
    invalidate()
  }

  const onMotionChange = () => {
    motionAllowed = !motion.matches
    if (!motionAllowed) retreat()
    sync()
  }

  return {
    mount() {
      if (release || !supportsWebGpu()) return
      mounted = true
      retired = false
      awake = true
      // The fresh observer, not the last lifetime, says where the island stands now.
      onscreen = false
      visible = !document.hidden
      motionAllowed = !motion.matches
      motion.addEventListener("change", onMotionChange)
      // Watching comes before loading: an island the visitor cannot see never asks
      // for the chunk it could not show them.
      release = attach()
      sync()
    },
    pause() {
      awake = false
      sync()
    },
    resume() {
      awake = true
      sync()
    },
    destroy() {
      mounted = false
      motion.removeEventListener("change", onMotionChange)
      release?.()
      release = undefined
      retreat()
    },
  }
}

type HomePrismHook = {
  el: HTMLElement
  controller?: HomePrismController
}

export const HomePrism = {
  mounted(this: HomePrismHook) {
    this.controller = createHomePrismController(this.el)
    this.controller.mount()
  },
  disconnected(this: HomePrismHook) {
    this.controller?.pause()
  },
  reconnected(this: HomePrismHook) {
    this.controller?.resume()
  },
  destroyed(this: HomePrismHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
