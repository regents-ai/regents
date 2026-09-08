import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {ArtworkRenderer} from "../product_artwork"

/** Layout/fallback styling stays in the homepage; this hook owns only the canvas. */
export function createProductArtworkController(root: HTMLElement): CanvasIslandController {
  const canvas = root.querySelector<HTMLCanvasElement>("[data-product-artwork-canvas]")
  if (!canvas) {
    root.dataset.artworkFailed = "true"
    return {mount() {}, pause() {}, resume() {}, destroy() {}}
  }
  canvas.style.pointerEvents = "none"
  const controller = createCanvasIsland<ArtworkRenderer>(root, {
    supportsWebGpu: () => {
      const available = Boolean(navigator.gpu)
      if (!available) root.dataset.artworkFailed = "true"
      return available
    },
  }, {
    canvasSelector: "[data-product-artwork-canvas]",
    readyFlag: "artworkReady",
    motionSensitive: false,
    async browserLoad(target, size, onDeviceLost) {
      try {
        const {createArtworkRenderer} = await import("../product_artwork")
        return await createArtworkRenderer(root, target, size, onDeviceLost)
      } catch (error) {
        root.dataset.artworkFailed = "true"
        throw error
      }
    },
    interact({renderer, nudge, onReady}) {
      const host = root.closest<HTMLElement>(
        "[data-product-artwork-host], .rg-capability-card, .rl-hero-stakers, article, a",
      ) ?? root.parentElement ?? root
      const motion = window.matchMedia("(prefers-reduced-motion: reduce)")
      const fine = window.matchMedia("(hover: hover) and (pointer: fine)")
      const permitted = () => !motion.matches && fine.matches
      const rest = (snap = false) => {
        renderer()?.point(0, 0, false, snap)
        nudge()
      }
      const onPointer = (event: PointerEvent) => {
        if (!permitted() || event.pointerType === "touch") return
        const box = host.getBoundingClientRect()
        if (!box.width || !box.height) return
        renderer()?.point(
          ((event.clientX - box.left) / box.width - 0.5) * 2,
          ((event.clientY - box.top) / box.height - 0.5) * 2,
          true,
        )
        nudge()
      }
      const onLeave = () => rest(!permitted())
      const onPreference = () => rest(true)
      // No click, focus, keyboard, preventDefault, pointer capture or touch handlers.
      host.addEventListener("pointerenter", onPointer, {passive: true})
      host.addEventListener("pointermove", onPointer, {passive: true})
      host.addEventListener("pointerleave", onLeave, {passive: true})
      motion.addEventListener("change", onPreference)
      fine.addEventListener("change", onPreference)
      onReady(() => renderer()?.point(0, 0, false, true))
      return () => {
        host.removeEventListener("pointerenter", onPointer)
        host.removeEventListener("pointermove", onPointer)
        host.removeEventListener("pointerleave", onLeave)
        motion.removeEventListener("change", onPreference)
        fine.removeEventListener("change", onPreference)
      }
    },
  })
  return controller
}

type ArtworkHook = {
  el: HTMLElement
  controller?: CanvasIslandController
  artworkIdentity?: string
}
const identity = (root: HTMLElement) => `${root.dataset.artworkBrand}:${root.dataset.artworkVariant}`
export const ProductArtwork = {
  mounted(this: ArtworkHook) {
    this.artworkIdentity = identity(this.el)
    this.controller = createProductArtworkController(this.el)
    this.controller.mount()
  },
  updated(this: ArtworkHook) {
    if (this.artworkIdentity !== identity(this.el)) {
      this.controller?.destroy()
      delete this.el.dataset.artworkFailed
      this.artworkIdentity = identity(this.el)
      this.controller = createProductArtworkController(this.el)
      this.controller.mount()
    }
  },
  disconnected(this: ArtworkHook) {
    this.controller?.pause()
  },
  reconnected(this: ArtworkHook) {
    this.controller?.resume()
  },
  destroyed(this: ArtworkHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
