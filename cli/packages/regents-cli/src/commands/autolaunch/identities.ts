import {
  createPublicClient,
  createWalletClient,
  http,
  parseEventLogs,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { base, baseSepolia } from "viem/chains";

import { getFlag, type ParsedCliArgs } from "../../parse.js";
import { printJson } from "../../printer.js";
import { assertSuccessfulReceipt } from "../../internal-runtime/base-contract-client.js";
import {
  AGENT_PRIVATE_KEY_ENV,
  autolaunchChainId,
  type AutolaunchChainId,
} from "./shared.js";

const IDENTITY_REGISTRY_ABI = [
  {
    inputs: [],
    name: "register",
    outputs: [{ internalType: "uint256", name: "agentId", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "string", name: "agentURI", type: "string" }],
    name: "register",
    outputs: [{ internalType: "uint256", name: "agentId", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, internalType: "uint256", name: "agentId", type: "uint256" },
      { indexed: false, internalType: "string", name: "agentURI", type: "string" },
      { indexed: true, internalType: "address", name: "owner", type: "address" },
    ],
    name: "Registered",
    type: "event",
  },
] as const;
const ERC8004_QUERY = `
  query Agents($where: Agent_filter, $first: Int!) {
    agents(where: $where, first: $first, orderBy: updatedAt, orderDirection: desc) {
      chainId
      agentId
      owner
      operators
      agentWallet
      registrationFile {
        name
        description
        image
        ens
        webEndpoint
        active
      }
    }
  }
`;
const ERC8004_MAX_RESULTS = 100;

interface GraphAgent {
  readonly chainId?: string | number;
  readonly agentId?: string | number;
  readonly owner?: string | null;
  readonly operators?: readonly string[] | null;
  readonly agentWallet?: string | null;
  readonly registrationFile?: {
    readonly name?: string | null;
    readonly description?: string | null;
    readonly image?: string | null;
    readonly ens?: string | null;
    readonly webEndpoint?: string | null;
    readonly active?: boolean | null;
  } | null;
}

interface IdentityRecord {
  readonly agent_id: string;
  readonly chain_id: number;
  readonly token_id: string;
  readonly owner_address: string | null;
  readonly operator_addresses: string[];
  readonly agent_wallet: string | null;
  readonly access_mode: "owner" | "operator" | "wallet_bound";
  readonly name: string;
  readonly description: string | null;
  readonly image_url: string | null;
  readonly ens: string | null;
  readonly web_endpoint: string | null;
  readonly active: boolean;
  readonly registry_address: string;
}

export interface IdentityListResult {
  readonly ok: true;
  readonly chain_id: number;
  readonly owner_address: string;
  readonly registry_address: string;
  readonly launchable: IdentityRecord[];
  readonly owned: IdentityRecord[];
  readonly operated: IdentityRecord[];
  readonly wallet_bound: IdentityRecord[];
}

export interface IdentityMintResult {
  readonly ok: true;
  readonly chain_id: number;
  readonly owner_address: string;
  readonly registry_address: string;
  readonly tx_hash: string;
  readonly block_number: string;
  readonly agent_id: string | null;
  readonly agent_uri: string | null;
}

const rpcUrlForChain = (chainId: AutolaunchChainId, args: ParsedCliArgs): string => {
  const explicit = getFlag(args, "rpc-url");
  if (explicit) {
    return explicit;
  }

  if (chainId === "84532") {
    const envValue = process.env.BASE_SEPOLIA_RPC_URL;
    if (envValue) {
      return envValue;
    }
  }

  if (chainId === "8453") {
    const envValue = process.env.BASE_MAINNET_RPC_URL ?? process.env.BASE_RPC_URL;
    if (envValue) {
      return envValue;
    }
  }

  throw new Error("missing Base RPC URL (--rpc-url or BASE_SEPOLIA_RPC_URL / BASE_MAINNET_RPC_URL)");
};

const privateKeyForCommand = (args: ParsedCliArgs): Hex => {
  const explicit =
    getFlag(args, "private-key") ??
    process.env[AGENT_PRIVATE_KEY_ENV] ??
    process.env.REGENT_WALLET_PRIVATE_KEY;

  if (!explicit) {
    throw new Error(
      "missing private key (--private-key, AUTOLAUNCH_AGENT_PRIVATE_KEY, or REGENT_WALLET_PRIVATE_KEY)",
    );
  }

  const normalized = explicit.trim() as Hex;
  if (!/^0x[0-9a-fA-F]{64}$/.test(normalized)) {
    throw new Error("private key must be a 32-byte hex string");
  }

  return normalized;
};

const ownerAddressForList = (args: ParsedCliArgs): Address => {
  const explicit = getFlag(args, "owner");
  if (explicit) {
    return normalizeCliAddress(explicit);
  }

  return privateKeyToAccount(privateKeyForCommand(args)).address;
};

const normalizeCliAddress = (value: string): Address => {
  const normalized = value.trim().toLowerCase();
  if (!/^0x[0-9a-f]{40}$/.test(normalized)) {
    throw new Error("expected a valid 20-byte hex address");
  }

  return normalized as Address;
};

const subgraphUrlForChain = (chainId: AutolaunchChainId): string => {
  const value = process.env.AUTOLAUNCH_ERC8004_SUBGRAPH_URL;
  if (!value) {
    throw new Error(`missing AUTOLAUNCH_ERC8004_SUBGRAPH_URL for chain ${chainId}`);
  }

  return value;
};

const registryAddressForChain = (chainId: AutolaunchChainId): Address => {
  const value = process.env.AUTOLAUNCH_IDENTITY_REGISTRY_ADDRESS;
  if (!value) {
    throw new Error(`missing AUTOLAUNCH_IDENTITY_REGISTRY_ADDRESS for chain ${chainId}`);
  }

  return normalizeCliAddress(value);
};

const chainForViem = (chainId: AutolaunchChainId) =>
  chainId === "84532" ? baseSepolia : base;

const fetchErc8004Agents = async (
  chainId: AutolaunchChainId,
  where: Record<string, unknown>,
): Promise<GraphAgent[]> => {
  const response = await fetch(subgraphUrlForChain(chainId), {
    method: "POST",
    headers: { accept: "application/json", "content-type": "application/json" },
    body: JSON.stringify({
      query: ERC8004_QUERY,
      variables: { where, first: ERC8004_MAX_RESULTS },
    }),
  });

  if (!response.ok) {
    throw new Error(`ERC-8004 subgraph request failed: ${await response.text()}`);
  }

  const payload = (await response.json()) as { data?: { agents?: GraphAgent[] } };
  return payload.data?.agents ?? [];
};

const buildIdentityRecord = (
  chainId: AutolaunchChainId,
  agent: GraphAgent,
  walletAddress: Address,
  mode: "owner" | "operator" | "wallet_bound",
): IdentityRecord => {
  const registration = agent.registrationFile ?? undefined;
  const tokenId = String(agent.agentId ?? "");
  const registryAddress = registryAddressForChain(chainId);
  const owner = typeof agent.owner === "string" ? agent.owner.toLowerCase() : null;
  const operators = Array.isArray(agent.operators)
    ? agent.operators
        .filter((value): value is string => typeof value === "string")
        .map((value) => value.toLowerCase())
    : [];
  const agentWallet = typeof agent.agentWallet === "string" ? agent.agentWallet.toLowerCase() : null;

  const accessMode: IdentityRecord["access_mode"] =
    owner === walletAddress
      ? "owner"
      : operators.includes(walletAddress)
        ? "operator"
        : mode;

  return {
    agent_id: `eip155:${chainId}:${registryAddress}:${tokenId}`,
    chain_id: Number.parseInt(chainId, 10),
    token_id: tokenId,
    owner_address: owner,
    operator_addresses: operators,
    agent_wallet: agentWallet,
    access_mode: accessMode,
    name: registration?.name?.trim() || `ERC-8004 Agent #${tokenId}`,
    description: registration?.description?.trim() || null,
    image_url: registration?.image?.trim() || null,
    ens: registration?.ens?.trim() || null,
    web_endpoint: registration?.webEndpoint?.trim() || null,
    active: Boolean(registration?.active),
    registry_address: registryAddress,
  };
};

const sortIdentities = (items: readonly IdentityRecord[]): IdentityRecord[] => {
  return [...items].sort((left, right) => {
    const modeRank = (value: IdentityRecord["access_mode"]): number =>
      value === "owner" ? 0 : value === "operator" ? 1 : 2;
    return (
      modeRank(left.access_mode) - modeRank(right.access_mode) ||
      left.name.localeCompare(right.name) ||
      left.agent_id.localeCompare(right.agent_id)
    );
  });
};

export async function listAutolaunchIdentities(args: ParsedCliArgs): Promise<IdentityListResult> {
  const chainId = autolaunchChainId(args);
  const walletAddress = ownerAddressForList(args);
  const owned = (
    await fetchErc8004Agents(chainId, {
      owner_in: [walletAddress],
    })
  ).map((agent) => buildIdentityRecord(chainId, agent, walletAddress, "owner"));
  const operated = (
    await fetchErc8004Agents(chainId, {
      operators_contains: [walletAddress],
    })
  ).map((agent) => buildIdentityRecord(chainId, agent, walletAddress, "operator"));
  const walletBound = (
    await fetchErc8004Agents(chainId, {
      agentWallet: walletAddress,
    })
  ).map((agent) => buildIdentityRecord(chainId, agent, walletAddress, "wallet_bound"));

  const launchableMap = new Map<string, IdentityRecord>();
  for (const item of [...owned, ...operated]) {
    if (!launchableMap.has(item.agent_id)) {
      launchableMap.set(item.agent_id, item);
    }
  }

  const walletBoundOnly = walletBound.filter((item) => !launchableMap.has(item.agent_id));

  return {
    ok: true,
    chain_id: Number.parseInt(chainId, 10),
    owner_address: walletAddress,
    registry_address: registryAddressForChain(chainId),
    launchable: sortIdentities([...launchableMap.values()]),
    owned: sortIdentities(owned),
    operated: sortIdentities(
      operated.filter((item) => !owned.some((ownedItem) => ownedItem.agent_id === item.agent_id)),
    ),
    wallet_bound: sortIdentities(walletBoundOnly),
  };
}

export async function runAutolaunchIdentitiesList(args: ParsedCliArgs): Promise<void> {
  printJson(await listAutolaunchIdentities(args));
}

export async function mintAutolaunchIdentity(args: ParsedCliArgs): Promise<IdentityMintResult> {
  const chainId = autolaunchChainId(args);
  const privateKey = privateKeyForCommand(args);
  const account = privateKeyToAccount(privateKey);
  const chain = chainForViem(chainId);
  const registryAddress = registryAddressForChain(chainId);
  const rpcUrl = rpcUrlForChain(chainId, args);
  const publicClient = createPublicClient({ chain, transport: http(rpcUrl) });
  const walletClient = createWalletClient({
    account,
    chain,
    transport: http(rpcUrl),
  });
  const agentUri = getFlag(args, "agent-uri");

  const txHash = await walletClient.writeContract({
    address: registryAddress,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "register",
    args: agentUri ? [agentUri] : [],
  });

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  assertSuccessfulReceipt(receipt);
  const events = parseEventLogs({
    abi: IDENTITY_REGISTRY_ABI,
    logs: receipt.logs,
    eventName: "Registered",
  });
  const registered = events[0];
  const rawAgentId = registered?.args.agentId;
  const agentId =
    rawAgentId !== undefined
      ? `eip155:${chainId}:${registryAddress}:${typeof rawAgentId === "bigint" ? rawAgentId.toString() : String(rawAgentId)}`
      : null;

  return {
    ok: true,
    chain_id: Number.parseInt(chainId, 10),
    owner_address: account.address,
    registry_address: registryAddress,
    tx_hash: txHash,
    block_number: receipt.blockNumber.toString(),
    agent_id: agentId,
    agent_uri: agentUri ?? null,
  };
}

export async function runAutolaunchIdentitiesMint(args: ParsedCliArgs): Promise<void> {
  printJson(await mintAutolaunchIdentity(args));
}
