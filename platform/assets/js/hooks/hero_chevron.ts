/**
 * LiveView hook for the home hero's bottom double chevron (`HeroChevron`),
 * powered by `createCanvasIsland` + `vgpu` (`hero_chevron/renderer.ts`).
 *
 * Appears once the first press reveals the `Agent-native` hero center, keeps a
 * static Lucide double-chevron fallback for reduced motion or browsers without
 * WebGPU, and smooth-scrolls to `#products` on click.
 */
import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {HeroChevronRenderer} from "../hero_chevron/renderer"
import type {Hook} from "../hook_composition"

type HeroChevronHook = Hook & {
  el: HTMLElement
  island?: CanvasIslandController
  cleanupClick?: () => void
}

export const HeroChevron: Hook = {
  mounted(this: HeroChevronHook) {
    const link = this.el
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")

    const onClick = (event: MouseEvent) => {
      const href = link.getAttribute("href") ?? ""
      if (!href.startsWith("#")) return
      const target = document.getElementById(href.slice(1))
      if (!target) return
      event.preventDefault()
      target.scrollIntoView({
        behavior: reduced.matches ? "auto" : "smooth",
        block: "start",
      })
    }
    link.addEventListener("click", onClick)
    this.cleanupClick = () => link.removeEventListener("click", onClick)

    this.island = createCanvasIsland<HeroChevronRenderer>(
      link,
      {},
      {
        canvasSelector: "[data-hero-chevron-canvas]",
        readyFlag: "heroChevronReady",
        motionSensitive: true,
        continuous: true,
        maxDevicePixelRatio: 3,
        browserLoad: async (canvas, size, onDeviceLost) => {
          const {createHeroChevronRenderer} = await import("../hero_chevron/renderer")
          return createHeroChevronRenderer(canvas, size, onDeviceLost)
        },
        interact({renderer}) {
          const events = new AbortController()
          const opts = {passive: true, signal: events.signal}
          link.addEventListener("pointerenter", () => renderer()?.setHover(true), opts)
          link.addEventListener("pointerleave", () => {
            renderer()?.setHover(false)
            renderer()?.setPress(false)
          }, opts)
          link.addEventListener("pointerdown", () => renderer()?.setPress(true), opts)
          link.addEventListener("pointerup", () => renderer()?.setPress(false), opts)
          link.addEventListener("pointercancel", () => renderer()?.setPress(false), opts)
          link.addEventListener("focus", () => renderer()?.setHover(true), opts)
          link.addEventListener("blur", () => {
            renderer()?.setHover(false)
            renderer()?.setPress(false)
          }, opts)
          return () => events.abort()
        },
      },
    )
    this.island.mount()
  },

  disconnected(this: HeroChevronHook) {
    this.island?.pause()
  },

  reconnected(this: HeroChevronHook) {
    this.island?.resume()
  },

  destroyed(this: HeroChevronHook) {
    this.cleanupClick?.()
    this.cleanupClick = undefined
    this.island?.destroy()
  },
}
