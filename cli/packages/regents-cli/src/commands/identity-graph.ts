import { createPublicClient, http } from "viem";

import type { RegentIdentityReceipt } from "../internal-types/index.js";

import { readIdentityReceipt } from "../internal-runtime/identity/cache.js";
import { getBooleanFlag, parseCliArgs, type ParsedCliArgs } from "../parse.js";
import {
  CLI_PALETTE,
  printJson,
  printText,
  renderKeyValuePanel,
  renderPanel,
  renderTablePanel,
} from "../printer.js";
import { receiptAgentKey, receiptAgentTokenId } from "../internal-runtime/identity/shared.js";
import { loadResolvedPlatformSession, requestPlatformSessionJson } from "./platform.js";
import { requestProductJson } from "./product-http.js";

type CheckStatus = "MATCH" | "MISMATCH" | "UNVERIFIABLE";

interface GraphCheck {
  readonly item: string;
  readonly status: CheckStatus;
  readonly detail: string;
  readonly reason?: string;
  readonly next?: string;
}

interface PlatformLink {
  readonly platform_agent_id: string | null;
  readonly regent_id: string | null;
  readonly public_slug: string | null;
  readonly claimed_name: string | null;
  readonly hosted_runtime_id: string | null;
  readonly techtree: {
    readonly profile_id: string | null;
    readonly node_ids: readonly string[];
    readonly bbh_run_ids: readonly string[];
    readonly review_ids: readonly string[];
  };
}

interface ProductLinkResult<TLink> {
  readonly link: TLink | null;
  readonly check: GraphCheck;
}

interface AutolaunchLink {
  readonly subject_id: string | null;
  readonly launch_id: string | null;
  readonly auction_id: string | null;
}

const ERC721_OWNER_OF_ABI = [
  {
    type: "function",
    name: "ownerOf",
    stateMutability: "view",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ name: "owner", type: "address" }],
  },
] as const;

const asRecord = (value: unknown): Record<string, unknown> | null =>
  value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;

const asRecordArray = (value: unknown): readonly Record<string, unknown>[] =>
  Array.isArray(value)
    ? value.flatMap((item) => {
        const record = asRecord(item);
        return record ? [record] : [];
      })
    : [];

const asText = (value: unknown): string | null =>
  typeof value === "string" && value.trim() !== "" ? value : null;

const asId = (value: unknown): string | null => {
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }

  return asText(value);
};

const asIdArray = (value: unknown): readonly string[] =>
  Array.isArray(value) ? value.flatMap((item) => asId(item) ?? []) : [];

const sameAddress = (left: string, right: string): boolean =>
  left.toLowerCase() === right.toLowerCase();

const errorText = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

const rpcUrlForReceipt = (receipt: RegentIdentityReceipt): string | undefined =>
  receipt.network === "base"
    ? process.env.BASE_MAINNET_RPC_URL ?? process.env.BASE_RPC_URL
    : process.env.BASE_SEPOLIA_RPC_URL;

const registryOwnershipCheck = async (receipt: RegentIdentityReceipt): Promise<GraphCheck> => {
  const item = "registry ownership (chain)";
  const rpcUrl = rpcUrlForReceipt(receipt);

  if (!rpcUrl) {
    return {
      item,
      status: "UNVERIFIABLE",
      detail: `agent ${receiptAgentKey(receipt)} on ${receipt.agent_registry}`,
      reason:
        receipt.network === "base"
          ? "Set BASE_MAINNET_RPC_URL or BASE_RPC_URL to verify registry ownership onchain."
          : "Set BASE_SEPOLIA_RPC_URL to verify registry ownership onchain.",
    };
  }

  try {
    const publicClient = createPublicClient({ transport: http(rpcUrl) });
    const owner = (await publicClient.readContract({
      address: receipt.agent_registry as `0x${string}`,
      abi: ERC721_OWNER_OF_ABI,
      functionName: "ownerOf",
      args: [BigInt(receiptAgentTokenId(receipt))],
    })) as string;

    if (sameAddress(owner, receipt.address)) {
      return {
        item,
        status: "MATCH",
        detail: `the registry owner of agent ${receiptAgentKey(receipt)} is the saved wallet`,
      };
    }

    return {
      item,
      status: "MISMATCH",
      detail: `the registry says agent ${receiptAgentKey(receipt)} is owned by ${owner}, not ${receipt.address}`,
      next: "Chain wins for ownership. Run regents identity ensure --force-refresh to rebuild the local identity from the owning wallet.",
    };
  } catch (error) {
    return {
      item,
      status: "UNVERIFIABLE",
      detail: `agent ${receiptAgentKey(receipt)} on ${receipt.agent_registry}`,
      reason: errorText(error),
    };
  }
};

