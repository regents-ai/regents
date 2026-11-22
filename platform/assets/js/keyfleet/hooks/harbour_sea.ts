import {animate, createScope, utils} from "animejs"

import {createCanvasIsland, type CanvasIslandController, type LoadRenderer} from "../canvas_island"
import type {Place} from "../swarm_city/city"
import type {Theme} from "../swarm_city/looks"
import type {CityView, SwarmCityRenderer} from "../swarm_city/renderer"
import type {Agent} from "../swarm_city/swarm"
import {showingTheme, watchTheme} from "../../theme"
import {SLOW} from "./motion/shared"

/** The browser is saving data, by its own setting or the system's. */
const savingData = () =>
  matchMedia("(prefers-reduced-data: reduce)").matches ||
  (navigator as Navigator & {connection?: {saveData: boolean}}).connection?.saveData === true

/**
 * One holder as the server wrote it, with the name of the Key its disc shows
 * under the mouse and how many Keys they hold.
 */
type CrewMember = Agent & {readonly label: string; readonly owned: number | null}

/** The agents as the server wrote them: who, the place of their last action, and their colour. */
const crewOf = (root: HTMLElement): CrewMember[] => JSON.parse(root.dataset.harbourCrew!) as CrewMember[]

/** Where a district leads: the page's name and address. */
type District = {readonly name: string; readonly path: string}

/** Where each district leads, when the city stands for one fleet. */
const districtsOf = (root: HTMLElement): Partial<Record<Place, District>> =>
  root.dataset.harbourDistricts ? (JSON.parse(root.dataset.harbourDistricts) as Record<Place, District>) : {}

const PLACES: readonly Place[] = ["castle", "forge", "inn"]

/** The whole city, seen from above its southern edge. */
const OVERVIEW = {x: 0, y: 5, z: 0.4, yaw: 0.65, pitch: 0.62, distance: 40}

/** Space kept between a disc's name and the sides of the picture, in pixels. */
const TAG_MARGIN = 4
/** How far a press may travel and still count as a press, not a drag, in pixels. */
const DRAG_SLOP = 5
/** How far one drag across the whole picture turns the city, and tips it, in radians. */
const TURN_ACROSS = Math.PI
const TIP_DOWN = 1.2
/** The camera never looks up from under the roofs or straight down on them. */
const LOWEST = 0.12
const HIGHEST = 1.15
/** How long a district takes to light, in milliseconds. */
const LIGHT = 320

const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value))

type HarbourSeaController = CanvasIslandController & {
  /** Hands the crew the server wrote last to the city on screen. */
  sync(): void
}

/**
 * The swarm city: a dense city of thin outlined towers with three downtowns,
 * and one disc for each recent agent, flying to the district of its last
 * action and circling its towers, in the page's theme.
 *
 * The city always moves, so it draws every frame while the tab is showing. A
 * visitor who asked for less motion gets one still picture, redrawn only when
 * an agent moves on, the theme changes or a drag turns it, and so does a
 * browser saving data or a device that can't give the city its frames, such
 * as a phone saving power, until the tab is shown again.
 * Without WebGPU nothing is drawn and the page's own ground shows.
 *
 * Where the city takes presses, a drag turns it, a mouse over a disc names its
 * Key and how many Keys its holder holds, a mouse over a district lights it and
 * names where it leads, pressing a disc or its name hands its holder to `open`, and pressing a district that leads
 * somewhere hands its address to `go`. Anime.js eases the districts' light and a released
 * drag; the renderer reads both when it draws.
 */
