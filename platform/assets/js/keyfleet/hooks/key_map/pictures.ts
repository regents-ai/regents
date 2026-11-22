/**
 * Loads the map's card close-ups a few at a time, nearest the point the viewer
 * is heading for first: where the map is gliding to, or where it rests. A
 * picture asked for again elsewhere, or no longer wanted, gives up its place, so
 * a fast pan never leaves a queue of pictures nobody will see.
 *
 * Each picture is an image element and the world point it is drawn at. Setting
 * its `src` starts the load; removing it stops one under way. A picture already
 * loading for another element waits for it, then comes from the browser's cache.
 */
export type Pictures = {
  /** Loads `address` into `img`, drawn at world point (x, y), in its turn. */
  want(img: HTMLImageElement, address: string, x: number, y: number): void
  /** Forgets `img`'s picture, waiting or loading. */
  drop(img: HTMLImageElement): void
  /** Loads pictures the viewer is about to reach, each at its world point. */
  ahead(pictures: [string, number, number][]): void
  /** The world point the viewer is heading for. */
  focus(x: number, y: number): void
  /** Moves every world point by a whole copy of the map. */
  shift(dx: number, dy: number): void
  destroy(): void
}

type Wanted = {img: HTMLImageElement; address: string; x: number; y: number}

// Enough to keep the map filling, few enough that a card server never sees a burst.
const inFlight = 8

export function createPictures(): Pictures {
  const waiting = new Map<HTMLImageElement, Wanted>()
  // The address each loading element is fetching.
  const loading = new Map<HTMLImageElement, string>()
  // The pictures loaded ahead, kept until they finish so the browser keeps them.
  const preloads = new Set<HTMLImageElement>()
  let fx = 0
  let fy = 0
  // Set once the map is gone, so an answer arriving after it starts nothing.
  let destroyed = false

  const finish = (img: HTMLImageElement) => {
    if (!loading.delete(img)) return
    preloads.delete(img)
    pump()
  }

  const pump = () => {
    while (loading.size < inFlight && waiting.size) {
      const fetching = new Set(loading.values())
      let next: Wanted | undefined
      let nearest = Infinity
      for (const wanted of waiting.values()) {
        const distance = Math.hypot(wanted.x - fx, wanted.y - fy)
        if (distance < nearest && !fetching.has(wanted.address)) [next, nearest] = [wanted, distance]
      }
      if (!next) return
      waiting.delete(next.img)
      loading.set(next.img, next.address)
      next.img.src = next.address
    }
  }

  // Every image is listened to once, the first time it is wanted.
  const heard = new WeakSet<HTMLImageElement>()
  const listen = (img: HTMLImageElement) => {
    if (heard.has(img)) return
    heard.add(img)
    img.addEventListener("load", () => finish(img))
    img.addEventListener("error", () => finish(img))
  }

  const pictures: Pictures = {
    want(img, address, x, y) {
      if (destroyed) return
      pictures.drop(img)
      listen(img)
      waiting.set(img, {img, address, x, y})
      pump()
    },

    drop(img) {
      waiting.delete(img)
      if (loading.delete(img)) {
        img.removeAttribute("src")
        pump()
      }
    },

    // A new destination replaces the last one's pictures not yet started.
    ahead(list) {
      if (destroyed) return
      for (const img of preloads) {
        if (waiting.delete(img)) preloads.delete(img)
      }
      for (const [address, x, y] of list) {
        const img = new Image()
        img.decoding = "async"
        listen(img)
        preloads.add(img)
        waiting.set(img, {img, address, x, y})
      }
      pump()
    },

    focus(x, y) {
      fx = x
      fy = y
    },

    shift(dx, dy) {
      fx += dx
      fy += dy
      for (const wanted of waiting.values()) {
        wanted.x += dx
        wanted.y += dy
      }
    },

    destroy() {
      destroyed = true
      waiting.clear()
      loading.forEach((_, img) => img.removeAttribute("src"))
      loading.clear()
      preloads.clear()
    },
  }

  return pictures
}
