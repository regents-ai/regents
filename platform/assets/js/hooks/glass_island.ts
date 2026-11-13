import type {CanvasIslandController} from "../canvas_island"

type GlassIslandHook = {
  el: HTMLElement
  controller?: CanvasIslandController
  glass?: MutationObserver
  connected?: boolean
  follow?: () => void
}

/**
 * The hook for a picture on the home page's glass panel, which goes away (shrunk and
 * clear) while the visitor flies the picture behind it. The Datascape hook round the
 * panel says which on its root, and it mounts first, as LiveView mounts hooks in page
 * order. The picture draws only while the panel can be seen and the page is connected.
 */
export const glassIsland = (create: (root: HTMLElement) => CanvasIslandController) => ({
  mounted(this: GlassIslandHook) {
    const controller = create(this.el)
    const home = this.el.closest<HTMLElement>("[data-datascape-glass-state]")
    this.controller = controller
    this.connected = true
    this.follow = () => {
      const away =
        home?.dataset.datascapeGlassState === "away" && home.dataset.datascapeReady !== "false"
      if (this.connected && !away) controller.resume()
      else controller.pause()
    }
    if (home) {
      this.glass = new MutationObserver(this.follow)
      this.glass.observe(home, {attributeFilter: ["data-datascape-glass-state", "data-datascape-ready"]})
    }
    controller.mount()
    this.follow()
  },
  disconnected(this: GlassIslandHook) {
    this.connected = false
    this.follow?.()
  },
  reconnected(this: GlassIslandHook) {
    this.connected = true
    this.follow?.()
  },
  destroyed(this: GlassIslandHook) {
    this.glass?.disconnect()
    this.controller?.destroy()
    this.controller = undefined
  },
})
