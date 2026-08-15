import type {Hook} from "../hook_composition"
import {connectedEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  executePreparedRedemptionAction,
  type PreparedRedemptionAction,
  RedemptionExecutionError,
} from "../wallet_actions/redemption"

const pendingKey = "regent:redemption:submitted"
const inFlightActionIds = new Set<string>()

export type StoredRedemptionSubmission = {
  envelope: PreparedRedemptionAction
  transaction_hash: `0x${string}`
}

type SubmissionStorage = Pick<Storage, "setItem">

type RedemptionHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
}

export const RedemptionWallet: Hook = {
  mounted(this: RedemptionHook) {
    const restored = readStoredSubmission()
    if (restored) this.pushEvent("restore_redemption_submission", restored)

    for (const event of ["redemption:confirmed", "redemption:reverted", "redemption:abandoned"]) {
      this.handleEvent(event, () => sessionStorage.removeItem(pendingKey))
    }

    this.handleEvent("redemption:prepared", async payload => {
      const envelope = (payload as {envelope: PreparedRedemptionAction}).envelope
      if (inFlightActionIds.has(envelope.action_id)) return
      inFlightActionIds.add(envelope.action_id)
      this.el.dataset.walletActionPending = "true"
      setSigningDisabled(this.el, true)

      const connected = connectedEthereumWallet(envelope.expected_signer)
      if (!connected) {
        this.pushEvent("redemption_wallet_failed", {
          message: "Connect the wallet shown on this account before continuing.",
        })
        unlock(this.el, envelope.action_id)
        return
      }

      try {
        const hash = await executePreparedRedemptionAction(
          envelope,
          connected.provider,
          undefined,
          submittedHash =>
            recordSubmittedRedemption(
              envelope,
              submittedHash,
              payload => this.pushEvent("redemption_submitted", payload),
              sessionStorage,
            ),
        )
        this.pushEvent("confirm_redemption", {
          action_id: envelope.action_id,
          transaction_hash: hash,
        })
      } catch (error) {
        if (error instanceof RedemptionExecutionError) {
          this.pushEvent("confirm_redemption", {
            action_id: envelope.action_id,
            transaction_hash: error.transactionHash,
          })
        } else {
          // Reported unconditionally: browser state is evidence, never
          // authority. The database refuses `not_sent` once a hash is bound, so
          // withholding this would only strand a claim it can no longer close.
          if (userRejected(error)) {
            this.pushEvent("redemption_wallet_rejected", {
              action_id: envelope.action_id,
              code: 4001,
            })
          }
          const message = error instanceof Error ? error.message : "The wallet action did not complete."
          this.pushEvent("redemption_wallet_failed", {message})
        }
      } finally {
        unlock(this.el, envelope.action_id)
      }
    })
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

/**
 * The exact EIP-1193 user-rejection code, walked out of whatever wrapper viem
 * put around it. Message text is never authority, so nothing else qualifies.
 */
export function userRejected(error: unknown): boolean {
  const seen = new Set<unknown>()
  let current: unknown = error

  while (current && typeof current === "object" && !seen.has(current)) {
    seen.add(current)
    if ((current as {code?: unknown}).code === 4001) return true
    current = (current as {cause?: unknown}).cause
  }

  return false
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
    .querySelectorAll<HTMLButtonElement>("[phx-click='sign_prepared_redemption']")
    .forEach(button => (button.disabled = disabled))
}

function unlock(root: HTMLElement, actionId: string): void {
  inFlightActionIds.delete(actionId)
  root.dataset.walletActionPending = "false"
  setSigningDisabled(root, false)
}
