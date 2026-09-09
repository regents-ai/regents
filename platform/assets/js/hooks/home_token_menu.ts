import type {Hook} from "../hook_composition"

type TokenMenuHook = Hook & {el: HTMLDetailsElement; cleanup?: () => void}

// Native details supplies click/tap and keyboard disclosure without LiveView trips.
export const HomeTokenMenu: Hook = {
  mounted(this: TokenMenuHook) {
    const menu = this.el
    const summary = menu.querySelector("summary")
    const close = () => { menu.open = false }
    const enter = (event: PointerEvent) => {
      if (event.pointerType === "mouse") menu.open = true
    }
    const leave = () => {
      if (!menu.contains(document.activeElement)) close()
    }
    const blur = (event: FocusEvent) => {
      if (!(event.relatedTarget instanceof Node) || !menu.contains(event.relatedTarget)) close()
    }
    const outside = (event: PointerEvent) => {
      if (event.target instanceof Node && !menu.contains(event.target)) close()
    }
    const keydown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && menu.open) {
        event.preventDefault()
        close()
        summary?.focus()
      }
    }
    const copyReset = installTokenCopy(menu)
    menu.addEventListener("pointerenter", enter)
    menu.addEventListener("pointerleave", leave)
    menu.addEventListener("focusout", blur)
    document.addEventListener("pointerdown", outside)
    document.addEventListener("keydown", keydown)
    this.cleanup = () => {
      copyReset()
      menu.removeEventListener("pointerenter", enter)
      menu.removeEventListener("pointerleave", leave)
      menu.removeEventListener("focusout", blur)
      document.removeEventListener("pointerdown", outside)
      document.removeEventListener("keydown", keydown)
    }
  },
  destroyed(this: TokenMenuHook) {
    this.cleanup?.()
  },
}

// Copying the contract address off the $REGENT heading: green check and a
// fading "CA copied" toast for three seconds, then back to the copy glyph.
function installTokenCopy(root: ParentNode): () => void {
  const button = root.querySelector<HTMLButtonElement>("[data-token-copy]")
  if (!button) return () => {}
  const copyGlyph = button.querySelector<HTMLElement>("[data-copy-glyph]")
  const checkGlyph = button.querySelector<HTMLElement>("[data-check-glyph]")
  const toast = button.querySelector<HTMLElement>("[data-copy-toast]")
  let timer: number | undefined

  const restore = () => {
    button.classList.remove("is-copied")
    if (copyGlyph) copyGlyph.hidden = false
    if (checkGlyph) checkGlyph.hidden = true
    if (toast) toast.textContent = ""
  }

  const click = async () => {
    const address = button.dataset.copyAddress
    if (!address) return
    try {
      await navigator.clipboard.writeText(address)
    } catch {
      return
    }
    if (copyGlyph) copyGlyph.hidden = true
    if (checkGlyph) checkGlyph.hidden = false
    if (toast) toast.textContent = "CA copied"
    button.classList.add("is-copied")
    window.clearTimeout(timer)
    timer = window.setTimeout(restore, 3000)
  }

  button.addEventListener("click", click)
  return () => {
    window.clearTimeout(timer)
    button.removeEventListener("click", click)
  }
}