const createHarbourSeaController = (
  root: HTMLElement,
  open: (agentId: string) => void,
  go: (path: string) => void,
): HarbourSeaController => {
  const view: CityView = {...OVERVIEW, castle: 0, forge: 0, inn: 0}
  const scope = createScope({root})
  let sync = () => {}

  const browserLoad: LoadRenderer<SwarmCityRenderer> = async (canvas, size, onDeviceLost) => {
    const {createSwarmCityRenderer} = await import("../swarm_city/renderer")
    return createSwarmCityRenderer(canvas, size, onDeviceLost, view, showingTheme())
  }

  const island = createCanvasIsland<SwarmCityRenderer>(root, {}, {
    canvasSelector: "[data-harbour-canvas]",
    readyFlag: "harbourReady",
    browserLoad,
    motionSensitive: false,
    continuous: true,
    interact({renderer, nudge, onReady, onStrain}) {
      const calm = window.matchMedia("(prefers-reduced-motion: reduce)")
      const saving = savingData()
      let strained = false
      const holding = () => calm.matches || saving || strained
      const stage = root.querySelector<HTMLElement>("[data-harbour-stage]")!
      const canvas = root.querySelector<HTMLCanvasElement>("[data-harbour-canvas]")!
      const tag = root.querySelector<HTMLElement>("[data-harbour-tag]")!
      let crew = crewOf(root)
      let districts = districtsOf(root)
      let theme: Theme = showingTheme()
      let hovered: Place | null = null

      scope.add("light", () => {
        for (const place of PLACES) {
          const level = place === hovered ? 1 : 0
          if (view[place] === level) continue
          if (holding()) view[place] = level
          else animate(view, {[place]: level, duration: LIGHT, ease: "outQuad"})
        }
        if (holding()) nudge()
      })
      // A released drag carries on turning a little and comes to rest.
      scope.add("coast", (yaw: number, pitch: number) => {
        animate(view, {yaw, pitch, duration: 900, ease: "outCubic"})
      })

      const restyle = () => {
        const next = showingTheme()
        if (next === theme) return
        theme = next
        void renderer()?.setTheme(theme).then(() => nudge())
      }
      const onCalmChange = () => {
        renderer()?.setCalm(holding())
        nudge()
      }

      const pointOf = (event: MouseEvent): [number, number] => {
        const box = canvas.getBoundingClientRect()
        return [(event.clientX - box.left) / box.width, (event.clientY - box.top) / box.height]
      }
      /** Stands the name on a point of the canvas, kept inside the picture. */
      const standAt = (u: number, v: number) => {
        tag.hidden = false
        const box = root.getBoundingClientRect()
        const half = tag.offsetWidth / 2
        const x = Math.min(Math.max(u * box.width, half + TAG_MARGIN), box.width - half - TAG_MARGIN)
        const y = Math.max(v * box.height, tag.offsetHeight + TAG_MARGIN * 2)
        tag.style.translate = `${x}px ${y}px`
      }
      const hover = (place: Place | null) => {
        if (place === hovered) return
        hovered = place
        scope.methods.light!()
      }
      const hideTag = () => {
        tag.hidden = true
        delete tag.dataset.harbourDistrict
        delete tag.dataset.harbourShip
      }
      /** Names a disc's Key, with how many Keys its holder holds raised after it. */
      const nameShip = (agent: CrewMember) => {
        delete tag.dataset.harbourDistrict
        tag.dataset.harbourShip = agent.id
        tag.replaceChildren(agent.label)
        if (agent.owned) {
          const owned = document.createElement("sup")
          owned.textContent = agent.owned === 1 ? "1 Key owned" : `${agent.owned} Keys owned`
          tag.append(owned)
        }
        tag.style.setProperty("--sail", agent.color)
      }

      // A drag: where it started, the view it started from, and how fast it was turning when let go.
      let drag: {id: number; x: number; y: number; yaw: number; pitch: number; moved: boolean} | undefined
      let turning = {yaw: 0, pitch: 0, at: 0}
      let dragged = false

      const onPointerDown = (event: PointerEvent) => {
        if (!renderer() || event.button !== 0) return
        utils.remove(view, undefined, "yaw")
        utils.remove(view, undefined, "pitch")
        drag = {id: event.pointerId, x: event.clientX, y: event.clientY, yaw: view.yaw, pitch: view.pitch, moved: false}
        turning = {yaw: 0, pitch: 0, at: event.timeStamp}
        dragged = false
      }
      const onDrag = (event: PointerEvent) => {
        if (!drag || event.pointerId !== drag.id) return false
        const box = canvas.getBoundingClientRect()
        const dx = event.clientX - drag.x
        const dy = event.clientY - drag.y
        if (!drag.moved && Math.hypot(dx, dy) < DRAG_SLOP) return true
        if (!drag.moved) {
          drag.moved = true
          canvas.setPointerCapture(drag.id)
          hideTag()
          hover(null)
          stage.dataset.harbourDragging = ""
        }
        const yaw = drag.yaw - (dx / box.width) * TURN_ACROSS
        const pitch = clamp(drag.pitch + (dy / box.height) * TIP_DOWN, LOWEST, HIGHEST)
        const elapsed = Math.max(1, event.timeStamp - turning.at) / 1000
        turning = {yaw: (yaw - view.yaw) / elapsed, pitch: (pitch - view.pitch) / elapsed, at: event.timeStamp}
        view.yaw = yaw
        view.pitch = pitch
        if (holding()) nudge()
        return true
      }
      const onPointerUp = (event: PointerEvent) => {
        if (!drag || event.pointerId !== drag.id) return
        dragged = drag.moved
        drag = undefined
        delete stage.dataset.harbourDragging
        // A drag let go mid-swing carries on a little; one held still first stays put.
        if (!dragged || holding() || event.timeStamp - turning.at > 80) return
        scope.methods.coast!(view.yaw + turning.yaw * 0.25, clamp(view.pitch + turning.pitch * 0.25, LOWEST, HIGHEST))
      }
      const onPointerCancel = () => {
        drag = undefined
        delete stage.dataset.harbourDragging
      }
      const onPointerMove = (event: PointerEvent) => {
        const city = renderer()
        if (onDrag(event) || event.pointerType !== "mouse" || !city) return
        const [u, v] = pointOf(event)
        const node = city.nodeAt(u, v)
        canvas.style.cursor = node ? "pointer" : ""
        if (!node) {
          const place = city.districtAt(u, v)?.place ?? null
          const district = place && districts[place]
          canvas.style.cursor = district ? "pointer" : ""
          if (district) {
            delete tag.dataset.harbourShip
            tag.textContent = district.name
            tag.dataset.harbourDistrict = ""
            standAt(u, v)
          } else hideTag()
          return hover(place)
        }
        nameShip(crew.find(member => member.id === node.id)!)
        standAt(node.u, node.v)
        hover(null)
      }
      // A disc's name opens its card as the disc does.
      const onTagClick = () => {
        const id = tag.dataset.harbourShip
        if (!id) return
        hideTag()
        open(id)
      }
      const onPointerLeave = () => {
        if (drag?.moved) return
        hideTag()
        hover(null)
        canvas.style.cursor = ""
      }
      const onClick = (event: MouseEvent) => {
        const city = renderer()
        if (dragged || !city) {
          dragged = false
          return
        }
        const [u, v] = pointOf(event)
        const node = city.nodeAt(u, v)
        if (node) {
          hideTag()
          return open(node.id)
        }
        const place = city.districtAt(u, v)?.place
        const district = place && districts[place]
        if (!district) return
        hideTag()
        go(district.path)
      }
      // The city fades out and comes back as the still picture, rather than
      // stopping mid-flight. Given another chance, it moves on from there.
      onStrain(held => {
        strained = held
        if (!held) return onCalmChange()
        void canvas.animate({opacity: [1, 0]}, {duration: SLOW, easing: "ease-in"}).finished.then(() => {
          onCalmChange()
          canvas.animate({opacity: [0, 1]}, {duration: SLOW, easing: "ease-out"})
        })
      })
      onReady(() => {
        const city = renderer()!
        city.setCalm(holding())
        city.setAgents(crew)
        // The theme may have changed while the city was loading.
        theme = showingTheme()
        void city.setTheme(theme).then(() => nudge())
      })
      sync = () => {
        crew = crewOf(root)
        districts = districtsOf(root)
        renderer()?.setAgents(crew)
        nudge()
      }
      const forgetTheme = watchTheme(restyle)
      calm.addEventListener("change", onCalmChange)
      canvas.addEventListener("pointerdown", onPointerDown)
      stage.addEventListener("pointermove", onPointerMove)
      canvas.addEventListener("pointerup", onPointerUp)
      canvas.addEventListener("pointercancel", onPointerCancel)
      stage.addEventListener("pointerleave", onPointerLeave)
      canvas.addEventListener("click", onClick)
      tag.addEventListener("click", onTagClick)

      return () => {
        sync = () => {}
        drag = undefined
        forgetTheme()
        calm.removeEventListener("change", onCalmChange)
        hideTag()
        canvas.removeEventListener("pointerdown", onPointerDown)
        stage.removeEventListener("pointermove", onPointerMove)
        canvas.removeEventListener("pointerup", onPointerUp)
        canvas.removeEventListener("pointercancel", onPointerCancel)
        stage.removeEventListener("pointerleave", onPointerLeave)
        canvas.removeEventListener("click", onClick)
        tag.removeEventListener("click", onTagClick)
      }
    },
  })

  return {
    ...island,
    sync: () => sync(),
    destroy() {
      scope.revert()
      island.destroy()
    },
  }
}

