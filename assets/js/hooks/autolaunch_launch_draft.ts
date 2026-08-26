import type {Hook} from "../hook_composition"
import {activeEthereumWallet} from "../wallet_actions/connected_wallet"

type LaunchDraftHook = Hook & {
  el: HTMLElement
  defaultTreasury?: () => void
  patchedForm?: () => void
}

/**
 * Who the Treasury field belongs to: the address the default last wrote there,
 * and whether the customer has since taken the field over.
 */
type Ownership = {saved: string | undefined; filled: string | null; touched: boolean}

const treasuryField = 'input[name="launch_draft[treasury]"]'

/**
 * The address a blank draft's Treasury should start as, or `null` to leave the
 * field exactly as it is.
 *
 * The default is an ordinary starting value, not a decision. It fills an empty
 * field and refreshes one still holding what it filled last, so switching wallet
 * before typing follows the selection. Once the field belongs to the customer,
 * nothing writes it again, however the selected wallet changes afterwards.
 */
export function defaultedTreasury(
  current: string,
  wallet: string | null,
  {filled, touched}: Ownership,
): string | null {
  if (!wallet || touched || current === wallet) return null
  return current === "" || current === filled ? wallet : null
}

/**
 * Who the field belongs to once the server has re-rendered the form.
 *
 * A saved-draft count that moved means the save went through and the server
 * cleared the form, so the next draft starts over from the wallet selected now.
 * Any other form carrying errors is one the server sent back with what was
 * submitted, and every address on it is the customer's — including one that
 * still reads exactly like the default.
 */
export function ownershipAfterPatch(
  ownership: Ownership,
  saved: string | undefined,
  errors: boolean,
): Ownership {
  if (saved !== ownership.saved) return {saved, filled: null, touched: false}
  return errors ? {...ownership, touched: true} : ownership
}

export const AutolaunchLaunchDraft: Hook = {
  mounted(this: LaunchDraftHook) {
    let ownership: Ownership = {saved: this.el.dataset.savedDrafts, filled: null, touched: false}

    this.defaultTreasury = () => {
      const input = this.el.querySelector<HTMLInputElement>(treasuryField)
      if (!input) return

      const wallet = activeEthereumWallet()?.address ?? null
      const next = defaultedTreasury(input.value, wallet, ownership)
      if (next === null) return

      input.value = next
      ownership = {...ownership, filled: next}
    }

    // Any edit hands the field over, including clearing it and retyping the very
    // address the default put there.
    this.el.addEventListener("input", ({target}) => {
      if ((target as Element).matches(treasuryField)) ownership = {...ownership, touched: true}
    })

    this.patchedForm = () => {
      ownership = ownershipAfterPatch(
        ownership,
        this.el.dataset.savedDrafts,
        this.el.dataset.draftErrors === "true",
      )

      this.defaultTreasury?.()
    }

    // Privy's selection is what this reads, and a successful save clears the
    // form on the server, so the same default is applied again on every
    // re-render.
    window.addEventListener("ash:wallet-state", this.defaultTreasury)
    this.defaultTreasury()
  },

  updated(this: LaunchDraftHook) {
    this.patchedForm?.()
  },

  destroyed(this: LaunchDraftHook) {
    if (this.defaultTreasury) {
      window.removeEventListener("ash:wallet-state", this.defaultTreasury)
    }
  },
}
