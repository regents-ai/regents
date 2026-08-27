import type {Hook} from "../hook_composition"

type ResultHook = Hook & {
  el: HTMLDialogElement
  pushEvent(event: string, payload: unknown): void
  restoreFocusTo?: HTMLElement | null
  openDialog?: () => void
  closeDialog?: () => void
  releaseListeners?: () => void
}

// The server owns which result is on screen; this hook owns only whether the
// native dialog is open, and it never invents a status, a hash or a link.
export const TransactionResultModal: Hook = {
  mounted(this: ResultHook) {
    const dialog = this.el
    const currentResult = () => dialog.dataset.resultId ?? ""

    const closeDialog = () => {
      if (dialog.open) dialog.close()
    }

    const activeElement = () =>
      document.activeElement instanceof HTMLElement ? document.activeElement : null

    // The shell makes its scroller inert while the mobile menu is open, so focus
    // goes to the control that closes that menu rather than behind it.
    const fallback = () => {
      const scroller = document.querySelector<HTMLElement>("#app-shell-scroller")
      if (!scroller) return null
      return scroller.inert
        ? document.querySelector<HTMLElement>("#mobile-menu-button")
        : scroller
    }

    const restoreFocus = () => {
      const previous = this.restoreFocusTo
      this.restoreFocusTo = null
      const usable =
        previous && previous.isConnected && !previous.closest("[inert]") ? previous : fallback()
      usable?.focus()
    }

    const openDialog = () => {
      if (!currentResult()) return closeDialog()
      if (dialog.open) return
      this.restoreFocusTo ??= activeElement()
      dialog.showModal()
    }

    // Modality ends here, before the server is told anything: the id says which
    // result was on screen, so a stale close cannot pop the one queued behind it.
    const dismiss = () => {
      const id = currentResult()
      if (!id) return
      closeDialog()
      restoreFocus()
      this.pushEvent("dismiss_transaction_result", {id})
    }

    const onCancel = (event: Event) => {
      event.preventDefault()
      dismiss()
    }

    const onClick = (event: Event) => {
      const target = event.target
      if (target instanceof Element && target.closest("[data-transaction-result-close]")) dismiss()
    }

    // A press on the backdrop lands on the dialog element itself, outside its
    // own box.
    const onPointerDown = (event: PointerEvent) => {
      const box = dialog.getBoundingClientRect()
      const outside =
        event.clientX < box.left ||
        event.clientX > box.right ||
        event.clientY < box.top ||
        event.clientY > box.bottom
      if (outside) dismiss()
    }

    dialog.addEventListener("cancel", onCancel)
    dialog.addEventListener("click", onClick)
    dialog.addEventListener("pointerdown", onPointerDown)

    this.openDialog = openDialog
    this.closeDialog = closeDialog
    this.releaseListeners = () => {
      dialog.removeEventListener("cancel", onCancel)
      dialog.removeEventListener("click", onClick)
      dialog.removeEventListener("pointerdown", onPointerDown)
    }

    openDialog()
  },

  // A patch may replace the teleported dialog, which closes it natively. Closing
  // first and reopening after is that lifecycle, never a dismissal.
  beforeUpdate(this: ResultHook) {
    this.closeDialog?.()
  },

  updated(this: ResultHook) {
    this.openDialog?.()
  },

  destroyed(this: ResultHook) {
    this.closeDialog?.()
    this.releaseListeners?.()
  },
}
