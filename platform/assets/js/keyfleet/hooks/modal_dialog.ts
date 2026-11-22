import type {Hook} from "../../hook_composition"

interface ModalDialogHook {
  el: HTMLDialogElement
  pushEventTo(target: HTMLElement, event: string, payload: Record<string, never>): void
  opener?: string
  shown?: string
}

const focusable =
  "a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex='-1'])"

// The control the last press reached, when that control has an id. Safari
// doesn't focus a link or button when it is clicked, so what has focus can't
// say which control opened a dialog. A key press, or going back or forward,
// starts afresh.
let pressed: string | undefined

// Whether the last press was a pointer's, not a key's: focus handed back
// after a pointer closes a dialog shows no ring, and after a key it does.
let pointerPress = false

export function watchPresses(doc: Document) {
  doc.addEventListener("click", notePress, true)
  doc.addEventListener("keydown", noteKey, true)
  doc.defaultView?.addEventListener("popstate", forgetPress)
}

// A click a key made, Enter or Space on a button, counts no presses.
function notePress(event: MouseEvent) {
  pressed = (event.target as Element | null)?.closest?.("a[id], button[id], [tabindex][id]")?.id
  pointerPress = event.detail > 0
}

function noteKey() {
  forgetPress()
  pointerPress = false
}

function forgetPress() {
  pressed = undefined
}

// The control that opened the dialog: the one just pressed, or else the one
// with focus.
export function openerOf(active: Element | null, body: Element | null) {
  return pressed ?? (active && active !== body && active.id ? active.id : undefined)
}

// Tab and Shift+Tab step through the dialog's controls and go round at either
// end, never leaving it. Every control is a stop, as Safari would otherwise
// pass over links and buttons and find its way out.
export function stepTab(event: KeyboardEvent, controls: HTMLElement[], active: Element | null) {
  if (event.key !== "Tab" || controls.length === 0) return
  event.preventDefault()
  const at = controls.indexOf(active as HTMLElement)
  const step = event.shiftKey ? -1 : 1
  const from = at === -1 && event.shiftKey ? 0 : at
  controls[(from + step + controls.length) % controls.length].focus()
}

// The dialogs open in the page, bottom first, in the order they opened.
const stack: HTMLDialogElement[] = []

// Every dialog in the page steps down from being a modal, so the sign-in
// window above them can be used: a modal one would hold the page, sign-in
// with it, out of reach, whichever dialog sign-in was opened from.
function stepDown() {
  for (const dialog of stack) {
    if (!dialog.matches(":modal")) continue
    dialog.close()
    dialog.show()
  }
}

// Every dialog is a modal again, above the page, bottom first so the one on
// top stays on top. Says whether any had stepped down.
function stepUp() {
  if (stack.every(dialog => dialog.matches(":modal"))) return false
  for (const dialog of stack) {
    dialog.close()
    dialog.showModal()
  }
  return true
}

// A <dialog> the page opens as a modal for as long as it is in the page. It
// opens with focus on its title, and on its title again when it comes to show
// something else. Closing it asks the page to take it away: by going back when
// `data-close` is "back", or else by sending `data-close-event` to whichever
// part of the page drew it. Once it has gone, focus returns to whatever opened
// it, with its ring only when a key closed it. Signing in from inside it lets
// the sign-in window above every dialog be used; on a press back inside a
// dialog, they are all modals again, above the page.
export const ModalDialog: Hook = {
  mounted(this: ModalDialogHook) {
    const dialog = this.el
    this.opener = openerOf(document.activeElement, document.body)
    this.shown = dialog.dataset.shown

    dialog.addEventListener("close", () => {
      // Closed only to be shown again, modal or not.
      if (dialog.open) return
      if (dialog.dataset.close === "back") history.back()
      else if (dialog.dataset.closeEvent) this.pushEventTo(dialog, dialog.dataset.closeEvent, {})
    })

    dialog.addEventListener("keydown", event => stepTab(event, visibleControls(dialog), document.activeElement))

    dialog.addEventListener("click", event => {
      const control = (event.target as Element).closest<HTMLElement>("[data-account-target='sign-in']")
      if (!control || !dialog.matches(":modal")) return
      stepDown()
    })

    dialog.addEventListener("pointerdown", stepUp)

    if (!dialog.open) dialog.showModal()
    stack.push(dialog)
    focusTitle(dialog)
  },

  updated(this: ModalDialogHook) {
    if (this.el.dataset.shown === this.shown) return
    this.shown = this.el.dataset.shown
    this.el.querySelector(".rg-dialog__body")?.scrollTo({top: 0})
    this.el.querySelector<HTMLElement>("[data-modal-scroll]")?.scrollTo({top: 0})
    focusTitle(this.el)
  },

  destroyed(this: ModalDialogHook) {
    stack.splice(stack.indexOf(this.el), 1)
    if (this.opener) document.getElementById(this.opener)?.focus({focusVisible: !pointerPress})
  },
}

function focusTitle(dialog: HTMLDialogElement) {
  dialog.querySelector<HTMLElement>("[data-modal-title]")?.focus()
}

function visibleControls(dialog: HTMLDialogElement) {
  return Array.from(dialog.querySelectorAll<HTMLElement>(focusable)).filter(
    control => control.getClientRects().length > 0,
  )
}
