import {effect, frame, init, surface, type Effect, type Gpu, type Surface} from "vgpu"
import type {IslandRenderer} from "../canvas_island"
import {artworkWgsl} from "./shader"

export interface ArtworkRenderer extends IslandRenderer {
  point(x: number, y: number, hover: boolean, snap?: boolean): void
}

type Pool = {
  ready: Promise<{gpu: Gpu; artwork: Effect}>
  users: Set<() => void>
  gpu?: Gpu
  failed: boolean
  releaseErrors?: () => void
}
let shared: Pool | undefined

/** One effect/uniform allocation and device for this product's mounted artworks. */
function acquire(onLost: () => void) {
  if (!shared) {
    const pool: Pool = {ready: undefined!, users: new Set(), failed: false}
    shared = pool
    const fail = () => {
      if (pool.failed) return
      pool.failed = true
      if (shared === pool) shared = undefined
      // Never dispose a surface in the middle of VGPU encoding a frame.
      queueMicrotask(() => {
        for (const listener of [...pool.users]) listener()
        pool.releaseErrors?.()
        pool.gpu?.dispose()
      })
    }
    pool.ready = (async () => {
      const gpu = await init({powerPreference: "low-power", label: "product-artwork.shared"})
      pool.gpu = gpu
      pool.releaseErrors = gpu.onError(fail)
      void gpu.gpu.lost.then(fail)
      try {
        const artwork = effect(gpu, artworkWgsl, {label: "product-artwork.materials"})
        await artwork.compile({colors: [navigator.gpu.getPreferredCanvasFormat()]})
        await gpu.settled()
        if (pool.failed) throw new Error("Product artwork GPU validation failed")
        return {gpu, artwork}
      } catch (error) {
        fail()
        throw error
      }
    })()
    // Init can fail before a device exists; detach this rejected pool for a later mount.
    void pool.ready.catch(() => {
      pool.failed = true
      if (shared === pool) shared = undefined
    })
  }
  const pool = shared
  // Reserve before awaiting: a stale first loader cannot dispose a second loader's device.
  const listener = () => onLost()
  pool.users.add(listener)
  let released = false
  return {
    pool,
    release() {
      if (released) return
      released = true
      pool.users.delete(listener)
      if (pool.users.size !== 0) return
      if (shared === pool) shared = undefined
      pool.releaseErrors?.()
      pool.gpu?.dispose()
    },
  }
}

/** Resolve canonical CSS tokens through the browser's color parser, including oklch. */
function palette(root: HTMLElement) {
  const style = getComputedStyle(root)
  const sample = document.createElement("canvas")
  sample.width = sample.height = 1
  const context = sample.getContext("2d", {willReadFrequently: true})
  if (!context) throw new Error("Color sampling unavailable")
  const read = (token: string) => {
    const value = style.getPropertyValue(token).trim()
    if (!value || !CSS.supports("color", value)) throw new Error(`Missing artwork token: ${token}`)
    context.clearRect(0, 0, 1, 1)
    context.fillStyle = value
    context.fillRect(0, 0, 1, 1)
    const rgba = context.getImageData(0, 0, 1, 1).data
    return Array.from(rgba, channel => channel / 255)
  }
  return {
    charcoal: read("--palette-charcoal"),
    blue: read("--palette-powder-blue"),
    orange: read("--palette-tangerine-tango"),
    platinum: read("--palette-platinum"),
  }
}

export async function createArtworkRenderer(
  root: HTMLElement,
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
): Promise<ArtworkRenderer> {
  const source = root.dataset.artworkVariant ?? ""
  const variant = Number(source)
  const brand = variant < 3 ? "techtree" : variant < 6 ? "autolaunch" : variant < 9 ? "patchbay" : "platform"
  if (!/^[0-9]$/.test(source) || root.dataset.artworkBrand !== brand) {
    throw new Error("Product artwork requires the agreed brand/variant pair")
  }
  const colors = palette(root)
  let disposed = false
  let broken = false
  const lost = () => {
    if (disposed || broken) return
    broken = true
    root.dataset.artworkFailed = "true"
    delete root.dataset.artworkReady
    onDeviceLost()
  }
  const lease = acquire(lost)
  let canvasSurface: Surface | undefined
  try {
    const {gpu, artwork} = await lease.pool.ready
    if (lease.pool.failed) throw new Error("Product artwork device lost during initialization")
    canvasSurface = surface(gpu, canvas, {
      autoResize: false,
      alphaMode: "opaque",
      format: navigator.gpu.getPreferredCanvasFormat(),
      colorSpace: "srgb",
      size,
      label: `product-artwork.${variant}`,
    })
    const target = canvasSurface
    let point = [0, 0, 0]
    let goal = [0, 0, 0]
    const dispose = () => {
      if (disposed) return
      disposed = true
      target.dispose()
      lease.release()
    }
    return {
      point(x, y, hover, snap = false) {
        goal = [Math.max(-1, Math.min(1, x)), Math.max(-1, Math.min(1, y)), Number(hover)]
        if (snap) point = [...goal]
      },
      resize(width, height) {
        if (!disposed && !broken) target.resize([width, height])
      },
      step(snap) {
        if (disposed || broken) return false
        const moved = point.some((value, index) => Math.abs(value - goal[index]) > 0.001)
        point = point.map((value, index) => snap || !moved ? goal[index] : value + (goal[index] - value) * 0.23)
        return moved
      },
      present() {
        if (disposed || broken || lease.pool.failed) return
        try {
          artwork.set({params: {
            ...colors,
            resolution: target.size,
            pointer: point.slice(0, 2),
            variant,
            hover: point[2],
          }})
          frame(gpu, current => current.pass(target, artwork))
        } catch {
          queueMicrotask(lost)
        }
      },
      async settled() {
        await gpu.gpu.queue.onSubmittedWorkDone()
        await gpu.settled()
        if (disposed || broken || lease.pool.failed) throw new Error("Product artwork frame unavailable")
        delete root.dataset.artworkFailed
      },
      dispose,
    }
  } catch (error) {
    disposed = true
    canvasSurface?.dispose()
    lease.release()
    throw error
  }
}
