import type {Address, Hex} from "viem"

import type {Hook} from "../hook_composition"
import {report} from "../visit_log"
import {leave} from "./motion/moments"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import type {EthereumProvider} from "../wallet_actions/connected_wallet"
import {
  failure,
  landedCalls,
  NothingSent,
  refusedAtomic,
  sendStep,
  sendSteps,
  sendsAtomically,
  signStep,
  type Step,
  type StepChain,
} from "../wallet_actions/send_step"

/**
 * Who sends, on which chain, the steps the buttons name, and the on-screen
 * inputs they were built from, all on the server. It never changes: a new
 * figure is a new review with a new id.
 */
export type Review = {
  id: string
  component_id: string
  signer: Address
  chain: StepChain
  steps: Step[]
  inputs: Record<string, string>
}

// Settles once the server has answered and the page shows the answer, so a
// button goes straight from waiting on the wallet to confirming.
type Push = (event: string, payload: unknown) => Promise<void>

type OnchainStepsHook = Hook & {
  el: HTMLElement
  js(): {ignoreAttributes(el: HTMLElement, attrs: string[]): void}
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEventTo(target: HTMLElement, event: string, payload?: unknown): Promise<PromiseSettledResult<{reply: unknown}>[]>
  review?: Review
  clicked?: (event: Event) => void
  refresh?: () => void
  walletChanged?: () => void
  leaving?: AbortController
}

// How many of a button's presses the wallet still has. The mark comes off when
// the last one is answered.
const presses = new WeakMap<HTMLElement, number>()

/**
 * The wallet buttons of one server component. The component's root carries the
 * hook and a DOM id; each button names its step with `data-onchain-step`, and
 * each form field the review depends on is marked `data-onchain-input="name"`.
 */
export const OnchainSteps: Hook = {
  mounted(this: OnchainStepsHook) {
    const push: Push = (event, payload) =>
      this.pushEventTo(this.el, event, payload).then(() => undefined, () => undefined)
    const leaving = this.leaving = new AbortController()
    let capabilityRead = 0
    const checkAtomic = async () => {
      const read = ++capabilityRead
      const review = this.review
      if (!review || !this.el.hasAttribute("data-onchain-bundle") || review.steps.length < 2 ||
          !review.steps.every(step => step.kind === "transaction")) return
      const wallet = signerWallet(review)
      const atomic = wallet ? await sendsAtomically(review.chain, review.signer, wallet.provider) : false
      if (!leaving.signal.aborted && read === capabilityRead) {
        void push("onchain_atomic", {review_id: review.id, atomic})
      }
    }

    // Every hook on the page hears this event; keep only this component's review.
    // No review means signed out: a press then sends nothing.
    this.handleEvent("onchain-steps:review", payload => {
      const {component_id, review} = payload as {component_id: string; review: Review | null}
      if (component_id !== this.el.id) return
      this.review = review ?? undefined
      void checkAtomic()
    })

    // Every press runs on its own and reaches the wallet, even while an earlier
    // one is still there. On a component with review inputs, a press with no
    // review yet, or whose review no longer matches the form on screen, asks the
    // server for the matching review and sends what comes back.
    this.clicked = event => {
      const button = (event.target as Element | null)?.closest<HTMLElement>(
        "[data-onchain-step], button[data-onchain-bundle]",
      )
      if (!button || !this.el.contains(button)) return
      if (button.hasAttribute("data-onchain-bundle") && this.el.hasAttribute("data-onchain-bundle")) {
        this.js().ignoreAttributes(button, ["data-awaiting-wallet"])
        const release = mark(button)
        void pressCalls(this.review, push, leaving.signal).finally(release)
        return
      }
      const name = button.dataset.onchainStep
      if (!name) return
      // The mark is this island's own, so a page update while the wallet has the
      // press leaves it on the button.
      this.js().ignoreAttributes(button, ["data-awaiting-wallet"])
      const release = mark(button)
      const form = formInputs(this.el)
      const wallet = activeEthereumWallet()
      const asks =
        !this.review?.steps.some(step => step.step === name) ||
        (Object.keys(form).length > 0 && !sameInputs(this.review.inputs, form))
      lost(this.el, false)
      // The server never heard the press, so it cannot say why; the page does, and
      // reports it.
      const unheard = () => {
        lost(this.el, true)
        report({name: "press.unsent", where: name, outcome: "lost"})
      }
      const refreshAfter = () => {
        if ("refreshFunds" in this.el.dataset) {
          void push("refresh_funds", {address: activeEthereumWallet()?.address ?? null})
        }
      }

      if (wallet && asks) {
        void this.pushEventTo(this.el, "prepare_and_send", {
          form,
          step: name,
          wallet: wallet.address,
        })
          .then(([result]) => {
            if (result?.status !== "fulfilled") return unheard()
            const reply = result.value.reply as {review?: Review; send?: string; reason?: string}
            if (reply.review && reply.send) return press(reply.review, reply.send, push)
            if (reply.reason === "blocked") return undefined
            return push("step_failed", {step: name, reason: "step_unknown"})
          })
          // A lost connection drops the question; the button comes back to press again.
          .catch(unheard)
          .finally(() => {
            release()
            refreshAfter()
          })
      } else {
        void push("step_pressed", {step: name, form})
        void press(this.review, name, push).finally(() => {
          release()
          refreshAfter()
        })
      }
    }
    this.el.addEventListener("click", this.clicked)

    // The panel follows the active wallet and rechecks batch support when it changes.
    this.walletChanged = () => {
      const address = activeEthereumWallet()?.address ?? null
      void push("onchain_active_wallet", {address})
      if ("refreshFunds" in this.el.dataset) void push("refresh_funds", {address})
      void checkAtomic()
    }
    window.addEventListener("ash:wallet-state", this.walletChanged)

    if ("refreshFunds" in this.el.dataset) {
      this.refresh = () => {
        if (document.visibilityState === "hidden") return
        void push("refresh_funds", {address: activeEthereumWallet()?.address ?? null})
      }
      document.addEventListener("visibilitychange", this.refresh)
      this.el.addEventListener("ash:refresh-funds", this.refresh)
    }

    this.walletChanged()
    window.dispatchEvent(new CustomEvent("ash:wallet-sync"))
  },

  destroyed(this: OnchainStepsHook) {
    this.leaving?.abort()
    if (this.clicked) this.el.removeEventListener("click", this.clicked)
    if (this.walletChanged) window.removeEventListener("ash:wallet-state", this.walletChanged)
    if (this.refresh) {
      document.removeEventListener("visibilitychange", this.refresh)
      this.el.removeEventListener("ash:refresh-funds", this.refresh)
    }
  },
}

