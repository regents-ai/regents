import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"
import {executePreparedStakingAction, type PreparedStakingAction} from "../wallet_actions/staking"

type StakeHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  publishActiveWallet?: () => void
}

export const StakeWallet: Hook = {
  mounted(this: StakeHook) {
    this.publishActiveWallet = () => this.pushEvent("staking_active_wallet", {
      address: activeEthereumWallet()?.address ?? null,
    })
    window.addEventListener("ash:wallet-state", this.publishActiveWallet)
    this.publishActiveWallet()

    this.el.addEventListener("click", event => {
      if ((event.target as HTMLElement | null)?.closest("[data-stake-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
      }
    })

    this.handleEvent("staking:wallet-action", payload => {
      const envelope = (payload as {envelope: PreparedStakingAction}).envelope
      const active = activeEthereumWallet()
      if (active) void executePreparedStakingAction(envelope, active.provider).catch(() => undefined)
    })
  },

  destroyed(this: StakeHook) {
    if (this.publishActiveWallet) window.removeEventListener("ash:wallet-state", this.publishActiveWallet)
  },
}
