import {
  createPublicClient,
  getAddress,
  http,
  isAddress,
  type Address,
  type PublicClient,
} from "viem"
import {mainnet} from "viem/chains"

import type {Hook} from "../hook_composition"

export type EnsIdentity = {name: string; avatar: string | null}

const ensClient = createPublicClient({
  chain: mainnet,
  transport: http("https://ethereum-rpc.publicnode.com"),
})

export function shortenAddress(address: string): string {
  return address.length === 42 ? `${address.slice(0, 6)}…${address.slice(-4)}` : address
}

export async function resolveEnsIdentity(
  address: Address,
  client: Pick<PublicClient, "getEnsName" | "getEnsAddress" | "getEnsAvatar"> = ensClient,
): Promise<EnsIdentity | null> {
  const name = await client.getEnsName({address})
  if (!name) return null

  const forward = await client.getEnsAddress({name})
  if (!forward || getAddress(forward) !== getAddress(address)) return null

  const avatar = await client.getEnsAvatar({name}).catch(() => null)
  return {name, avatar}
}

type AccountIdentityHook = Hook & {
  el: HTMLElement
  identityGeneration?: number
  copyListener?: (event: Event) => void
  copyReset?: number
}

function elements(root: HTMLElement) {
  return {
    labels: root.querySelectorAll<HTMLElement>("[data-account-identity-label]"),
    avatars: root.querySelectorAll<HTMLImageElement>("[data-account-identity-avatar]"),
    address: root.querySelector<HTMLElement>("[data-account-identity-address]"),
    copyLabel: root.querySelector<HTMLElement>("[data-account-copy-label]"),
  }
}

function render(root: HTMLElement, label: string, avatar: string | null, address: string): void {
  const targets = elements(root)
  targets.labels.forEach(target => (target.textContent = label))
  targets.address && (targets.address.textContent = shortenAddress(address))
  targets.avatars.forEach(target => {
    if (avatar) target.src = avatar
  })
}

function startResolution(hook: AccountIdentityHook): void {
  const address = hook.el.dataset.walletAddress ?? ""
  const fallbackLabel = hook.el.dataset.fallbackLabel ?? shortenAddress(address)
  const fallbackAvatar = hook.el.dataset.fallbackAvatar || null
  const generation = (hook.identityGeneration ?? 0) + 1
  hook.identityGeneration = generation

  render(hook.el, fallbackLabel, fallbackAvatar, address)
  if (!isAddress(address)) return

  void resolveEnsIdentity(getAddress(address)).then(identity => {
    if (
      hook.identityGeneration !== generation ||
      hook.el.dataset.walletAddress !== address ||
      !hook.el.isConnected ||
      !identity
    ) return
    render(hook.el, identity.name, identity.avatar ?? fallbackAvatar, address)
  }).catch(() => undefined)
}

export const AccountIdentity: Hook = {
  mounted(this: AccountIdentityHook) {
    this.copyListener = event => {
      const target = event.target instanceof Element ? event.target : null
      if (!target?.closest("[data-account-copy-address]")) return

      const address = this.el.dataset.walletAddress ?? ""
      if (!isAddress(address)) return

      void navigator.clipboard.writeText(getAddress(address)).then(() => {
        const label = elements(this.el).copyLabel
        if (!label) return
        label.textContent = "Copied"
        if (this.copyReset) window.clearTimeout(this.copyReset)
        this.copyReset = window.setTimeout(() => {
          const current = elements(this.el).copyLabel
          if (current) current.textContent = "Copy address"
        }, 1_500)
      }).catch(() => undefined)
    }

    this.el.addEventListener("click", this.copyListener)
    startResolution(this)
  },

  updated(this: AccountIdentityHook) {
    startResolution(this)
  },

  destroyed(this: AccountIdentityHook) {
    this.identityGeneration = (this.identityGeneration ?? 0) + 1
    if (this.copyListener) this.el.removeEventListener("click", this.copyListener)
    if (this.copyReset) window.clearTimeout(this.copyReset)
  },
}
