import {beforeEach, describe, expect, it, vi} from "vitest"

import {TransactionResultModal} from "../js/hooks/transaction_result_modal"

class FakeElement {
  isConnected = true
  inert = false
  focusCount = 0
  closestSelectors = new Set<string>()

  focus() {
    fakeDocument.activeElement = this
    this.focusCount += 1
  }

  closest(selector: string) {
    return this.closestSelectors.has(selector) ? this : null
  }
}

const scroller = new FakeElement()
const menuButton = new FakeElement()

const fakeDocument = {
  activeElement: null as FakeElement | null,
  body: new FakeElement(),
  documentElement: new FakeElement(),
  querySelector(selector: string) {
    if (selector === "#app-shell-scroller") return scroller
    if (selector === "#mobile-menu-button") return menuButton
    return null
  },
}

vi.stubGlobal("Element", FakeElement)
vi.stubGlobal("HTMLElement", FakeElement)
vi.stubGlobal("document", fakeDocument)

type Listener = (event: unknown) => void

const first = "action-1:action:confirmed:0xabc"
const second = "action-1:approval:confirmed:0xdef"

function fixture(resultId?: string) {
  const listeners = new Map<string, Listener>()
  const calls: string[] = []

  const dialog = {
    open: false,
    dataset: {resultId} as {resultId?: string},
    getBoundingClientRect: () => ({left: 100, top: 100, right: 200, bottom: 200}),
    showModal() {
      calls.push("showModal")
      dialog.open = true
    },
    close() {
      calls.push("close")
      dialog.open = false
    },
    addEventListener(type: string, listener: Listener) {
      listeners.set(type, listener)
    },
    removeEventListener(type: string) {
      listeners.delete(type)
    },
  }

  const hook = {el: dialog, pushEvent: vi.fn()}
  const call = (name: string) =>
    (TransactionResultModal[name] as ((this: unknown) => void) | undefined)?.call(hook)

  return {
    dialog,
    hook,
    calls,
    listeners,
    call,
    cancel() {
      const preventDefault = vi.fn()
      listeners.get("cancel")?.({preventDefault})
      return preventDefault
    },
    clickClose() {
      const target = new FakeElement()
      target.closestSelectors.add("[data-transaction-result-close]")
      listeners.get("click")?.({target})
    },
    pointerDown(clientX: number, clientY: number) {
      listeners.get("pointerdown")?.({clientX, clientY})
    },
  }
}

describe("transaction result modal hook", () => {
  beforeEach(() => {
    fakeDocument.activeElement = null
    scroller.inert = false
    scroller.focusCount = 0
    menuButton.focusCount = 0
    fakeDocument.body.focusCount = 0
    fakeDocument.documentElement.focusCount = 0
  })

  it("opens natively for the queued result and never reopens what is already open", () => {
    const {call, calls, dialog} = fixture(first)

    call("mounted")

    expect(calls).toEqual(["showModal"])
    expect(dialog.open).toBe(true)

    // Opening again while it is already open changes nothing.
    call("updated")
    expect(calls).toEqual(["showModal"])
  })

  it("stays closed and pushes nothing when no result is queued", () => {
    const {call, calls, hook, cancel} = fixture(undefined)

    call("mounted")
    cancel()

    expect(calls).toEqual([])
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })

  it("closes locally before telling the server, and names the result it was showing", () => {
    const trigger = new FakeElement()
    trigger.focus()
    const {call, calls, hook, cancel, dialog} = fixture(first)

    call("mounted")
    const preventDefault = cancel()

    expect(preventDefault).toHaveBeenCalled()
    expect(calls).toEqual(["showModal", "close"])
    expect(dialog.open).toBe(false)
    expect(hook.pushEvent).toHaveBeenCalledWith("dismiss_transaction_result", {id: first})
    expect(trigger.focusCount).toBe(2)
  })

  it("dismisses on the Close control and on a press outside the dialog box", () => {
    const closed = fixture(first)
    closed.call("mounted")
    closed.clickClose()

    expect(closed.hook.pushEvent).toHaveBeenCalledWith("dismiss_transaction_result", {id: first})

    const backdrop = fixture(first)
    backdrop.call("mounted")
    backdrop.pointerDown(150, 150)

    expect(backdrop.hook.pushEvent).not.toHaveBeenCalled()

    backdrop.pointerDown(10, 150)
    expect(backdrop.hook.pushEvent).toHaveBeenCalledWith("dismiss_transaction_result", {id: first})
  })

  // A LiveView patch may replace the teleported dialog, which closes it
  // natively. That lifecycle is never a dismissal.
  it("closes and reopens across a patch without dismissing", () => {
    const {call, calls, hook, dialog} = fixture(first)

    call("mounted")
    call("beforeUpdate")

    expect(dialog.open).toBe(false)
    expect(hook.pushEvent).not.toHaveBeenCalled()

    call("updated")

    expect(calls).toEqual(["showModal", "close", "showModal"])
    expect(dialog.open).toBe(true)
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })

  it("shows the next queued result after the server advances the queue", () => {
    const {call, calls, dialog} = fixture(first)

    call("mounted")
    call("beforeUpdate")
    dialog.dataset.resultId = second
    call("updated")

    expect(calls).toEqual(["showModal", "close", "showModal"])
    expect(dialog.dataset.resultId).toBe(second)
  })

  it("stays closed once the server has emptied the queue", () => {
    const {call, calls, dialog} = fixture(first)

    call("mounted")
    call("beforeUpdate")
    delete dialog.dataset.resultId
    call("updated")

    expect(calls).toEqual(["showModal", "close"])
    expect(dialog.open).toBe(false)
  })

  it("restores focus to the shell when the trigger has gone", () => {
    const trigger = new FakeElement()
    trigger.focus()
    const {call, cancel} = fixture(first)

    call("mounted")
    trigger.isConnected = false
    cancel()

    expect(scroller.focusCount).toBe(1)
    expect(menuButton.focusCount).toBe(0)
  })

  // With nothing focused the document names its own body, which cannot take
  // focus back. That is no target at all, so the shell answers instead.
  it("never hands focus back to the bare document", () => {
    for (const bare of [fakeDocument.body, fakeDocument.documentElement]) {
      scroller.focusCount = 0
      fakeDocument.activeElement = bare

      const {call, cancel} = fixture(first)
      call("mounted")
      cancel()

      expect(bare.focusCount).toBe(0)
      expect(scroller.focusCount).toBe(1)
    }
  })

  it("keeps focus out of an inert subtree behind the mobile menu", () => {
    const trigger = new FakeElement()
    trigger.closestSelectors.add("[inert]")
    trigger.focus()
    scroller.inert = true
    const {call, cancel} = fixture(first)

    call("mounted")
    cancel()

    expect(menuButton.focusCount).toBe(1)
    expect(scroller.focusCount).toBe(0)
  })

  it("closes locally and removes every listener when destroyed", () => {
    const {call, calls, hook, listeners, dialog} = fixture(first)

    call("mounted")
    expect([...listeners.keys()]).toEqual(["cancel", "click", "pointerdown"])

    call("destroyed")

    expect(calls).toEqual(["showModal", "close"])
    expect(dialog.open).toBe(false)
    expect(listeners.size).toBe(0)
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })
})
