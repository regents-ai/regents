export type EthereumProvider = {
  request(args: {method: string; params?: unknown[]}): Promise<unknown>
}

let connectedWallets = new Map<string, EthereumProvider>()

declare global {
  interface Window {
    __ashPlatformTestWallet?: {address: string; provider: EthereumProvider}
  }
}

export function replaceConnectedEthereumWallets(
  wallets: ReadonlyArray<readonly [string, EthereumProvider]>,
): void {
  connectedWallets = new Map(wallets.map(([address, provider]) => [address.toLowerCase(), provider]))
}

export function connectedEthereumWallet(expectedSigner?: string): {
  address: string
  provider: EthereumProvider
} | null {
  if (
    window.location.origin === "http://127.0.0.1:4002" &&
    window.__ashPlatformTestWallet
  ) {
    const testWallet = window.__ashPlatformTestWallet
    if (!expectedSigner || testWallet.address.toLowerCase() === expectedSigner.toLowerCase()) {
      return testWallet
    }
    return null
  }

  if (expectedSigner) {
    return selectConnectedEthereumWallet([...connectedWallets.entries()], expectedSigner)
  }

  const first = connectedWallets.entries().next().value as [string, EthereumProvider] | undefined
  return first ? {address: first[0], provider: first[1]} : null
}

export function selectConnectedEthereumWallet(
  wallets: ReadonlyArray<readonly [string, EthereumProvider]>,
  expectedSigner: string,
): {address: string; provider: EthereumProvider} | null {
  const expected = expectedSigner.toLowerCase()
  const selected = wallets.find(([address]) => address.toLowerCase() === expected)
  return selected ? {address: selected[0], provider: selected[1]} : null
}
