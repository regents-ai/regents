import {expect, it, vi} from "vitest"

import {ModalDialog} from "../js/hooks/modal_dialog"

// Vitest here runs without a document, so the dialog is the small surface the
// hook touches: open state, its data attributes, showModal and the close event.
function mountDialog(dismissEvent?: string) {
  const listeners = new Map<string, () => void>()
  const dialog = {
    open: false,
    dataset: dismissEvent ? {dismissEvent} : {},
    showModal: vi.fn(() => {
      dialog.open = true
    }),
    addEventListener: vi.fn((name: string, listener: () => void) => listeners.set(name, listener)),
  }
  const pushEvent = vi.fn()
  ModalDialog.mounted!.call({el: dialog, pushEvent})
  return {dialog, pushEvent, close: () => listeners.get("close")?.()}
}

it("opens as a modal the moment it mounts", () => {
  const {dialog} = mountDialog("dismiss_wallet_reconnect")

  expect(dialog.showModal).toHaveBeenCalledOnce()
  expect(dialog.open).toBe(true)
})

it("tells the server which event dismisses it when the visitor closes it", () => {
  const {close, pushEvent} = mountDialog("dismiss_wallet_reconnect")

  close()

  expect(pushEvent).toHaveBeenCalledWith("dismiss_wallet_reconnect", {})
})

it("stays quiet on close when no dismiss event is named", () => {
  const {close, pushEvent} = mountDialog()

  close()

  expect(pushEvent).not.toHaveBeenCalled()
})
