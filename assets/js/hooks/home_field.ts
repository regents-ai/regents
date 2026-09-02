import type {FieldRenderer} from "../home_field"
import {HERO_PALETTE_EVENT} from "../home_field/palette"
import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
} from "../canvas_island"

export type HomeFieldOptions = CanvasIslandOptions<FieldRenderer>

const browserLoadField: LoadRenderer<FieldRenderer> = (canvas, size, onDeviceLost) =>
  import("../home_field").then(({createFieldRenderer}) =>
    createFieldRenderer(canvas, size, onDeviceLost),
  )

/**
 * The field of squares behind the whole page.
 *
 * It follows the same island rules as the crown, with one difference: the picture
 * is still, so a visitor who asked for less motion is shown it too — once, and
 * then only again when the window changes size.
 */
export const createHomeFieldController = (
  root: HTMLElement,
  options: HomeFieldOptions = {},
): CanvasIslandController =>
  createCanvasIsland(root, options, {
    canvasSelector: "[data-home-field-canvas]",
    readyFlag: "fieldReady",
    browserLoad: browserLoadField,
    motionSensitive: false,
    interact({root: island, nudge}) {
      // The palette is the page's, not this island's: the hero says which one is
      // showing, and the next frame is drawn in it.
      const page = () => island.parentElement!
      const onPalette = () => nudge()

      page().addEventListener(HERO_PALETTE_EVENT, onPalette)
      return () => page().removeEventListener(HERO_PALETTE_EVENT, onPalette)
    },
  })

type HomeFieldHook = {
  el: HTMLElement
  controller?: CanvasIslandController
}

export const HomeField = {
  mounted(this: HomeFieldHook) {
    this.controller = createHomeFieldController(this.el)
    this.controller.mount()
  },
  disconnected(this: HomeFieldHook) {
    this.controller?.pause()
  },
  reconnected(this: HomeFieldHook) {
    this.controller?.resume()
  },
  destroyed(this: HomeFieldHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
