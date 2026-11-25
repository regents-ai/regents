type WorkspaceSearchHook = {
  el: HTMLElement
  pushEvent(event: string, payload: object): void
  controller?: AbortController
  select?: () => void
}

export const WorkspaceSearch = {
  mounted(this: WorkspaceSearchHook) {
    const dialog = this.el.closest<HTMLDialogElement>("dialog")!
    const input = dialog.querySelector<HTMLInputElement>("#shell-search-input")!
    const list = dialog.querySelector<HTMLElement>("#shell-search-results")!
    const items = () => [...list.querySelectorAll<HTMLAnchorElement>("[data-search-result]")]
    const controller = new AbortController()
    const {signal} = controller
    this.controller = controller

    let trigger: HTMLButtonElement | null = null
    let active = 0
    let query = list.dataset.query

    const select = (index: number, scroll = false) => {
      const results = items()
      active = results.length ? (index + results.length) % results.length : 0
      const current = results[active]
      results.forEach(item => item.setAttribute("aria-selected", String(item === current)))
      if (current) {
        input.setAttribute("aria-activedescendant", current.id)
        if (scroll) current.scrollIntoView({block: "nearest"})
      } else {
        input.removeAttribute("aria-activedescendant")
      }
    }

    this.select = () => {
      const next = list.dataset.query
      select(next === query ? Math.min(active, items().length - 1) : 0)
      query = next
    }

    const open = (button: HTMLButtonElement) => {
      trigger = button
      if (!dialog.open) dialog.showModal()
      input.focus()
      input.select()
      this.pushEvent("open", {product: button.dataset.workspaceSearch})
      select(0)
    }

    document.addEventListener("click", event => {
      const target = event.target
      if (!(target instanceof Element)) return
      const button = target.closest<HTMLButtonElement>("[data-workspace-search]")
      if (!button) return
      event.preventDefault()
      open(button)
    }, {signal})

    document.addEventListener("keydown", event => {
      if (event.defaultPrevented || event.repeat) return
      const typing = event.target instanceof Element &&
        event.target.closest("input, textarea, select, [contenteditable]")
      const docsShortcut = event.key === "/" && !typing && !!document.querySelector(".docs")
      const command = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k"
      if (!command && !docsShortcut) return
      const button = document.querySelector<HTMLButtonElement>("[data-workspace-search]")
      if (!button || document.querySelector("dialog:modal") || dialog.open) return
      event.preventDefault()
      open(button)
    }, {signal})

    dialog.addEventListener("keydown", event => {
      if (event.key === "Escape") {
        event.preventDefault()
        dialog.close()
      } else if (event.target === input && ["ArrowUp", "ArrowDown"].includes(event.key)) {
        event.preventDefault()
        select(active + (event.key === "ArrowDown" ? 1 : -1), true)
      } else if (event.target === input && event.key === "Enter" && !event.isComposing) {
        if (input.value.trim() !== list.dataset.query) return
        event.preventDefault()
        items()[active]?.click()
      }
    }, {signal})

    dialog.addEventListener("click", event => {
      const target = event.target
      if (target === dialog || (target instanceof Element && target.closest("[data-search-close]"))) {
        event.preventDefault()
        dialog.close()
      }
    }, {signal})

    dialog.addEventListener("close", () => trigger?.focus(), {signal})

    // The native button can already have opened the dialog before LiveView connects.
    const button = document.querySelector<HTMLButtonElement>("[data-workspace-search]")
    if (dialog.open && button) {
      open(button)
      if (input.value.trim()) this.pushEvent("search", {q: input.value})
    }
  },

  updated(this: WorkspaceSearchHook) {
    this.select?.()
  },

  destroyed(this: WorkspaceSearchHook) {
    this.controller?.abort()
  },
}
