/**
 * Draws the homepage's hex field with WebGPU through vgpu, behind the hero,
 * only when something changed. There is no clock and no idle loop. A pointer or a preview sets a target, the picture eases toward it
 * for a few frames and stops; a wake or a ring fades within the island's
 * easing frames, so the field is always still again shortly after the last
 * touch. Loaded only once a field is really going to be shown.
 *
 * The tiles nearest a mouse stand raised, each as high as the page's own
 * animation says, one frame at a time.
 *
 * Each value reaches the shader when it changes: the size when the canvas is
 * resized, the colours when the theme changes, the pointer on each frame.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"

import {EASING_FRAME_LIMIT, type IslandRenderer} from "../canvas_island"
import {fieldWgsl, MARKS, TILES} from "./shader"

export type Rgb = readonly [number, number, number]
type Vec4 = [number, number, number, number]

/** How far one frame closes the gap to a target, and when the gap counts as closed. */
const EASE = 0.2
const CLOSE = 0.002

/**
 * How many frames a wake or a ring lasts, and how many tiles a ring spreads
 * each frame. A mark is gone before the island's easing frames run out, so
 * the frame that snaps home has nothing left to remove.
 */
const LIFE = EASING_FRAME_LIMIT - 2
const RING_SPREAD = 0.3

/** A wake or a ring laid at x, y (0..1 across the canvas), `age` frames ago. */
type Mark = {x: number; y: number; age: number; ring: boolean}
const unmarked = [0, 0, 0, -1] as const

/** Full strength at first, easing out to nothing at the end of its life. */
const strength = (m: Mark) => {
  const t = Math.min(1, m.age / LIFE)
  return (m.ring ? 0.9 : 1) * (1 - t * t * (3 - 2 * t))
}

/** One eased value: where it is, and where it is going. */
const eased = (value = 0) => ({value, target: value})
type Eased = ReturnType<typeof eased>

/** Moves every value one frame toward its target, or onto it. True when anything moved. */
const advance = (values: Eased[], snap: boolean) => {
  let moved = false
  for (const v of values) {
    const gap = v.target - v.value
    if (gap === 0) continue
    v.value = snap || Math.abs(gap) < CLOSE ? v.target : v.value + gap * EASE
    moved = true
  }
  return moved
}

/** A raised tile: its centre in CSS pixels across the canvas, and how high it stands, 0..1 of the most. */
export type Tile = {x: number; y: number; h: number}
const unraised = [0, 0, 0, 0] as const

export type FieldRenderer = IslandRenderer & {
  /**
   * The lines' colour, the preview's light, the page's ground, the deep tone
   * the raised tiles turn, and how dark their shadow is, from the page's theme.
   */
  tones(line: Rgb, light: Rgb, ground: Rgb, deep: Rgb, shadow: number): void
  /** The fade toward the edges: centre and radii 0..1 across the canvas, where it starts and ends along the radius. */
  fade(x: number, y: number, width: number, height: number, from: number, to: number): void
  /** The raised tiles, and how high a tile stands at most, in CSS pixels. */
  stand(tiles: readonly Tile[], most: number): void
  /** Where the pointer stands, 0..1 across the canvas. */
  point(x: number, y: number): void
  /** The pointer left. */
  rest(): void
  /** Where the Key sits, 0..1 across the canvas, and how far its light reaches in CSS pixels. */
  key(x: number, y: number, reach: number): void
  /** Whether the Key is being previewed. */
  lit(on: boolean): void
  /** A pointer or a finger passed over x, y (0..1 across the canvas). */
  wake(x: number, y: number): void
  /** A press at x, y sends a ring out across the tiles. */
  ring(x: number, y: number): void
}

