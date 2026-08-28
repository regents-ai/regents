import type {Hook} from "../hook_composition"
import {activeEthereumWallet, type SelectedWallet} from "../wallet_actions/connected_wallet"
import {
  executePreparedRedemptionAction,
  observeRedemptionTransaction,
  type ObservedRedemptionResult,
  type PreparedRedemptionAction,
  type RedemptionAction,
  type RedemptionRuntime,
  type SubmittedRedemptionTransaction,
} from "../wallet_actions/redemption"

type ResultDisplay = Readonly<{message: string; href: string | null}>
type ResultSlot = {
  readonly id: string
  readonly generation: number
  readonly action: RedemptionAction
  readonly initiator: HTMLElement
  submitted: SubmittedRedemptionTransaction | null
}
type PendingInitiator = {
  action: RedemptionAction
  element: HTMLElement
  generation: number
  signer: string
}

type RedemptionState = {
  alive: boolean
  generation: number
  wallet: SelectedWallet | null
  cancellations: Set<() => void>
  results: Map<string, ResultDisplay>
  queue: ResultSlot[]
  visible: ResultSlot | null
  initiators: PendingInitiator[]
  dialog: HTMLDialogElement
  text: HTMLElement
  link: HTMLAnchorElement
  click: (event: MouseEvent) => void
  close: () => void
  cancel: () => void
  publishActiveWallet: () => void
}

type RedemptionHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  redemptionState?: RedemptionState
}

const redemptionActions = new Set<RedemptionAction>([
  "approve_nft_collection",
  "approve_exact_usdc",
  "redeem",
  "claim",
])

