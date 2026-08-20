import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {activeSigner, userRejected} from "./stake_wallet"
import {
  executePreparedRedemptionAction,
  type PreparedRedemptionAction,
} from "../wallet_actions/redemption"

const pendingKey = "regent:redemption:submitted"
const inFlightActionIds = new Set<string>()

// The closed set of failures this surface can describe. Provider, viem, revert
// and wallet-vendor text is never a customer message, so it is never sent.
type FailureReason = "wallet_unavailable" | "signer_changed" | "unknown"

export type StoredRedemptionSubmission = {
  envelope: PreparedRedemptionAction
  transaction_hash: `0x${string}`
}

type SubmissionStorage = Pick<Storage, "setItem">

type RedemptionHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  publishActiveWallet?: () => void
}

export const RedemptionWallet: Hook = {
  mounted(this: RedemptionHook) {
    const restored = readStoredSubmission()
    if (restored) this.pushEvent("restore_redemption_submission", restored)

    const failed = (reason: FailureReason) => this.pushEvent("redemption_wallet_failed", {reason})

    // Privy's selection is what Redeem reads, so every change is republished and
    // the server decides what that wallet is allowed to see.
    this.publishActiveWallet = () =>
      this.pushEvent("redemption_active_wallet", {
        address: activeEthereumWallet()?.address ?? null,
      })
    window.addEventListener("ash:wallet-state", this.publishActiveWallet)
    this.publishActiveWallet()

    // A claim is only asked for once the wallet in front of the customer really
    // is the reviewed signer. A negative preflight asks for nothing at all.
    const requestDispatch = async (actionId: string, signer: string) => {
      const address = await activeSigner(signer)
      if (address) this.pushEvent("sign_prepared_redemption", {"action-id": actionId, address})
      else failed("wallet_unavailable")
    }

    this.el.addEventListener("click", async event => {
      const target = (event.target as HTMLElement | null) ?? null
      const confirm = target?.closest<HTMLElement>("[data-redeem-confirm]")
      if (confirm?.dataset.redeemConfirm && confirm.dataset.redeemSigner) {
        await requestDispatch(confirm.dataset.redeemConfirm, confirm.dataset.redeemSigner)
        return
      }

      if (target?.closest("[data-redeem-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
        return
      }

      const button = target?.closest<HTMLElement>("[data-copy-signer]")
      const signer = button?.dataset.copySigner
      if (!button || !signer) return

      try {
        await navigator.clipboard.writeText(signer)
        button.textContent = "Copied"
      } catch {
        // No Clipboard API, or the browser refused the write. Either way the
        // reason is never customer copy; the full address stays on screen.
        button.textContent = "Copy failed"
      }
    })

    // Every terminal outcome clears the stored submission, so a reload never
    // asks the server to restore work that already ended.
    for (const event of [
      "redemption:confirmed",
      "redemption:reverted",
      "redemption:unverified",
      "redemption:abandoned",
    ]) {
      this.handleEvent(event, () => sessionStorage.removeItem(pendingKey))
    }

    this.handleEvent("redemption:prepared", async payload => {
      const envelope = (payload as {envelope: PreparedRedemptionAction}).envelope
      if (inFlightActionIds.has(envelope.action_id)) return
      inFlightActionIds.add(envelope.action_id)
      this.el.dataset.walletActionPending = "true"
      setSigningDisabled(this.el, true)

      // The claim is already durable, so a preflight that fails here is proof
      // the wallet was never asked for anything: the claim is released and the
      // reason says which wallet to come back with.
      const notStarted = (reason: FailureReason | null = null) =>
        this.pushEvent("redemption_dispatch_not_started", {
          action_id: envelope.action_id,
          reason,
        })

      const connected = activeEthereumWallet()
      if (!connected || !(await activeSigner(envelope.expected_signer))) {
        notStarted(connected ? "signer_changed" : "wallet_unavailable")
        unlock(this.el, envelope.action_id)
        return
      }

      let sendStarted = false

      try {
        const hash = await executePreparedRedemptionAction(envelope, connected.provider, undefined, {
          onSendStarted: () => (sendStarted = true),
          onSubmitted: submittedHash =>
            recordSubmittedRedemption(
              envelope,
              submittedHash,
              payload => this.pushEvent("redemption_submitted", payload),
              sessionStorage,
            ),
        })
        this.pushEvent("confirm_redemption", {
          action_id: envelope.action_id,
          transaction_hash: hash,
        })
      } catch (error) {
        // Below the send marker nothing was broadcast, whatever the wallet said,
        // so the claim is released rather than closed.
        if (!sendStarted) {
          notStarted()
          return
        }

        // Reported unconditionally: browser state is evidence, never authority.
        // The database refuses `not_sent` once a hash is bound, so withholding
        // this would only strand a claim it can no longer close.
        if (userRejected(error)) {
          this.pushEvent("redemption_wallet_rejected", {
            action_id: envelope.action_id,
            code: 4001,
          })
          return
        }
        failed("unknown")
      } finally {
        unlock(this.el, envelope.action_id)
      }
    })
  },

  destroyed(this: RedemptionHook) {
    if (this.publishActiveWallet) {
      window.removeEventListener("ash:wallet-state", this.publishActiveWallet)
    }
  },
}

export function recordSubmittedRedemption(
  envelope: PreparedRedemptionAction,
  hash: `0x${string}`,
  push: (payload: {action_id: string; transaction_hash: string}) => void,
  storage: SubmissionStorage,
): StoredRedemptionSubmission {
  const stored = {envelope, transaction_hash: hash}
  push({action_id: envelope.action_id, transaction_hash: hash})
  try {
    storage.setItem(pendingKey, JSON.stringify(stored))
  } catch {
    // The connected LiveView already received the hash; storage is refresh recovery only.
  }
  return stored
}

function readStoredSubmission(): StoredRedemptionSubmission | null {
  try {
    const value = sessionStorage.getItem(pendingKey)
    return value ? (JSON.parse(value) as StoredRedemptionSubmission) : null
  } catch {
    sessionStorage.removeItem(pendingKey)
    return null
  }
}

function setSigningDisabled(root: HTMLElement, disabled: boolean): void {
  root
    .querySelectorAll<HTMLButtonElement>("[data-redeem-confirm]")
    .forEach(button => (button.disabled = disabled))
}

function unlock(root: HTMLElement, actionId: string): void {
  inFlightActionIds.delete(actionId)
  root.dataset.walletActionPending = "false"
  setSigningDisabled(root, false)
}
