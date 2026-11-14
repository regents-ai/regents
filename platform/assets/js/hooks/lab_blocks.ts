/**
 * The Overview hero's product map (`RegentsWeb.Components.LabBlocks`).
 *
 * The server draws the whole scene; this hook brings it in, picks within it and
 * draws it again on the GPU (`lab_blocks/renderer.ts`). On arrival the crown
 * comes up, the products' blocks settle, the beams draw out from their first
 * end and the names follow, once, in about a second. A beam under the mouse,
 * focused or tapped, is picked: it and its two blocks light, everything else
 * steps back, and its sentence shows in the caption. A block under the mouse or
 * focused lights every beam it has. A pick made from the keyboard, or for a
 * visitor who asked for less motion, simply shows.
 *
 * Once the GPU picture shows, a mouse over the stage turns the view a few
 * degrees, and the names and lines on the page turn with it. A finger or a pen
 * leaves it where it is, and nothing is drawn while nothing moves.
 */
import {createScope, createTimeline, stagger, utils, type Scope} from "animejs"

import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import type {LabBlocksRenderer, Palette} from "../lab_blocks/renderer"
import {camera, channels, computed, project, type CameraJson, type Scene} from "../lab_blocks/scene"
import {watchTheme} from "../theme"
import {EASE_OUT, FAST, lastInputByPointer, play, rest, still} from "./motion/shared"

/** One line, by its place among the lines, or one place, by its name. */
type Pick = {line: number} | {place: string} | null

type LabBlocksHook = {el: HTMLElement; scope?: Scope; island?: CanvasIslandController}

/** How far a mouse turns the view: to each side, and up or down, in radians. */
const YAW = (4 * Math.PI) / 180
const PITCH = (2.5 * Math.PI) / 180

