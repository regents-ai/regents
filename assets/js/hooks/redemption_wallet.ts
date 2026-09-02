import type {Hook} from "../hook_composition"
import {activeEthereumWallet, type SelectedWallet} from "../wallet_actions/connected_wallet"
import {
  clearProgress,
  renderResult,
  setProgress,
  type ResultDisplay,
} from "./transaction_feedback"
import {
  executePreparedRedemptionAction,
  isRedemptionWalletDrift,
  RedemptionExecutionFailure,
  type PreparedRedemptionAction,
  type RedemptionAction,
  type RedemptionRuntime,
  type SubmittedRedemptionTransaction,
} from "../wallet_actions/redemption"

type ResultSlot = {
  readonly id: string
  readonly order: number
  readonly generation: number
  readonly action: RedemptionAction
  readonly initiator: HTMLElement
  readonly signer: string
  readonly subject: string
  handedOff: boolean
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
  observations: Map<string, ResultSlot>
  queue: ResultSlot[]
  dismissedOperations: Set<ResultSlot>
  nextOrder: number
  preparingAttemptId: string | null
  visible: ResultSlot | null
  ignoreNextClose: boolean
  initiators: Map<string, PendingInitiator>
  dialog: HTMLDialogElement
  dialogTitle: HTMLElement
  text: HTMLElement
  detail: HTMLElement
  walletText: HTMLElement
  link: HTMLAnchorElement
  progress: HTMLElement
  progressTitle: HTMLElement
  progressCopy: HTMLElement
  click: (event: MouseEvent) => void
  selectionChanged: (event: Event) => void
  close: () => void
  cancel: () => void
  publishActiveWallet: () => void
  walletFailure: () => void
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
      observations: new Map(),
      queue: [],
      dismissedOperations: new Set(),
      nextOrder: 0,
      preparingAttemptId: null,
      visible: null,
      ignoreNextClose: false,
      initiators: new Map(),
      dialog,
      dialogTitle: requiredElement(dialog, "[data-redemption-result-title]"),
      text: requiredElement(dialog, "[data-redemption-result-text]"),
      detail: requiredElement(dialog, "[data-redemption-result-detail]"),
      walletText: requiredElement(dialog, "[data-redemption-result-wallet]"),
      link: requiredElement<HTMLAnchorElement>(dialog, "[data-redemption-result-link]"),
      progress: requiredElement(this.el, "[data-redemption-progress]"),
      progressTitle: requiredElement(this.el, "[data-redemption-progress-title]"),
      progressCopy: requiredElement(this.el, "[data-redemption-progress-copy]"),
      click: () => undefined,
      selectionChanged: () => undefined,
      close: () => undefined,
      cancel: () => undefined,
      publishActiveWallet: () => undefined,
      walletFailure: () => undefined,
    }
    this.redemptionState = state

    state.publishActiveWallet = () => {
      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(this.el, state, wallet)
      this.pushEvent("redemption_active_wallet", {address: wallet?.address ?? null})
    }

    state.click = event => {
      const target = event.target as HTMLElement | null
      if (target?.closest("[data-redeem-connect]")) {
        setProgress(state, "preparing", "Opening wallet connection", "Choose a wallet in Privy to continue on Base.")
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
      if (!sameWallet(state.wallet, wallet)) resetForWallet(this.el, state, wallet)

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
        state.preparingAttemptId = attemptId
        setProgress(state, "preparing", `Preparing ${actionLabel(action).toLowerCase()}`, "Building the exact transaction for your wallet to sign.")
        this.pushEvent("prepare_redemption", {action, attempt_id: attemptId})
      }
    }

    state.selectionChanged = event => {
      const target = event.target as HTMLElement | null
      if (target?.closest("#redemption-selection")) clearPendingInitiators(state)
    }

    state.close = () => {
      if (state.ignoreNextClose) {
        state.ignoreNextClose = false
        presentNext(this.el, state)
        return
      }
      if (!state.alive || !state.visible) return
      const closed = state.visible
      state.visible = null
      const awaitingResult = closed.handedOff || state.observations.get(closed.id) === closed
      const index = state.queue.indexOf(closed)
      if (index >= 0) state.queue.splice(index, 1)
      state.results.delete(closed.id)
      if (awaitingResult) state.dismissedOperations.add(closed)
      restoreFocus(this.el, closed.initiator)
      presentNext(this.el, state)
    }
    state.cancel = () => undefined
    state.walletFailure = () => {
      setProgress(state, "failed", "Wallet connection not completed", "Try again and finish the connection in Privy.")
    }

    this.el.addEventListener("click", state.click)
    this.el.addEventListener("change", state.selectionChanged)
    this.el.addEventListener("input", state.selectionChanged)
    state.dialog.addEventListener("close", state.close)
    state.dialog.addEventListener("cancel", state.cancel)
    window.addEventListener("ash:wallet-state", state.publishActiveWallet)
    window.addEventListener("ash:wallet-connect-failed", state.walletFailure)
    state.publishActiveWallet()

    this.handleEvent("redemption:wallet-action", payload => {
      const {attempt_id: attemptId, envelope} = payload as {
        attempt_id?: unknown
        envelope?: PreparedRedemptionAction
      }
      if (typeof attemptId !== "string" || !envelope) return
      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(this.el, state, wallet)
      const initiator = takeInitiator(state, attemptId, envelope.action, envelope.expected_signer)
      if (!initiator) return
      state.preparingAttemptId = null

      const slot: ResultSlot = {
        id: crypto.randomUUID(),
        order: initiator.order,
        generation: state.generation,
        action: envelope.action,
        initiator: initiator.element,
        signer: initiator.signer,
        subject: actionSubject(envelope),
        handedOff: false,
        submitted: null,
      }
      insertQueue(state, slot)

      if (!wallet) {
        settleImmediate(this.el, state, slot, "Connect or switch wallet and try again.")
        return
      }

      const runtime = runtimeFor(state, slot.generation)
      setProgress(state, "preparing", `Preparing ${actionLabel(slot.action).toLowerCase()}`, "Simulating the exact transaction on Base.")
      void executePreparedRedemptionAction(
        envelope,
        initiator.provider,
        undefined,
        activeEthereumWallet,
        runtime,
        () => {
          slot.handedOff = true
          setProgress(state, "signature", `${actionLabel(slot.action)} in your wallet`, "Review the exact Base transaction, then confirm or cancel it.")
        },
        () => settleImmediate(this.el, state, slot, "The submission outcome is unknown."),
      )
        .then(submitted => {
          if (!liveSlot(state, slot)) return
          slot.handedOff = false
          restoreDismissedSlot(state, slot)
          slot.submitted = submitted
          state.observations.set(slot.id, slot)
          setProgress(state, "submitted", "Transaction submitted", "Waiting for Base to confirm the transaction.")
          updateSubmittedResult(this.el, state, slot, submitted.hash)
          this.pushEvent("observe_redemption_transaction", observation(slot.id, submitted))
        })
        .catch(error => {
          if (!liveSlot(state, slot)) return
          slot.handedOff = false
          restoreDismissedSlot(state, slot)
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
      if (typeof attemptId === "string") {
        const initiator = state.initiators.get(attemptId)
        state.initiators.delete(attemptId)
        state.preparingAttemptId = null
        if (initiator) setProgress(state, "failed", `${actionLabel(initiator.action)} is not ready`, "Review the current Base status shown on the page, then try again.")
      }
    })

    this.handleEvent("redemption:transaction-result", payload => {
      const {observation_id: observationId, result} = payload as {
        observation_id?: unknown
        result?: unknown
      }
      if (typeof observationId !== "string" || !transactionResult(result)) return
      const observed = state.observations.get(observationId)
      if (observed) settleObserved(this, state, observed, result)
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
    window.removeEventListener("ash:wallet-connect-failed", state.walletFailure)
    state.visible = null
    state.queue.length = 0
    state.results.clear()
    state.observations.clear()
    state.dismissedOperations.clear()
    state.initiators.clear()
    if (state.dialog.open) state.dialog.close()
    this.redemptionState = undefined
  },
}

function runtimeFor(state: RedemptionState, generation: number): RedemptionRuntime {
  return {
    alive: () => state.alive && state.generation === generation,
    hostAlive: () => state.alive,
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
  if (!liveSlot(state, slot)) return
  setProgress(state, "failed", `${actionLabel(slot.action)} not completed`, message)
  const display: ResultDisplay = Object.freeze({
    title: `${actionLabel(slot.action)} not completed`,
    message,
    detail: "No confirmed Base transaction changed your redemption position.",
    href: null,
    tone: "error",
  })
  state.results.set(slot.id, display)
  presentOrUpdate(root, state, slot, display)
}

function settleObserved(
  hook: RedemptionHook,
  state: RedemptionState,
  slot: ResultSlot,
  result: TransactionResult,
): void {
  if (!liveSlot(state, slot) || !slot.submitted || state.observations.get(slot.id) !== slot) return
  state.observations.delete(slot.id)
  restoreDismissedSlot(state, slot)
  const href = `https://basescan.org/tx/${slot.submitted.hash}`
  const label = actionLabel(slot.action)

  const display: ResultDisplay = result === "success"
    ? {
        title: `${label} confirmed`,
        message: redemptionSuccess(slot),
        detail: "Your collection and vest are refreshing in place from the latest Base block.",
        href,
        tone: "success",
      }
    : result === "reverted"
      ? {
          title: `${label} reverted`,
          message: "Base included the transaction, but the contract reverted it.",
          detail: "Your confirmed collection and redemption position did not change.",
          href,
          tone: "error",
        }
      : result === "delayed"
        ? {
            title: "Confirmation is taking longer",
            message: "The wallet returned a transaction hash, but Base has not confirmed it yet.",
            detail: "Use the BaseScan link to follow it before attempting the same action again.",
            href,
            tone: "pending",
          }
        : {
            title: "Confirmation unavailable",
            message: "Alchemy has not returned a verifiable Base result.",
            detail: "Check BaseScan or your wallet activity before trying the same action again.",
            href,
            tone: "pending",
          }
  state.results.set(slot.id, Object.freeze(display))
  if (result === "success") {
    setProgress(state, "confirmed", `${label} confirmed`, "Refreshing your redemption data from Base.")
    if (sameAddress(slot.signer, state.wallet?.address)) {
      hook.pushEvent("refresh_redemption", {refresh_owned: slot.action === "redeem"})
    }
  } else if (result === "reverted") {
    setProgress(state, "failed", `${label} reverted`, "The confirmed position did not change.")
  } else {
    setProgress(state, "submitted", display.title, display.message)
  }
  presentOrUpdate(hook.el, state, slot, display)
}

function updateSubmittedResult(
  root: HTMLElement,
  state: RedemptionState,
  slot: ResultSlot,
  hash: string,
): void {
  if (!state.results.has(slot.id)) return
  const display: ResultDisplay = Object.freeze({
    title: "Transaction submitted",
    message: "Privy returned the transaction hash. Alchemy is checking its Base result.",
    detail: "You can keep using the page while confirmation completes.",
    href: `https://basescan.org/tx/${hash}`,
    tone: "pending",
  })
  state.results.set(slot.id, display)
  presentOrUpdate(root, state, slot, display)
}

function presentOrUpdate(
  root: HTMLElement,
  state: RedemptionState,
  slot: ResultSlot,
  display: ResultDisplay,
): void {
  if (state.visible === slot) renderResult(state, display, slot.signer)
  else presentNext(root, state)
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

  renderResult(state, display, next.signer)
  state.visible = next
  state.dialog.showModal()
}

function resetForWallet(root: HTMLElement, state: RedemptionState, wallet: SelectedWallet | null): void {
  state.wallet = wallet
  invalidateGeneration(root, state)
}

function invalidateGeneration(root: HTMLElement, state: RedemptionState): void {
  state.generation += 1
  cancelAll(state)
  const retainedSlots = state.queue.filter(slot => slot.submitted || slot.handedOff)
  const retained = new Set([
    ...retainedSlots.map(slot => slot.id),
    ...[...state.dismissedOperations].map(slot => slot.id),
  ])
  const visible = state.visible && retained.has(state.visible.id) ? state.visible : null
  state.queue.splice(0, state.queue.length, ...retainedSlots)
  retainOnly(state.results, retained)
  retainOnly(state.observations, retained)
  state.visible = visible
  state.initiators.clear()
  state.nextOrder = retainedSlots.reduce((next, slot) => Math.max(next, slot.order + 1), 0)
  state.preparingAttemptId = null
  if (retained.size === 0) clearProgress(state)
  if (state.dialog.open && !visible) {
    state.ignoreNextClose = true
    state.dialog.close()
  } else {
    presentNext(root, state)
  }
}

type TransactionResult = "success" | "reverted" | "delayed" | "unavailable"

function transactionResult(value: unknown): value is TransactionResult {
  return value === "success" || value === "reverted" || value === "delayed" || value === "unavailable"
}

function observation(id: string, submitted: SubmittedRedemptionTransaction) {
  return {
    observation_id: id,
    hash: submitted.hash,
    signer: submitted.signer,
    to: submitted.transaction.to,
    data: submitted.transaction.data,
  }
}

function retainOnly<T>(map: Map<string, T>, ids: Set<string>): void {
  for (const id of map.keys()) if (!ids.has(id)) map.delete(id)
}

function clearPendingInitiators(state: RedemptionState): void {
  let clearedPreparing = false
  for (const [attemptId, initiator] of state.initiators) {
    if (initiator.action !== "claim") {
      state.initiators.delete(attemptId)
      if (state.preparingAttemptId === attemptId) clearedPreparing = true
    }
  }
  if (clearedPreparing) {
    state.preparingAttemptId = null
    clearProgress(state)
  }
}

function cancelAll(state: RedemptionState): void {
  for (const cancel of [...state.cancellations]) cancel()
  state.cancellations.clear()
}

function liveSlot(state: RedemptionState, slot: ResultSlot): boolean {
  return state.alive && (state.queue.includes(slot) || state.dismissedOperations.has(slot))
}

function restoreDismissedSlot(state: RedemptionState, slot: ResultSlot): void {
  if (state.dismissedOperations.delete(slot)) state.queue.push(slot)
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

function sameAddress(first: string, second?: string): boolean {
  return typeof second === "string" && first.toLowerCase() === second.toLowerCase()
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

function actionSubject(envelope: PreparedRedemptionAction): string {
  return envelope.action === "redeem" && typeof envelope.arguments.token_id === "number"
    ? `Animata #${envelope.arguments.token_id}`
    : actionLabel(envelope.action)
}

function redemptionSuccess(slot: ResultSlot): string {
  switch (slot.action) {
    case "approve_nft_collection": return "The selected NFT collection was approved successfully."
    case "approve_exact_usdc": return "Exactly 80 USDC was approved successfully."
    case "redeem": return `${slot.subject} was redeemed successfully.`
    case "claim": return "Your unlocked REGENT was claimed successfully."
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
