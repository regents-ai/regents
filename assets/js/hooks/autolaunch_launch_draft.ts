import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"

type LaunchDraftHook = Hook & {
  el: HTMLElement
  defaultTreasury?: () => void
}

/**
 * The address a blank draft's Treasury should start as, or `null` to leave the
 * field exactly as it is.
 *
 * The default is an ordinary starting value, not a decision. It fills an empty
 * field and refreshes one still holding what it filled last, so switching wallet
 * before typing follows the selection. Anything else on screen — an address the
 * customer typed, a value the server echoed back after refusing a save — belongs
 * to the customer and is never overwritten.
 */
export function defaultedTreasury(
  current: string,
  wallet: string | null,
  filled: string | null,
): string | null {
  if (!wallet || current === wallet) return null
  return current === "" || current === filled ? wallet : null
}

export const AutolaunchLaunchDraft: Hook = {
  mounted(this: LaunchDraftHook) {
    let filled: string | null = null

    const field = () =>
      this.el.querySelector<HTMLInputElement>('input[name="launch_draft[treasury]"]')

    this.defaultTreasury = () => {
      const input = field()
      if (!input) return

      const wallet = activeEthereumWallet()?.address ?? null
      const next = defaultedTreasury(input.value, wallet, filled)
      if (next === null) return

      input.value = next
      filled = next
    }

    // Privy's selection is what this reads, and a successful save clears the form
    // on the server, so the same default is applied again on every re-render.
    window.addEventListener("ash:wallet-state", this.defaultTreasury)
    this.defaultTreasury()
  },

  updated(this: LaunchDraftHook) {
    this.defaultTreasury?.()
  },

  destroyed(this: LaunchDraftHook) {
    if (this.defaultTreasury) {
      window.removeEventListener("ash:wallet-state", this.defaultTreasury)
    }
  },
}
