type Part = {id: string | null; title: string | null; text: string}
type Page = {path: string; name: string; section: string; description: string; parts: Part[]}
type Hit = {href: string; title: string; context: string; score: number}

const MAX_HITS = 8

/**
 * The docs pages: the search box, the "On this page" list that follows the
 * reader, View as Markdown, and the phone menu closing once a page is chosen.
 * Everything it needs is on the page already, so it runs only where the docs
 * shell is.
 */
export function installDocs() {
  const root = document.querySelector<HTMLElement>("[data-docs]")
  if (!root) return

  installSearch(root)
  installSpy(root)
  installMarkdown(root)
  installMenu(root)
}

function installSearch(root: HTMLElement) {
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

  input.addEventListener("input", show)
  input.addEventListener("focus", show)
  input.addEventListener("keydown", event => {
    if (event.key === "ArrowDown" && hits.length) {
      event.preventDefault()
      select((active + 1) % hits.length)
    } else if (event.key === "ArrowUp" && hits.length) {
      event.preventDefault()
      select((active - 1 + hits.length) % hits.length)
    } else if (event.key === "Enter" && hits[active]) {
      event.preventDefault()
      window.location.assign(hits[active].href)
    } else if (event.key === "Escape") {
      if (list.hidden) input.blur()
      close()
    }
  })

  root.addEventListener("focusout", event => {
    const next = event.relatedTarget
    if (!(next instanceof Node) || !input.parentElement?.contains(next)) close()
  })

  // "/" or ⌘K / Ctrl+K moves to the search box from anywhere on the page.
  document.addEventListener("keydown", event => {
    const typing = event.target instanceof HTMLElement && event.target.closest("input, textarea, [contenteditable]")
    const slash = event.key === "/" && !typing
    const command = event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey)
    if (!slash && !command) return
    event.preventDefault()
    input.focus()
    input.select()
  })
}

// Every word of the query has to appear; a title match counts most, then the
// section heading, then the words under it.
function search(pages: Page[], query: string): Hit[] {
  const words = query.split(/\s+/)
  const hits: Hit[] = []

  for (const page of pages) {
    for (const part of page.parts) {
      const title = (part.title ?? page.name).toLowerCase()
      const text = `${page.name} ${page.description} ${part.text}`.toLowerCase()
      if (!words.every(word => title.includes(word) || text.includes(word))) continue

      const score =
        words.filter(word => page.name.toLowerCase().includes(word)).length * 3 +
        words.filter(word => title.includes(word)).length * 2 +
        (part.id ? 0 : 1)

      hits.push({
        href: part.id ? `${page.path}#${part.id}` : page.path,
        title: part.title ? `${page.name} · ${part.title}` : page.name,
        context: excerpt(part.text || page.description, words[0]),
        score,
      })
    }
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
  link.tabIndex = -1
  const title = document.createElement("strong")
  title.textContent = hit.title
  const context = document.createElement("span")
  context.textContent = hit.context
  link.append(title, context)
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
function installSpy(root: HTMLElement) {
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

  const visible = new Set<Element>()
  const mark = () => {
    const current = headings.find(heading => visible.has(heading)) ?? above(headings)
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
    {rootMargin: "-120px 0px -60% 0px"},
  )
  headings.forEach(heading => observer.observe(heading))
}

// With no heading in the reading band, the last one scrolled past.
function above(headings: HTMLElement[]): HTMLElement | undefined {
  return headings.filter(heading => heading.getBoundingClientRect().top < 120).at(-1)
}

// The page's Markdown, the same text Copy for LLM copies, in a new tab.
function installMarkdown(root: HTMLElement) {
  const button = root.querySelector<HTMLButtonElement>("[data-docs-markdown]")
  const copy = root.querySelector<HTMLButtonElement>("#docs-copy")
  if (!button || !copy) return

  button.addEventListener("click", () => {
    const blob = new Blob([copy.dataset.copyText ?? ""], {type: "text/plain;charset=utf-8"})
    const url = URL.createObjectURL(blob)
    window.open(url, "_blank", "noopener")
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
  })
}

// On a phone the sidebar is a panel; choosing a page or heading closes it.
function installMenu(root: HTMLElement) {
  const nav = root.querySelector<HTMLElement>("#docs-nav")
  if (!nav) return

  nav.addEventListener("click", event => {
    if (event.target instanceof Element && event.target.closest("a") && nav.matches(":popover-open")) nav.hidePopover()
  })
}
