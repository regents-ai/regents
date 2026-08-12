// Camera architecture adapted from graphcon-deck (MIT, Yohei Nakajima).
import {animate, type AnimationParams} from "animejs"

import {
  boundsForNodes,
  clampZoom,
  fitCamera,
  focusNodeIds,
  zoomCameraAt,
  type CameraEdge,
  type CameraNode,
  type CameraPoint,
  type CameraTransform,
} from "../techtree_camera_math"

export const CAMERA_ENTRY_DURATION = 360
export const CAMERA_GLIDE_DURATION = 420
export const CAMERA_RESET_DURATION = 220
export const CAMERA_FIT_MARGIN = 48
export const CAMERA_FOCUS_MARGIN = 72
export const CAMERA_INITIAL_ZOOM_MAX = 1
export const CAMERA_FOCUS_ZOOM_MAX = 1.6

const CANONICAL_NODE_LINK_SELECTOR = 'a[data-phx-link="patch"][href]'

export type CameraAnimation = {
  cancel(): unknown
}

type CameraAnimationOptions = {
  x: number
  y: number
  zoom: number
  duration: number
  ease: "inQuart" | "outQuart"
  onUpdate(): void
  onComplete(): void
}

export type CameraDriver = {
  animate(target: CameraTransform, options: CameraAnimationOptions): CameraAnimation
}

export type CameraTransition = {
  kind: "entry" | "focus" | "reset"
  source?: "pointer" | "keyboard"
  reducedMotion?: boolean
  onSettled?: () => void
}

export type CameraController = {
  readonly active: CameraAnimation | null
  readonly state: CameraTransform
  transition(target: CameraTransform, intent: CameraTransition): CameraAnimation | null
  jump(target: CameraTransform): void
  interrupt(): void
  render(): void
  destroy(): void
}

const animeDriver: CameraDriver = {
  animate: (target, options) => animate(target, options as AnimationParams),
}

const durationFor = (kind: CameraTransition["kind"]) =>
  kind === "entry"
    ? CAMERA_ENTRY_DURATION
    : kind === "reset"
      ? CAMERA_RESET_DURATION
      : CAMERA_GLIDE_DURATION

export const createCameraController = (
  render: (camera: CameraTransform) => void,
  driver: CameraDriver = animeDriver,
): CameraController => {
  const current: CameraTransform = {x: 0, y: 0, zoom: 1}
  let active: CameraAnimation | null = null
  let generation = 0

  const cancelActive = () => {
    active?.cancel()
    active = null
  }

  const renderCurrent = () => render({...current})
  const settle = (target: CameraTransform) => {
    Object.assign(current, target)
    renderCurrent()
  }

  return {
    get active() {
      return active
    },
    get state() {
      return {...current}
    },
    transition(target, intent) {
      cancelActive()
      const intentGeneration = ++generation

      if (intent.reducedMotion || intent.source === "keyboard") {
        settle(target)
        intent.onSettled?.()
        return null
      }

      active = driver.animate(current, {
        ...target,
        duration: durationFor(intent.kind),
        ease: intent.kind === "reset" ? "inQuart" : "outQuart",
        onUpdate: renderCurrent,
        onComplete: () => {
          if (generation !== intentGeneration) return
          settle(target)
          active = null
          intent.onSettled?.()
        },
      })
      return active
    },
    jump(target) {
      cancelActive()
      generation += 1
      settle(target)
    },
    interrupt() {
      cancelActive()
      generation += 1
    },
    render: renderCurrent,
    destroy() {
      cancelActive()
      generation += 1
    },
  }
}

type FrameRenderer = {
  render(camera: CameraTransform): void
  setWorld(world: HTMLElement): void
  destroy(): void
}

const createFrameRenderer = (initialWorld: HTMLElement): FrameRenderer => {
  let world = initialWorld
  let frame: number | null = null
  let pending: CameraTransform | null = null

  const paint = () => {
    frame = null
    if (!pending) return
    const camera = pending
    pending = null
    world.style.transform = `translate3d(${camera.x}px, ${camera.y}px, 0) scale(${camera.zoom})`
  }

  return {
    render(camera) {
      pending = camera
      frame ??= window.requestAnimationFrame(paint)
    },
    setWorld(nextWorld) {
      world = nextWorld
    },
    destroy() {
      if (frame !== null) window.cancelAnimationFrame(frame)
      frame = null
      pending = null
    },
  }
}

