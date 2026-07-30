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

type PointerPosition = CameraPoint & {id: number}

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
    let dragged = false

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
      if (event.pointerType === "mouse" && event.button !== 0) return
      camera.interrupt()
      const point = localPoint(stage, event.clientX, event.clientY)
      pointers.set(event.pointerId, {...point, id: event.pointerId})
      stage.setPointerCapture(event.pointerId)
      dragged = false

      if (pointers.size > 1) beginPinch()
      else beginPan({...point, id: event.pointerId})
    }

    const onPointerMove = (event: PointerEvent) => {
      if (!pointers.has(event.pointerId)) return
      const point = localPoint(stage, event.clientX, event.clientY)
      pointers.set(event.pointerId, {...point, id: event.pointerId})

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
        dragged = true
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
      if (!dragged && Math.hypot(deltaX, deltaY) < 6) return

      dragged = true
      event.preventDefault()
      stage.focus({preventScroll: true})
      camera.jump({
        x: pan.camera.x + deltaX,
        y: pan.camera.y + deltaY,
        zoom: pan.camera.zoom,
      })
    }

    const onPointerEnd = (event: PointerEvent) => {
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
      onSettled?: () => void,
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
          onSettled,
        },
      )
      return true
    }

    const onClick = (event: MouseEvent) => {
      if (dragged) {
        event.preventDefault()
        event.stopPropagation()
        dragged = false
        return
      }

      const target = event.target instanceof Element ? event.target : null
      const node = target?.closest<HTMLElement>("[data-node-id]")
      const link = target?.closest<HTMLAnchorElement>("a[href]")
      if (!node?.dataset.nodeId || !link) return
      if (continuingLinks.delete(link)) return

      const source = event.detail === 0 ? "keyboard" : "pointer"
      if (source === "pointer" && !motionPreference.matches) {
        const focused = focusNode(node.dataset.nodeId, source, () => {
          continuingLinks.add(link)
          link.click()
        })
        if (focused) {
          event.preventDefault()
          event.stopPropagation()
        }
      } else {
        focusNode(node.dataset.nodeId, source)
      }
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
    stage.addEventListener("pointercancel", onPointerEnd)
    stage.addEventListener("wheel", onWheel, {passive: false})
    stage.addEventListener("click", onClick)
    stage.addEventListener("keydown", onKeydown)
    stage.dataset.cameraReady = "true"
    fitWholeGraph("entry")

    this.cleanupCamera = () => {
      stage.removeEventListener("pointerdown", onPointerDown)
      stage.removeEventListener("pointermove", onPointerMove)
      stage.removeEventListener("pointerup", onPointerEnd)
      stage.removeEventListener("pointercancel", onPointerEnd)
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
