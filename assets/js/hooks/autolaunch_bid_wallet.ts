import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  sendBidStep,
  sendableStep,
  userRejected,
  type BidOperation,
} from "../wallet_actions/autolaunch_bids"

const pendingKey = "regent:autolaunch-bid:open"

// The closed set of failures this surface can describe. Provider, viem, revert
// and wallet-vendor text is never a customer message, so it is never sent.
type FailureReason = "wallet_unavailable" | "unknown"

type BidHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEventTo(target: HTMLElement, event: string, payload: unknown): void
  publishActiveWallet?: () => void
}

export const AutolaunchBidWallet: Hook = {
  mounted(this: BidHook) {
    let operation: BidOperation | null = null
    let sending = false

    const push = (event: string, payload: unknown) => this.pushEventTo(this.el, event, payload)
    const failed = (reason: FailureReason) => push("bid_wallet_failed", {reason})

    // Privy's selection is what the bidder reads, so every change is republished
    // and the server decides what that wallet is allowed to see.
    this.publishActiveWallet = () =>
      push("bid_active_wallet", {address: activeEthereumWallet()?.address ?? null})
    window.addEventListener("ash:wallet-state", this.publishActiveWallet)
    this.publishActiveWallet()

    if (sessionStorage.getItem(pendingKey)) push("restore_bid_operation", {})

    this.handleEvent("autolaunch-bid:operation", payload => {
      operation = payload as BidOperation
      rememberOperation(operation, sessionStorage)
    })

    this.handleEvent("autolaunch-bid:cleared", () => {
      operation = null
      sessionStorage.removeItem(pendingKey)
    })

    // A claim is only asked for once the wallet in front of the customer really
    // is the reviewed signer. A negative preflight asks for nothing at all.
    this.el.addEventListener("click", async event => {
      const target = (event.target as HTMLElement | null) ?? null

      if (target?.closest("[data-bid-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
        return
      }

      const confirm = target?.closest<HTMLElement>("[data-bid-send]")
      const actionId = confirm?.dataset.bidSend
      const signer = confirm?.dataset.bidSigner
      if (!actionId || !signer) return

      const address = await activeSigner(signer)
      if (address) push("sign_bid_step", {"action-id": actionId, address})
      else failed("wallet_unavailable")
    })

    this.handleEvent("autolaunch-bid:send", async payload => {
      const {action_id: actionId, step: stepName} = payload as {action_id: string; step: string}
      const held = operation
      if (!held || sending) return
      sending = true

      // The claim is already durable, so a failure below the send marker is
      // proof the wallet was never asked for anything: the exact step is
      // released and the same review stays sendable.
      let sendStarted = false
      const notStarted = () => push("bid_dispatch_not_started", {action_id: actionId})

      try {
        const step = sendableStep(held, actionId, stepName)
        const connected = activeEthereumWallet()
        if (!connected || !(await activeSigner(held.signer))) {
          notStarted()
          return
        }

        const hash = await sendBidStep(
          held,
          step,
          connected.provider,
          () => (sendStarted = true),
        )

        // The hash is reported once and the browser stops. It never waits on a
        // receipt and never decides an outcome.
        push("bid_submitted", {action_id: actionId, transaction_hash: hash})
      } catch (error) {
        if (!sendStarted) {
          notStarted()
          return
        }

        // A rejection of the transaction request itself, reported unconditionally:
        // browser state is evidence, never authority. The database refuses to
        // close a step once a hash is bound, so withholding this would only
        // strand a claim the server can no longer end.
        if (userRejected(error)) {
          push("bid_wallet_rejected", {action_id: actionId, code: 4001})
          return
        }

        failed("unknown")
      } finally {
        sending = false
      }
    })
  },

  destroyed(this: BidHook) {
    if (this.publishActiveWallet) {
      window.removeEventListener("ash:wallet-state", this.publishActiveWallet)
    }
  },
}

/**
 * The active wallet's own address when both the Privy selection and the
 * provider's current account are exactly the reviewed signer, or `null`.
 * A missing provider, a refused read and a changed account are all `null`.
 */
export async function activeSigner(expectedSigner: string): Promise<string | null> {
  const active = activeEthereumWallet()
  if (!active || !sameAddress(active.address, expectedSigner)) return null

  const accounts = await active.provider.request({method: "eth_accounts"}).catch(() => null)
  const [account] = Array.isArray(accounts) ? accounts : []
  return typeof account === "string" && sameAddress(account, expectedSigner) ? active.address : null
}

/**
 * The recovery hint, and only that: the identity of an operation a reload should
 * ask the server about. No transaction, signer or outcome is ever restored from
 * here, and a terminal operation leaves nothing behind.
 */
export function rememberOperation(
  operation: BidOperation,
  storage: Pick<Storage, "setItem" | "removeItem">,
): void {
  try {
    if (operation.terminal) storage.removeItem(pendingKey)
    else storage.setItem(pendingKey, operation.action_id)
  } catch {
    // The connected LiveView already holds the operation; this is refresh only.
  }
}

function sameAddress(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase()
}
