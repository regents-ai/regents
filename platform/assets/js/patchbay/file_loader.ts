import type {Hook} from "../hook_composition"

const MAX_BYTES = 2 * 1024 * 1024

type FileLoaderHook = Hook & {
  el: HTMLElement
  pushEvent?: (event: string, payload: Record<string, unknown>) => void
  cleanup?: () => void
}

export const PatchbayFileLoader: Hook = {
  mounted(this: FileLoaderHook) {
    const input = this.el.querySelector<HTMLInputElement>('input[type="file"]')
    if (!input) return

    const onChange = async () => {
      const file = input.files?.[0]
      if (!file) return

      const eventName = this.el.dataset.event ?? "run_stack_check"
      const targetSelector = this.el.dataset.target

      if (file.size > MAX_BYTES) {
        this.pushEvent?.("file_load_error", {
          message: `File "${file.name}" is ${(file.size / (1024 * 1024)).toFixed(2)} MB (max 2 MB).`,
        })
        input.value = ""
        return
      }

      try {
        const text = await file.text()
        if (targetSelector) {
          const area = document.querySelector<HTMLTextAreaElement>(targetSelector)
          if (area) area.value = text
        }
        this.pushEvent?.(eventName, {manifest: text, filename: file.name})
      } catch {
        this.pushEvent?.("file_load_error", {
          message: `Could not read "${file.name}".`,
        })
      } finally {
        input.value = ""
      }
    }

    input.addEventListener("change", onChange)
    this.cleanup = () => input.removeEventListener("change", onChange)
  },

  destroyed(this: FileLoaderHook) {
    this.cleanup?.()
  },
}
