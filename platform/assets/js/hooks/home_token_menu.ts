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
    menu.addEventListener("pointerenter", enter)
    menu.addEventListener("pointerleave", leave)
    menu.addEventListener("focusout", blur)
    document.addEventListener("pointerdown", outside)
    document.addEventListener("keydown", keydown)
    this.cleanup = () => {
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