export const LabBlocks = {
  mounted(this: LabBlocksHook) {
    const root = this.el
    const scene = JSON.parse(root.dataset.scene!) as Scene
    const stage = root.querySelector<HTMLElement>(".lab-blocks__stage")!
    const lines = [...root.querySelectorAll<SVGGElement>("[data-link]")]
    const places = [...root.querySelectorAll<HTMLElement>(".lab-blocks__place")]
    const says = [...root.querySelectorAll<HTMLElement>("[data-say]")]
    const art = [...root.querySelectorAll<SVGElement>("[data-art-node], [data-art-link]")]
    // The crown steps back while anything is picked.
    const faders = [...root.querySelectorAll<Element>(".lab-blocks__name, .lab-blocks__crown"), ...art]
    const names = places.map(place => place.dataset.node!)
    const ends = lines.map(line => [line.dataset.from!, line.dataset.to!] as const)

    let hovered: Pick = null
    let focused: Pick = null
    let current: Pick = null
    let shown = ""
    let lifted = {lines: new Set<number>(), places: new Set<string>()}
    let renderer: () => LabBlocksRenderer | undefined = () => undefined
    let nudge = () => {}

    const lineOf = (target: EventTarget | null) => {
      const line = target instanceof Element ? target.closest<SVGGElement>("[data-link]") : null
      return line ? lines.indexOf(line) : -1
    }
    const pickAt = (target: EventTarget | null): Pick => {
      const line = lineOf(target)
      if (line >= 0) return {line}
      const place = target instanceof Element ? target.closest<HTMLElement>(".lab-blocks__place") : null
      return place ? {place: place.dataset.node!} : null
    }

    /** The GPU picture follows the pick. */
    const tell = () => {
      renderer()?.pick(new Set([...lifted.places].map(name => names.indexOf(name))), lifted.lines, current !== null)
      nudge()
    }

    const opacityOf = (el: Element) => Number(getComputedStyle(el).opacity)

    const show = (pick: Pick) => {
      const key = pick === null ? "" : "line" in pick ? `line ${pick.line}` : `place ${pick.place}`
      if (key === shown) return
      shown = key
      current = pick

      const touching =
        pick === null ? [] : "line" in pick ? [pick.line] : ends.flatMap(([from, to], line) =>
          from === pick.place || to === pick.place ? [line] : [])
      lifted = {
        lines: new Set(touching),
        places: new Set([...(pick && "place" in pick ? [pick.place] : []), ...touching.flatMap(line => ends[line]!)]),
      }
      const say = pick && "line" in pick ? String(pick.line) : ""

      // Each change starts from wherever the last one had got to.
      const before = new Map(faders.map(el => [el, opacityOf(el)]))
      const saidBefore = says.find(el => el.hasAttribute("data-shown"))
      rest(faders)

      if (pick === null) delete root.dataset.labBlocksPick
      else root.dataset.labBlocksPick = "line" in pick ? "line" : "place"
      lines.forEach((line, index) => line.toggleAttribute("data-picked", lifted.lines.has(index)))
      places.forEach(place => place.toggleAttribute("data-picked", lifted.places.has(place.dataset.node!)))
      for (const el of art) {
        const node = el.dataset.artNode
        const line = el.dataset.artLink
        el.toggleAttribute(
          "data-picked",
          (node !== undefined && lifted.places.has(node)) || (line !== undefined && lifted.lines.has(Number(line))),
        )
      }
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

    // The composition the stage shows, and the colours the theme gives it.
    const layout = (): keyof Scene =>
      getComputedStyle(root.querySelector('.lab-blocks__art [data-layout="wide"]')!).display === "none" ? "narrow" : "wide"
    const palette = (): Palette => {
      const style = getComputedStyle(root)
      const colour = (name: string) => computed(style.getPropertyValue(name))
      const quiet = colour("--lab-blocks-quiet")
      return {
        near: colour("--lab-blocks-near"),
        far: colour("--lab-blocks-far"),
        seam: colour("--lab-blocks-seam"),
        crownTop: colour("--lab-blocks-crown-top"),
        crownFoot: colour("--lab-blocks-crown-foot"),
        beamTone: colour("--lab-blocks-beam-tone"),
        litTone: colour("--lab-blocks-lit-tone"),
        places: places.map(place => {
          const tint = place.style.getPropertyValue("--tint")
          return tint ? channels(tint) : quiet
        }),
      }
    }

    // The names and lines on the page turn with the view. Each is placed by the
    // server for the view at rest; a turned view moves each place's block and
    // name by how far its block has moved, and lays each line again on the
    // stage showing, the other stage keeping its line at rest. A place's block
    // and name move, not the place: a moved place would stack as a whole, under
    // the GPU picture.
    const laid = {wide: "--wm", narrow: "--nm"} as const
    const restingLines = lines.map(line => ({
      wide: line.style.getPropertyValue(laid.wide),
      narrow: line.style.getPropertyValue(laid.narrow),
    }))
    const movers = places.map(place => [...place.querySelectorAll<HTMLElement>(".lab-blocks__block, .lab-blocks__name")])
    const follow = (view: CameraJson) => {
      const which = layout()
      const other = which === "wide" ? "narrow" : "wide"
      const resting = camera(scene[which].camera)
      const turned = camera(view)
      const {width, height} = stage.getBoundingClientRect()
      scene[which].blocks.forEach((middle, index) => {
        const [x0, y0] = project(resting, middle)
        const [x1, y1] = project(turned, middle)
        const moved = `${(((x1 - x0) * width) / 100).toFixed(2)}px ${(((y1 - y0) * height) / 100).toFixed(2)}px`
        for (const each of movers[index]!) each.style.translate = moved
      })
      lines.forEach((line, index) => {
        const [[x, y], [x1, y1]] = scene[which].lines[index]!.map(end => project(turned, scene[which].blocks[end]!))
        const [dx, dy] = [x1! - x!, y1! - y!]
        line.style.setProperty(laid[which], `matrix(${[dx, dy, -dy, dx, x!, y!].map(value => value.toFixed(3)).join(", ")})`)
        line.style.setProperty(laid[other], restingLines[index]![other])
      })
    }

    const scope = createScope({root})
    this.scope = scope

    scope.add(() => {
      /** Moves elements from the opacity each had to the one the stylesheet now gives it. */
      scope.add("fade", (targets: Element[], from: Map<Element, number>) => {
        play(targets, {opacity: {from: (el: unknown) => from.get(el as Element)!}, duration: FAST, ease: EASE_OUT})
      })

      /**
       * The one arrival: the crown comes up from its left, the products' blocks
       * settle from the farthest to the nearest, the beams draw out from their
       * first end, and the names follow.
       */
      scope.add("enter", () => {
        const shows = root.querySelector(`.lab-blocks__art [data-layout="${layout()}"]`)!
        const crown = [...root.querySelectorAll<SVGUseElement>(".lab-blocks__crown use")]
          .map(cell => ({cell, left: cell.getBoundingClientRect().left}))
          .sort((a, b) => a.left - b.left)
          .map(({cell}) => cell)
        // A beam's stroke is drawn on the screen, not stretched with the stage, so
        // its dash is as long as the beam is on the screen.
        const beams = [...root.querySelectorAll<SVGLineElement>("[data-art-link]")]
        const lengths = new Map(beams.map(beam => {
          const box = beam.getScreenCTM()!
          const from = beam.getPointAtLength(0).matrixTransform(box)
          const to = beam.getPointAtLength(beam.getTotalLength()).matrixTransform(box)
          return [beam, Math.hypot(to.x - from.x, to.y - from.y)]
        }))
        const length = (beam: unknown) => lengths.get(beam as SVGLineElement)!
        createTimeline({
          defaults: {ease: EASE_OUT},
          onComplete: self => {
            root.dataset.labBlocksMotion = "rest"
            utils.cleanInlineStyles(self)
          },
        })
          .add(crown, {opacity: [0, 1], scale: [0.9, 1], duration: 520, delay: stagger(18)}, 0)
          .add(shows.querySelectorAll("[data-art-node]"), {opacity: [0, 1], scale: [0.82, 1], duration: 560, delay: stagger(60)}, 140)
          .set(beams, {opacity: 1, strokeDasharray: (beam: unknown) => `${length(beam)} ${length(beam)}`, strokeDashoffset: length}, 0)
          .add(beams, {strokeDashoffset: 0, duration: 520, delay: stagger(28)}, 420)
          .add(root.querySelectorAll(".lab-blocks__name"), {opacity: [0, 1], duration: 300, delay: stagger(40)}, 640)
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

      // Only a real mouse turns the view, and only the GPU picture turns.
      stage.addEventListener("pointermove", (event: PointerEvent) => {
        if (event.pointerType !== "mouse" || root.dataset.labBlocksReady !== "true") return
        const box = stage.getBoundingClientRect()
        const x = ((event.clientX - box.left) / box.width) * 2 - 1
        const y = ((event.clientY - box.top) / box.height) * 2 - 1
        renderer()?.tilt(-x * YAW, y * PITCH)
        nudge()
      }, options)
      stage.addEventListener("pointerleave", () => {
        renderer()?.tilt(0, 0)
        nudge()
      }, options)

      const stopWatchingTheme = watchTheme(() => {
        renderer()?.paint(palette())
        nudge()
      })
      const resized = new ResizeObserver(() => {
        renderer()?.show(layout())
        nudge()
      })
      resized.observe(stage)
      return () => {
        events.abort()
        stopWatchingTheme()
        resized.disconnect()
      }
    })

    // The scene waits undrawn only while the stylesheet still holds it; a page
    // whose script came late, or a visitor who asked for less motion, gets it as it is.
    const waiting = root
      .getAnimations({subtree: true})
      .some(animation => animation instanceof CSSAnimation && animation.animationName.startsWith("lab-blocks-wait"))
    if (waiting && !still(root)) {
      root.dataset.labBlocksMotion = "entering"
      scope.methods.enter!()
    } else {
      root.dataset.labBlocksMotion = "rest"
    }

    this.island = createCanvasIsland<LabBlocksRenderer>(root, {}, {
      canvasSelector: "[data-lab-blocks-canvas]",
      readyFlag: "labBlocksReady",
      motionSensitive: true,
      // A turn eases out over more frames than the island's usual budget; the
      // renderer says itself when it has settled, and draws nothing after that.
      continuous: true,
      // The blocks' edges are the picture; they stay sharp on a dense screen.
      maxDevicePixelRatio: 2,
      browserLoad: async (canvas, size, onDeviceLost) => {
        const {createLabBlocksRenderer} = await import("../lab_blocks/renderer")
        const made = await createLabBlocksRenderer(canvas, size, onDeviceLost, scene, palette(), follow)
        made.show(layout())
        return made
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
  disconnected(this: LabBlocksHook) {
    this.island?.pause()
  },
  reconnected(this: LabBlocksHook) {
    this.island?.resume()
  },
  destroyed(this: LabBlocksHook) {
    this.island?.destroy()
    this.scope?.revert()
  },
}
