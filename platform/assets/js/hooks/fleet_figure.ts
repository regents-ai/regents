/**
 * The home page's web of cards. The server draws its lines as a still
 * picture; this hook draws them again with vgpu, flowing from the fleet to
 * the apps and from the apps to staking, and lights a card's lines while the
 * pointer or the keyboard is on it.
 *
 * Every line is read back from the page: its ends are the centres of the two
 * cards it joins, and its label sits on its middle, which fixes its bend. So
 * the picture follows the cards wherever the layout puts them.
 */
import {
  createCanvasIsland,
  type CanvasIslandController,
  type CanvasIslandOptions,
  type LoadRenderer,
} from "../canvas_island"
import type {FleetLine, FleetWebLook, FleetWebRenderer, Rgb} from "../fleet_web/renderer"

/**
 * One of the figure's colour tokens as the three 0..1 channels the shader
 * takes. The token can hold `light-dark()`, which a 2D canvas will not read,
 * so a probe in the stage resolves it to a plain colour first.
 */
let swatch: CanvasRenderingContext2D | undefined

const channels = (stage: Element, token: string): Rgb => {
  swatch ??= document.createElement("canvas").getContext("2d", {willReadFrequently: true})!
  const probe = stage.appendChild(document.createElement("i"))
  probe.style.color = `var(${token})`
  swatch.fillStyle = getComputedStyle(probe).color
  probe.remove()
  swatch.fillRect(0, 0, 1, 1)
  const [red, green, blue] = swatch.getImageData(0, 0, 1, 1).data
  return [red / 255, green / 255, blue / 255]
}

const centre = (element: Element, frame: DOMRect): [number, number] => {
  const box = element.getBoundingClientRect()
  return [
    (box.left + box.width / 2 - frame.left) / frame.width,
    (box.top + box.height / 2 - frame.top) / frame.height,
  ]
}

const readLook = (root: HTMLElement, canvas: HTMLCanvasElement, lit: string | null): FleetWebLook => {
  const frame = canvas.getBoundingClientRect()
  const card = (id: string) => root.querySelector(`[data-card="${id}"]`)!
  const lines: FleetLine[] = [...root.querySelectorAll<HTMLElement>("[data-line]")].map(word => {
    const [fromId, toId] = word.dataset.line!.split(" ")
    const from = centre(card(fromId), frame)
    const to = centre(card(toId), frame)
    const middle = centre(word, frame)
    return {
      from,
      to,
      // A quadratic curve's middle is halfway between its bend and the
      // midpoint of its ends.
      bend: [2 * middle[0] - (from[0] + to[0]) / 2, 2 * middle[1] - (from[1] + to[1]) / 2],
      revenue: word.dataset.kind === "revenue",
      lit: lit === fromId || lit === toId,
    }
  })
  return {
    lines,
    ink: channels(canvas.parentElement!, "--fleet-ink"),
    revenue: channels(canvas.parentElement!, "--fleet-revenue"),
  }
}

export const createFleetFigureController = (
  root: HTMLElement,
  options: CanvasIslandOptions<FleetWebRenderer> = {},
): CanvasIslandController => {
  let lit: string | null = null
  const canvas = () => root.querySelector<HTMLCanvasElement>("[data-fleet-canvas]")!

  const browserLoad: LoadRenderer<FleetWebRenderer> = async (element, size, onDeviceLost) => {
    const {createFleetWebRenderer} = await import("../fleet_web/renderer")
    return createFleetWebRenderer(element, size, onDeviceLost, readLook(root, element, lit))
  }

  return createCanvasIsland(root, options, {
    canvasSelector: "[data-fleet-canvas]",
    readyFlag: "fleetReady",
    browserLoad,
    motionSensitive: true,
    continuous: true,
    interact({renderer, nudge, onReady}) {
      const refresh = () => {
        renderer()?.look(readLook(root, canvas(), lit))
        nudge()
      }
      const light = (event: Event) => {
        const card = (event.target as Element).closest<HTMLElement>("[data-card]")
        lit = card?.dataset.card ?? null
        refresh()
      }
      const dim = () => {
        lit = null
        refresh()
      }

      // The layout can move every card; the theme can change both colours.
      const resized = new ResizeObserver(refresh)
      resized.observe(root)
      const themed = new MutationObserver(refresh)
      themed.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
      const scheme = window.matchMedia("(prefers-color-scheme: dark)")
      scheme.addEventListener("change", refresh)
      root.addEventListener("pointerover", light)
      root.addEventListener("pointerleave", dim)
      root.addEventListener("focusin", light)
      root.addEventListener("focusout", dim)
      onReady(refresh)

      return () => {
        resized.disconnect()
        themed.disconnect()
        scheme.removeEventListener("change", refresh)
        root.removeEventListener("pointerover", light)
        root.removeEventListener("pointerleave", dim)
        root.removeEventListener("focusin", light)
        root.removeEventListener("focusout", dim)
      }
    },
  })
}

type FleetFigureHook = {
  el: HTMLElement
  controller?: CanvasIslandController
}

export const FleetFigure = {
  mounted(this: FleetFigureHook) {
    this.controller = createFleetFigureController(this.el)
    this.controller.mount()
  },
  disconnected(this: FleetFigureHook) {
    this.controller?.pause()
  },
  reconnected(this: FleetFigureHook) {
    this.controller?.resume()
  },
  destroyed(this: FleetFigureHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