export const RedemptionWallet: Hook = {
  mounted(this: RedemptionHook) {
    const dialog = requiredElement<HTMLDialogElement>(this.el, "#redemption-result-dialog")
    const state: RedemptionState = {
      alive: true,
      generation: 0,
      wallet: activeEthereumWallet(),
      cancellations: new Set(),
      results: new Map(),
      queue: [],
      visible: null,
      initiators: [],
      dialog,
      text: requiredElement(dialog, "[data-redemption-result-text]"),
      link: requiredElement<HTMLAnchorElement>(dialog, "[data-redemption-result-link]"),
      click: () => undefined,
      close: () => undefined,
      cancel: () => undefined,
      publishActiveWallet: () => undefined,
    }
    this.redemptionState = state

    state.publishActiveWallet = () => {
      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(state, wallet)
      this.pushEvent("redemption_active_wallet", {address: wallet?.address ?? null})
    }

    state.click = event => {
      const target = event.target as HTMLElement | null
      if (target?.closest("[data-redeem-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
        return
      }

      if (target === state.dialog) {
        state.dialog.close()
        return
      }

      const initiator = target?.closest<HTMLElement>('[phx-click="prepare_redemption"]')
      const action = initiator?.getAttribute("phx-value-action") ?? null
      if (initiator && redemptionAction(action) && state.wallet) {
        state.initiators.push({
          action,
          element: initiator,
          generation: state.generation,
          signer: state.wallet.address,
        })
      }
    }

    state.close = () => {
      if (!state.alive || !state.visible) return
      const closed = state.visible
      state.visible = null
      if (state.queue[0] === closed) state.queue.shift()
      state.results.delete(closed.id)
      restoreFocus(this.el, closed.initiator)
      presentNext(this.el, state)
    }
    state.cancel = () => undefined

    this.el.addEventListener("click", state.click)
    state.dialog.addEventListener("close", state.close)
    state.dialog.addEventListener("cancel", state.cancel)
    window.addEventListener("ash:wallet-state", state.publishActiveWallet)
    state.publishActiveWallet()

    this.handleEvent("redemption:wallet-action", payload => {
      const envelope = (payload as {envelope: PreparedRedemptionAction}).envelope
      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(state, wallet)
      const initiator = takeInitiator(state, envelope.action, envelope.expected_signer)
      if (!initiator) return

      const slot: ResultSlot = {
        id: crypto.randomUUID(),
        generation: state.generation,
        action: envelope.action,
        initiator,
        submitted: null,
      }
      state.queue.push(slot)

      if (!wallet) {
        settleImmediate(this.el, state, slot, "Connect or switch wallet and try again.")
        return
      }

      const runtime = runtimeFor(state, slot.generation)
      void executePreparedRedemptionAction(envelope, wallet.provider)
        .then(submitted => {
          if (!runtime.alive()) return
          slot.submitted = submitted
          observeRedemptionTransaction(submitted, runtime, result => {
            settleObserved(this, state, slot, result)
          })
        })
        .catch(error => {
          if (!runtime.alive()) return
          settleImmediate(
            this.el,
            state,
            slot,
            userRejected(error) ? "Request canceled." : "The submission outcome is unknown.",
          )
        })
    })
  },

  destroyed(this: RedemptionHook) {
    const state = this.redemptionState
    if (!state) return
    state.alive = false
    state.generation += 1
    cancelAll(state)
    this.el.removeEventListener("click", state.click)
    state.dialog.removeEventListener("close", state.close)
    state.dialog.removeEventListener("cancel", state.cancel)
    window.removeEventListener("ash:wallet-state", state.publishActiveWallet)
    state.visible = null
    state.queue.length = 0
    state.results.clear()
    state.initiators.length = 0
    if (state.dialog.open) state.dialog.close()
    this.redemptionState = undefined
  },
}

function runtimeFor(state: RedemptionState, generation: number): RedemptionRuntime {
  return {
    alive: () => state.alive && state.generation === generation,
    registerCancellation: cancel => {
      if (!state.alive || state.generation !== generation) {
        cancel()
        return () => undefined
      }
      state.cancellations.add(cancel)
      return () => state.cancellations.delete(cancel)
    },
  }
}

function settleImmediate(
  root: HTMLElement,
  state: RedemptionState,
  slot: ResultSlot,
  message: string,
): void {
  if (!currentSlot(state, slot)) return
  state.results.set(slot.id, Object.freeze({message, href: null}))
  presentNext(root, state)
}

function settleObserved(
  hook: RedemptionHook,
  state: RedemptionState,
  slot: ResultSlot,
  result: ObservedRedemptionResult,
): void {
  if (!currentSlot(state, slot) || !slot.submitted) return
  const href =
    result === "success" || result === "reverted"
      ? `https://basescan.org/tx/${slot.submitted.hash}`
      : null
  const label = actionLabel(slot.action)
  const message =
    result === "success"
      ? `${label} succeeded on Base.`
      : result === "reverted"
        ? `${label} reverted on Base.`
        : result === "delayed"
          ? "Block inclusion is delayed."
          : "Verification is unavailable."
  state.results.set(slot.id, Object.freeze({message, href}))
  if (result === "success") hook.pushEvent("refresh_redemption", {})
  presentNext(hook.el, state)
}

function presentNext(root: HTMLElement, state: RedemptionState): void {
  if (
    !state.alive ||
    state.visible ||
    state.dialog.open ||
    !root.isConnected ||
    !state.dialog.isConnected
  ) return
  const next = state.queue[0]
  if (!next) return
  const display = state.results.get(next.id)
  if (!display) return

  state.text.textContent = display.message
  state.link.textContent = ""
  state.link.removeAttribute("href")
  state.link.hidden = true
  if (display.href) {
    state.link.textContent = "View on BaseScan"
    state.link.href = display.href
    state.link.target = "_blank"
    state.link.rel = "noopener noreferrer"
    state.link.hidden = false
  }
  state.visible = next
  state.dialog.showModal()
}

function resetForWallet(state: RedemptionState, wallet: SelectedWallet | null): void {
  state.generation += 1
  state.wallet = wallet
  cancelAll(state)
  state.visible = null
  state.queue.length = 0
  state.results.clear()
  state.initiators.length = 0
  if (state.dialog.open) state.dialog.close()
}

function cancelAll(state: RedemptionState): void {
  for (const cancel of [...state.cancellations]) cancel()
  state.cancellations.clear()
}

function currentSlot(state: RedemptionState, slot: ResultSlot): boolean {
  return state.alive && state.generation === slot.generation && state.queue.includes(slot)
}

function takeInitiator(
  state: RedemptionState,
  action: RedemptionAction,
  expectedSigner: string,
): HTMLElement | null {
  const index = state.initiators.findIndex(candidate =>
    candidate.action === action &&
    candidate.generation === state.generation &&
    candidate.signer.toLowerCase() === expectedSigner.toLowerCase()
  )
  if (index >= 0) return state.initiators.splice(index, 1)[0]!.element
  return null
}

function restoreFocus(root: HTMLElement, initiator: HTMLElement): void {
  if (focusable(initiator)) {
    initiator.focus({preventScroll: true})
    return
  }
  root.querySelector<HTMLElement>("#redemption-page-heading")?.focus({preventScroll: true})
}

function focusable(element: HTMLElement): boolean {
  return element.isConnected && !element.closest("[inert]") && !element.hasAttribute("disabled")
}

function sameWallet(first: SelectedWallet | null, second: SelectedWallet | null): boolean {
  if (!first || !second) return first === second
  return first.provider === second.provider && first.address.toLowerCase() === second.address.toLowerCase()
}

function redemptionAction(value: string | null): value is RedemptionAction {
  return typeof value === "string" && redemptionActions.has(value as RedemptionAction)
}

function actionLabel(action: RedemptionAction): string {
  switch (action) {
    case "approve_nft_collection": return "NFT approval"
    case "approve_exact_usdc": return "USDC approval"
    case "redeem": return "Animata redemption"
    case "claim": return "REGENT claim"
  }
}

function userRejected(error: unknown): boolean {
  if ((typeof error !== "object" || error === null) && typeof error !== "function") return false
  try {
    return Reflect.get(error, "code") === 4001
  } catch {
    return false
  }
}

function requiredElement<T extends Element>(root: ParentNode, selector: string): T {
  const element = root.querySelector<T>(selector)
  if (!element) throw new Error(`Redeem hook is missing ${selector}`)
  return element
}
