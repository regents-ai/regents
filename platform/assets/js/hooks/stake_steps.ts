import type {Address} from "viem"

import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {failure, NothingSent, sendStep, type Step, type StepChain} from "../wallet_actions/send_step"

/** What was on the Stake form when the server built the review. */
export type Inputs = {action: string; amount: string; for_other: boolean; receiver: string; acknowledged: boolean}

/** Who sends, on which chain, and the steps the page's buttons name, all built on the server. */
export type Review = {
  component_id: string
  signer: Address
  chain: StepChain
  steps: Step[]
  inputs: Inputs
}

/** The server's answer to a press ahead of the form: the review for it and the step to send, or nothing. */
type Prepared = {review?: Review; send?: string}

type Push = (event: string, payload: unknown) => void

type StakeStepsHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): Promise<unknown>
  review?: Review
  clicked?: (event: Event) => void
  walletChanged?: () => void
}

// How many of a button's presses the wallet still has. The mark comes off when
// the last one is answered.
const presses = new WeakMap<HTMLElement, number>()

export const StakeSteps: Hook = {
  mounted(this: StakeStepsHook) {
    const push: Push = (event, payload) => void this.pushEvent(event, payload)

    // Every hook on the page hears this event; keep only this page's review.
    this.handleEvent("onchain-steps:review", payload => {
      const review = payload as Review
      if (review.component_id === this.el.id) this.review = review
    })

    // Every press runs on its own and reaches the wallet, even while an earlier
    // one is still there. A press on the form's button whose review no longer
    // matches the form asks the server for the matching step and sends what
    // comes back. With no wallet active, the press opens the connect step.
    this.clicked = event => {
      const button = (event.target as Element | null)?.closest<HTMLElement>("[data-onchain-step]")
      const name = button?.dataset.onchainStep
      if (!button || !name) return
      const release = mark(button)
      const form = button.dataset.onchainForm === undefined ? null : formInputs(this.el)

      if (form && activeEthereumWallet() && !sameInputs(this.review?.inputs, form)) {
        void this.pushEvent("prepare_and_send", {form})
          .then(reply => {
            const {review, send} = reply as Prepared
            if (review && send) return press(review, send, push)
          })
          // A lost connection drops the question; the button comes back to press again.
          .catch(() => {})
          .finally(release)
      } else {
        void press(this.review, name, push).finally(release)
      }
    }
    this.el.addEventListener("click", this.clicked)

    // Signed out, the figures shown are for the wallet the wallet app has open.
    this.walletChanged = () => push("staking_active_wallet", {address: activeEthereumWallet()?.address ?? null})
    window.addEventListener("ash:wallet-state", this.walletChanged)
    this.walletChanged()
    window.dispatchEvent(new CustomEvent("ash:wallet-sync"))
  },

  destroyed(this: StakeStepsHook) {
    if (this.clicked) this.el.removeEventListener("click", this.clicked)
    if (this.walletChanged) window.removeEventListener("ash:wallet-state", this.walletChanged)
  },
}

/**
 * Sends the named step from Privy's active wallet, the only wallet that acts,
 * when it is the signer the server built the step for. Reports only what the
 * wallet answered: the hash and the calldata it carried, or why nothing was
 * sent. The server decides what the hash did.
 */
export async function press(review: Review | undefined, name: string, push: Push): Promise<void> {
  const step = review?.steps.find(candidate => candidate.step === name)
  let sending = false

  try {
    if (!activeEthereumWallet()) {
      window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
      throw new NothingSent("wallet_unavailable")
    }
    if (!review || !step) throw new NothingSent("step_unknown")
    const wallet = () => {
      const active = activeEthereumWallet()
      return active?.address.toLowerCase() === review.signer.toLowerCase() ? active : null
    }
    if (!wallet()) throw new NothingSent("wallet_unavailable")

    const transaction_hash = await sendStep(review.chain, review.signer, step, wallet, () => {
      sending = true
    })
    push("step_sent", {step: name, transaction_hash, data: step.data, from: review.signer})
  } catch (error) {
    push("step_failed", {step: name, reason: failure(sending, error)})
  }
}

/** The Stake form as it is on screen now. */
export function formInputs(root: HTMLElement): Inputs {
  const input = (id: string) => root.querySelector<HTMLInputElement>(`#${id}`)
  const forOther = input("staking-for-other")?.checked ?? false

  return {
    action: root.dataset.stakingMode ?? "",
    amount: input("staking-amount")?.value ?? "",
    for_other: forOther,
    receiver: input("staking-recipient")?.value ?? "",
    acknowledged: forOther && (input("staking-recipient-acknowledged")?.checked ?? false),
  }
}

function sameInputs(review: Inputs | undefined, form: Inputs): boolean {
  return !!review &&
    review.action === form.action &&
    review.amount === form.amount &&
    review.for_other === form.for_other &&
    review.receiver === form.receiver &&
    review.acknowledged === form.acknowledged
}

// Marked with a data attribute and CSS only: the button keeps taking presses.
function mark(button: HTMLElement): () => void {
  presses.set(button, (presses.get(button) ?? 0) + 1)
  button.dataset.awaitingWallet = "true"

  return () => {
    const left = (presses.get(button) ?? 1) - 1
    presses.set(button, left)
    if (left <= 0) delete button.dataset.awaitingWallet
  }
}
