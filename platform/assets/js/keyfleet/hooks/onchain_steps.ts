import type {Address, Hash, Hex} from "viem"

import type {Hook} from "../../hook_composition"
import {report} from "../../visit_log"
import {activeEthereumWallet, type SelectedWallet} from "../../wallet_actions/connected_wallet"
import {
  failure,
  NothingSent,
  sendStep,
  signStep,
  type Failure,
  type Step,
  type StepChain,
} from "../../wallet_actions/send_step"

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

/**
 * A press the server refused to prepare, with the note it shows the person for
 * it: one the chain's state makes certain to fail ("blocked"), in the words
 * beside its button, or any other ("step_unknown"); and its cause, "values"
 * when a value the press was built from is why, or "state" when the chain's or
 * the page's own state alone is.
 */
export type Refused = {reason: "step_unknown" | "blocked"; cause: "values" | "state"; note: string}

/**
 * What the wallet answered one press: the hash or signature, or why nothing was
 * sent, or may have been; or the server's refusal.
 */
export type Pressed = {transaction_hash: Hash} | {signature: Hex} | {reason: Failure} | Refused

/** A press of one of the group's buttons with the form it reads; "lost" when the page lost its connection. */
export type PressButton = (button: HTMLElement, form: Record<string, string>) => Promise<Pressed | "lost">

// The server event a press asks for its steps with: the person's takes the
// form as the page's own, and the browser agent's builds the agent's values
// for that press alone.
type Ask = "prepare_and_send" | "prepare_for_agent"

type Push = (event: string, payload: unknown) => void

type OnchainStepsHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEventTo(target: HTMLElement, event: string, payload?: unknown): Promise<PromiseSettledResult<{reply: unknown}>[]>
  review?: Review
  clicked?: (event: Event) => void
  pressButton?: PressButton
  refresh?: () => void
  walletChanged?: () => void
}

// How many of a button's presses the wallet still has. The mark comes off when
// the last one is answered.
const presses = new WeakMap<HTMLElement, number>()

/**
 * The wallet buttons of one server component. The component's root carries the
 * hook and a DOM id; each button names its step with `data-onchain-step`, and
 * each form field the review depends on is marked `data-onchain-input="name"`.
 * A root marked `data-refresh-funds` also asks the server to read its funds
 * again (`refresh_funds`) when the wallet changes, when the page comes back
 * into view, when the panel holding it opens (`ash:refresh-funds` on the root)
 * and after each press.
 */
export const OnchainSteps: Hook = {
  mounted(this: OnchainStepsHook) {
    // A press that outlives its panel ends quietly.
    const push: Push = (event, payload) =>
      this.pushEventTo(this.el, event, payload).then(() => undefined, () => undefined)

    // Every hook on the page hears this event; keep only this component's review.
    // No review means none is built yet, or no wallet may send.
    this.handleEvent("onchain-steps:review", payload => {
      const {component_id, review} = payload as {component_id: string; review: Review | null}
      if (component_id === this.el.id) this.review = review ?? undefined
    })

    // Every press runs on its own and reaches the wallet, even while an earlier
    // one is still there. A press whose step isn't on the page yet, whose
    // review no longer matches the form, or whose button the chain's state
    // holds back, asks the server for the matching review and sends what comes
    // back. The browser's own agent presses the same way, with its values over
    // the form's, and the server judges those values. All its press tells the
    // server is marked as the agent's, and the agent hears every answer in its
    // own: the person's form, the note below their buttons and the line saying
    // the page lost its connection stay as they are.
    const pressWith = async (button: HTMLElement, form: Record<string, string>, ask: Ask): Promise<Pressed | "lost"> => {
      const name = button.dataset.onchainStep!
      const agent = ask === "prepare_for_agent"
      const tell: Push = agent ? (event, payload) => push(event, {...(payload as object), agent: true}) : push
      const release = mark(button)
      const wallet = activeEthereumWallet()
      const asks =
        (button as HTMLButtonElement).disabled === true ||
        asksServer(this.review, name, form) ||
        // Steps held for another wallet than the one open at the press are asked
        // for again, built for the open one: the steps sent always go to the
        // wallet they were built for.
        this.review?.signer.toLowerCase() !== wallet?.address.toLowerCase()
      // The lost line speaks for the person's own presses alone.
      if (!agent) lost(this.el, false)
      // The server hears the press, and the form it was made from, just before
      // the wallet does and once its steps are built from that form: a
      // proposal's words are saved then. The press never waits on this. With
      // no wallet open no wallet is asked, so the press is not heard: no words
      // are saved and the form keeps what was typed, the person's press or the
      // agent's.
      const heard = () => tell("step_pressed", {step: name, form})

      try {
        if (!wallet) return await press(this.review, name, null, tell)
        if (!asks) {
          heard()
          return await press(this.review, name, wallet, tell)
        }
        // The ask names the open wallet: a page that has just joined again can ask
        // before the server has heard which wallet is open. The steps that come
        // back are built for that wallet, and are sent only while it is still
        // the one open.
        const [result] = await this.pushEventTo(this.el, ask, {form, step: name, address: wallet.address})
        if (result?.status !== "fulfilled") return lostPress(this.el, name, agent)
        const reply = result.value.reply as {review: Review; send: string} | Refused
        // Refused: the reply says why. For the person's press the server has
        // already written the same note below the buttons; the agent hears it
        // alone.
        if ("note" in reply) return reply
        // The agent's steps were built from the agent's values alone, and the
        // server has already done what hearing that press does.
        if (!agent) heard()
        return await press(reply.review, reply.send, wallet, tell)
      } catch {
        return lostPress(this.el, name, agent)
      } finally {
        release()
        // The press may have spent funds or changed what the wallet allows.
        this.refresh?.()
      }
    }
    this.pressButton = (button, form) => pressWith(button, form, "prepare_and_send")

    // Signed out, a button carries the page's sign-in mark, and its press
    // opens sign-in instead (auth_lazy.ts).
    this.clicked = event => {
      const button = (event.target as Element | null)?.closest<HTMLElement>("[data-onchain-step]")
      if (!button?.dataset.onchainStep || !this.el.contains(button)) return
      if (button.dataset.accountTarget === "sign-in") return
      void this.pressButton!(button, formInputs(this.el))
    }
    this.el.addEventListener("click", this.clicked)

    // The server decides which wallet may act; it hears every change of the
    // wallet Privy has active and pushes a new review, or none.
    this.walletChanged = () => push("onchain_active_wallet", {address: activeEthereumWallet()?.address ?? null})
    window.addEventListener("ash:wallet-state", this.walletChanged)
    this.walletChanged()

    if (this.el.hasAttribute("data-refresh-funds")) {
      this.refresh = () => push("refresh_funds", {})
      window.addEventListener("ash:wallet-state", this.refresh)
      window.addEventListener("focus", this.refresh)
      this.el.addEventListener("ash:refresh-funds", this.refresh)
      this.refresh()
    }
    window.dispatchEvent(new CustomEvent("ash:wallet-sync"))
  },

  // A page that rejoins gets a fresh component on the server, which no longer
  // knows the active wallet or the review this hook holds. The review is let go
  // and the wallet told again, so the next press is sent from a review the
  // server remembers. The rejoin redraws the component, which hides its lost
  // line: that press was made before the page was back.
  reconnected(this: OnchainStepsHook) {
    this.review = undefined
    this.walletChanged?.()
  },

  destroyed(this: OnchainStepsHook) {
    if (this.clicked) this.el.removeEventListener("click", this.clicked)
    if (this.walletChanged) window.removeEventListener("ash:wallet-state", this.walletChanged)
    if (this.refresh) {
      window.removeEventListener("ash:wallet-state", this.refresh)
      window.removeEventListener("focus", this.refresh)
      this.el.removeEventListener("ash:refresh-funds", this.refresh)
    }
  },
}

