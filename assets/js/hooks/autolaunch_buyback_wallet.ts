import type {Hook} from "../hook_composition"
import {
  executePreparedAutolaunchBuyback,
  type PreparedAutolaunchBuyback,
} from "../wallet_actions/autolaunch_buybacks"
import {connectedEthereumWallet} from "../wallet_actions/connected_wallet"

const pendingKey = "regent:autolaunch-buyback:submitted"
const inFlight = new Set<string>()

type StoredSubmission = {
  envelope: PreparedAutolaunchBuyback
  transaction_hash: `0x${string}`
}

type BuybackHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
}

export const AutolaunchBuybackWallet: Hook = {
  mounted(this: BuybackHook) {
    let stored = readSubmission()
    if (stored) this.pushEvent("restore_autolaunch_buyback_submission", stored)

    for (const event of [
      "autolaunch-buyback:confirmed",
      "autolaunch-buyback:reverted",
      "autolaunch-buyback:abandoned",
    ]) {
      this.handleEvent(event, () => {
        stored = null
        sessionStorage.removeItem(pendingKey)
      })
    }

    this.handleEvent("autolaunch-buyback:prepared", async payload => {
      const envelope = (payload as {envelope: PreparedAutolaunchBuyback}).envelope
      if (inFlight.has(envelope.action_id)) return

      const connected = connectedEthereumWallet(envelope.expected_signer)
      if (!connected) {
        this.pushEvent("autolaunch_buyback_wallet_failed", {
          message: "Connect the wallet shown on this account before continuing.",
        })
        return
      }

      inFlight.add(envelope.action_id)
      this.el.dataset.walletActionPending = "true"

      try {
        const transactionHash = await executePreparedAutolaunchBuyback(
          envelope,
          connected.provider,
          undefined,
          hash => {
            stored = recordAutolaunchBuybackSubmission(envelope, hash)
            this.pushEvent("autolaunch_buyback_submitted", {
              action_id: envelope.action_id,
              transaction_hash: hash,
            })
          },
        )

        this.pushEvent("confirm_autolaunch_buyback", {
          action_id: envelope.action_id,
          transaction_hash: transactionHash,
        })
      } catch (error) {
        const message = error instanceof Error ? error.message : "The wallet action did not complete."
        this.pushEvent("autolaunch_buyback_wallet_failed", {message})
      } finally {
        inFlight.delete(envelope.action_id)
        this.el.dataset.walletActionPending = "false"
      }
    })
  },
}

export function recordAutolaunchBuybackSubmission(
  envelope: PreparedAutolaunchBuyback,
  hash: `0x${string}`,
  storage: Pick<Storage, "setItem"> = sessionStorage,
): StoredSubmission {
  const submission = {envelope, transaction_hash: hash}

  try {
    storage.setItem(pendingKey, JSON.stringify(submission))
  } catch {
    // The connected LiveView already has the submitted hash.
  }

  return submission
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