/**
 * Sends or signs the named step from the review's signer when it is Privy's
 * active wallet. While another wallet or none is
 * active, the press sends nothing and the server's note names the right wallet. Reports only what the wallet
 * answered, against the review it sent from: the hash or signature, or why
 * nothing was sent. The server decides what the hash did.
 */
export async function press(review: Review | undefined, name: string, push: Push): Promise<void> {
  const step = review?.steps.find(candidate => candidate.step === name)
  let sending = false
  const started = () => {
    sending = true
  }

  try {
    if (!review) throw new NothingSent("step_unknown")
    const wallet = () => signerWallet(review)
    if (!wallet()) throw new NothingSent("wallet_unavailable")
    if (!step) throw new NothingSent("step_unknown")

    if (step.kind === "signature") {
      const signature: Hex = await signStep(review.chain, review.signer, step, wallet, started)
      await push("step_signed", {review_id: review.id, step: name, signature})
    } else {
      const transaction_hash = await sendStep(review.chain, review.signer, step, wallet, started)
      await push("step_sent", {review_id: review.id, step: name, transaction_hash})
    }
  } catch (error) {
    await push("step_failed", {step: name, reason: failure(sending, error)})
  }
}

async function pressCalls(review: Review | undefined, push: Push, leaving: AbortSignal): Promise<void> {
  let sending = false
  let sent
  try {
    if (!review) throw new NothingSent("step_unknown")
    const steps = review.steps.filter(step => step.kind === "transaction")
    if (steps.length < 2 || steps.length !== review.steps.length) throw new NothingSent("step_unknown")
    sent = await sendSteps(review.chain, review.signer, steps, () => signerWallet(review), () => {
      sending = true
    })
  } catch (error) {
    if (review && sending && refusedAtomic(error)) {
      await push("onchain_atomic", {review_id: review.id, atomic: false, refused: true})
    } else {
      await push("step_failed", {step: "calls", reason: failure(sending, error)})
    }
    return
  }

  const calls_id = sent.id
  await push("calls_sent", {review_id: review.id, calls_id})
  if (!leaving.aborted) void followCalls(review.signer, sent.provider, calls_id, push, leaving)
}

async function followCalls(
  signer: Address,
  provider: EthereumProvider,
  calls_id: string,
  push: Push,
  leaving: AbortSignal,
): Promise<void> {
  const landed = await landedCalls(signer, provider, calls_id, leaving)
  if (leaving.aborted) return
  const [transaction_hash, ...other] = landed?.hashes ?? []
  if (transaction_hash && other.length === 0) {
    await push("calls_landed", {calls_id, transaction_hash})
  } else if (landed?.status === "failure" && !transaction_hash) {
    await push("calls_failed", {calls_id})
  } else {
    await push("calls_unconfirmed", {calls_id})
  }
}

function signerWallet(review: Review) {
  const active = activeEthereumWallet()
  return active?.address.toLowerCase() === review.signer.toLowerCase() ? active : null
}

/**
 * The review's inputs as they are on screen now: text as typed, a box as
 * "true" or "false", and a group of choices as the one chosen.
 */
export function formInputs(root: HTMLElement): Record<string, string> {
  const inputs: Record<string, string> = {}
  root.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-onchain-input]").forEach(input => {
    const name = input.dataset.onchainInput
    if (!name) return
    if (input instanceof HTMLInputElement && input.type === "radio") {
      if (input.checked) inputs[name] = input.value
    } else {
      inputs[name] = input instanceof HTMLInputElement && input.type === "checkbox" ? String(input.checked) : input.value
    }
  })
  return inputs
}

function sameInputs(review: Record<string, string>, form: Record<string, string>): boolean {
  const names = new Set([...Object.keys(review), ...Object.keys(form)])
  return [...names].every(name => review[name] === form[name])
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

// The component's `data-onchain-lost` line, shown when a press could not reach
// the server. The next press fades it out; a render from the server hides it at
// once.
function lost(root: HTMLElement, shown: boolean): void {
  const line = root.querySelector<HTMLElement>("[data-onchain-lost]")
  if (!line) return
  if (!shown && !line.hidden) leave(line, line.parentElement)
  line.hidden = !shown
}
