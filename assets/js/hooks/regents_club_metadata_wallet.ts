import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {
  beginMetadataAttempt,
  executePreparedMetadataAction,
  MetadataExecutionFailure,
  type MetadataAttempt,
  type PreparedMetadataAction,
} from "../wallet_actions/regents_club_metadata"

type MetadataHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  metadataState?: {
    attempts: Map<string, MetadataAttempt>
    alive: boolean
    click: (event: MouseEvent) => void
    walletState: () => void
  }
}

export const RegentsClubMetadataWallet: Hook = {
  mounted(this: MetadataHook) {
    const state: NonNullable<MetadataHook["metadataState"]> = {
      attempts: new Map<string, MetadataAttempt>(),
      alive: true,
      click: (_event: MouseEvent): void => {},
      walletState: (): void => {},
    }
    this.metadataState = state

    state.walletState = () => {
      this.pushEvent("regents_club_metadata_active_wallet", {
        address: activeEthereumWallet()?.address ?? null,
      })
    }

    state.click = event => {
      const target = event.target instanceof Element ? event.target : null
      if (target?.closest("[data-regents-club-metadata-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
        return
      }
      const confirmation = target?.closest<HTMLElement>("[data-regents-club-metadata-confirm]")
      if (confirmation) {
        event.preventDefault()
        const attemptId = confirmation.dataset.attemptId
        if (attemptId && state.attempts.has(attemptId)) {
          this.pushEvent("confirm_regents_club_metadata", {attempt_id: attemptId})
        }
        return
      }
      if (!target?.closest("[data-regents-club-metadata-submit]")) return
      event.preventDefault()

      const wallet = activeEthereumWallet()
      if (!wallet) return this.pushEvent("regents_club_metadata_browser_refused", {})
      const attemptId = crypto.randomUUID()

      void beginMetadataAttempt(attemptId, wallet)
        .then(attempt => {
          if (!state.alive) return
          state.attempts.set(attemptId, attempt)
          // No target, calldata, URI, value, or arbitrary form value crosses
          // this browser-to-server boundary.
          this.pushEvent("prepare_regents_club_metadata", {
            address: attempt.signer,
            attempt_id: attempt.attemptId,
          })
        })
        .catch(() => this.pushEvent("regents_club_metadata_browser_refused", {}))
    }

    this.el.addEventListener("click", state.click)
    window.addEventListener("ash:wallet-state", state.walletState)
    state.walletState()

    this.handleEvent("regents-club-metadata:prepared", payload => {
      const {attempt_id: id, envelope} = payload as {
        attempt_id?: unknown
        envelope?: PreparedMetadataAction
      }
      if (typeof id !== "string" || !envelope) return
      const attempt = state.attempts.get(id)
      if (!attempt) return
      state.attempts.delete(id)

      void executePreparedMetadataAction(attempt, envelope)
        .then(hash => this.pushEvent("regents_club_metadata_submitted", {attempt_id: id, hash}))
        .catch(error => {
          const kind = error instanceof MetadataExecutionFailure ? error.kind : "refused"
          this.pushEvent(`regents_club_metadata_${kind}`, {attempt_id: id})
        })
    })

    this.handleEvent("regents-club-metadata:refused", payload => {
      const id = (payload as {attempt_id?: unknown}).attempt_id
      if (typeof id === "string") state.attempts.delete(id)
    })
  },

  destroyed(this: MetadataHook) {
    const state = this.metadataState
    if (!state) return
    state.alive = false
    state.attempts.clear()
    this.el.removeEventListener("click", state.click)
    window.removeEventListener("ash:wallet-state", state.walletState)
    this.metadataState = undefined
  },
}
