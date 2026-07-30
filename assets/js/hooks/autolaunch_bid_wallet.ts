import type {Hook} from "../hook_composition"
import {connectedEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  executePreparedAuctionBidAction,
  type PreparedAuctionBidAction,
} from "../wallet_actions/autolaunch_bids"

const pendingKey = "regent:autolaunch-bid:submitted"
const inFlight = new Set<string>()

type StoredSubmission = {
  envelope: PreparedAuctionBidAction
  approval_transaction_hash?: `0x${string}`
  transaction_hash?: `0x${string}`
}

type BidHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
}

export const AutolaunchBidWallet: Hook = {
  mounted(this: BidHook) {
    let stored = readSubmission()
    if (stored) this.pushEvent("restore_autolaunch_bid_submission", stored)

    for (const event of [
      "autolaunch-bid:confirmed",
      "autolaunch-bid:reverted",
      "autolaunch-bid:approval-reverted",
      "autolaunch-bid:abandoned",
    ]) {
      this.handleEvent(event, () => {
        stored = null
        sessionStorage.removeItem(pendingKey)
      })
    }

    this.handleEvent("autolaunch-bid:prepared", async payload => {
      const envelope = (payload as {envelope: PreparedAuctionBidAction}).envelope
      if (inFlight.has(envelope.action_id)) return

      const connected = connectedEthereumWallet(envelope.expected_signer)
      if (!connected) {
        this.pushEvent("autolaunch_bid_wallet_failed", {
          message: "Connect the wallet shown on this account before continuing.",
        })
        return
      }

      inFlight.add(envelope.action_id)
      this.el.dataset.walletActionPending = "true"

      try {
        const result = await executePreparedAuctionBidAction(
          envelope,
          connected.provider,
          undefined,
          {
            existingApprovalHash:
              stored?.envelope.action_id === envelope.action_id
                ? stored.approval_transaction_hash
                : undefined,
            onSubmitted: (phase, hash) => {
              stored = recordAutolaunchBidSubmission(stored, envelope, phase, hash)
              this.pushEvent("autolaunch_bid_submitted", {
                action_id: envelope.action_id,
                phase,
                transaction_hash: hash,
              })
            },
          },
        )

        this.pushEvent("confirm_autolaunch_bid", {
          action_id: envelope.action_id,
          transaction_hash: result.transactionHash,
          approval_transaction_hash: result.approvalHash ?? null,
        })
      } catch (error) {
        const message = error instanceof Error ? error.message : "The wallet action did not complete."
        this.pushEvent("autolaunch_bid_wallet_failed", {message})
      } finally {
        inFlight.delete(envelope.action_id)
        this.el.dataset.walletActionPending = "false"
      }
    })
  },
}

export function recordAutolaunchBidSubmission(
  current: StoredSubmission | null,
  envelope: PreparedAuctionBidAction,
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
