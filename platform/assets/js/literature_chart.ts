/**
 * The literature chart. Each book starts on its exact scores; this spreads the
 * books so none covers another or a quadrant name, draws a line from each moved
 * book back to its scores, switches between covers and titles, and opens a
 * book's details on a press as well as on hover.
 */

type Box = {x: number; y: number; w: number; h: number}
type Book = Box & {el: HTMLElement; ax: number; ay: number}

const GAP = 4
const STEPS = 480
const SETTLE_STEPS = 160
const PULL = 0.04
const GLIDE_MS = 420
const SVG = "http://www.w3.org/2000/svg"

export function installLiteratureChart() {
  document.querySelectorAll<HTMLElement>("[data-literature-chart]").forEach(mount)
}

function mount(chart: HTMLElement) {
  const plot = chart.querySelector<HTMLElement>(".lit-plot")
  const leaders = chart.querySelector<SVGSVGElement>(".lit-leaders")
  if (!plot || !leaders) return
  const place = () => layout(chart, plot, leaders)

  chart.querySelectorAll<HTMLButtonElement>("[data-lit-mode]").forEach(button =>
    button.addEventListener("click", () => {
      if (chart.dataset.mode === button.dataset.litMode) return
      chart.dataset.mode = button.dataset.litMode
      chart.querySelectorAll("[data-lit-mode]").forEach(other =>
        other.setAttribute("aria-pressed", String(other === button)),
      )
      // The books glide to their new places; the lines return once they arrive.
      leaders.style.opacity = "0"
      place()
      window.setTimeout(() => (leaders.style.opacity = ""), GLIDE_MS)
    }),
  )

  chart.addEventListener("click", event => {
    const book = bookOf(event.target, ".lit-mark")
    if (!book) return
    const open = !book.hasAttribute("data-open")
    closeAll(chart)
    setOpen(book, open)
  })

  chart.addEventListener("focusin", event => {
    const book = bookOf(event.target, ".lit-mark")
    if (!book || !(event.target as Element).matches(":focus-visible")) return
    closeAll(chart)
    setOpen(book, true)
  })

  chart.addEventListener("focusout", event => {
    const book = bookOf(event.target, ".lit-book")
    if (book && !book.contains(event.relatedTarget as Node | null)) setOpen(book, false)
  })

  document.addEventListener("click", event => {
    if (!bookOf(event.target, ".lit-book")) closeAll(chart)
  })

  document.addEventListener("keydown", event => {
    if (event.key === "Escape") closeAll(chart)
  })

  place()
  new ResizeObserver(place).observe(plot)
  void document.fonts.ready.then(place)
  requestAnimationFrame(() => requestAnimationFrame(() => chart.classList.add("is-animated")))
}

function bookOf(target: EventTarget | null, selector: string): HTMLElement | null {
  const hit = target instanceof Element ? target.closest(selector) : null
  return hit?.closest<HTMLElement>(".lit-book") ?? null
}

function setOpen(book: HTMLElement, open: boolean) {
  book.toggleAttribute("data-open", open)
  book.querySelector(".lit-mark")?.setAttribute("aria-expanded", String(open))
}

function closeAll(chart: HTMLElement) {
  chart.querySelectorAll<HTMLElement>(".lit-book[data-open]").forEach(book => setOpen(book, false))
}