/**
 * Sends or signs the named step from the review's signer, through the wallet
 * open when the wallet is asked: Privy's active wallet, read then, while it is
 * the review's signer. When another wallet, or none, is open by then, the
 * site's own checks send nothing and say why. With no wallet open at the press
 * (`wallet` is null), it sends nothing and reports why. Reports only what the
 * wallet answered, against the review it sent from: the hash or signature, or
 * why nothing was sent, and returns the same answer. The server decides what
 * the hash did.
 */
export async function press(
  review: Review | undefined,
  name: string,
  wallet: SelectedWallet | null,
  push: Push,
): Promise<Pressed> {
  const step = review?.steps.find(candidate => candidate.step === name)
  let sending = false
  const started = () => {
    sending = true
  }

  try {
    if (!wallet) throw new NothingSent("wallet_unavailable")
    if (!review || !step) throw new NothingSent("step_unknown")
    // The site's send reads its wallet each time it asks, as the site's own
    // hook gives it: the open wallet while it is the review's signer, and none
    // otherwise.
    const signer = review.signer.toLowerCase()
    const open = () => {
      const active = activeEthereumWallet()
      return active?.address.toLowerCase() === signer ? active : null
    }

    if (step.kind === "signature") {
      const signature = await signStep(review.chain, review.signer, step, open, started)
      push("step_signed", {review_id: review.id, step: name, signature})
      return {signature}
    }
    const transaction_hash = await sendStep(review.chain, review.signer, step, open, started)
    push("step_sent", {review_id: review.id, step: name, transaction_hash})
    return {transaction_hash}
  } catch (error) {
    const reason = failure(sending, error)
    push("step_failed", {step: name, reason})
    return {reason}
  }
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

/**
 * Whether a press must ask the server for its review first: its step isn't in
 * the review on the page (none has arrived yet, as when the button has just
 * appeared), or the review was built from other inputs than the form shows.
 */
export function asksServer(review: Review | undefined, name: string, form: Record<string, string>): boolean {
  if (!review?.steps.some(step => step.step === name)) return true
  return Object.keys(form).length > 0 && !sameInputs(review.inputs, form)
}

function sameInputs(review: Record<string, string>, form: Record<string, string>): boolean {
  const names = new Set([...Object.keys(review), ...Object.keys(form)])
  return [...names].every(name => review[name] === form[name])
}

// The component's `data-onchain-lost` line, shown when the person's own press
// could not reach the server, and hidden by their next press. The next render
// from the server hides it again.
function lost(root: HTMLElement, shown: boolean): void {
  const line = root.querySelector<HTMLElement>("[data-onchain-lost]")
  if (line) line.hidden = !shown
}

// A press that could not reach the server: the answer says so, and for the
// person's own press so does the page. The server never heard the press, so it
// cannot say why; the page reports it, the agent's marked as the agent's.
function lostPress(root: HTMLElement, step: string, agent: boolean): "lost" {
  if (!agent) lost(root, true)
  report({name: "press.unsent", where: step, outcome: "lost", ...(agent ? {agent: true as const} : {})})
  return "lost"
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
