/**
 * A tree canvas: an endless surface of cards, each an item of the workspace
 * or a notebook, laid out as a tree in slices (`./layout`), with the links
 * between them drawn under the cards. Dragging pans it with a throw, the
 * wheel and a pinch zoom it, and the corner says how far it is zoomed.
 *
 * Pressing or focusing a card brings it to the middle and lights its whole
 * line, everything it came from and everything made from it, and dims the
 * rest. On a screen with WebGPU the links are drawn on the GPU, with a glow
 * along the lit line; otherwise the drawn links light up instead.
 *
 * Only the cards near the view are in the page, from a pool, as the key
 * map's tiles are. One card is always kept: the one Tab reaches, which
 * follows the view. Tab and Shift+Tab step through the cards in reading
 * order and leave at either end; arrow keys pan, plus and minus zoom, and
 * Escape puts the light out.
 *
 * When the arrangement changes, the cards and their links glide to their
 * new places together, and the camera follows the lit card or opens on the
 * new arrangement; a new reading of the same arrangement moves the cards the
 * same way and leaves the camera where it was. Nothing glides under reduced
 * motion or after a key press.
 */
import {animate, type JSAnimation} from "animejs"

import {createCamera} from "../../camera"
import {createCanvasIsland} from "../../canvas_island"
import {watchTheme} from "../../../theme"
import {tone} from "../../theme_tone"
import {EASE_IN_OUT, lastInputByPointer, still} from "../motion/shared"
import {CARD, curve, HEADING, layout, localClock, type Arrange, type Every, type Layout, type TreeLink} from "./layout"
import type {GraphRenderer, Link} from "./renderer"

/** A card as the page describes it, in the element's `data-tree`. */
export type TreeCard = {
  readonly id: string
  readonly kind: string
  readonly title: string
  readonly href: string
  /** A page of this site, opened in place; otherwise an ordinary link. */
  readonly patch: boolean
  readonly tone: string
  readonly standing: string | null
  readonly author: string
  readonly created: string
  readonly changed: string
  readonly archived: boolean
  readonly folder: string | null
}

export type TreeData = {readonly cards: readonly TreeCard[]; readonly links: readonly TreeLink[]}

export type TreeStage = {update(): void; pause(): void; resume(): void; destroy(): void}

type Point = {x: number; y: number}

const ZOOM = {min: 0.1, max: 2}
// The closest a first view or a fit goes in, and how far one step zooms.
const FIT_MAX = 1
const OPEN_ZOOM = 0.8
const STEP = 1.25
const PAN = 64
const GLIDE = 400
const GRID = 24
const PAD = 32
// How far a heading sits in from its slice's edges, at full size.
const INSET = 8
// The room at the foot of the canvas the zoom takes, with a gap above it.
const FOOT = 72
const DASHED = new Set(["forks", "reviews", "contradicts"])

const svgNs = "http://www.w3.org/2000/svg"

