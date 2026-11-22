/*!
 * Drag and inertia adapted from thiings-grid, https://github.com/charlieclark/thiings-grid
 * at a1607d3cee9e6969f5f504f0c253ee94aa50bf54. MIT License, Copyright (c) 2025 Charlie Clark.
 * See THIRD_PARTY_NOTICES.md.
 */

// Release velocity keeps the last five pointer samples, weighted 2^i toward the
// most recent, and is dropped when the finger rested before letting go.
const historySize = 5
const restBeforeRelease = 100
// Samples are px/ms; the coast integrates px per 60 Hz frame.
const velocityScale = 16
// Per-millisecond friction, applied as friction^dt.
const friction = 0.997
const minVelocity = 0.05
const focusDuration = 400
// How far a press may travel and still count as a tap.
const tapTravel: Record<string, number> = {mouse: 6, pen: 6, touch: 10}
// How far one pixel of wheel travel zooms: a mouse wheel's notch, or a
// trackpad's pinch, which the browser reports as a wheel with Control held.
const wheelZoom = 0.0015
const pinchZoom = 0.01

export type Camera = {
  /** The world point at the centre of the stage. */
  x: number
  y: number
  /** Screen pixels per world pixel; 1 for a stage that does not zoom. */
  zoom: number
  /** Moves the camera now. */
  jumpTo(x: number, y: number, zoom?: number): void
  /** Eases the camera to a point and zoom, or jumps there under reduced motion. */
  glideTo(x: number, y: number, zoom?: number): void
  /** Zooms by `factor` about a point of the screen, the stage's middle when none is given. */
  zoomBy(factor: number, clientX?: number, clientY?: number): void
  /** Where the camera is gliding to, or where it is. */
  heading(): [number, number]
  /** Moves the camera by a whole copy of the map, which the viewer never sees. */
  shift(dx: number, dy: number): void
  /** Rescales every position, glide included, when the cell size changes. */
  scale(factor: number): void
  destroy(): void
}

export type CameraOptions = {
  /** Draws the frame; runs once per animation frame while anything moves. */
  onFrame(): void
  /** A press that neither dragged nor stopped a moving map, and what it pressed. */
  onTap(clientX: number, clientY: number, target: EventTarget | null): void
  reducedMotion(): boolean
  /**
   * The zoom a stage allows. With it, the wheel and a pinch zoom about the
   * pointer; without it, the wheel pans and the zoom stays 1.
   */
  zoom?: {min: number; max: number}
}

type Drag = {
  pointerId: number
  pointerType: string
  startX: number
  startY: number
  lastX: number
  lastY: number
  lastTime: number
  travel: number
  history: [number, number][]
  stoppedTheMap: boolean
}

type Pinch = {distance: number; midX: number; midY: number}

type Glide = {
  fromX: number
  fromY: number
  fromZoom: number
  toX: number
  toY: number
  toZoom: number
  start: number
}

