import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  executeStakingClick,
  observeStakingTransaction,
  prepareStakingClick,
  StakingLocalRefusal,
  type ImmediateStakingResult,
  type ObservedStakingResult,
  type StakingAction,
  type StakingRuntime,
  type StakingTiming,
  type StakingTransactionRole,
  type SubmittedStakingTransaction,
} from "../wallet_actions/staking"

type ResultDisplay = Readonly<{message: string; href: string | null}>
type ResultSlot = {
  readonly id: string
  readonly action: StakingAction
  readonly role: "action"
  readonly initiator: HTMLElement
  readonly submitted: SubmittedStakingTransaction | null
}

type StakeState = {
  alive: boolean
  cancellations: Set<() => void>
  replayClaims: Set<string>
  walletRequests: Set<string>
  actionIds: Set<string>
  observationSlots: Map<string, ResultSlot>
  results: Map<string, ResultDisplay>
  queue: ResultSlot[]
  visible: ResultSlot | null
  dialog: HTMLDialogElement
  text: HTMLElement
  link: HTMLAnchorElement
  click: (event: MouseEvent) => void
  close: () => void
  cancel: (event: Event) => void
  publishActiveWallet: () => void
}

type StakeHook = Hook & {
  el: HTMLElement
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
      cancellations: new Set(),
      replayClaims: new Set(),
      walletRequests: new Set(),
      actionIds: new Set(),
      observationSlots: new Map(),
      results: new Map(),
      queue: [],
      visible: null,
      dialog,
      text: requiredElement(dialog, "[data-staking-result-text]"),
      link: requiredElement<HTMLAnchorElement>(dialog, "[data-staking-result-link]"),
      click: () => undefined,
      close: () => undefined,
      cancel: () => undefined,
      publishActiveWallet: () =>
        this.pushEvent("staking_active_wallet", {address: activeEthereumWallet()?.address ?? null}),
    }
    this.stakeState = state
    const runtime = runtimeFor(state)

    const reserve = (slot: ResultSlot, display?: ResultDisplay): void => {
      if (!state.alive) return
      state.queue.push(slot)
      if (display) state.results.set(slot.id, display)
      if (slot.submitted) state.observationSlots.set(slot.id, slot)
      presentNext(this.el, state)
    }

    const callbacksFor = (initiator: HTMLElement) => ({
      claimRole: (actionId: string, role: StakingTransactionRole): boolean => {
        const key = `${actionId}:${role}`
        if (!state.alive || state.replayClaims.has(key)) return false
        state.replayClaims.add(key)
        return true
      },
      timing: logTiming,
      walletRequestStarted: (actionId: string, role: StakingTransactionRole): void => {
        state.walletRequests.add(`${actionId}:${role}`)
      },
      immediate: (result: ImmediateStakingResult): void => {
        // Approval is a wallet prerequisite, not a Regent result surface.
        if (result.role === "approval") return
        reserve(
          Object.freeze({
            id: crypto.randomUUID(),
            action: result.action,
            role: result.role,
            initiator,
            submitted: null,
          }),
          Object.freeze({message: result.message, href: null}),
        )
      },
      submitted: (submitted: SubmittedStakingTransaction): void => {
        // The valid hash still unlocks the main send; it is not presented or observed here.
        if (submitted.role === "approval") return
        const slot: ResultSlot = Object.freeze({
          id: crypto.randomUUID(),
          action: submitted.action,
          role: submitted.role,
          initiator,
          submitted,
        })
        reserve(slot)
        observeStakingTransaction(submitted, runtime, result => {
          settleObserved(this, state, slot, result)
        })
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

      const clickedAt = performance.now()
      const traceId = crypto.randomUUID()
      const actionId = crypto.randomUUID()
      const role: StakingTransactionRole = "action"
      state.actionIds.add(actionId)

      try {
        const click = prepareStakingClick(
          {
            action,
            amount: this.el.querySelector<HTMLInputElement>("#staking-amount")?.value ?? "",
            allowanceAtomic: this.el.dataset.stakingAllowance ?? "",
            chainId: this.el.dataset.stakingChainId ?? "",
            expectedSigner: this.el.dataset.stakingSigner ?? "",
          },
          activeEthereumWallet(),
          {actionId, traceId},
        )
        logTiming({
          trace_id: traceId,
          action,
          role,
          phase: "click_to_local_ready",
          milliseconds: elapsed(clickedAt),
        })
        void executeStakingClick(click, callbacksFor(initiator), runtime)
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
        reserve(
          Object.freeze({
            id: crypto.randomUUID(),
            action,
            role,
            initiator,
            submitted: null,
          }),
          Object.freeze({message, href: null}),
        )
      }
    }

    state.close = () => {
      if (!state.alive || !state.visible) return
      const closed = state.visible
      state.visible = null
      const head = state.queue[0]
      if (head === closed) state.queue.shift()
      state.observationSlots.delete(closed.id)
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
  },

  destroyed(this: StakeHook) {
    const state = this.stakeState
    if (!state) return
    state.alive = false
    for (const cancel of [...state.cancellations]) cancel()
    state.cancellations.clear()
    this.el.removeEventListener("click", state.click)
    state.dialog.removeEventListener("close", state.close)
    state.dialog.removeEventListener("cancel", state.cancel)
    window.removeEventListener("ash:wallet-state", state.publishActiveWallet)
    if (state.dialog.open) state.dialog.close()
    state.replayClaims.clear()
    state.walletRequests.clear()
    state.actionIds.clear()
    state.observationSlots.clear()
    state.results.clear()
    state.queue.length = 0
    state.visible = null
    this.stakeState = undefined
  },
}

function runtimeFor(state: StakeState): StakingRuntime {
  return {
    alive: () => state.alive,
    registerCancellation: cancel => {
      if (!state.alive) {
        cancel()
        return () => undefined
      }
      state.cancellations.add(cancel)
      return () => state.cancellations.delete(cancel)
    },
  }
}

function settleObserved(
  hook: StakeHook,
  state: StakeState,
  slot: ResultSlot,
  result: ObservedStakingResult,
): void {
  if (!state.alive || state.results.has(slot.id) || state.observationSlots.get(slot.id) !== slot) return
  const href =
    (result === "success" || result === "reverted") && slot.submitted
      ? `https://basescan.org/tx/${slot.submitted.hash}`
      : null
  const label = roleLabel(slot.action)
  const message =
    result === "success"
      ? `${label} succeeded on Base.`
      : result === "reverted"
        ? `${label} reverted on Base.`
        : result === "delayed"
          ? "Block inclusion is delayed."
          : "Verification is unavailable."
  state.results.set(slot.id, Object.freeze({message, href}))
  if (result === "success") hook.pushEvent("refresh_staking", {})
  presentNext(hook.el, state)
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

  state.text.textContent = ""
  state.link.textContent = ""
  state.link.removeAttribute("href")
  state.link.hidden = true
  state.text.textContent = display.message
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