type PointerPosition = CameraPoint & {id: number; pointerType: string}

type TechtreeCameraHookState = {
  el: HTMLElement
  cameraDriver?: CameraDriver
  camera?: CameraController
  cameraWorld?: HTMLElement
  cameraWorldBeforeUpdate?: string
  refreshCamera?: () => void
  cleanupCamera?: () => void
}

const numberFrom = (value: string | undefined) => {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : 0
}

const worldSignature = (world: HTMLElement | undefined) =>
  world ? `${world.dataset.worldWidth}:${world.dataset.worldHeight}` : ""

const viewportFor = (stage: HTMLElement) => ({
  width: stage.clientWidth,
  height: stage.clientHeight,
})

const worldBounds = (world: HTMLElement) => ({
  x: 0,
  y: 0,
  width: numberFrom(world.dataset.worldWidth),
  height: numberFrom(world.dataset.worldHeight),
})

const mapNodes = (world: HTMLElement, zoom: number): CameraNode[] =>
  [...world.querySelectorAll<HTMLElement>("[data-node-id]")].map((node) => ({
    id: node.dataset.nodeId ?? "",
    x: numberFrom(node.dataset.nodeX),
    y: numberFrom(node.dataset.nodeY),
    width: node.offsetWidth || node.getBoundingClientRect().width / zoom,
    height: node.offsetHeight || node.getBoundingClientRect().height / zoom,
  }))

const mapEdges = (world: HTMLElement): CameraEdge[] =>
  [...world.querySelectorAll<HTMLElement>("[data-edge-kind]")].map((edge) => ({
    kind: edge.dataset.edgeKind ?? "",
    fromNodeId: edge.dataset.fromNodeId ?? "",
    toNodeId: edge.dataset.toNodeId ?? "",
  }))

const localPoint = (stage: HTMLElement, clientX: number, clientY: number) => {
  const box = stage.getBoundingClientRect()
  return {x: clientX - box.left, y: clientY - box.top}
}

const midpoint = (first: PointerPosition, second: PointerPosition) => ({
  x: (first.x + second.x) / 2,
  y: (first.y + second.y) / 2,
})

const distance = (first: PointerPosition, second: PointerPosition) =>
  Math.hypot(second.x - first.x, second.y - first.y)