export function createCamera(stage: HTMLElement, options: CameraOptions): Camera {
  let drag: Drag | null = null
  let glide: Glide | null = null
  let pinch: Pinch | null = null
  // Where each finger on a stage that zooms is, for a pinch.
  const touches = new Map<number, [number, number]>()
  let vx = 0
  let vy = 0
  let frame = 0
  let lastFrame = 0
  // Set when a press ended as a drag, so the browser's click that follows is dropped.
  let dragged = false

  const coasting = () => Math.hypot(vx, vy) >= minVelocity
  const clampZoom = (zoom: number) =>
    options.zoom ? Math.min(options.zoom.max, Math.max(options.zoom.min, zoom)) : 1

  const tick = (now: number) => {
    frame = 0
    const dt = Math.min(64, Math.max(0, now - lastFrame))
    lastFrame = now
    if (glide) {
      const t = Math.min(1, (now - glide.start) / focusDuration)
      const eased = 1 - (1 - t) ** 3
      camera.x = glide.fromX + (glide.toX - glide.fromX) * eased
      camera.y = glide.fromY + (glide.toY - glide.fromY) * eased
      camera.zoom = glide.fromZoom + (glide.toZoom - glide.fromZoom) * eased
      if (t === 1) glide = null
    } else if (!drag && coasting()) {
      camera.x -= (vx * dt) / velocityScale / camera.zoom
      camera.y -= (vy * dt) / velocityScale / camera.zoom
      const decay = friction ** dt
      vx *= decay
      vy *= decay
    }
    options.onFrame()
    if (glide || (!drag && coasting())) schedule()
  }

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(tick)
  }

  const stop = () => {
    vx = 0
    vy = 0
    glide = null
  }

  // A point of the screen, from the stage's middle.
  const fromMiddle = (clientX: number, clientY: number): [number, number] => {
    const rect = stage.getBoundingClientRect()
    return [
      clientX - rect.left - stage.clientLeft - stage.clientWidth / 2,
      clientY - rect.top - stage.clientTop - stage.clientHeight / 2,
    ]
  }

  // The world point under the screen point stays under it.
  const zoomAbout = (zoom: number, px: number, py: number) => {
    const next = clampZoom(zoom)
    camera.x += px / camera.zoom - px / next
    camera.y += py / camera.zoom - py / next
    camera.zoom = next
  }

  const camera: Camera = {
    x: 0,
    y: 0,
    zoom: 1,
    jumpTo(x, y, zoom = camera.zoom) {
      stop()
      camera.x = x
      camera.y = y
      camera.zoom = clampZoom(zoom)
      schedule()
    },
    glideTo(x, y, zoom = camera.zoom) {
      if (options.reducedMotion()) return camera.jumpTo(x, y, zoom)
      vx = 0
      vy = 0
      glide = {
        fromX: camera.x,
        fromY: camera.y,
        fromZoom: camera.zoom,
        toX: x,
        toY: y,
        toZoom: clampZoom(zoom),
        start: performance.now(),
      }
      lastFrame = performance.now()
      schedule()
    },
    zoomBy(factor, clientX, clientY) {
      stop()
      const [px, py] = clientX === undefined || clientY === undefined ? [0, 0] : fromMiddle(clientX, clientY)
      zoomAbout(camera.zoom * factor, px, py)
      schedule()
    },
    heading() {
      return glide ? [glide.toX, glide.toY] : [camera.x, camera.y]
    },
    scale(factor) {
      camera.x *= factor
      camera.y *= factor
      if (glide) {
        glide.fromX *= factor
        glide.toX *= factor
        glide.fromY *= factor
        glide.toY *= factor
      }
    },
    shift(dx, dy) {
      camera.x += dx
      camera.y += dy
      if (glide) {
        glide.fromX += dx
        glide.toX += dx
        glide.fromY += dy
        glide.toY += dy
      }
    },
    destroy() {
      cancelAnimationFrame(frame)
      stage.removeEventListener("pointerdown", down)
      stage.removeEventListener("pointermove", move)
      stage.removeEventListener("pointerup", up)
      stage.removeEventListener("pointercancel", cancel)
      stage.removeEventListener("lostpointercapture", lost)
      stage.removeEventListener("wheel", wheel)
      stage.removeEventListener("click", swallowClick, true)
    },
  }

  const pinchOf = (): Pinch => {
    const [[ax, ay], [bx, by]] = [...touches.values()]
    return {distance: Math.hypot(bx - ax, by - ay) || 1, midX: (ax + bx) / 2, midY: (ay + by) / 2}
  }

  const down = (event: PointerEvent) => {
    if (options.zoom && event.pointerType === "touch") {
      touches.set(event.pointerId, [event.clientX, event.clientY])
      // A second finger turns the drag into a pinch.
      if (touches.size === 2 && drag) {
        stage.setPointerCapture(event.pointerId)
        pinch = pinchOf()
        return
      }
    }
    if (!event.isPrimary || event.button !== 0) return
    // A new press replaces a drag whose release never arrived.
    if (drag) release()
    const stoppedTheMap = coasting() || glide !== null
    dragged = false
    stop()
    stage.toggleAttribute("data-dragging", true)
    drag = {
      pointerId: event.pointerId,
      // Browsers that cannot tell report an empty type; treat it as a mouse.
      pointerType: event.pointerType || "mouse",
      startX: event.clientX,
      startY: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      lastTime: performance.now(),
      travel: 0,
      history: [],
      stoppedTheMap,
    }
  }

  const pinchMove = (event: PointerEvent) => {
    if (!pinch || !touches.has(event.pointerId)) return
    touches.set(event.pointerId, [event.clientX, event.clientY])
    const next = pinchOf()
    const [px, py] = fromMiddle(next.midX, next.midY)
    zoomAbout(camera.zoom * (next.distance / pinch.distance), px, py)
    camera.x -= (next.midX - pinch.midX) / camera.zoom
    camera.y -= (next.midY - pinch.midY) / camera.zoom
    pinch = next
    schedule()
  }

  const move = (event: PointerEvent) => {
    if (pinch) return pinchMove(event)
    if (touches.has(event.pointerId)) touches.set(event.pointerId, [event.clientX, event.clientY])
    if (event.pointerId !== drag?.pointerId) return
    // The mouse button came up where this element never heard it.
    if (drag.pointerType === "mouse" && event.buttons === 0) return void release()
    const now = performance.now()
    const dx = event.clientX - drag.lastX
    const dy = event.clientY - drag.lastY
    const elapsed = now - drag.lastTime || 1
    drag.history.push([dx / elapsed, dy / elapsed])
    if (drag.history.length > historySize) drag.history.shift()
    drag.travel = Math.max(drag.travel, Math.hypot(event.clientX - drag.startX, event.clientY - drag.startY))
    // The stage takes the pointer only once the press is a drag, so a tap
    // still reaches what it pressed.
    if (drag.travel > tapTravel[drag.pointerType] && !stage.hasPointerCapture(drag.pointerId)) {
      stage.setPointerCapture(drag.pointerId)
    }
    drag.lastX = event.clientX
    drag.lastY = event.clientY
    drag.lastTime = now
    camera.x -= dx / camera.zoom
    camera.y -= dy / camera.zoom
    schedule()
  }

  const release = () => {
    const released = drag
    drag = null
    stage.toggleAttribute("data-dragging", false)
    return released
  }

  // Lifting either finger ends a pinch, and the press with it, with no throw.
  const endPinch = () => {
    pinch = null
    touches.clear()
    if (drag) release()
    dragged = true
  }

  const up = (event: PointerEvent) => {
    if (pinch && touches.has(event.pointerId)) return endPinch()
    touches.delete(event.pointerId)
    if (event.pointerId !== drag?.pointerId) return
    const released = release()!
    if (released.travel <= tapTravel[released.pointerType] && !released.stoppedTheMap) {
      options.onTap(event.clientX, event.clientY, event.target)
      return
    }
    dragged = true
    if (options.reducedMotion() || performance.now() - released.lastTime > restBeforeRelease) return
    let weight = 0
    let sumX = 0
    let sumY = 0
    released.history.forEach(([x, y], index) => {
      weight += 2 ** index
      sumX += x * 2 ** index
      sumY += y * 2 ** index
    })
    if (!weight) return
    vx = (sumX / weight) * velocityScale
    vy = (sumY / weight) * velocityScale
    lastFrame = performance.now()
    schedule()
  }

  const cancel = (event: PointerEvent) => {
    if (pinch && touches.has(event.pointerId)) return endPinch()
    touches.delete(event.pointerId)
    if (event.pointerId === drag?.pointerId) release()
  }

  // A card that held a finger until the stage took it reports the loss too,
  // and that is not the stage's.
  const lost = (event: PointerEvent) => {
    if (event.target === stage) cancel(event)
  }

  const swallowClick = (event: MouseEvent) => {
    if (!dragged) return
    dragged = false
    event.stopPropagation()
    event.preventDefault()
  }

  // On a stage that zooms, the wheel zooms about the pointer, and so does a
  // trackpad's pinch. Elsewhere wheel and trackpad scrolling pan the map, and
  // ctrl-wheel stays the browser's zoom.
  const wheel = (event: WheelEvent) => {
    const page = event.deltaMode === WheelEvent.DOM_DELTA_PAGE
    const line = event.deltaMode === WheelEvent.DOM_DELTA_LINE ? 16 : 1
    if (options.zoom) {
      event.preventDefault()
      const travel = event.deltaY * (page ? stage.clientHeight : line)
      camera.zoomBy(Math.exp(-travel * (event.ctrlKey ? pinchZoom : wheelZoom)), event.clientX, event.clientY)
      return
    }
    if (event.ctrlKey) return
    event.preventDefault()
    stop()
    camera.x += event.deltaX * (page ? stage.clientWidth : line)
    camera.y += event.deltaY * (page ? stage.clientHeight : line)
    schedule()
  }

  stage.addEventListener("pointerdown", down)
  stage.addEventListener("pointermove", move)
  stage.addEventListener("pointerup", up)
  stage.addEventListener("pointercancel", cancel)
  // Losing capture any other way (the element hidden, capture released) ends the drag too.
  stage.addEventListener("lostpointercapture", lost)
  stage.addEventListener("wheel", wheel, {passive: false})
  stage.addEventListener("click", swallowClick, true)

  return camera
}