export function createTreeStage(root: HTMLElement): TreeStage {
  const surface = root.querySelector<HTMLElement>("[data-tree-surface]")!
  const grid = root.querySelector<HTMLElement>("[data-tree-grid]")!
  const back = root.querySelector<HTMLElement>("[data-tree-back]")!
  const front = root.querySelector<HTMLElement>("[data-tree-front]")!
  const lines = root.querySelector<SVGSVGElement>("[data-tree-links]")!
  const deck = root.querySelector<HTMLElement>("[data-tree-cards]")!
  const headings = root.querySelector<HTMLElement>("[data-tree-headings]")!
  const level = root.querySelector<HTMLOutputElement>("[data-tree-zoom-level]")!
  const events = new AbortController()

  let json = ""
  let arrange: Arrange = "time"
  let every: Every = "day"
  let cards = new Map<string, TreeCard>()
  let laid: Layout | undefined
  // Where each card is drawn now: where the layout put it, or on its way there.
  let shown = new Map<string, Point>()
  let gliding: JSAnimation | undefined
  let lit: string | undefined
  let line = new Set<string>()
  // The card Tab reaches.
  let current: string | undefined
  let width = 0
  let height = 0
  let gridSize = 0
  let shownZoom = ""
  let island: {renderer(): GraphRenderer | undefined; nudge(): void} | undefined

  const placed = new Map<string, HTMLElement>()
  const spare: HTMLElement[] = []
  let paths: SVGPathElement[] = []
  let marks: {el: HTMLElement; size: readonly [number, number]}[] = []

  const instant = () => still(root) || !lastInputByPointer()

  // Pooled cards: made once, filled for whichever item they show.
  const make = () => {
    const el = document.createElement("div")
    el.className = "tree-card"
    el.innerHTML =
      '<p class="tree-card-top"><span class="tree-card-kind"></span>' +
      '<span class="tree-card-standing"><span class="workspace-graph-mark" aria-hidden="true"></span><span></span></span></p>' +
      '<a class="tree-card-title"></a><p class="tree-card-meta"></p>'
    // A drag that starts on a title pans the canvas, rather than carrying the link off.
    el.querySelector<HTMLAnchorElement>(".tree-card-title")!.draggable = false
    deck.append(el)
    return el
  }

  const fill = (el: HTMLElement, card: TreeCard) => {
    el.dataset.id = card.id
    el.dataset.tone = card.tone
    el.toggleAttribute("data-archived", card.archived)
    el.querySelector(".tree-card-kind")!.textContent = card.kind
    const badge = el.querySelector<HTMLElement>(".tree-card-standing")!
    badge.hidden = card.standing === null
    badge.lastElementChild!.textContent = card.standing ?? ""
    const link = el.querySelector<HTMLAnchorElement>(".tree-card-title")!
    link.textContent = card.title
    link.href = card.href
    if (card.patch) {
      link.dataset.phxLink = "patch"
      link.dataset.phxLinkState = "push"
    } else {
      delete link.dataset.phxLink
      delete link.dataset.phxLinkState
    }
    el.querySelector(".tree-card-meta")!.textContent = [card.author, card.folder].filter(Boolean).join(" · ")
  }

  const mark = (el: HTMLElement, id: string) => {
    el.toggleAttribute("data-lit", line.has(id))
    el.toggleAttribute("data-pressed", id === lit)
    el.querySelector<HTMLAnchorElement>(".tree-card-title")!.tabIndex = id === current ? 0 : -1
  }

  const take = (id: string) => {
    let el = placed.get(id)
    if (!el) {
      el = spare.pop() ?? make()
      el.hidden = false
      fill(el, cards.get(id)!)
      mark(el, id)
      placed.set(id, el)
      el.dataset.x = el.dataset.y = ""
    }
    const at = shown.get(id)!
    const [x, y] = [String(Math.round(at.x)), String(Math.round(at.y))]
    if (el.dataset.x !== x || el.dataset.y !== y) {
      el.style.transform = `translate3d(${x}px, ${y}px, 0)`
      el.dataset.x = x
      el.dataset.y = y
    }
    return el
  }

  const free = (id: string) => {
    const el = placed.get(id)!
    // A focused card stays until focus leaves it, while it is still there.
    if (cards.has(id) && el.contains(document.activeElement)) return
    el.hidden = true
    // A spare card is no item's until it is filled again.
    delete el.dataset.id
    placed.delete(id)
    spare.push(el)
  }

  const camera = createCamera(surface, {
    onFrame: () => render(),
    onTap: (_x, _y, target) => press(target),
    reducedMotion: () => still(root),
    zoom: ZOOM,
  })

  // The world point at the canvas's top left corner, on screen.
  const origin = () => [width / 2 - camera.x * camera.zoom, height / 2 - camera.y * camera.zoom] as const

  const inView = (at: Point, margin: number) => {
    const half = [width / 2 / camera.zoom + margin, height / 2 / camera.zoom + margin]
    return (
      at.x + CARD.width > camera.x - half[0] &&
      at.x < camera.x + half[0] &&
      at.y + CARD.height > camera.y - half[1] &&
      at.y < camera.y + half[1]
    )
  }

  function render() {
    if (!laid) return
    const [ox, oy] = origin()
    const zoom = camera.zoom
    const world = `translate3d(${ox}px, ${oy}px, 0) scale(${zoom})`
    back.style.transform = world
    front.style.transform = world

    let size = GRID * zoom
    while (size < 12) size *= 2
    if (size !== gridSize) {
      gridSize = size
      grid.style.backgroundSize = `${size}px ${size}px`
    }
    const mod = (value: number) => ((value % size) + size) % size
    grid.style.transform = `translate3d(${mod(ox) - size}px, ${mod(oy) - size}px, 0)`

    // The Tab stop follows the view, so Tab into the canvas lands on a card in sight.
    if (current && !inView(shown.get(current)!, 0) && !placed.get(current)?.contains(document.activeElement)) {
      const was = current
      const sighted = laid.order.find(id => inView(shown.get(id)!, 0))
      if (sighted) current = sighted
      if (placed.has(was)) mark(placed.get(was)!, was)
      if (placed.has(current)) mark(placed.get(current)!, current)
    }
    for (const id of [...placed.keys()]) {
      if (!shown.has(id) || (!inView(shown.get(id)!, CARD.width) && id !== current)) free(id)
    }
    for (const [id, at] of shown) {
      if (id === current || inView(at, CARD.width)) take(id)
    }

    placeHeadings(ox, oy, zoom)

    const percent = `${Math.round(zoom * 100)}%`
    if (percent !== shownZoom) level.value = shownZoom = percent

    island?.renderer()?.view(ox, oy, zoom)
    island?.nudge()
  }

  // Each slice's heading stays in sight while any of its slice is: along the
  // top for a column of time, along the left for a band. Zoomed out past the
  // room its slice keeps for it, it shrinks with the cards rather than cover
  // them.
  function placeHeadings(ox: number, oy: number, zoom: number) {
    laid!.slices.forEach((slice, index) => {
      const {el, size} = marks[index]
      const left = ox + slice.x * zoom
      const top = oy + slice.y * zoom
      const right = left + slice.width * zoom
      const bottom = top + slice.height * zoom
      const off = right < 0 || left > width || bottom < 0 || top > height
      if (el.hidden !== off) el.hidden = off
      if (off) return
      const scale = Math.min(1, (HEADING * zoom) / (size[1] + 2 * INSET))
      const [w, h, inset] = [size[0] * scale, size[1] * scale, INSET * scale]
      const x = arrange === "time" ? left + inset : Math.min(Math.max(left + inset, inset), right - w - inset)
      const y = arrange === "time" ? Math.min(Math.max(top + inset, inset), bottom - h - inset) : top + inset
      el.style.transform = `translate3d(${Math.round(x)}px, ${Math.round(y)}px, 0) scale(${scale})`
    })
  }

  // Links follow the cards wherever they are drawn.
  function drawLinks() {
    if (!laid) return
    const gpu: Link[] = []
    laid.paths.forEach((path, index) => {
      const points = curve(shown.get(path.from)!, shown.get(path.to)!)
      const [x1, y1, c1x, c1y, c2x, c2y, x2, y2] = points.map(Math.round)
      paths[index].setAttribute("d", `M${x1} ${y1}C${c1x} ${c1y} ${c2x} ${c2y} ${x2} ${y2}`)
      gpu.push({points, against: path.type === "contradicts", dashed: path.back || DASHED.has(path.type)})
    })
    island?.renderer()?.links(gpu)
    island?.nudge()
  }

  // Everything the lit card came from and everything made from it.
  const lineOf = (id: string) => {
    const reach = (step: Map<string, string[]>) => {
      const seen = new Set([id])
      const queue = [id]
      while (queue.length) {
        for (const next of step.get(queue.shift()!) ?? []) {
          if (!seen.has(next)) {
            seen.add(next)
            queue.push(next)
          }
        }
      }
      return seen
    }
    const down = new Map<string, string[]>()
    const up = new Map<string, string[]>()
    for (const path of laid!.paths) {
      down.set(path.from, [...(down.get(path.from) ?? []), path.to])
      up.set(path.to, [...(up.get(path.to) ?? []), path.from])
    }
    return new Set([...reach(up), ...reach(down)])
  }

  function relight() {
    line = lit && laid ? lineOf(lit) : new Set()
    surface.toggleAttribute("data-lighting", lit !== undefined)
    placed.forEach((el, id) => mark(el, id))
    const on = new Set<number>()
    laid?.paths.forEach((path, index) => {
      const both = line.has(path.from) && line.has(path.to)
      paths[index].toggleAttribute("data-lit", both)
      if (both) on.add(index)
    })
    island?.renderer()?.light(on)
    island?.nudge()
  }

  const centre = (id: string, glide: boolean) => {
    const at = shown.get(id)!
    const [x, y] = [at.x + CARD.width / 2, at.y + CARD.height / 2]
    if (glide) camera.glideTo(x, y)
    else camera.jumpTo(x, y)
  }

  // Lights a card's line and brings it to the middle.
  const choose = (id: string) => {
    if (lit === id && current === id) return
    lit = id
    current = id
    relight()
    centre(id, !instant())
  }

  const unlight = () => {
    if (lit === undefined) return
    lit = undefined
    relight()
  }

  const press = (target: EventTarget | null) => {
    const el = target instanceof Element ? target.closest<HTMLElement>(".tree-card") : null
    if (!el) return unlight()
    // The title is a link to the item's page, which opens as links do.
    if (target instanceof Element && target.closest("a")) return
    choose(el.dataset.id!)
    el.querySelector<HTMLAnchorElement>(".tree-card-title")!.focus({preventScroll: true})
  }

  const fit = (glide: boolean) => {
    if (!laid || !width || !height) return
    const {left, top, right, bottom} = laid.bounds
    const zoom = Math.min(FIT_MAX, (width - 2 * PAD) / (right - left), (height - 2 * PAD) / (bottom - top))
    const [x, y] = [(left + right) / 2, (top + bottom) / 2]
    if (glide) camera.glideTo(x, y, zoom)
    else camera.jumpTo(x, y, zoom)
  }

  // A first view shows everything when it fits legibly, else the card that
  // changed last: across the middle, short of any empty canvas beyond the
  // slices' sides, above the zoom, and with the top of the slices above it
  // when they both fit, so no heading stands over a card.
  const open = (glide: boolean) => {
    if (!laid || !width || !height) return
    const {left, top, right, bottom} = laid.bounds
    const fits = Math.min((width - 2 * PAD) / (right - left), (height - 2 * PAD) / (bottom - top))
    if (fits >= 0.5) return fit(glide)
    const newest = [...cards.values()].reduce((a, b) => (Date.parse(b.changed) > Date.parse(a.changed) ? b : a))
    const at = shown.get(newest.id)!
    const [across, half, pad] = [width / 2 / OPEN_ZOOM, height / 2 / OPEN_ZOOM, PAD / OPEN_ZOOM]
    const x =
      right - left + 2 * pad <= 2 * across
        ? (left + right) / 2
        : Math.min(Math.max(at.x + CARD.width / 2, left - pad + across), right + pad - across)
    const y = Math.max(top - pad + half, at.y + CARD.height + FOOT / OPEN_ZOOM - half)
    if (glide) camera.glideTo(x, y, OPEN_ZOOM)
    else camera.jumpTo(x, y, OPEN_ZOOM)
  }

  // The slices' bands, their headings and the links, for a new layout.
  const build = (next: Layout) => {
    back.replaceChildren(
      ...next.slices.map((slice, index) => {
        const band = document.createElement("div")
        band.className = "tree-canvas-band"
        band.toggleAttribute("data-odd", index % 2 === 1)
        band.style.transform = `translate3d(${slice.x}px, ${slice.y}px, 0)`
        band.style.width = `${slice.width}px`
        band.style.height = `${slice.height}px`
        return band
      }),
    )
    const made = next.slices.map(slice => {
      const heading = document.createElement("p")
      heading.className = "tree-canvas-heading"
      heading.textContent = slice.label
      return heading
    })
    headings.replaceChildren(...made)
    // Measured once: a heading keeps its size however the camera moves.
    marks = made.map(el => ({el, size: [el.offsetWidth, el.offsetHeight] as const}))
    paths = next.paths.map(path => {
      const el = document.createElementNS(svgNs, "path")
      el.dataset.type = path.type
      el.toggleAttribute("data-back", path.back)
      return el
    })
    lines.replaceChildren(...paths)
  }

  const load = () => {
    const data = JSON.parse(json) as TreeData
    const first = laid === undefined
    const rearranged = !first && (root.dataset.arrange !== arrange || root.dataset.every !== every)
    arrange = root.dataset.arrange as Arrange
    every = root.dataset.every as Every
    cards = new Map(data.cards.map(card => [card.id, card]))
    const now = Date.now()
    const next = layout(
      data.cards.map(card => ({
        id: card.id,
        created: Date.parse(card.created),
        changed: Date.parse(card.changed),
        author: card.author,
      })),
      data.links,
      arrange,
      every,
      now,
      localClock(now),
    )
    gliding?.pause()
    gliding = undefined
    for (const id of [...placed.keys()]) {
      if (!cards.has(id)) free(id)
      else fill(placed.get(id)!, cards.get(id)!)
    }
    const from = new Map([...shown].filter(([id]) => next.cards.has(id)))
    const to = new Map([...next.cards].map(([id, at]) => [id, {x: at.x, y: at.y}]))
    laid = next
    build(next)
    if (lit && !cards.has(lit)) lit = undefined
    if (!current || !cards.has(current)) current = next.order[0]

    const moving = !first && !instant() && [...from].some(([id, at]) => at.x !== to.get(id)!.x || at.y !== to.get(id)!.y)
    if (moving) {
      shown = new Map([...to].map(([id, at]) => [id, from.get(id) ?? at]))
      const state = {t: 0}
      gliding = animate(state, {
        t: 1,
        duration: GLIDE,
        ease: EASE_IN_OUT,
        onUpdate: () => {
          to.forEach((end, id) => {
            const start = from.get(id) ?? end
            shown.set(id, {x: start.x + (end.x - start.x) * state.t, y: start.y + (end.y - start.y) * state.t})
          })
          drawLinks()
          render()
        },
      })
    } else shown = to
    drawLinks()
    relight()
    if (first) open(false)
    else if (rearranged) {
      // Where the lit card is going, or a first view of the new arrangement.
      if (lit) {
        const at = to.get(lit)!
        const glide = !instant()
        if (glide) camera.glideTo(at.x + CARD.width / 2, at.y + CARD.height / 2)
        else camera.jumpTo(at.x + CARD.width / 2, at.y + CARD.height / 2)
      } else open(!instant())
    }
    render()
  }

  const keydown = (event: KeyboardEvent) => {
    if (!laid || event.altKey || event.ctrlKey || event.metaKey) return
    const card = event.target instanceof Element ? event.target.closest<HTMLElement>(".tree-card") : null
    if (event.key === "Tab" && card) {
      const index = laid.order.indexOf(card.dataset.id!)
      const next = laid.order[index + (event.shiftKey ? -1 : 1)]
      // From the first or last card, Tab leaves the canvas as it would anywhere.
      if (next === undefined) return
      event.preventDefault()
      current = next
      centre(next, false)
      render()
      placed.get(next)!.querySelector<HTMLAnchorElement>(".tree-card-title")!.focus({preventScroll: true})
      return
    }
    const pans: Record<string, [number, number]> = {
      ArrowLeft: [-PAN, 0],
      ArrowRight: [PAN, 0],
      ArrowUp: [0, -PAN],
      ArrowDown: [0, PAN],
    }
    if (pans[event.key]) {
      event.preventDefault()
      const [dx, dy] = pans[event.key]
      camera.jumpTo(camera.x + dx / camera.zoom, camera.y + dy / camera.zoom)
    } else if (event.key === "+" || event.key === "=") {
      event.preventDefault()
      camera.zoomBy(STEP)
    } else if (event.key === "-" || event.key === "_") {
      event.preventDefault()
      camera.zoomBy(1 / STEP)
    } else if (event.key === "Escape" && lit !== undefined) {
      // The light is the nearest thing Escape puts away, before any open
      // section of the page around the canvas.
      event.preventDefault()
      event.stopPropagation()
      unlight()
    }
  }

  const zoomed = (event: MouseEvent) => {
    const button = event.target instanceof Element ? event.target.closest<HTMLElement>("[data-tree-zoom]") : null
    if (!button) return
    const step = button.dataset.treeZoom
    if (step === "in") camera.zoomBy(STEP)
    else if (step === "out") camera.zoomBy(1 / STEP)
    else fit(!instant())
  }

  // Focus from the keyboard chooses the card; a press chooses it itself
  // (`press`), and one that becomes a drag pans instead.
  const focused = (event: FocusEvent) => {
    const el = event.target instanceof Element ? event.target.closest<HTMLElement>(".tree-card") : null
    if (el && !lastInputByPointer()) choose(el.dataset.id!)
  }

  const measure = () => {
    const firstSize = !width || !height
    width = surface.clientWidth
    height = surface.clientHeight
    if (firstSize && laid) open(false)
    render()
  }

  const resize = new ResizeObserver(measure)
  resize.observe(surface)
  const options = {signal: events.signal}
  root.addEventListener("keydown", keydown, options)
  root.addEventListener("click", zoomed, options)
  surface.addEventListener("focusin", focused, options)

  const controller = createCanvasIsland<GraphRenderer>(surface, {}, {
    canvasSelector: "[data-tree-canvas]",
    readyFlag: "canvasReady",
    motionSensitive: true,
    continuous: false,
    browserLoad: async (canvas, size, lost) => {
      const {createGraphRenderer} = await import("./renderer")
      return createGraphRenderer(canvas, size, lost)
    },
    interact: ({renderer, nudge, onReady}) => {
      island = {renderer, nudge}
      const retone = () => {
        renderer()?.tones(
          tone(surface, "--color-fg-muted"),
          0.55,
          tone(surface, "--ash-accent"),
          tone(surface, "--color-error"),
        )
        nudge()
      }
      onReady(() => {
        retone()
        drawLinks()
        relight()
        render()
      })
      const forget = watchTheme(retone)
      return () => {
        forget()
        island = undefined
      }
    },
  })
  controller.mount()

  const update = () => {
    const next = root.dataset.tree ?? ""
    if (next === json && root.dataset.arrange === arrange && root.dataset.every === every) return
    json = next
    load()
  }

  width = surface.clientWidth
  height = surface.clientHeight
  update()

  return {
    update,
    pause: () => controller.pause(),
    resume: () => controller.resume(),
    destroy() {
      gliding?.pause()
      events.abort()
      resize.disconnect()
      camera.destroy()
      controller.destroy()
    },
  }
}
