import type {Hook} from "../hook_composition"
import {activeEthereumWallet, type SelectedWallet} from "../wallet_actions/connected_wallet"
import {renderResult, type ResultDisplay} from "./transaction_feedback"
import {
  executeStakingClick,
  prepareStakingClick,
  StakingLocalRefusal,
  type ImmediateStakingResult,
  type StakingAction,
  type StakingRuntime,
  type StakingTiming,
  type StakingTransactionRole,
  type SubmittedStakingTransaction,
} from "../wallet_actions/staking"

type ResultSlot = {
  readonly id: string
  readonly generation: number
  readonly action: StakingAction
  readonly role: StakingTransactionRole
  readonly initiator: HTMLElement
  readonly amount: string
  readonly signer: string
  handedOff: boolean
  submitted: SubmittedStakingTransaction | null
}

type StakeState = {
  alive: boolean
  generation: number
  wallet: SelectedWallet | null
  cancellations: Set<() => void>
  replayClaims: Set<string>
  observationSlots: Map<string, ResultSlot>
  results: Map<string, ResultDisplay>
  queue: ResultSlot[]
  dismissedOperations: Set<ResultSlot>
  visible: ResultSlot | null
  ignoreNextClose: boolean
  dialog: HTMLDialogElement
  dialogTitle: HTMLElement
  text: HTMLElement
  detail: HTMLElement
  walletText: HTMLElement
  link: HTMLAnchorElement
  click: (event: MouseEvent) => void
  close: () => void
  cancel: (event: Event) => void
  publishActiveWallet: () => void
}

type StakeHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  stakeState?: StakeState
}

const stakingActions = new Set<StakingAction>([
  "stake",
  "unstake",
  "claim_usdc",
  "claim_regent",
  "claim_and_restake_regent",
])

