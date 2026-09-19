import type {Hook} from "../hook_composition"

type CopyTextHook = Hook & {
  el: HTMLElement
  cleanup?: () => void
}

/** A button that copies its `data-copy-text` and says so for a moment. */
export const CopyText: Hook = {
  mounted(this: CopyTextHook) {
    const button = this.el
    const label = button.textContent
    let timer: number | undefined

    const restore = () => {
      button.textContent = label
      timer = undefined
    }
    const click = async () => {
      const text = button.dataset.copyText
      if (!text) return
      try {
        await navigator.clipboard.writeText(text)
      } catch {
        return
      }
      button.textContent = "Copied"
      window.clearTimeout(timer)
      timer = window.setTimeout(restore, 1500)
    }

    button.addEventListener("click", click)
    this.cleanup = () => {
      window.clearTimeout(timer)
      button.removeEventListener("click", click)
    }
  },

  destroyed(this: CopyTextHook) {
    this.cleanup?.()
  },
}
