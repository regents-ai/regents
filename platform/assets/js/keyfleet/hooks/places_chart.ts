/**
 * The chart above the workspace's four places: a ridge rises over the place
 * that is open, and a little over the one a mouse points at. It only
 * decorates; the tabs under it say everything, and the page is whole before
 * it loads.
 */
import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {ChartRenderer} from "../places_chart/renderer"
import {watchTheme} from "../../theme"
import {tone} from "../theme_tone"

/** How far a ridge rises: over the open place, the one pointed at, and the rest. */
const OPEN = 1
const POINTED = 0.55
const RESTING = 0.18

type ChartHook = {el: HTMLElement; controller?: CanvasIslandController; restate?: () => void}

export const PlacesChart = {
  mounted(this: ChartHook) {
    const root = this.el
    const places = root.parentElement!
    const tabs = () => [...places.querySelectorAll<HTMLElement>("[data-tab]")].slice(0, 4)

    this.controller = createCanvasIsland<ChartRenderer>(root, {}, {
      canvasSelector: "[data-chart-canvas]",
      readyFlag: "chartReady",
      motionSensitive: true,
      continuous: false,
      browserLoad: async (canvas, size, lost) => {
        const {createChartRenderer} = await import("../places_chart/renderer")
        return createChartRenderer(canvas, size, lost)
      },
      interact: ({canvas, renderer, nudge, onReady}) => {
        let pointed: string | undefined
        const height = (tab: HTMLElement) =>
          tab.dataset.tab === root.dataset.place ? OPEN : tab.dataset.tab === pointed ? POINTED : RESTING
        const raise = () => {
          const [a, b, c, d] = tabs().map(height)
          renderer()?.rise([a ?? RESTING, b ?? RESTING, c ?? RESTING, d ?? RESTING])
          nudge()
        }
        // Each ridge stands over its own tab, wherever the layout puts the tabs.
        const aim = () => {
          const box = canvas().getBoundingClientRect()
          if (box.width === 0) return
          const spots = tabs().map(tab => tab.getBoundingClientRect())
          const [a, b, c, d] = spots.map(at => (at.left + at.width / 2 - box.left) / box.width)
          renderer()?.place([a ?? 1 / 8, b ?? 3 / 8, c ?? 5 / 8, d ?? 7 / 8], (spots[0]?.width ?? box.width / 4) / box.width)
          nudge()
        }
        const retone = () => {
          renderer()?.tones(
            tone(root, "--color-fg-muted"),
            0.45,
            tone(root, "--kf-place-project"),
            tone(root, "--kf-place-docs"),
            tone(root, "--kf-place-code"),
            tone(root, "--kf-place-public"),
          )
          nudge()
        }
        onReady(() => {
          retone()
          aim()
          raise()
        })
        this.restate = raise

        const events = new AbortController()
        const options = {signal: events.signal, passive: true}
        for (const tab of tabs()) {
          tab.addEventListener(
            "pointerenter",
            event => {
              if (event.pointerType !== "mouse") return
              pointed = tab.dataset.tab
              raise()
            },
            options,
          )
          tab.addEventListener(
            "pointerleave",
            () => {
              pointed = undefined
              raise()
            },
            options,
          )
        }
        const forget = watchTheme(retone)
        const resized = new ResizeObserver(aim)
        resized.observe(places)

        return () => {
          events.abort()
          forget()
          resized.disconnect()
          this.restate = undefined
        }
      },
    })
    this.controller.mount()
  },
  updated(this: ChartHook) {
    this.restate?.()
  },
  disconnected(this: ChartHook) {
    this.controller?.pause()
  },
  reconnected(this: ChartHook) {
    this.controller?.resume()
  },
  destroyed(this: ChartHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
