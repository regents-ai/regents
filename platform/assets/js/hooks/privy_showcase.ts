import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"

type ReferenceHook = Hook & {
  el: HTMLElement
  pushEvent(event: string, payload: unknown): void
  cleanup?: () => void
}

// This is only an observer for the reference page. The ordinary auth_lazy.ts
// listener owns every data-account-target button and the existing Privy bridge.
// Do not create another PrivyProvider or request a signature from this hook.
export const PrivyShowcase: Hook = {
  mounted(this: ReferenceHook) {
    const publish = () => this.pushEvent("privy_wallet_changed", {
      address: activeEthereumWallet()?.address ?? null,
    })
    window.addEventListener("ash:wallet-state", publish)
    publish()
    if (this.el.dataset.privyEnabled === "true") {
      // A page load restores the SDK's current selection without opening a modal.
      window.dispatchEvent(new Event("ash:wallet-sync"))
    }
    this.cleanup = () => window.removeEventListener("ash:wallet-state", publish)
  },
  destroyed(this: ReferenceHook) { this.cleanup?.() },
}
