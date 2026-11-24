type Part = {id: string | null; title: string | null; text: string}
type Page = {
  path: string
  name: string
  product: string
  product_name: string
  section: string
  description: string
  parts: Part[]
}
type Hit = {
  href: string
  product: string
  productName: string
  title: string
  context: string
  score: number
}

const MAX_HITS = 10

type DocsHook = {el: HTMLElement; controller?: AbortController; observer?: IntersectionObserver}

/**
 * The unified all-products docs pages: cross-product search, the "On this page"
 * list that follows the reader, Ask AI popover, and the phone menu closing once
 * a page is chosen. Everything it needs is on the page already. Each docs page
 * mounts it afresh, and leaving the page takes every listener with it.
 */
export const Docs = {
  mounted(this: DocsHook) {
    this.controller = new AbortController()
    const {signal} = this.controller
    installSearch(this.el, signal)
    this.observer = installSpy(this.el)
    installAskMenu(this.el, signal)
    installMenu(this.el, signal)
  },

  destroyed(this: DocsHook) {
    this.controller?.abort()
    this.observer?.disconnect()
  },
}

function installSearch(root: HTMLElement, signal: AbortSignal) {
  const input = root.querySelector<HTMLInputElement>("#docs-search-input")
  const list = root.querySelector<HTMLUListElement>("#docs-search-results")
  const source = root.querySelector<HTMLScriptElement>("#docs-search-index")
  if (!input || !list || !source) return

  const pages = JSON.parse(source.textContent ?? "[]") as Page[]
  let hits: Hit[] = []
  let active = -1

  const close = () => {
    list.hidden = true
    input.setAttribute("aria-expanded", "false")
    input.removeAttribute("aria-activedescendant")
    active = -1
  }

  const select = (index: number) => {
    active = index
    list.querySelectorAll("li[role=option]").forEach((item, i) => {
      item.setAttribute("aria-selected", String(i === index))
      if (i === index) {
        input.setAttribute("aria-activedescendant", item.id)
        item.scrollIntoView({block: "nearest"})
      }
    })
  }

  const show = () => {
    const query = input.value.trim().toLowerCase()
    if (!query) return close()

    hits = search(pages, query)
    list.replaceChildren(...(hits.length ? hits.map(result) : [none()]))
    list.hidden = false
    input.setAttribute("aria-expanded", "true")
    select(hits.length ? 0 : -1)
  }

  input.addEventListener("input", show, {signal})
  input.addEventListener("focus", show, {signal})
  input.addEventListener("keydown", event => {
    if (event.key === "ArrowDown" && hits.length) {
      event.preventDefault()
      select((active + 1) % hits.length)
    } else if (event.key === "ArrowUp" && hits.length) {
      event.preventDefault()
      select((active - 1 + hits.length) % hits.length)
    } else if (event.key === "Enter" && hits[active]) {
      event.preventDefault()
      const anchor = list.querySelector<HTMLAnchorElement>(`#docs-search-result-${active} a`)
      close()
      anchor?.click()
    } else if (event.key === "Escape") {
      if (list.hidden) input.blur()
      close()
    }
  }, {signal})

  list.addEventListener("click", event => {
    if (event.target instanceof Element && event.target.closest("a")) close()
  }, {signal})

  root.addEventListener("focusout", event => {
    const next = event.relatedTarget
    if (!(next instanceof Node) || !input.parentElement?.contains(next)) close()
  }, {signal})

  // "/" or ⌘K / Ctrl+K moves to the search box from anywhere on the page.
  document.addEventListener("keydown", event => {
    const typing = event.target instanceof HTMLElement && event.target.closest("input, textarea, [contenteditable]")
    const slash = event.key === "/" && !typing
    const command = event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey)
    if (!slash && !command) return
    event.preventDefault()
    input.focus()
    input.select()
  }, {signal})
}

// Every word of the query has to appear; product name + page title matches
// count most, followed by section headings, then body prose. Deduplicate so one
// long page does not crowd out matching products.
function search(pages: Page[], query: string): Hit[] {
  const words = query.split(/\s+/)
  const hits: Hit[] = []

  for (const page of pages) {
    const productLower = page.product_name.toLowerCase()
    const pageLower = page.name.toLowerCase()
    let bestForPage: Hit | null = null
    let secondForPage: Hit | null = null

    for (const part of page.parts) {
      const title = (part.title ?? page.name).toLowerCase()
      const text = `${page.product_name} ${page.section} ${page.name} ${page.description} ${part.text}`.toLowerCase()
      if (!words.every(word => title.includes(word) || text.includes(word))) continue

      const score =
        words.filter(word => productLower.includes(word)).length * 4 +
        words.filter(word => pageLower.includes(word)).length * 3 +
        words.filter(word => title.includes(word)).length * 2 +
        (part.id ? 0 : 2)

      const hit: Hit = {
        href: part.id ? `${page.path}#${part.id}` : page.path,
        product: page.product,
        productName: page.product_name,
        title: part.title ? `${page.name} · ${part.title}` : page.name,
        context: excerpt(part.text || page.description, words[0]),
        score,
      }

      if (!bestForPage || hit.score > bestForPage.score) {
        secondForPage = bestForPage
        bestForPage = hit
      } else if (!secondForPage || hit.score > secondForPage.score) {
        secondForPage = hit
      }
    }

    if (bestForPage) hits.push(bestForPage)
    if (secondForPage) hits.push(secondForPage)
  }

  return hits.sort((a, b) => b.score - a.score).slice(0, MAX_HITS)
}

