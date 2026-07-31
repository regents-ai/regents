import type {Hook} from "../hook_composition"
import {connectedEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  executePreparedSubjectPaymentAction,
  type PreparedSubjectPaymentAction,
} from "../wallet_actions/autolaunch_subject_payments"

const pendingKey = "regent:autolaunch-subject-payment:submitted"
const inFlight = new Set<string>()

type StoredSubmission = {
  envelope: PreparedSubjectPaymentAction
  approval_transaction_hash?: `0x${string}`
  transaction_hash?: `0x${string}`
}

type SubjectPaymentHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
}

export const AutolaunchSubjectPaymentWallet: Hook = {
  mounted(this: SubjectPaymentHook) {
    let stored = readSubmission()
    if (stored) this.pushEvent("restore_autolaunch_subject_payment_submission", stored)

    for (const event of [
      "autolaunch-subject-payment:confirmed",
      "autolaunch-subject-payment:reverted",
      "autolaunch-subject-payment:approval-reverted",
      "autolaunch-subject-payment:abandoned",
    ]) {
      this.handleEvent(event, () => {
        stored = null
        sessionStorage.removeItem(pendingKey)
      })
    }

    this.handleEvent("autolaunch-subject-payment:prepared", async payload => {
      const envelope = (payload as {envelope: PreparedSubjectPaymentAction}).envelope
      if (inFlight.has(envelope.action_id)) return

      const connected = connectedEthereumWallet(envelope.expected_signer)
      if (!connected) {
        this.pushEvent("autolaunch_subject_payment_wallet_failed", {
          message: "Connect the wallet shown on this account before continuing.",
        })
        return
      }

      inFlight.add(envelope.action_id)
      this.el.dataset.walletActionPending = "true"

      try {
        const result = await executePreparedSubjectPaymentAction(
          envelope,
          connected.provider,
          undefined,
          {
            existingApprovalHash:
              stored?.envelope.action_id === envelope.action_id
                ? stored.approval_transaction_hash
                : undefined,
            onSubmitted: (phase, hash) => {
              stored = recordSubjectPaymentSubmission(stored, envelope, phase, hash)
              this.pushEvent("autolaunch_subject_payment_submitted", {
                action_id: envelope.action_id,
                phase,
                transaction_hash: hash,
              })
            },
          },
        )

        this.pushEvent("confirm_autolaunch_subject_payment", {
          action_id: envelope.action_id,
          transaction_hash: result.transactionHash,
          approval_transaction_hash: result.approvalHash ?? null,
        })
      } catch (error) {
        const message = error instanceof Error ? error.message : "The wallet action did not complete."
        this.pushEvent("autolaunch_subject_payment_wallet_failed", {message})
      } finally {
        inFlight.delete(envelope.action_id)
        this.el.dataset.walletActionPending = "false"
      }
    })
  },
}

export function recordSubjectPaymentSubmission(
  current: StoredSubmission | null,
  envelope: PreparedSubjectPaymentAction,
  phase: "approval" | "action",
  hash: `0x${string}`,
  storage: Pick<Storage, "setItem"> = sessionStorage,
): StoredSubmission {
  const next =
    phase === "approval"
      ? {...(current ?? {envelope}), envelope, approval_transaction_hash: hash}
      : {...(current ?? {envelope}), envelope, transaction_hash: hash}

  try {
    storage.setItem(pendingKey, JSON.stringify(next))
  } catch {
    // The connected LiveView already has the submitted hash.
  }
  return next
}

function readSubmission(): StoredSubmission | null {
  try {
    const value = sessionStorage.getItem(pendingKey)
    return value ? (JSON.parse(value) as StoredSubmission) : null
  } catch {
    sessionStorage.removeItem(pendingKey)
    return null
  }
}