const platformLinkResult = async (
  args: ParsedCliArgs,
  receipt: RegentIdentityReceipt,
  configPath?: string,
): Promise<ProductLinkResult<PlatformLink>> => {
  const item = "platform link";

  try {
    const { origin, session } = await loadResolvedPlatformSession(args);
    const { data } = await requestPlatformSessionJson({
      origin,
      session,
      method: "GET",
      path: "/api/platform/projection",
      commandName: "regents identity graph",
      configPath,
    });

    const projection = asRecord(data.projection) ?? {};
    const profiles = asRecordArray(projection.public_profiles);
    const identityLinks = asRecord(projection.identity_links) ?? {};
    const techtreeLinks = asRecord(identityLinks.techtree) ?? {};
    const profile =
      profiles.find((candidate) => {
        const wallet = asText(candidate.wallet_address);
        return wallet !== null && sameAddress(wallet, receipt.address);
      }) ?? profiles[0];
    const regents = asRecordArray(projection.regents);
    const regentRecord = asRecord(regents[0]?.regent);

    if (!profile && !regentRecord) {
      return {
        link: null,
        check: {
          item,
          status: "MATCH",
          detail: "Platform has no agent record for this account yet",
        },
      };
    }

    const link: PlatformLink = {
      platform_agent_id: asId(profile?.id ?? regentRecord?.id),
      regent_id: asId(regentRecord?.id),
      public_slug: asText(profile?.slug ?? regentRecord?.slug),
      claimed_name: asText(profile?.claimed_label ?? regentRecord?.claimed_label),
      hosted_runtime_id: asText(regentRecord?.sprite_service_name ?? regentRecord?.sprite_name),
      techtree: {
        profile_id: asId(techtreeLinks.profile_id),
        node_ids: asIdArray(techtreeLinks.node_ids),
        bbh_run_ids: asIdArray(techtreeLinks.bbh_run_ids),
        review_ids: asIdArray(techtreeLinks.review_ids),
      },
    };

    const profileWallet = asText(profile?.wallet_address);
    if (profileWallet && !sameAddress(profileWallet, receipt.address)) {
      return {
        link,
        check: {
          item,
          status: "MISMATCH",
          detail: `Platform records wallet ${profileWallet} for this agent, not ${receipt.address}`,
          next: "Chain wins for ownership. Re-link the Platform agent to the registry-owning wallet with regents agent link.",
        },
      };
    }

    return {
      link,
      check: {
        item,
        status: "MATCH",
        detail: link.public_slug
          ? `Platform agent ${link.public_slug} matches the saved wallet`
          : "Platform record matches the saved wallet",
      },
    };
  } catch (error) {
    return {
      link: null,
      check: { item, status: "UNVERIFIABLE", detail: "Platform projection", reason: errorText(error) },
    };
  }
};