function excerpt(text: string, word: string): string {
  const at = text.toLowerCase().indexOf(word)
  if (at < 40) return text.slice(0, 120)
  return `…${text.slice(at - 30, at + 90)}`
}

function result(hit: Hit, index: number): HTMLLIElement {
  const item = document.createElement("li")
  item.id = `docs-search-result-${index}`
  item.setAttribute("role", "option")
  item.setAttribute("aria-selected", "false")

  const link = document.createElement("a")
  link.href = hit.href
  // LiveView follows these links inside the site, as it does the sidebar's.
  link.dataset.phxLink = "redirect"
  link.dataset.phxLinkState = "push"
  link.tabIndex = -1

  const head = document.createElement("div")
  head.className = "docs-search__head"

  const badge = document.createElement("em")
  badge.className = "docs-search__product"
  badge.dataset.docsProduct = hit.product
  badge.textContent = hit.productName

  const title = document.createElement("strong")
  title.textContent = hit.title

  head.append(badge, title)

  const context = document.createElement("span")
  context.textContent = hit.context

  link.append(head, context)
  item.append(link)
  return item
}

function none(): HTMLLIElement {
  const item = document.createElement("li")
  item.className = "docs-search__none"
  item.textContent = "No results"
  return item
}

// The heading the reader is in, marked in the "On this page" list beside the page.
// The reading band starts under the docs bar, which stays in view as the page scrolls.
function installSpy(root: HTMLElement): IntersectionObserver | undefined {
  const list = root.querySelector<HTMLElement>("[data-docs-spy]")
  if (!list) return

  const links = new Map<string, HTMLAnchorElement>()
  list.querySelectorAll<HTMLAnchorElement>("a[href^='#']").forEach(link => {
    links.set(decodeURIComponent(link.hash.slice(1)), link)
  })
  const headings = [...links.keys()]
    .map(id => document.getElementById(id))
    .filter((heading): heading is HTMLElement => heading !== null)
  if (!headings.length) return

  const band = Math.round(root.querySelector(".docs-bar")?.getBoundingClientRect().bottom ?? 120)
  const visible = new Set<Element>()
  const mark = () => {
    const current = headings.find(heading => visible.has(heading)) ?? above(headings, band)
    links.forEach((link, id) => {
      if (current && id === current.id) link.setAttribute("aria-current", "true")
      else link.removeAttribute("aria-current")
    })
  }

  const observer = new IntersectionObserver(
    entries => {
      entries.forEach(entry => (entry.isIntersecting ? visible.add(entry.target) : visible.delete(entry.target)))
      mark()
    },
    {rootMargin: `-${band}px 0px -60% 0px`},
  )
  headings.forEach(heading => observer.observe(heading))
  return observer
}

// With no heading in the reading band, the last one scrolled past.
function above(headings: HTMLElement[], band: number): HTMLElement | undefined {
  return headings.filter(heading => heading.getBoundingClientRect().top < band).at(-1)
}

// Keeps Ask AI's aria-expanded state in sync and positions the popover under its
// trigger in browsers without CSS Anchor Positioning.
function installAskMenu(root: HTMLElement, signal: AbortSignal) {
  const trigger = root.querySelector<HTMLButtonElement>("#docs-ask-trigger")
  const menu = root.querySelector<HTMLElement>("#docs-ask-menu")
  if (!trigger || !menu) return

  const anchored = typeof CSS !== "undefined" && CSS.supports("position-anchor: --docs-ask")
  const place = () => {
    if (anchored) return
    const box = trigger.getBoundingClientRect()
    menu.style.top = `${Math.round(box.bottom + 8)}px`
    menu.style.right = `${Math.max(8, Math.round(window.innerWidth - box.right))}px`
    menu.style.left = "auto"
    menu.style.bottom = "auto"
  }

  menu.addEventListener("beforetoggle", event => {
    const open = (event as ToggleEvent).newState === "open"
    trigger.setAttribute("aria-expanded", String(open))
    if (open) place()
  }, {signal})

  menu.addEventListener("click", event => {
    if (event.target instanceof Element && event.target.closest("a") && menu.matches(":popover-open")) {
      menu.hidePopover()
    }
  }, {signal})
}

// On a phone the sidebar is a panel; choosing a page or heading closes it.
function installMenu(root: HTMLElement, signal: AbortSignal) {
  const nav = root.querySelector<HTMLElement>("#docs-nav")
  const trigger = root.querySelector<HTMLButtonElement>("#docs-menu-trigger")
  if (!nav) return

  nav.addEventListener("beforetoggle", event => {
    const open = (event as ToggleEvent).newState === "open"
    trigger?.setAttribute("aria-expanded", String(open))
  }, {signal})

  nav.addEventListener("click", event => {
    if (event.target instanceof Element && event.target.closest("a") && nav.matches(":popover-open")) nav.hidePopover()
  }, {signal})
}
