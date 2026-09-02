export type EthereumProvider = {
  request(args: {method: string; params?: unknown[]}): Promise<unknown>
}

/**
 * One wallet Privy currently holds: the provider this page sends through, and
 * Privy's own way of letting go of it.
 */
export type ConnectedEthereumWallet = {provider: EthereumProvider; disconnect: () => void}

export type SelectedWallet = {address: string; provider: EthereumProvider}

// A visitor who chose Disconnect stays disconnected across reloads, whatever
// the wallet app still reports to Privy afterwards.
const disconnectedKey = "regent:wallet-disconnected:v1"

let connectedWallets = new Map<string, ConnectedEthereumWallet>()
let activeWallet: SelectedWallet | null = null

declare global {
  interface Window {
    __ashPlatformTestWallet?: {address: string; provider: EthereumProvider}
  }
}

export function replaceConnectedEthereumWallets(
  wallets: ReadonlyArray<readonly [string, ConnectedEthereumWallet]>,
): void {
  connectedWallets = new Map(wallets.map(([address, wallet]) => [address.toLowerCase(), wallet]))
}

export function connectedEthereumWallet(expectedSigner?: string): SelectedWallet | null {
  const testWallet = testEthereumWallet()
  if (testWallet) {
    if (!expectedSigner || testWallet.address.toLowerCase() === expectedSigner.toLowerCase()) {
      return testWallet
    }
    return null
  }

  if (expectedSigner) {
    return selectConnectedEthereumWallet([...connectedWallets.entries()], expectedSigner)
  }

  const first = connectedWallets.entries().next().value as
    | [string, ConnectedEthereumWallet]
    | undefined
  return first ? {address: first[0], provider: first[1].provider} : null
}

export function selectConnectedEthereumWallet(
  wallets: ReadonlyArray<readonly [string, ConnectedEthereumWallet]>,
  expectedSigner: string,
): SelectedWallet | null {
  const expected = expectedSigner.toLowerCase()
  const selected = wallets.find(([address]) => address.toLowerCase() === expected)
  return selected ? {address: selected[0], provider: selected[1].provider} : null
}

/**
 * The wallet Privy currently has selected, when that selection is an Ethereum
 * wallet that is still connected. Stake reads this and nothing else: an absent,
 * Solana or stale selection is no wallet, never a substitute one.
 */
export function replaceActiveEthereumWallet(wallet: SelectedWallet | null): void {
  activeWallet = wallet ? {address: wallet.address.toLowerCase(), provider: wallet.provider} : null
}

export function activeEthereumWallet(): SelectedWallet | null {
  return testEthereumWallet() ?? activeWallet
}

/**
 * Whether Privy's selected wallet is an Ethereum wallet that is still among the
 * connected ones. A Solana selection and a selection the provider has dropped
 * are both ineligible rather than a reason to pick another wallet.
 */
export function eligibleActiveWallet<W extends {address: string; type?: string}>(
  active: W | null | undefined,
  wallets: ReadonlyArray<{address: string}>,
): W | null {
  if (!active || active.type !== "ethereum") return null
  const address = active.address.toLowerCase()
  return wallets.some(wallet => wallet.address.toLowerCase() === address) ? active : null
}

/**
 * Every wallet Privy holds stops being this page's wallet, and the wallet apps
 * themselves are asked to drop the site. The releases are sent before this page
 * forgets them, and the page is disconnected from that point whatever any of
 * them answers, so a wallet app that never answers cannot hold Disconnect open.
 */
export async function disconnectEveryEthereumWallet(walletEvents: EventTarget): Promise<void> {
  const released = [...connectedWallets.values()].flatMap(wallet => [
    Promise.resolve().then(() => wallet.disconnect()),
    Promise.resolve().then(() => revokeSitePermissions(wallet.provider)),
  ])

  replaceConnectedEthereumWallets([])
  replaceActiveEthereumWallet(null)
  rememberWalletDisconnected()
  walletEvents.dispatchEvent(new CustomEvent("ash:wallet-state"))

  await Promise.allSettled(released)
}

// EIP-2255: the site asks the wallet app itself to take back the accounts it
// exposed. An app that refuses the request, or has never heard of it, is
// revoked as far as this page can take it.
function revokeSitePermissions(provider: EthereumProvider): Promise<unknown> {
  return provider.request({method: "wallet_revokePermissions", params: [{eth_accounts: {}}]})
}

export function walletDisconnected(): boolean {
  try {
    return disconnectedStorage()?.getItem(disconnectedKey) === "true"
  } catch {
    return false
  }
}

export function rememberWalletDisconnected(): void {
  try {
    disconnectedStorage()?.setItem(disconnectedKey, "true")
  } catch {
    // A browser that refuses storage still disconnected everything above.
  }
}

export function forgetWalletDisconnected(): void {
  try {
    disconnectedStorage()?.removeItem(disconnectedKey)
  } catch {
    // Nothing was remembered, so there is nothing to forget.
  }
}

function disconnectedStorage(): Pick<Storage, "getItem" | "setItem" | "removeItem"> | null {
  try {
    return window.localStorage ?? null
  } catch {
    return null
  }
}

// The browser test seam stands in for Privy's selection as well as for the
// connected set, so the same wallet drives Stake there as in a real browser —
// including staying gone after the visitor disconnects it.
function testEthereumWallet(): SelectedWallet | null {
  return window.location.origin === "http://127.0.0.1:4002" &&
    window.__ashPlatformTestWallet &&
    !walletDisconnected()
    ? window.__ashPlatformTestWallet
    : null
}