/** `cell` is the distance between neighbouring tiles in CSS pixels. */
export async function createFieldRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  cell: number,
): Promise<FieldRenderer> {
  // Device pixels per CSS pixel, so the tiles and the Key's reach keep their
  // CSS size at any screen density.
  let ratio = 1
  let key: Vec4 = [0.5, 0.5, 0, 0]
  const placed = (): Vec4 => [key[0], key[1], key[2] * ratio, 0]
  let raised: readonly Tile[] = []
  let lift = 0
  let shadow = 0
  const lifting = (): Vec4 => [lift * ratio, shadow, 0, 0]
  const standing = () =>
    Array.from({length: TILES}, (_, i) => {
      const tile = raised[i]
      return tile ? [tile.x * ratio, tile.y * ratio, tile.h, 0] : unraised
    })

  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a field still on
  // screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "premultiplied", label: "home-field"})
    stage.resize([size[0], size[1]])
    const shader = effect(gpu, prepareShader(fieldWgsl, "home-field.wgsl"), {
      label: "home-field.pass",
      set: {
        params: {
          size: [size[0], size[1], cell, 0],
          line: [1, 1, 1, 1],
          light: [1, 1, 1, 1],
          pointer: [0.5, 0.5, 0, 0],
          key: placed(),
          fade: [0.5, 0.5, 1, 1],
          stops: [1, 1, 0, 0],
          ground: [0, 0, 0, 1],
          deep: [0, 0, 0, 1],
          lift: lifting(),
          marks: Array.from({length: MARKS}, () => unmarked),
          tiles: standing(),
        },
      },
    })
    await shader.compile({colors: [stage.format]})
    const unsubscribe = stage.onResize(({width, height}) => {
      ratio = width / Math.max(1, canvas.clientWidth)
      shader.set({params: {size: [width, height, cell * ratio, 0], key: placed(), lift: lifting(), tiles: standing()}})
    })

    const x = eased(0.5)
    const y = eased(0.5)
    const presence = eased()
    const glow = eased()
    // The newest marks win once the field holds as many as it can draw.
    let marks: Mark[] = []
    const mark = (next: Mark) => {
      marks.push(next)
      if (marks.length > MARKS) marks.shift()
    }
    const age = () => {
      for (const m of marks) m.age += 1
      marks = marks.filter(m => m.age < LIFE)
    }
    // The pointer's first position is taken as it is, so the light appears
    // where the pointer is instead of sliding in from the last place it left.
    const jump = (value: Eased, to: number) => {
      value.target = to
      if (presence.value === 0) value.value = to
    }

    return {
      tones(line, light, ground, deep, dark) {
        shadow = dark
        shader.set({params: {line: [...line, 1], light: [...light, 1], ground: [...ground, 1], deep: [...deep, 1], lift: lifting()}})
      },
      fade(fx, fy, width, height, from, to) {
        shader.set({params: {fade: [fx, fy, width, height], stops: [from, to, 0, 0]}})
      },
      stand(tiles, most) {
        raised = tiles
        lift = most
        shader.set({params: {lift: lifting(), tiles: standing()}})
      },
      point(px, py) {
        jump(x, px)
        jump(y, py)
        presence.target = 1
      },
      rest() {
        presence.target = 0
      },
      key(kx, ky, reach) {
        key = [kx, ky, reach, 0]
        shader.set({params: {key: placed()}})
      },
      lit(on) {
        glow.target = on ? 1 : 0
      },
      wake(mx, my) {
        mark({x: mx, y: my, age: 0, ring: false})
      },
      ring(mx, my) {
        mark({x: mx, y: my, age: 0, ring: true})
      },
      resize(width, height) {
        stage.resize([width, height])
      },
      step(snap) {
        const marked = marks.length > 0
        if (snap) marks = []
        else age()
        return advance([x, y, presence, glow], snap) || marked
      },
      present() {
        shader.set({
          params: {
            pointer: [x.value, y.value, presence.value, glow.value],
            marks: Array.from({length: MARKS}, (_, i) => {
              const m = marks[i]
              return m ? [m.x, m.y, strength(m), m.ring ? m.age * RING_SPREAD : -1] : unmarked
            }),
          },
        })
        frame(gpu, current => current.pass(stage, shader))
      },
      async settled() {
        await gpu.gpu.queue.onSubmittedWorkDone()
        await gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        unsubscribe()
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    // Set first, so the loss that disposing the device reports is not taken
    // for one to recover from.
    disposed = true
    gpu.dispose()
    throw error
  }
}
