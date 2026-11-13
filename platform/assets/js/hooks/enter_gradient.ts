import {createCanvasIsland} from "../canvas_island"
import {glassIsland} from "./glass_island"

/**
 * Enter App's blue, drawn as a gradient that drifts slowly between neighbouring blues.
 * It moves by itself, so it is never drawn for a visitor who asked for less motion;
 * the stylesheet's flat blue stays, as it does until a first frame has landed.
 */
export const EnterGradient = glassIsland(root =>
  createCanvasIsland(root, {}, {
    canvasSelector: "[data-enter-gradient-canvas]",
    readyFlag: "enterGradientReady",
    browserLoad: async (canvas, size, onDeviceLost) => {
      const {createEnterGradientRenderer} = await import("../enter_gradient/renderer")
      return createEnterGradientRenderer(canvas, size, onDeviceLost)
    },
    motionSensitive: true,
    continuous: true,
  }),
)