export const TechtreeCamera = {
  mounted(this: TechtreeCameraHookState) {
    const stage = this.el
    const world = stage.querySelector<HTMLElement>("[data-techtree-map-world]")
    if (!world) return

    const renderer = createFrameRenderer(world)
    const camera = createCameraController(renderer.render, this.cameraDriver)
    const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)")
    const pointers = new Map<number, PointerPosition>()
    const continuingLinks = new WeakSet<HTMLAnchorElement>()
    let pan:
      | {pointerId: number; start: CameraPoint; camera: CameraTransform}
      | undefined
    let pinch:
      | {
          distance: number
          center: CameraPoint
          camera: CameraTransform
        }
      | undefined
    const draggedPointers = new Set<number>()
    let activationGesture:
      | {pointerId: number; link: HTMLAnchorElement; node: HTMLElement}
      | undefined
    let recoveredActivation:
      | {pointerId: number; link: HTMLAnchorElement; node: HTMLElement}
      | undefined
    let suppressedClick:
      | {pointerId: number; node: HTMLElement | null}
      | undefined

    this.cameraWorld = world
    this.camera = camera

    const fitWholeGraph = (kind: "entry" | "reset") => {
      const currentWorld = this.cameraWorld
      if (!currentWorld) return
      camera.transition(
        fitCamera(
          viewportFor(stage),
          worldBounds(currentWorld),
          CAMERA_FIT_MARGIN,
          CAMERA_INITIAL_ZOOM_MAX,
        ),
        {
          kind,
          reducedMotion: motionPreference.matches,
        },
      )
    }

    const beginPinch = () => {
      const [first, second] = [...pointers.values()]
      if (!first || !second) return
      pinch = {
        distance: Math.max(distance(first, second), 1),
        center: midpoint(first, second),
        camera: camera.state,
      }
      pan = undefined
    }

    const beginPan = (pointer: PointerPosition) => {
      pan = {
        pointerId: pointer.id,
        start: pointer,
        camera: camera.state,
      }
      pinch = undefined
    }

    const onPointerDown = (event: PointerEvent) => {
      const joinsActiveTouchGesture =
        event.pointerType === "touch" &&
        event.isPrimary === false &&
        [...pointers.values()].some(pointer => pointer.pointerType === "touch")
      const nativePreserved =
        event.defaultPrevented ||
        (event.isPrimary === false && !joinsActiveTouchGesture) ||
        event.button !== 0 ||
        event.metaKey ||
        event.ctrlKey ||
        event.shiftKey ||
        event.altKey
      if (nativePreserved) {
        activationGesture = undefined
        recoveredActivation = undefined
        suppressedClick = undefined
        return
      }

      const target = event.target instanceof Element ? event.target : null
      const link = target?.closest<HTMLAnchorElement>(CANONICAL_NODE_LINK_SELECTOR)
      const node = target?.closest<HTMLElement>("[data-node-id]")
      recoveredActivation = undefined
      suppressedClick = undefined
      activationGesture =
        pointers.size === 0 && link && node && link.parentElement === node
          ? {pointerId: event.pointerId, link, node}
          : undefined
      camera.interrupt()
      const point = localPoint(stage, event.clientX, event.clientY)
      pointers.set(event.pointerId, {
        ...point,
        id: event.pointerId,
        pointerType: event.pointerType,
      })
      stage.setPointerCapture(event.pointerId)

      if (pointers.size > 1) {
        activationGesture = undefined
        beginPinch()
      } else {
        beginPan({...point, id: event.pointerId, pointerType: event.pointerType})
      }
    }

    const onPointerMove = (event: PointerEvent) => {
      const pointer = pointers.get(event.pointerId)
      if (!pointer) return
      const point = localPoint(stage, event.clientX, event.clientY)
      pointers.set(event.pointerId, {...pointer, ...point})

      if (pointers.size > 1) {
        if (!pinch) beginPinch()
        const [first, second] = [...pointers.values()]
        if (!pinch || !first || !second) return
        const center = midpoint(first, second)
        const zoom = clampZoom(
          pinch.camera.zoom * (distance(first, second) / pinch.distance),
        )
        const worldX = (pinch.center.x - pinch.camera.x) / pinch.camera.zoom
        const worldY = (pinch.center.y - pinch.camera.y) / pinch.camera.zoom
        for (const pointerId of pointers.keys()) draggedPointers.add(pointerId)
        event.preventDefault()
        camera.jump({
          x: center.x - worldX * zoom,
          y: center.y - worldY * zoom,
          zoom,
        })
        return
      }

      if (!pan || pan.pointerId !== event.pointerId) return
      const deltaX = point.x - pan.start.x
      const deltaY = point.y - pan.start.y
      if (!draggedPointers.has(event.pointerId) && Math.hypot(deltaX, deltaY) < 6) {
        return
      }

      draggedPointers.add(event.pointerId)
      event.preventDefault()
      stage.focus({preventScroll: true})
      camera.jump({
        x: pan.camera.x + deltaX,
        y: pan.camera.y + deltaY,
        zoom: pan.camera.zoom,
      })
    }

    const finishPointer = (event: PointerEvent, allowRecovery: boolean) => {
      if (!pointers.has(event.pointerId)) {
        if (recoveredActivation?.pointerId === event.pointerId) {
          recoveredActivation = undefined
        }
        if (suppressedClick?.pointerId === event.pointerId) suppressedClick = undefined
        return
      }

      const hitTarget =
        typeof document === "undefined"
          ? null
          : document.elementFromPoint(event.clientX, event.clientY)
      const gesture =
        activationGesture?.pointerId === event.pointerId ? activationGesture : undefined
      const terminalNode =
        hitTarget instanceof Element
          ? hitTarget.closest<HTMLElement>("[data-node-id]")
          : null
      const originMatches = terminalNode !== null && terminalNode === gesture?.node

      if (allowRecovery && gesture && originMatches && !draggedPointers.has(event.pointerId)) {
        recoveredActivation = gesture
      } else {
        recoveredActivation = undefined
      }
      suppressedClick =
        allowRecovery && draggedPointers.has(event.pointerId)
          ? {pointerId: event.pointerId, node: gesture?.node ?? terminalNode}
          : undefined
      if (gesture) activationGesture = undefined
      draggedPointers.delete(event.pointerId)
      pointers.delete(event.pointerId)
      if (stage.hasPointerCapture(event.pointerId)) {
        stage.releasePointerCapture(event.pointerId)
      }
      const [remaining] = [...pointers.values()]
      if (remaining) beginPan(remaining)
      else {
        pan = undefined
        pinch = undefined
      }
    }

    const onPointerEnd = (event: PointerEvent) => finishPointer(event, true)

    const onPointerCancel = (event: PointerEvent) => {
      finishPointer(event, false)
    }

    const onLostPointerCapture = (event: PointerEvent) => {
      if (pointers.has(event.pointerId)) finishPointer(event, false)
    }

    const onWheel = (event: WheelEvent) => {
      event.preventDefault()
      const unit =
        event.deltaMode === WheelEvent.DOM_DELTA_LINE
          ? 16
          : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
            ? stage.clientHeight
            : 1
      const zoom = camera.state.zoom * Math.exp(-event.deltaY * unit * 0.0015)
      camera.jump(
        zoomCameraAt(
          camera.state,
          localPoint(stage, event.clientX, event.clientY),
          zoom,
        ),
      )
    }

    const focusNode = (
      nodeId: string,
      source: "pointer" | "keyboard",
    ) => {
      const currentWorld = this.cameraWorld
      if (!currentWorld) return false
      const ids = focusNodeIds(nodeId, mapEdges(currentWorld))
      const bounds = boundsForNodes(mapNodes(currentWorld, camera.state.zoom), ids)
      if (!bounds) return false

      camera.transition(
        fitCamera(
          viewportFor(stage),
          bounds,
          CAMERA_FOCUS_MARGIN,
          CAMERA_FOCUS_ZOOM_MAX,
        ),
        {
          kind: "focus",
          source,
          reducedMotion: motionPreference.matches,
        },
      )
      return true
    }

    const onClick = (event: MouseEvent) => {
      const pointerId =
        "pointerId" in event && typeof event.pointerId === "number"
          ? event.pointerId
          : undefined
      const target = event.target instanceof Element ? event.target : null
      const targetNode = target?.closest<HTMLElement>("[data-node-id]") ?? null
      const suppress =
        pointerId !== undefined &&
        suppressedClick?.pointerId === pointerId &&
        (!targetNode || targetNode === suppressedClick.node)
      suppressedClick = undefined
      if (suppress) {
        recoveredActivation = undefined
        event.preventDefault()
        event.stopPropagation()
        return
      }

      const source = event.detail === 0 ? "keyboard" : "pointer"
      const targetLink =
        target?.closest<HTMLAnchorElement>(CANONICAL_NODE_LINK_SELECTOR) ?? null
      const modified =
        event.defaultPrevented ||
        event.metaKey ||
        event.ctrlKey ||
        event.shiftKey ||
        event.altKey
      const recovery = recoveredActivation
      recoveredActivation = undefined
      const recoveredLink =
        source === "pointer" &&
        !modified &&
        !targetLink &&
        pointerId !== undefined &&
        recovery?.pointerId === pointerId &&
        (!targetNode || targetNode === recovery.node)
          ? recovery.link
          : null
      const link = targetLink ?? recoveredLink
      if (modified) return

      const node = target?.closest<HTMLElement>("[data-node-id]") ??
        link?.closest<HTMLElement>("[data-node-id]")
      if (!node?.dataset.nodeId || !link) return
      if (continuingLinks.delete(link)) return

      focusNode(node.dataset.nodeId, source)
      if (!recoveredLink) return

      const currentWorld = this.cameraWorld
      const recoveryIsCurrent =
        recovery?.node.isConnected === true &&
        recoveredLink.isConnected &&
        recoveredLink.matches(CANONICAL_NODE_LINK_SELECTOR) &&
        recoveredLink.parentElement === recovery.node &&
        recoveredLink.closest<HTMLElement>("[data-node-id]") === recovery.node &&
        currentWorld?.isConnected === true &&
        stage.contains(currentWorld) &&
        currentWorld.contains(recovery.node)
      if (!recoveryIsCurrent) return

      event.preventDefault()
      event.stopPropagation()
      continuingLinks.add(recoveredLink)
      recoveredLink.click()
    }

    const onKeydown = (event: KeyboardEvent) => {
      if (event.target !== stage) return
      const panStep = 48
      const current = camera.state
      let target: CameraTransform | undefined

      if (event.key === "ArrowLeft") target = {...current, x: current.x + panStep}
      if (event.key === "ArrowRight") target = {...current, x: current.x - panStep}
      if (event.key === "ArrowUp") target = {...current, y: current.y + panStep}
      if (event.key === "ArrowDown") target = {...current, y: current.y - panStep}
      if (event.key === "+" || event.key === "=") {
        target = zoomCameraAt(
          current,
          {x: stage.clientWidth / 2, y: stage.clientHeight / 2},
          current.zoom * 1.2,
        )
      }
      if (event.key === "-" || event.key === "_") {
        target = zoomCameraAt(
          current,
          {x: stage.clientWidth / 2, y: stage.clientHeight / 2},
          current.zoom / 1.2,
        )
      }

      if (!target) return
      event.preventDefault()
      camera.transition(target, {kind: "focus", source: "keyboard"})
    }

    this.refreshCamera = () => {
      const nextWorld = stage.querySelector<HTMLElement>("[data-techtree-map-world]")
      if (!nextWorld) return
      this.cameraWorld = nextWorld
      renderer.setWorld(nextWorld)
      camera.render()
      if (this.cameraWorldBeforeUpdate !== worldSignature(nextWorld)) {
        fitWholeGraph("reset")
      }
    }

    stage.addEventListener("pointerdown", onPointerDown)
    stage.addEventListener("pointermove", onPointerMove)
    stage.addEventListener("pointerup", onPointerEnd)
    stage.addEventListener("pointercancel", onPointerCancel)
    stage.addEventListener("lostpointercapture", onLostPointerCapture)
    stage.addEventListener("wheel", onWheel, {passive: false})
    stage.addEventListener("click", onClick)
    stage.addEventListener("keydown", onKeydown)
    stage.dataset.cameraReady = "true"
    fitWholeGraph("entry")

    this.cleanupCamera = () => {
      stage.removeEventListener("pointerdown", onPointerDown)
      stage.removeEventListener("pointermove", onPointerMove)
      stage.removeEventListener("pointerup", onPointerEnd)
      stage.removeEventListener("pointercancel", onPointerCancel)
      stage.removeEventListener("lostpointercapture", onLostPointerCapture)
      stage.removeEventListener("wheel", onWheel)
      stage.removeEventListener("click", onClick)
      stage.removeEventListener("keydown", onKeydown)
      delete stage.dataset.cameraReady
      camera.destroy()
      renderer.destroy()
    }
  },
  beforeUpdate(this: TechtreeCameraHookState) {
    this.cameraWorldBeforeUpdate = worldSignature(this.cameraWorld)
  },
  updated(this: TechtreeCameraHookState) {
    this.refreshCamera?.()
    this.cameraWorldBeforeUpdate = undefined
  },
  destroyed(this: TechtreeCameraHookState) {
    this.cleanupCamera?.()
    this.camera = undefined
    this.cameraWorld = undefined
    this.refreshCamera = undefined
    this.cleanupCamera = undefined
  },
}