function layout(chart: HTMLElement, plot: HTMLElement, leaders: SVGSVGElement) {
  const width = plot.clientWidth
  const height = plot.clientHeight
  if (!width || !height) return
  const margin = parseFloat(getComputedStyle(plot.parentElement ?? plot).paddingLeft) || 0

  const obstacles: Box[] = Array.from(plot.querySelectorAll<HTMLElement>("[data-lit-obstacle]"), el => ({
    x: el.offsetLeft + el.offsetWidth / 2,
    y: el.offsetTop + el.offsetHeight / 2,
    w: el.offsetWidth,
    h: el.offsetHeight,
  }))

  const books: Book[] = Array.from(plot.querySelectorAll<HTMLElement>(".lit-book"), el => {
    const ax = ((Number(el.dataset.humanity) + 10) / 20) * width
    const ay = ((10 - Number(el.dataset.ai)) / 20) * height
    return {el, ax, ay, x: ax, y: ay, w: el.offsetWidth, h: el.offsetHeight}
  })

  for (let step = 0; step < STEPS; step++) {
    books.forEach((book, i) => books.slice(i + 1).forEach(other => separate(book, other)))
    books.forEach(book => {
      if (step < STEPS - SETTLE_STEPS) {
        book.x += (book.ax - book.x) * PULL
        book.y += (book.ay - book.y) * PULL
      }
      book.x = clamp(book.x, book.w / 2 - margin, width + margin - book.w / 2)
      book.y = clamp(book.y, book.h / 2 - margin, height + margin - book.h / 2)
      obstacles.forEach(obstacle => evade(book, obstacle, width, height, margin))
    })
  }

  leaders.setAttribute("viewBox", `0 0 ${width} ${height}`)
  leaders.replaceChildren()

  books.forEach(book => {
    book.el.style.left = `${((book.x - book.w / 2) / width) * 100}%`
    book.el.style.top = `${((book.y - book.h / 2) / height) * 100}%`
    book.el.dataset.sideX = book.x > width / 2 ? "left" : "right"
    book.el.dataset.sideY = book.y > height / 2 ? "up" : "down"

    // The line runs from the scores to the nearest edge of the moved book.
    const edgeX = clamp(book.ax, book.x - book.w / 2, book.x + book.w / 2)
    const edgeY = clamp(book.ay, book.y - book.h / 2, book.y + book.h / 2)
    if (Math.hypot(edgeX - book.ax, edgeY - book.ay) < 2) return
    const line = document.createElementNS(SVG, "line")
    line.setAttribute("x1", String(book.ax))
    line.setAttribute("y1", String(book.ay))
    line.setAttribute("x2", String(edgeX))
    line.setAttribute("y2", String(edgeY))
    leaders.append(line)
  })

  chart.classList.add("is-placed")
}

// Pushes two overlapping books apart along the shorter way out, half each.
// Books with the same scores part in page order.
function separate(a: Box, b: Box) {
  const overlapX = (a.w + b.w) / 2 + GAP - Math.abs(a.x - b.x)
  const overlapY = (a.h + b.h) / 2 + GAP - Math.abs(a.y - b.y)
  if (overlapX <= 0 || overlapY <= 0) return

  if (overlapX < overlapY) {
    const direction = Math.sign(a.x - b.x) || -1
    a.x += (direction * overlapX) / 2
    b.x -= (direction * overlapX) / 2
  } else {
    const direction = Math.sign(a.y - b.y) || -1
    a.y += (direction * overlapY) / 2
    b.y -= (direction * overlapY) / 2
  }
}

// Steps a book off a quadrant name by the shortest move that keeps it on the chart.
function evade(book: Box, name: Box, width: number, height: number, margin: number) {
  const reachX = (book.w + name.w) / 2 + GAP
  const reachY = (book.h + name.h) / 2 + GAP
  if (Math.abs(book.x - name.x) >= reachX || Math.abs(book.y - name.y) >= reachY) return

  const moves = [
    {x: name.x - reachX, y: book.y},
    {x: name.x + reachX, y: book.y},
    {x: book.x, y: name.y - reachY},
    {x: book.x, y: name.y + reachY},
  ].filter(
    move =>
      move.x >= book.w / 2 - margin &&
      move.x <= width + margin - book.w / 2 &&
      move.y >= book.h / 2 - margin &&
      move.y <= height + margin - book.h / 2,
  )
  const nearest = moves.sort((a, b) => distance(book, a) - distance(book, b))[0]
  if (nearest) Object.assign(book, nearest)
}

function distance(from: {x: number; y: number}, to: {x: number; y: number}) {
  return Math.hypot(to.x - from.x, to.y - from.y)
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max)
}
