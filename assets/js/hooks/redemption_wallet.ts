import type {Hook} from "../hook_composition"
import {activeEthereumWallet, type SelectedWallet} from "../wallet_actions/connected_wallet"
import {
  executePreparedRedemptionAction,
  observeRedemptionTransaction,
  isRedemptionWalletDrift,
  RedemptionExecutionFailure,
  type ObservedRedemptionResult,
  type PreparedRedemptionAction,
  type RedemptionAction,
  type RedemptionRuntime,
  type SubmittedRedemptionTransaction,
} from "../wallet_actions/redemption"

type ResultDisplay = Readonly<{message: string; href: string | null}>
type ResultSlot = {
  readonly id: string
  readonly order: number
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
  provider: SelectedWallet["provider"]
  order: number
}

type RedemptionState = {
  alive: boolean
  generation: number
  wallet: SelectedWallet | null
  cancellations: Set<() => void>
  results: Map<string, ResultDisplay>
  queue: ResultSlot[]
  nextOrder: number
  visible: ResultSlot | null
  initiators: Map<string, PendingInitiator>
  dialog: HTMLDialogElement
  text: HTMLElement
  link: HTMLAnchorElement
  click: (event: MouseEvent) => void
  selectionChanged: (event: Event) => void
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
      nextOrder: 0,
      visible: null,
      initiators: new Map(),
      dialog,
      text: requiredElement(dialog, "[data-redemption-result-text]"),
      link: requiredElement<HTMLAnchorElement>(dialog, "[data-redemption-result-link]"),
      click: () => undefined,
      selectionChanged: () => undefined,
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

      if (target?.closest('[phx-click="redemption_selection_changed"], [phx-click="select_owned_animata"]')) {
        clearPendingInitiators(state)
        return
      }

      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(state, wallet)

      const initiator = target?.closest<HTMLElement>("[data-redemption-action]")
      const action = initiator?.getAttribute("data-redemption-action") ?? null
      if (initiator && redemptionAction(action) && wallet) {
        event.preventDefault()
        const attemptId = crypto.randomUUID()
        state.initiators.set(attemptId, {
          action,
          element: initiator,
          generation: state.generation,
          signer: wallet.address,
          provider: wallet.provider,
          order: state.nextOrder++,
        })
        this.pushEvent("prepare_redemption", {action, attempt_id: attemptId})
      }
    }

    state.selectionChanged = event => {
      const target = event.target as HTMLElement | null
      if (target?.closest("#redemption-selection")) clearPendingInitiators(state)
    }

    state.close = () => {
      if (!state.alive || !state.visible) return
      const closed = state.visible
      state.visible = null
      const index = state.queue.indexOf(closed)
      if (index >= 0) state.queue.splice(index, 1)
      state.results.delete(closed.id)
      restoreFocus(this.el, closed.initiator)
      presentNext(this.el, state)
    }
    state.cancel = () => undefined

    this.el.addEventListener("click", state.click)
    this.el.addEventListener("change", state.selectionChanged)
    this.el.addEventListener("input", state.selectionChanged)
    state.dialog.addEventListener("close", state.close)
    state.dialog.addEventListener("cancel", state.cancel)
    window.addEventListener("ash:wallet-state", state.publishActiveWallet)
    state.publishActiveWallet()

    this.handleEvent("redemption:wallet-action", payload => {
      const {attempt_id: attemptId, envelope} = payload as {
        attempt_id?: unknown
        envelope?: PreparedRedemptionAction
      }
      if (typeof attemptId !== "string" || !envelope) return
      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(state, wallet)
      const initiator = takeInitiator(state, attemptId, envelope.action, envelope.expected_signer)
      if (!initiator) return

      const slot: ResultSlot = {
        id: crypto.randomUUID(),
        order: initiator.order,
        generation: state.generation,
        action: envelope.action,
        initiator: initiator.element,
        submitted: null,
      }
      insertQueue(state, slot)

      if (!wallet) {
        settleImmediate(this.el, state, slot, "Connect or switch wallet and try again.")
        return
      }

      const runtime = runtimeFor(state, slot.generation)
      void executePreparedRedemptionAction(envelope, initiator.provider, undefined, activeEthereumWallet, runtime)
        .then(submitted => {
          if (!runtime.alive()) return
          slot.submitted = submitted
          observeRedemptionTransaction(submitted, runtime, result => {
            settleObserved(this, state, slot, result)
          })
        })
        .catch(error => {
          if (!runtime.alive()) return
          if (isRedemptionWalletDrift(error)) return
          const message =
            error instanceof RedemptionExecutionFailure
              ? error.displayMessage
              : userRejected(error)
                ? "Request canceled."
                : "Switch to Base before continuing."
          settleImmediate(
            this.el,
            state,
            slot,
            message,
          )
        })
    })

    this.handleEvent("redemption:wallet-refusal", payload => {
      const attemptId = (payload as {attempt_id?: unknown}).attempt_id
      if (typeof attemptId === "string") state.initiators.delete(attemptId)
    })
  },

  destroyed(this: RedemptionHook) {
    const state = this.redemptionState
    if (!state) return
    state.alive = false
    state.generation += 1
    cancelAll(state)
    this.el.removeEventListener("click", state.click)
    this.el.removeEventListener("change", state.selectionChanged)
    this.el.removeEventListener("input", state.selectionChanged)
    state.dialog.removeEventListener("close", state.close)
    state.dialog.removeEventListener("cancel", state.cancel)
    window.removeEventListener("ash:wallet-state", state.publishActiveWallet)
    state.visible = null
    state.queue.length = 0
    state.results.clear()
    state.initiators.clear()
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
  state.wallet = wallet
  invalidateGeneration(state)
}

function invalidateGeneration(state: RedemptionState): void {
  state.generation += 1
  cancelAll(state)
  state.visible = null
  state.queue.length = 0
  state.results.clear()
  state.initiators.clear()
  state.nextOrder = 0
  if (state.dialog.open) state.dialog.close()
}

function clearPendingInitiators(state: RedemptionState): void {
  for (const [attemptId, initiator] of state.initiators) {
    if (initiator.action !== "claim") state.initiators.delete(attemptId)
  }
}

function cancelAll(state: RedemptionState): void {
  for (const cancel of [...state.cancellations]) cancel()
  state.cancellations.clear()
}

function currentSlot(state: RedemptionState, slot: ResultSlot): boolean {
  return state.alive && state.generation === slot.generation && state.queue.includes(slot)
}

function insertQueue(state: RedemptionState, slot: ResultSlot): void {
  const index = state.queue.findIndex(candidate => candidate.order > slot.order)
  if (index < 0) state.queue.push(slot)
  else state.queue.splice(index, 0, slot)
}

function takeInitiator(
  state: RedemptionState,
  attemptId: string,
  action: RedemptionAction,
  expectedSigner: string,
): PendingInitiator | null {
  const candidate = state.initiators.get(attemptId)
  state.initiators.delete(attemptId)
  if (
    candidate &&
    candidate.action === action &&
    candidate.generation === state.generation &&
    candidate.signer.toLowerCase() === expectedSigner.toLowerCase() &&
    candidate.provider === state.wallet?.provider
  ) return candidate
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
