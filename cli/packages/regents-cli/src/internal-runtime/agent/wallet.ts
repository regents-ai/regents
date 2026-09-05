import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

export async function deriveWalletAddress(privateKey: `0x${string}`): Promise<`0x${string}`> {
  return privateKeyToAccount(privateKey).address as `0x${string}`;
}

export async function signPersonalMessage(
  privateKey: `0x${string}`,
  message: string,
): Promise<`0x${string}`> {
  const account = privateKeyToAccount(privateKey);
  return (await account.signMessage({ message })) as `0x${string}`;
}

export async function generateWallet(): Promise<{
  privateKey: `0x${string}`;
  address: `0x${string}`;
}> {
  const privateKey = generatePrivateKey();
  const account = privateKeyToAccount(privateKey);
  return {
    privateKey,
    address: account.address as `0x${string}`,
  };
}
