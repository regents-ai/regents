import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  executePreparedStakingAction,
  type PreparedStakingAction,
  WalletExecutionError,
} from "../wallet_actions/staking"

const inFlightActionIds = new Set<string>()
const pendingKey = "regent:staking:submitted"

// The closed set of failures this surface can describe. Provider, viem, revert
// and wallet-vendor text is never a customer message, so it is never sent.
type FailureReason = "wallet_unavailable" | "signer_changed" | "unknown"

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
  publishActiveWallet?: () => void
}

export const StakeWallet: Hook = {
  mounted(this: StakeHook) {
    const restored = readStoredSubmission()
    let currentSubmission = restored
    if (restored) this.pushEvent("restore_staking_submission", restored)

    const failed = (reason: FailureReason) => this.pushEvent("staking_wallet_failed", {reason})

    // Privy's selection is what Stake reads, so every change is republished and
    // the server decides what that wallet is allowed to see.
    this.publishActiveWallet = () =>
      this.pushEvent("staking_active_wallet", {address: activeEthereumWallet()?.address ?? null})
    window.addEventListener("ash:wallet-state", this.publishActiveWallet)
    this.publishActiveWallet()

    // A claim is only asked for once the wallet in front of the customer really
    // is the reviewed signer. A negative preflight asks for nothing at all.
    const requestDispatch = async (actionId: string, signer: string) => {
      const address = await activeSigner(signer)
      if (address) this.pushEvent("sign_prepared_staking", {"action-id": actionId, address})
      else failed("wallet_unavailable")
    }

    this.el.addEventListener("click", async event => {
      const target = (event.target as HTMLElement | null) ?? null
      const confirm = target?.closest<HTMLElement>("[data-stake-confirm]")
      if (confirm?.dataset.stakeConfirm && confirm.dataset.stakeSigner) {
        await requestDispatch(confirm.dataset.stakeConfirm, confirm.dataset.stakeSigner)
        return
      }

      if (target?.closest("[data-stake-connect]")) {
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

    this.handleEvent("staking:confirmed", () => sessionStorage.removeItem(pendingKey))
    this.handleEvent("staking:approval-reverted", () => sessionStorage.removeItem(pendingKey))
    this.handleEvent("staking:action-reverted", () => sessionStorage.removeItem(pendingKey))
    this.handleEvent("staking:abandoned", () => sessionStorage.removeItem(pendingKey))

    // The server verified the approval receipt and the exact allowance, so the
    // stake may follow through the same preflight. It never reapproves.
    this.handleEvent("staking:continue", async payload => {
      const {action_id: actionId, expected_signer: signer} = payload as {
        action_id: string
        expected_signer: string
      }
      await requestDispatch(actionId, signer)
    })

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
        .querySelectorAll<HTMLButtonElement>("[data-stake-confirm]")
        .forEach(button => (button.disabled = true))
      const connected = activeEthereumWallet()

      if (!connected) {
        failed("wallet_unavailable")
        unlock(this.el, envelope.action_id)
        return
      }

      // The claim is already durable. If the wallet moved between the claim and
      // this push, nothing is sent and nothing is closed: the request may still
      // be open in the original wallet, so only that wallet can end it.
      if (!(await activeSigner(envelope.expected_signer))) {
        failed("signer_changed")
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
        const stored = currentSubmission
        // Each precise outcome is the whole outcome for its bound hash, so
        // nothing follows it that could replace it with a generic failure.
        if (
          error instanceof WalletExecutionError &&
          error.code === "approval_reverted" &&
          stored?.approval_transaction_hash
        ) {
          this.pushEvent("staking_approval_reverted", {
            action_id: envelope.action_id,
            transaction_hash: stored.approval_transaction_hash,
          })
          return
        }
        if (
          error instanceof WalletExecutionError &&
          error.code === "action_reverted" &&
          stored?.transaction_hash
        ) {
          this.pushEvent("confirm_staking", {
            action_id: envelope.action_id,
            transaction_hash: stored.transaction_hash,
            approval_transaction_hash: stored.approval_transaction_hash ?? null,
          })
          return
        }
        // Reported unconditionally: browser state is evidence, never authority.
        // The database refuses `not_sent` once a hash is bound, so withholding
        // this would only strand a claim the server can no longer close. The
        // rejection is the whole outcome, so nothing follows it that could
        // overwrite the neutral notice with a failure the user did not cause.
        if (userRejected(error)) {
          this.pushEvent("staking_wallet_rejected", {
            action_id: envelope.action_id,
            phase,
            code: 4001,
          })
          return
        }
        failed("unknown")
      } finally {
        unlock(this.el, envelope.action_id)
      }
    }

    this.handleEvent("staking:prepared", onPrepared)
  },

  destroyed(this: StakeHook) {
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

  const accounts = await active.provider
    .request({method: "eth_accounts"})
    .catch(() => null)
  const [account] = Array.isArray(accounts) ? accounts : []
  return typeof account === "string" && sameAddress(account, expectedSigner) ? active.address : null
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

function sameAddress(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase()
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
    .querySelectorAll<HTMLButtonElement>("[data-stake-confirm]")
    .forEach(button => (button.disabled = false))
}