export const StakeWallet: Hook = {
  mounted(this: StakeHook) {
    const dialog = requiredElement<HTMLDialogElement>(this.el, "#staking-result-dialog")
    const state: StakeState = {
      alive: true,
      generation: 0,
      wallet: activeEthereumWallet(),
      cancellations: new Set(),
      replayClaims: new Set(),
      observationSlots: new Map(),
      results: new Map(),
      queue: [],
      dismissedOperations: new Set(),
      visible: null,
      ignoreNextClose: false,
      dialog,
      dialogTitle: requiredElement(dialog, "[data-staking-result-title]"),
      text: requiredElement(dialog, "[data-staking-result-text]"),
      detail: requiredElement(dialog, "[data-staking-result-detail]"),
      walletText: requiredElement(dialog, "[data-staking-result-wallet]"),
      link: requiredElement<HTMLAnchorElement>(dialog, "[data-staking-result-link]"),
      click: () => undefined,
      close: () => undefined,
      cancel: () => undefined,
      publishActiveWallet: () => undefined,
    }
    this.stakeState = state

    state.publishActiveWallet = () => {
      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(this.el, state, wallet)
      this.pushEvent("staking_active_wallet", {address: wallet?.address ?? null})
    }

    const reserve = (slot: ResultSlot, display?: ResultDisplay): void => {
      if (!state.alive) return
      state.queue.push(slot)
      if (display) state.results.set(slot.id, display)
      if (slot.submitted) state.observationSlots.set(slot.id, slot)
      presentNext(this.el, state)
    }

    const discard = (slot: ResultSlot): void => {
      if (!liveSlot(state, slot)) return
      state.dismissedOperations.delete(slot)
      state.observationSlots.delete(slot.id)
      state.results.delete(slot.id)
      const index = state.queue.indexOf(slot)
      if (index >= 0) state.queue.splice(index, 1)
      presentNext(this.el, state)
    }

    const callbacksFor = (slot: ResultSlot, runtime: StakingRuntime) => ({
      claimRole: (actionId: string, role: StakingTransactionRole): boolean => {
        const key = `${actionId}:${role}`
        if (!state.alive || !runtime.alive() || !currentSlot(state, slot) || state.replayClaims.has(key)) return false
        state.replayClaims.add(key)
        return true
      },
      timing: logTiming,
      walletRequestStarted: (_actionId: string, _role: StakingTransactionRole): void => {
        slot.handedOff = true
      },
      handoffTimedOut: (_actionId: string, role: StakingTransactionRole): void => {
        if (!liveSlot(state, slot)) return
        if (role === "approval") return
        settleImmediate(this.el, state, slot, "The submission outcome is unknown.")
      },
      immediate: (result: ImmediateStakingResult): void => {
        if (!liveSlot(state, slot)) return
        slot.handedOff = false
        restoreDismissedSlot(state, slot)
        // Approval is a wallet prerequisite, not a Regent result surface.
        if (result.role === "approval") {
          discard(slot)
          return
        }
        settleImmediate(this.el, state, slot, result.message)
      },
      submitted: (submitted: SubmittedStakingTransaction): void => {
        if (!liveSlot(state, slot)) return
        slot.handedOff = false
        restoreDismissedSlot(state, slot)
        if (submitted.role === "approval") {
          const approval: ResultSlot = {
            ...slot,
            id: crypto.randomUUID(),
            role: "approval",
            handedOff: false,
            submitted,
          }
          const actionIndex = state.queue.indexOf(slot)
          state.queue.splice(actionIndex, 0, approval)
          state.observationSlots.set(approval.id, approval)
          this.pushEvent("observe_staking_transaction", observation(approval.id, submitted))
          if (!runtime.alive()) discard(slot)
          return
        }
        slot.submitted = submitted
        state.observationSlots.set(slot.id, slot)
        updateSubmittedResult(this.el, state, slot, submitted.hash)
        this.pushEvent("observe_staking_transaction", observation(slot.id, submitted))
      },
    })

    state.click = event => {
      const target = event.target as HTMLElement | null
      if (target?.closest("[data-stake-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
        return
      }

      if (target === state.dialog) {
        state.dialog.close()
        return
      }

      const initiator = target?.closest<HTMLElement>("[data-staking-action]")
      if (!initiator) return
      const action = initiator.dataset.stakingAction
      if (!stakingAction(action)) return
      event.preventDefault()

      const wallet = activeEthereumWallet()
      if (!sameWallet(state.wallet, wallet)) resetForWallet(this.el, state, wallet)
      const generation = state.generation
      const runtime = runtimeFor(state, generation)
      const amount = this.el.querySelector<HTMLInputElement>("#staking-amount")?.value ?? ""
      const slot: ResultSlot = {
        id: crypto.randomUUID(),
        generation,
        action,
        role: "action",
        initiator,
        amount,
        signer: wallet?.address ?? "",
        handedOff: false,
        submitted: null,
      }
      reserve(slot)

      const clickedAt = performance.now()
      const traceId = crypto.randomUUID()
      const actionId = crypto.randomUUID()
      const role: StakingTransactionRole = "action"

      try {
        const click = prepareStakingClick(
          {
            action,
            amount,
            allowanceAtomic: this.el.dataset.stakingAllowance ?? "",
            chainId: this.el.dataset.stakingChainId ?? "",
            expectedSigner: this.el.dataset.stakingSigner ?? "",
          },
          wallet,
          {actionId, traceId},
        )
        logTiming({
          trace_id: traceId,
          action,
          role,
          phase: "click_to_local_ready",
          milliseconds: elapsed(clickedAt),
        })
        void executeStakingClick(click, callbacksFor(slot, runtime), runtime)
      } catch (error) {
        logTiming({
          trace_id: traceId,
          action,
          role,
          phase: "click_to_local_ready",
          milliseconds: elapsed(clickedAt),
        })
        const message =
          error instanceof StakingLocalRefusal
            ? error.displayMessage
            : "That staking action is unavailable. Refresh and try again."
        settleImmediate(this.el, state, slot, message)
      }
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
      const awaitingResult = closed.handedOff || state.observationSlots.get(closed.id) === closed
      const index = state.queue.indexOf(closed)
      if (index >= 0) state.queue.splice(index, 1)
      if (!awaitingResult) state.observationSlots.delete(closed.id)
      state.results.delete(closed.id)
      if (awaitingResult) state.dismissedOperations.add(closed)
      restoreFocus(this.el, closed.initiator)
      presentNext(this.el, state)
    }
    state.cancel = () => undefined

    this.el.addEventListener("click", state.click)
    state.dialog.addEventListener("close", state.close)
    state.dialog.addEventListener("cancel", state.cancel)
    window.addEventListener("ash:wallet-state", state.publishActiveWallet)
    state.publishActiveWallet()
    window.dispatchEvent(new CustomEvent("ash:wallet-sync"))

    this.handleEvent("staking:transaction-result", payload => {
      const {observation_id: observationId, result} = payload as {
        observation_id?: unknown
        result?: unknown
      }
      if (typeof observationId !== "string" || !transactionResult(result)) return
      const observed = state.observationSlots.get(observationId)
      if (observed) settleObserved(this, state, observed, result)
    })
  },

  destroyed(this: StakeHook) {
    const state = this.stakeState
    if (!state) return
    state.alive = false
    state.generation += 1
    for (const cancel of [...state.cancellations]) cancel()
    state.cancellations.clear()
    this.el.removeEventListener("click", state.click)
    state.dialog.removeEventListener("close", state.close)
    state.dialog.removeEventListener("cancel", state.cancel)
    window.removeEventListener("ash:wallet-state", state.publishActiveWallet)
    if (state.dialog.open) state.dialog.close()
    state.replayClaims.clear()
    state.observationSlots.clear()
    state.results.clear()
    state.queue.length = 0
    state.dismissedOperations.clear()
    state.visible = null
    this.stakeState = undefined
  },
}

function runtimeFor(state: StakeState, generation: number): StakingRuntime {
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

function resetForWallet(root: HTMLElement, state: StakeState, wallet: SelectedWallet | null): void {
  state.wallet = wallet
  invalidateGeneration(root, state)
}

function invalidateGeneration(root: HTMLElement, state: StakeState): void {
  state.generation += 1
  for (const cancel of [...state.cancellations]) cancel()
  state.cancellations.clear()
  const retainedSlots = state.queue.filter(slot => slot.submitted || slot.handedOff)
  const retained = new Set([
    ...retainedSlots.map(slot => slot.id),
    ...[...state.dismissedOperations].map(slot => slot.id),
  ])
  const visible = state.visible && retained.has(state.visible.id) ? state.visible : null
  state.queue.splice(0, state.queue.length, ...retainedSlots)
  retainOnly(state.observationSlots, retained)
  retainOnly(state.results, retained)
  state.visible = visible
  state.replayClaims.clear()
  if (state.dialog.open && !visible) {
    state.ignoreNextClose = true
    state.dialog.close()
  } else {
    presentNext(root, state)
  }
}

function currentSlot(state: StakeState, slot: ResultSlot): boolean {
  return state.alive && state.generation === slot.generation && state.queue.includes(slot)
}

function liveSlot(state: StakeState, slot: ResultSlot): boolean {
  return state.alive && (state.queue.includes(slot) || state.dismissedOperations.has(slot))
}

function restoreDismissedSlot(state: StakeState, slot: ResultSlot): void {
  if (state.dismissedOperations.delete(slot)) state.queue.push(slot)
}

function settleImmediate(root: HTMLElement, state: StakeState, slot: ResultSlot, message: string): void {
  if (!liveSlot(state, slot)) return
  const display: ResultDisplay = Object.freeze({
    title: `${roleLabel(slot.action)} not completed`,
    message,
    detail: "No confirmed Base transaction changed your staking position.",
    href: null,
    tone: "error",
  })
  state.results.set(slot.id, display)
  presentOrUpdate(root, state, slot, display)
}

function settleObserved(
  hook: StakeHook,
  state: StakeState,
  slot: ResultSlot,
  result: TransactionResult,
): void {
  if (!liveSlot(state, slot) || state.observationSlots.get(slot.id) !== slot) return
  state.observationSlots.delete(slot.id)
  restoreDismissedSlot(state, slot)
  const href = slot.submitted
    ? `https://basescan.org/tx/${slot.submitted.hash}`
    : null
  const label = slot.role === "approval" ? "REGENT approval" : roleLabel(slot.action)
  const display: ResultDisplay = result === "success"
    ? {
        title: `${label} confirmed`,
        message: successMessage(slot),
        detail: "Your position is refreshing in place from the latest Base block.",
        href,
        tone: "success",
      }
    : result === "reverted"
      ? {
          title: `${label} reverted`,
          message: "Base included the transaction, but the contract reverted it.",
          detail: "Your confirmed staking position did not change.",
          href,
          tone: "error",
        }
      : result === "delayed"
        ? {
            title: "Confirmation is taking longer",
            message: "The wallet returned a transaction hash, but Base has not confirmed it yet.",
            detail: "Use the BaseScan link to follow the transaction without losing the page state.",
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
  if (result === "success" && sameAddress(slot.signer, state.wallet?.address)) {
    hook.pushEvent("refresh_staking", {})
  }
  presentOrUpdate(hook.el, state, slot, display)
}

function updateSubmittedResult(
  root: HTMLElement,
  state: StakeState,
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
  state: StakeState,
  slot: ResultSlot,
  display: ResultDisplay,
): void {
  if (state.visible === slot) renderResult(state, display, slot.signer)
  else presentNext(root, state)
}

function presentNext(root: HTMLElement, state: StakeState): void {
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

function successMessage(slot: ResultSlot): string {
  if (slot.role === "approval") return "REGENT spending was approved successfully."
  const amount = slot.amount.trim()
  switch (slot.action) {
    case "stake": return `${amount} REGENT was staked successfully.`
    case "unstake": return `${amount} REGENT was returned to your wallet.`
    case "claim_usdc": return "Your available USDC rewards were claimed."
    case "claim_regent": return "Your available REGENT rewards were claimed."
    case "claim_and_restake_regent": return "Your available REGENT rewards were added to your stake."
  }
}

type TransactionResult = "success" | "reverted" | "delayed" | "unavailable"

function transactionResult(value: unknown): value is TransactionResult {
  return value === "success" || value === "reverted" || value === "delayed" || value === "unavailable"
}

function observation(id: string, submitted: SubmittedStakingTransaction) {
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

function restoreFocus(root: HTMLElement, initiator: HTMLElement): void {
  if (focusable(initiator)) {
    initiator.focus()
    return
  }
  root.querySelector<HTMLElement>("#staking-page-heading")?.focus()
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

function requiredElement<T extends Element>(root: ParentNode, selector: string): T {
  const element = root.querySelector<T>(selector)
  if (!element) throw new Error(`Stake hook is missing ${selector}`)
  return element
}

function stakingAction(value: string | undefined): value is StakingAction {
  return typeof value === "string" && stakingActions.has(value as StakingAction)
}

function roleLabel(action: StakingAction): string {
  switch (action) {
    case "stake": return "Stake"
    case "unstake": return "Unstake"
    case "claim_usdc": return "USDC claim"
    case "claim_regent": return "REGENT claim"
    case "claim_and_restake_regent": return "Claim and restake"
  }
}

function elapsed(startedAt: number): number {
  return Math.round(Math.max(0, performance.now() - startedAt) * 100) / 100
}

function logTiming(event: StakingTiming): void {
  console.info("[stake-wallet-timing]", event)
}
