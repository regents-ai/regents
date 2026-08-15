import type {Hook} from "../hook_composition"
import {connectedEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  executePreparedStakingAction,
  type PreparedStakingAction,
  WalletExecutionError,
} from "../wallet_actions/staking"

const inFlightActionIds = new Set<string>()
const pendingKey = "regent:staking:submitted"

type StoredSubmission = {
  envelope: PreparedStakingAction
  approval_transaction_hash?: `0x${string}`
  transaction_hash?: `0x${string}`
}

type SubmissionStorage = Pick<Storage, "setItem">

type StakeHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  removePrepared?: () => void
}

export const StakeWallet: Hook = {
  mounted(this: StakeHook) {
    const restored = readStoredSubmission()
    let currentSubmission = restored
    if (restored) this.pushEvent("restore_staking_submission", restored)

    this.handleEvent("staking:confirmed", () => sessionStorage.removeItem(pendingKey))
    this.handleEvent("staking:approval-reverted", () => sessionStorage.removeItem(pendingKey))
    this.handleEvent("staking:action-reverted", () => sessionStorage.removeItem(pendingKey))
    this.handleEvent("staking:abandoned", () => sessionStorage.removeItem(pendingKey))

    const onPrepared = async (payload: unknown) => {
      const prepared = payload as {
        envelope: PreparedStakingAction
        approval_transaction_hash?: `0x${string}` | null
      }
      const envelope = prepared.envelope
      if (inFlightActionIds.has(envelope.action_id)) return
      inFlightActionIds.add(envelope.action_id)
      const phase: "approval" | "action" =
        envelope.approval && !prepared.approval_transaction_hash ? "approval" : "action"
      this.el.dataset.walletActionPending = "true"
      this.el
        .querySelectorAll<HTMLButtonElement>("[phx-click='sign_prepared_staking']")
        .forEach(button => (button.disabled = true))
      const connected = connectedEthereumWallet(envelope.expected_signer)

      if (!connected) {
        this.pushEvent("staking_wallet_failed", {message: "Connect your wallet before continuing."})
        unlock(this.el, envelope.action_id)
        return
      }

      try {
        const result = await executePreparedStakingAction(
          envelope,
          connected.provider,
          undefined,
          {
            existingApprovalHash: prepared.approval_transaction_hash ?? undefined,
            onSubmitted: (phase, hash) => {
              currentSubmission = recordSubmittedAction(
                currentSubmission,
                envelope,
                phase,
                hash,
                payload => this.pushEvent("staking_submitted", payload),
                sessionStorage,
              )
            },
          },
        )
        if (result.phase === "action") {
          this.pushEvent("confirm_staking", {
            action_id: envelope.action_id,
            transaction_hash: result.transactionHash,
            approval_transaction_hash: result.approvalHash ?? null,
          })
        }
      } catch (error) {
        if (error instanceof WalletExecutionError && error.code === "approval_reverted") {
          const stored = currentSubmission
          if (stored?.approval_transaction_hash) {
            this.pushEvent("staking_approval_reverted", {
              action_id: envelope.action_id,
              transaction_hash: stored.approval_transaction_hash,
            })
          }
        }
        if (error instanceof WalletExecutionError && error.code === "action_reverted") {
          const stored = currentSubmission
          if (stored?.transaction_hash) {
            this.pushEvent("confirm_staking", {
              action_id: envelope.action_id,
              transaction_hash: stored.transaction_hash,
              approval_transaction_hash: stored.approval_transaction_hash ?? null,
            })
          }
        }
        // Reported unconditionally: browser state is evidence, never authority.
        // The database refuses `not_sent` once a hash is bound, so withholding
        // this would only strand a claim the server can no longer close.
        if (userRejected(error)) {
          this.pushEvent("staking_wallet_rejected", {
            action_id: envelope.action_id,
            phase,
            code: 4001,
          })
        }
        const message = error instanceof Error ? error.message : "The wallet action could not be completed."
        this.pushEvent("staking_wallet_failed", {message})
      } finally {
        unlock(this.el, envelope.action_id)
      }
    }

    this.handleEvent("staking:prepared", onPrepared)
  },
}

export function recordSubmittedAction(
  current: StoredSubmission | null,
  envelope: PreparedStakingAction,
  phase: "approval" | "action",
  hash: `0x${string}`,
  push: (payload: {action_id: string; phase: string; transaction_hash: string}) => void,
  storage: SubmissionStorage,
): StoredSubmission {
  const stored =
    phase === "approval"
      ? {...(current ?? {envelope}), envelope, approval_transaction_hash: hash}
      : {...(current ?? {envelope}), envelope, transaction_hash: hash}

  push({action_id: envelope.action_id, phase, transaction_hash: hash})
  try {
    storage.setItem(pendingKey, JSON.stringify(stored))
  } catch {
    // The connected LiveView already has the hash; persistence is only refresh recovery.
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

function readStoredSubmission(): StoredSubmission | null {
  try {
    const value = sessionStorage.getItem(pendingKey)
    return value ? (JSON.parse(value) as StoredSubmission) : null
  } catch {
    sessionStorage.removeItem(pendingKey)
    return null
  }
}

function unlock(root: HTMLElement, actionId: string): void {
  inFlightActionIds.delete(actionId)
  root.dataset.walletActionPending = "false"
  root
    .querySelectorAll<HTMLButtonElement>("[phx-click='sign_prepared_staking']")
    .forEach(button => (button.disabled = false))
}