const resolveSubjectId = async (
  tokenAddress: string,
  configPath?: string,
): Promise<string | null> => {
  try {
    const payload = await requestProductJson<Record<string, unknown>>(
      "GET",
      `/api/autolaunch/v1/agent/subjects/by-token/${encodeURIComponent(tokenAddress)}`,
      {
        requireAgentAuth: true,
        authAudience: "autolaunch",
        service: "autolaunch",
        commandName: "regents identity graph",
        configPath,
      },
    );

    return asId(asRecordArray(payload.subjects)[0]?.subject_id);
  } catch {
    return null;
  }
};

const autolaunchLinkResult = async (
  receipt: RegentIdentityReceipt,
  configPath?: string,
): Promise<ProductLinkResult<AutolaunchLink>> => {
  const item = "autolaunch link";

  try {
    const payload = await requestProductJson<Record<string, unknown>>("GET", "/api/autolaunch/v1/agent/agents", {
      requireAgentAuth: true,
      authAudience: "autolaunch",
      service: "autolaunch",
      commandName: "regents identity graph",
      configPath,
    });

    const agentId = receiptAgentKey(receipt);
    const card = asRecordArray(payload.items ?? payload.data).find(
      (candidate) => asId(candidate.agent_id) === agentId,
    );

    if (!card) {
      return {
        link: null,
        check: {
          item,
          status: "MATCH",
          detail: `Autolaunch has no record for agent ${agentId} yet`,
        },
      };
    }

    const cardOwner = asText(card.owner_address);
    const cardRegistry = asText(card.registry_address);
    const existingToken = asRecord(card.existing_token);
    const tokenAddress = asText(existingToken?.token_address);
    const link: AutolaunchLink = {
      subject_id: tokenAddress ? await resolveSubjectId(tokenAddress, configPath) : null,
      launch_id: null,
      auction_id: asId(existingToken?.auction_id),
    };

    if (cardOwner && !sameAddress(cardOwner, receipt.address)) {
      return {
        link,
        check: {
          item,
          status: "MISMATCH",
          detail: `Autolaunch records owner ${cardOwner} for agent ${agentId}, not ${receipt.address}`,
          next: "Chain wins for ownership. Refresh the Autolaunch agent record from the registry-owning wallet.",
        },
      };
    }

    if (cardRegistry && !sameAddress(cardRegistry, receipt.agent_registry)) {
      return {
        link,
        check: {
          item,
          status: "MISMATCH",
          detail: `Autolaunch records registry ${cardRegistry} for agent ${agentId}, not ${receipt.agent_registry}`,
          next: "Chain wins for ownership. Re-pair the agent in Autolaunch so it points at the saved registry.",
        },
      };
    }

    return {
      link,
      check: {
        item,
        status: "MATCH",
        detail: `Autolaunch agent record matches the saved wallet tuple`,
      },
    };
  } catch (error) {
    return {
      link: null,
      check: { item, status: "UNVERIFIABLE", detail: "Autolaunch agent record", reason: errorText(error) },
    };
  }
};

const mobileCheck: GraphCheck = {
  item: "mobile link",
  status: "UNVERIFIABLE",
  detail: "mobile identity record",
  reason: "Mobile identity APIs are not part of the CLI contract surface.",
};

const waitingGraph = () => ({
  ok: false,
  command: "identity graph",
  status: "waiting",
  agent_id: null,
  wallet_tuple: null,
  local_receipt: null,
  product_links: {
    platform: null,
    autolaunch: null,
    mobile: null,
    erc8004_agentbook: null,
  },
  checks: [] as GraphCheck[],
  gaps: ["Run regents identity ensure to create the local identity receipt."],
});

