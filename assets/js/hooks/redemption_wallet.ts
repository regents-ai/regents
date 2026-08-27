import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {executePreparedRedemptionAction, type PreparedRedemptionAction} from "../wallet_actions/redemption"

type RedemptionHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  publishActiveWallet?: () => void
}

export const RedemptionWallet: Hook = {
  mounted(this: RedemptionHook) {
    this.publishActiveWallet = () => this.pushEvent("redemption_active_wallet", {
      address: activeEthereumWallet()?.address ?? null,
    })
    window.addEventListener("ash:wallet-state", this.publishActiveWallet)
    this.publishActiveWallet()

    this.el.addEventListener("click", event => {
      if ((event.target as HTMLElement | null)?.closest("[data-redeem-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
      }
    })

    this.handleEvent("redemption:wallet-action", payload => {
      const envelope = (payload as {envelope: PreparedRedemptionAction}).envelope
      const active = activeEthereumWallet()
      if (active) void executePreparedRedemptionAction(envelope, active.provider).catch(() => undefined)
    })
  },

  destroyed(this: RedemptionHook) {
    if (this.publishActiveWallet) window.removeEventListener("ash:wallet-state", this.publishActiveWallet)
  },
}
