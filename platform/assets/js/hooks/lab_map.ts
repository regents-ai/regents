/**
 * The lab map in the Overview hero (`RegentsWeb.Components.LabMap`).
 *
 * The server draws the whole map; this hook only moves it. On arrival the dots
 * come up, the lines draw out from their first end and the names follow, all
 * inside a second. A line under the mouse, focused or tapped, is picked: it and
 * its two ends stay lifted, everything else dims, and its sentence shows in the
 * caption. A dot under the mouse or focused lifts every line it has. A pick made
 * from the keyboard, or for a visitor who asked for less motion, simply shows.
 *
 * Behind the map a slow glow round each product's dot is drawn on the GPU
 * (`lab_map/renderer.ts`) on the page's shared device, and follows the pick.
 * Without WebGPU, or with less motion asked for, the map stands without it.
 */
import {createScope, createTimeline, stagger, utils, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {LabMapRenderer, Spot} from "../lab_map/renderer"
import {EASE_OUT, FAST, lastInputByPointer, play, rest, still} from "./motion/shared"

/** One line, by its place among the lines, or one dot, by its name. */
type Pick = {line: number} | {dot: string} | null

type LabMapHook = {el: HTMLElement; scope?: Scope; island?: CanvasIslandController}

/** How far a product's glow reaches, in CSS pixels. */
const REACH = 92
/** The colour Sign-in with Agent's end of a line glows in; it has no colour of its own. */
const QUIET = [0.7, 0.7, 0.66] as const

const byte = (hex: string, at: number) => parseInt(hex.slice(at, at + 2), 16) / 255
const channels = (hex: string): Spot["tint"] => [byte(hex, 1), byte(hex, 3), byte(hex, 5)]

const percent = (el: HTMLElement, name: string) => parseFloat(el.style.getPropertyValue(name)) / 100

export const LabMap = {
  mounted(this: LabMapHook) {
    const root = this.el
    const lines = [...root.querySelectorAll<SVGGElement>(".lab-map__link")]
    const dots = [...root.querySelectorAll<HTMLElement>(".lab-map__node")]
    const says = [...root.querySelectorAll<HTMLElement>(".lab-map__say")]
    const faders = [...root.querySelectorAll<Element>(".lab-map__line, .lab-map__ink, .lab-map__node")]
    const names = dots.map(dot => dot.dataset.node!)
    const ends = lines.map(line => [line.dataset.from!, line.dataset.to!] as const)

    let hovered: Pick = null
    let focused: Pick = null
    let current: Pick = null
    let shown = ""
    let lifted = {lines: new Set<number>(), dots: new Set<string>()}
    let renderer: () => LabMapRenderer | undefined = () => undefined
    let nudge = () => {}

    const lineOf = (target: EventTarget | null) => {
      const line = target instanceof Element ? target.closest<SVGGElement>(".lab-map__link") : null
      return line ? lines.indexOf(line) : -1
    }
    const pickAt = (target: EventTarget | null): Pick => {
      const line = lineOf(target)
      if (line >= 0) return {line}
      const dot = target instanceof Element ? target.closest<HTMLElement>(".lab-map__node") : null
      return dot ? {dot: dot.dataset.node!} : null
    }

    /** The glow behind the map follows the pick. */
    const tell = () => {
      const [from, to] = current && "line" in current ? ends[current.line]! : []
      const line = from && to ? ([names.indexOf(from), names.indexOf(to)] as const) : null
      renderer()?.pick(new Set([...lifted.dots].map(name => names.indexOf(name))), line)
      nudge()
    }

    const opacityOf = (el: Element) => Number(getComputedStyle(el).opacity)

    const show = (pick: Pick) => {
      const key = pick === null ? "" : "line" in pick ? `line ${pick.line}` : `dot ${pick.dot}`
      if (key === shown) return
      shown = key
      current = pick

      const touching =
        pick === null ? [] : "line" in pick ? [pick.line] : ends.flatMap(([from, to], line) =>
          from === pick.dot || to === pick.dot ? [line] : [])
      lifted = {
        lines: new Set(touching),
        dots: new Set([...(pick && "dot" in pick ? [pick.dot] : []), ...touching.flatMap(line => ends[line]!)]),
      }
      const say = pick && "line" in pick ? String(pick.line) : ""

      // Each change starts from wherever the last one had got to.
      const before = new Map(faders.map(el => [el, opacityOf(el)]))
      const saidBefore = says.find(el => el.hasAttribute("data-shown"))
      rest(faders)

      if (pick === null) delete root.dataset.labMapPick
      else root.dataset.labMapPick = "line" in pick ? "line" : "dot"
      lines.forEach((line, index) => line.toggleAttribute("data-picked", lifted.lines.has(index)))
      dots.forEach(dot => dot.toggleAttribute("data-picked", lifted.dots.has(dot.dataset.node!)))
      for (const el of says) el.toggleAttribute("data-shown", el.dataset.say === say)

      if (lastInputByPointer() && !still(root)) {
        const changed = faders.filter(el => Math.abs(opacityOf(el) - before.get(el)!) > 0.01)
        if (changed.length > 0) scope.methods.fade!(changed, before)
        const saying = says.find(el => el.dataset.say === say)!
        if (saying !== saidBefore) scope.methods.fade!([saying], new Map([[saying, 0]]))
      }
      tell()
    }
    const update = () => show(hovered ?? focused)

    const scope = createScope({root})
    this.scope = scope

    scope.add(() => {
      /** Moves elements from the opacity each had to the one the stylesheet now gives it. */
      scope.add("fade", (targets: Element[], from: Map<Element, number>) => {
        play(targets, {opacity: {from: (el: unknown) => from.get(el as Element)!}, duration: FAST, ease: EASE_OUT})
      })

      /** The first arrival: dots, then lines drawn from their first end, then names. */
      scope.add("enter", () => {
        createTimeline({
          defaults: {ease: EASE_OUT},
          onComplete: self => {
            root.dataset.labMapMotion = "rest"
            utils.cleanInlineStyles(self)
          },
        })
          .add(root.querySelectorAll(".lab-map__dot"), {opacity: [0, 1], scale: [0.4, 1], duration: 360, delay: stagger(40)}, 0)
          .add(root.querySelectorAll(".lab-map__line"), {strokeDashoffset: [1, 0], duration: 480, delay: stagger(24)}, 120)
          .add(root.querySelectorAll(".lab-map__name"), {opacity: [0, 1], duration: 300, delay: stagger(40)}, 260)
      })

      const events = new AbortController()
      const options = {signal: events.signal}
      root.addEventListener("pointerover", (event: PointerEvent) => {
        if (event.pointerType === "touch") return
        hovered = pickAt(event.target)
        update()
      }, options)
      root.addEventListener("pointerleave", () => {
        hovered = null
        update()
      }, options)
      // A tapped or clicked line keeps its pick until focus moves on.
      root.addEventListener("click", (event: MouseEvent) => {
        const line = lineOf(event.target)
        if (line >= 0) lines[line]!.focus({preventScroll: true})
      }, options)
      root.addEventListener("focusin", (event: FocusEvent) => {
        focused = pickAt(event.target)
        update()
      }, options)
      root.addEventListener("focusout", (event: FocusEvent) => {
        focused = root.contains(event.relatedTarget as Node | null) ? pickAt(event.relatedTarget) : null
        update()
      }, options)
      return () => events.abort()
    })

    // The map waits undrawn only while the stylesheet still holds it; a page whose
    // script came late, or a visitor who asked for less motion, gets it as it is.
    const waiting = root
      .getAnimations({subtree: true})
      .some(animation => animation instanceof CSSAnimation && animation.animationName.startsWith("lab-map-wait"))
    if (waiting && !still(root)) {
      root.dataset.labMapMotion = "entering"
      scope.methods.enter!()
    } else {
      root.dataset.labMapMotion = "rest"
    }

    const spots: Spot[] = dots.map(dot => ({
      at: [percent(dot, "--x"), percent(dot, "--y")],
      tint: dot.dataset.tint ? channels(dot.dataset.tint) : QUIET,
      reach: dot.dataset.tint ? REACH : 0,
    }))

    this.island = createCanvasIsland<LabMapRenderer>(root, {}, {
      canvasSelector: "[data-lab-map-canvas]",
      readyFlag: "labMapReady",
      motionSensitive: true,
      continuous: true,
      browserLoad: async (canvas, size, onDeviceLost) => {
        const {createLabMapRenderer} = await import("../lab_map/renderer")
        return createLabMapRenderer(canvas, size, onDeviceLost, spots)
      },
      interact(island) {
        renderer = island.renderer
        nudge = island.nudge
        // A renderer that lands, the first or one after a lost device, starts from the current pick.
        island.onReady(tell)
        return () => {
          renderer = () => undefined
          nudge = () => {}
        }
      },
    })
    this.island.mount()
  },
  disconnected(this: LabMapHook) {
    this.island?.pause()
  },
  reconnected(this: LabMapHook) {
    this.island?.resume()
  },
  destroyed(this: LabMapHook) {
    this.island?.destroy()
    this.scope?.revert()
  },
}