const buildGraph = async (args: ParsedCliArgs, configPath?: string) => {
  const receipt = readIdentityReceipt();

  if (!receipt) {
    return waitingGraph();
  }

  const registryCheck = await registryOwnershipCheck(receipt);
  const platform = await platformLinkResult(args, receipt, configPath);
  const autolaunch = await autolaunchLinkResult(receipt, configPath);
  const checks = [registryCheck, platform.check, autolaunch.check, mobileCheck];
  const mismatched = checks.some((check) => check.status === "MISMATCH");
  const agentId = receiptAgentKey(receipt);

  return {
    ok: !mismatched,
    command: "identity graph",
    status: mismatched ? "mismatch" : "ready",
    agent_id: agentId,
    wallet_tuple: {
      wallet_address: receipt.address,
      chain_id: receipt.network === "base" ? 8453 : 84532,
      registry_address: receipt.agent_registry,
      token_id: receiptAgentTokenId(receipt),
    },
    local_receipt: {
      provider: receipt.provider,
      network: receipt.network,
      verified: receipt.verified,
      receipt_expires_at: receipt.receipt_expires_at,
    },
    product_links: {
      platform: platform.link,
      autolaunch: autolaunch.link,
      mobile: null,
      erc8004_agentbook: {
        agent_id: agentId,
        registry_address: receipt.agent_registry,
        token_id: receiptAgentTokenId(receipt),
      },
    },
    checks,
    gaps: [
      "Autolaunch does not expose launch_id on the agent record yet, so launch_id stays null.",
      "Platform does not expose mobile identity links through the CLI contract yet, so mobile stays null.",
    ],
  };
};

const statusColor = (status: CheckStatus): string => {
  if (status === "MATCH") {
    return CLI_PALETTE.emphasis;
  }
  if (status === "MISMATCH") {
    return CLI_PALETTE.error;
  }
  return CLI_PALETTE.secondary;
};

const checkRow = (check: GraphCheck) => ({
  cells: [
    check.item,
    check.status === "UNVERIFIABLE" ? `UNVERIFIABLE(${check.reason ?? "unknown"})` : check.status,
    check.detail,
  ],
  colors: [undefined, statusColor(check.status), undefined],
});

const renderHumanGraph = (graph: Awaited<ReturnType<typeof buildGraph>>): string => {
  const mappingRows = [
    { cells: ["agent id", graph.agent_id ?? "not ready"] },
    { cells: ["wallet", graph.wallet_tuple?.wallet_address ?? "not ready"] },
    { cells: ["chain", graph.wallet_tuple ? String(graph.wallet_tuple.chain_id) : "not ready"] },
    { cells: ["registry", graph.wallet_tuple?.registry_address ?? "not ready"] },
    { cells: ["token", graph.wallet_tuple?.token_id ?? "not ready"] },
  ];
  const nextLines = graph.checks
    .filter((check) => check.next !== undefined)
    .map((check) => `Next: ${check.next}`);

  return [
    renderKeyValuePanel("◆ IDENTITY GRAPH", [
      {
        label: "status",
        value: graph.status,
        valueColor: graph.ok ? CLI_PALETTE.emphasis : CLI_PALETTE.error,
      },
      { label: "source", value: graph.local_receipt ? "local receipt + product APIs + chain" : "missing" },
    ], {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
    renderTablePanel("◆ CURRENT MAPPING", [{ header: "field" }, { header: "value" }], mappingRows),
    ...(graph.checks.length > 0
      ? [
          renderTablePanel(
            "◆ CHECKS",
            [{ header: "item" }, { header: "status" }, { header: "detail" }],
            graph.checks.map(checkRow),
          ),
        ]
      : []),
    ...(nextLines.length > 0 || graph.gaps.length > 0
      ? [renderPanel("◆ NEXT", [...nextLines, ...graph.gaps])]
      : []),
  ].join("\n\n");
};

export async function runIdentityGraph(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<number> {
  const parsedArgs = Array.isArray(args) ? parseCliArgs(args) : (args as ParsedCliArgs);
  const json = getBooleanFlag(parsedArgs, "json");
  const graph = await buildGraph(parsedArgs, configPath);

  if (json) {
    printJson(graph);
  } else {
    printText(renderHumanGraph(graph));
  }

  return graph.ok ? 0 : 1;
}