/**
 * Whether a press lands on the open margin around a fleet's panel, where the
 * city shows through: the page that holds the panel, never the panel or
 * anything else on the page.
 */
const onMargin = (target: EventTarget | null) => {
  const panel = document.getElementById("fleet-view")
  return (
    target instanceof Element &&
    panel !== null &&
    target !== panel &&
    target.contains(panel) &&
    target.closest("#app-shell-scroller") !== null
  )
}

type HarbourSeaHook = {
  el: HTMLElement
  controller?: HarbourSeaController
  shownPath?: string
  shownPage?: string
  pressedMargin?: boolean
  onPageLoaded?: (event?: CustomEvent<{kind: string}>) => void
  onKey?: (event: KeyboardEvent) => void
  onPress?: (event: PointerEvent) => void
  onRelease?: (event: PointerEvent) => void
  onMarginClick?: (event: MouseEvent) => void
  pushEvent(event: string, payload: object): void
  liveSocket: {
    js(): {
      exec(el: HTMLElement, encodedJS: string): void
      navigate(href: string): void
      removeAttribute(el: HTMLElement, attr: string): void
    }
  }
}

/**
 * The backdrop's hook: the city behind every page of the app, which takes no
 * presses until the page is lifted away (pages/harbour.css). The city lives in
 * a sticky LiveView that never sees the page's params, so it tells the
 * backdrop which page is on screen, on mount and after every live navigation,
 * and the backdrop picks the crew for it.
 *
 * Any navigation, the bar's Chat and Workspace and the card's link to a Key
 * included, brings a lifted page back down, and a new page closes the card, so
 * nobody is left on a page they can't see. Escape brings the page back as the
 * bar's first button does, unless a Key's card is open: Escape closes that first.
 *
 * A press on the margin around a fleet's panel lifts the page as the city button
 * beside the fleet's name does. It must start and end there, so a drag that
 * selects text in the panel never lifts it, and a press that only closes an
 * open menu does nothing more.
 */
export const HarbourSea = {
  mounted(this: HarbourSeaHook) {
    this.onPageLoaded = event => {
      const kind = event?.detail.kind
      if (kind === "patch" || kind === "redirect")
        this.liveSocket.js().removeAttribute(document.body, "data-sea-lifted")
      const page = window.location.pathname + window.location.search
      if (this.shownPage !== undefined && page !== this.shownPage && document.getElementById("harbour-agent"))
        this.pushEvent("close_agent", {})
      this.shownPage = page
      const path = window.location.pathname
      if (path === this.shownPath) return
      this.shownPath = path
      this.pushEvent("show_page", {path})
    }
    window.addEventListener("phx:page-loading-stop", this.onPageLoaded as EventListener)
    this.onPageLoaded()
    this.onKey = event => {
      const back = document.getElementById("sea-return")
      if (event.key === "Escape" && back && document.body.hasAttribute("data-sea-lifted") && !document.querySelector("dialog[open]"))
        this.liveSocket.js().exec(back, back.getAttribute("phx-click")!)
    }
    window.addEventListener("keydown", this.onKey)
    this.onPress = event => {
      this.pressedMargin = onMargin(event.target) && !document.querySelector(":popover-open")
    }
    // A click lands on what holds both ends of a drag, so where the press ended
    // is read from the release itself.
    this.onRelease = event => {
      this.pressedMargin = this.pressedMargin && onMargin(event.target)
    }
    this.onMarginClick = event => {
      const lift = document.getElementById("sea-lift")
      const pressed = this.pressedMargin
      this.pressedMargin = false
      if (lift && pressed && onMargin(event.target))
        this.liveSocket.js().exec(lift, lift.getAttribute("phx-click")!)
    }
    window.addEventListener("pointerdown", this.onPress)
    window.addEventListener("pointerup", this.onRelease)
    window.addEventListener("click", this.onMarginClick)
    this.controller = createHarbourSeaController(
      this.el,
      id => this.pushEvent("show_agent", {id}),
      path => this.liveSocket.js().navigate(path),
    )
    this.controller.mount()
  },
  updated(this: HarbourSeaHook) {
    this.controller?.sync()
  },
  disconnected(this: HarbourSeaHook) {
    this.controller?.pause()
  },
  // A rejoin is a new backdrop process that knows nothing of the page yet.
  reconnected(this: HarbourSeaHook) {
    this.shownPath = undefined
    this.onPageLoaded?.()
    this.controller?.resume()
  },
  destroyed(this: HarbourSeaHook) {
    window.removeEventListener("phx:page-loading-stop", this.onPageLoaded as EventListener)
    window.removeEventListener("keydown", this.onKey!)
    window.removeEventListener("pointerdown", this.onPress!)
    window.removeEventListener("pointerup", this.onRelease!)
    window.removeEventListener("click", this.onMarginClick!)
    this.controller?.destroy()
    this.controller = undefined
  },
}
