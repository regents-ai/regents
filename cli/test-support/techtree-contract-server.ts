import http from "node:http";
import { once } from "node:events";
import type { AddressInfo } from "node:net";

import type {
  ActivityEvent,
  AgentInboxResponse,
  AgentOpportunitiesResponse,
  CommentCreateResponse,
  IdentityRegistrationCompletionResponse,
  IdentityRegistrationIntentResponse,
  IdentitySiwaNonceResponse,
  IdentitySiwaVerifyResponse,
  IdentityStatusResponse,
  NodeStarRecord,
  NodeCreateResponse,
  ScienceTaskChecklistEntry,
  ScienceTaskDetail,
  ScienceTaskDetailResponse,
  ScienceTaskListResponse,
  ScienceTaskMutationResponse,
  ScienceTaskRunEvidence,
  SiwaNonceResponse,
  SiwaVerifyResponse,
  TreeComment,
  TreeNode,
  WatchRecord,
  WorkPacketResponse,
} from "../packages/regents-cli/src/internal-types/index.js";

import {
  buildHttpSignatureSigningMessage,
  coveredComponentsForAgentHeaders,
  parseSignatureInputHeader,
} from "../packages/regents-cli/src/internal-runtime/siwa/signing.js";

const REQUIRED_AUTH_HEADERS = [
  "x-siwa-receipt",
  "x-key-id",
  "x-timestamp",
  "signature-input",
  "signature",
  "x-agent-wallet-address",
  "x-agent-chain-id",
  "x-agent-registry-address",
  "x-agent-token-id",
] as const;

const REQUIRED_SIGNATURE_COMPONENTS = coveredComponentsForAgentHeaders({
  includeContentDigest: false,
});

const TEST_AGENT_WALLET = "0x1111111111111111111111111111111111111111" as const;
const TEST_AGENT_REGISTRY = "0x2222222222222222222222222222222222222222" as const;
const TEST_AGENT_TOKEN_ID = "99";
const TEST_AGENT_SUMMARY = {
  id: 1,
  label: "Contract test agent",
  wallet_address: TEST_AGENT_WALLET,
} as const;
const agentRegistryBinding = (): string =>
  `eip155:8453:${TEST_AGENT_REGISTRY}`;
const agentIdentityKey = (agentRegistry: string, tokenId: string): string =>
  `${agentRegistry}:${tokenId}`;

export interface ForcedRouteResponse {
  statusCode: number;
  payload: unknown;
}

export interface TechtreeContractServerOptions {
  healthResponse?: ForcedRouteResponse;
  nonceResponse?: ForcedRouteResponse;
  verifyResponse?: ForcedRouteResponse;
  inboxResponse?: ForcedRouteResponse;
  opportunitiesResponse?: ForcedRouteResponse;
}

export interface ContractRequestRecord {
  method: string;
  pathname: string;
  search: string;
  headers: Record<string, string>;
  body: unknown;
}

interface IssuedNonceRecord {
  walletAddress: `0x${string}`;
  chainId: number;
  audience: "platform" | "autolaunch" | "techtree" | "regent-services";
  expiresAtUnixSeconds: number;
}

interface RegistrationIntentRecord {
  intentId: string;
  address: `0x${string}`;
  network: "base";
  provider: "coinbase-cdp";
  message: string;
}

interface RegisteredIdentityRecord {
  address: `0x${string}`;
  network: "base";
  agentId: string;
  tokenId: string;
  agentRegistry: string;
}

interface IssuedIdentityNonceRecord {
  nonceToken: string;
  address: `0x${string}`;
  network: "base";
  agentId: string;
  tokenId: string;
  agentRegistry: string;
  expiresAtUnixSeconds: number;
}

interface ReceiptClaims {
  walletAddress: `0x${string}`;
  chainId: number;
  registryAddress?: `0x${string}`;
  tokenId?: string;
  keyId: string;
  expiresAt: string;
}

interface BaseNodeRecord {
  id: number;
  seed: string;
  kind: TreeNode["kind"];
  title: string;
  status: TreeNode["status"];
  parent_id: number | null;
  notebook_source: string;
  summary: string | null;
  slug: string | null;
  sidelinks: Array<{
    node_id: number;
    tag: string;
    ordinal: number;
  }>;
}

const defaultScienceTaskChecklist = (): Record<string, ScienceTaskChecklistEntry> => ({
  instruction_and_tests_match: {
    status: "pass",
    note: "Contract test checklist entry",
  },
});

const defaultScienceTaskRunEvidence = (
  command: string,
  summary: string,
): ScienceTaskRunEvidence => ({
  command,
  summary,
  key_lines: [summary],
});

const scienceTaskPacketFiles = (taskSlug: string) => ({
  "instruction.md": {
    encoding: "utf8" as const,
    content: `# ${taskSlug}\n`,
  },
  "task.toml": {
    encoding: "utf8" as const,
    content: `name = "${taskSlug}"\n`,
  },
  "tests/test_task.py": {
    encoding: "utf8" as const,
    content: "def test_placeholder():\n    assert True\n",
  },
});

const scienceTaskExportTargetPath = (
  scienceDomain: string,
  scienceField: string,
  taskSlug: string,
): string => `tasks/${scienceDomain}/${scienceField}/${taskSlug}`;

const json = (res: http.ServerResponse, statusCode: number, payload: unknown): void => {
  res.statusCode = statusCode;
  res.setHeader("content-type", "application/json");
  res.end(`${JSON.stringify(payload)}\n`);
};

const text = (res: http.ServerResponse, statusCode: number, payload: string): void => {
  res.statusCode = statusCode;
  res.setHeader("content-type", "text/plain; charset=utf-8");
  res.end(payload);
};

const normalizeHeaders = (headers: http.IncomingHttpHeaders): Record<string, string> => {
  return Object.fromEntries(
    Object.entries(headers).flatMap(([key, value]) => {
      if (value === undefined) {
        return [];
      }

      return [[key.toLowerCase(), Array.isArray(value) ? value.join(", ") : value]];
    }),
  );
};

const readJsonBody = async (req: http.IncomingMessage): Promise<unknown> => {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }

  const raw = Buffer.concat(chunks).toString("utf8");
  if (raw.trim() === "") {
    return undefined;
  }

  return JSON.parse(raw);
};

const createdAt = (): string => "2026-03-10T00:00:00.000Z";
const currentUnixSeconds = (): number => Math.floor(Date.now() / 1000);

const makeReceipt = (claims: ReceiptClaims): string => {
  return `receipt-valid.${Buffer.from(JSON.stringify(claims), "utf8").toString("base64url")}`;
};

const parseReceipt = (receipt: string): ReceiptClaims | null => {
  if (!receipt.startsWith("receipt-valid.")) {
    return null;
  }

  try {
    const encoded = receipt.slice("receipt-valid.".length);
    const parsed = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8")) as ReceiptClaims;
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
};

const parseSig1SignatureHeader = (value: string): Buffer | null => {
  const match = /^sig1=:([A-Za-z0-9+/=]+):$/.exec(value.trim());
  if (!match?.[1]) {
    return null;
  }

  const signatureBytes = Buffer.from(match[1], "base64");
  return signatureBytes.byteLength === 65 ? signatureBytes : null;
};

export class TechtreeContractServer {
  readonly requests: ContractRequestRecord[] = [];
  readonly createdNodes = new Map<string, NodeCreateResponse>();
  readonly createdComments = new Map<string, CommentCreateResponse>();

  baseUrl = "";

  private readonly options: TechtreeContractServerOptions;

  private readonly liveNodes = new Map<number, BaseNodeRecord>([
    [
      1,
      {
        id: 1,
        seed: "ml",
        kind: "hypothesis",
        title: "Root node",
        status: "anchored",
        parent_id: null,
        notebook_source: "print('root')",
        summary: "A root node",
        slug: "root-node",
        sidelinks: [],
      },
    ],
    [
      2,
      {
        id: 2,
        seed: "ml",
        kind: "data",
        title: "Child node",
        status: "anchored",
        parent_id: 1,
        notebook_source: "print('child')",
        summary: "A child node",
        slug: "child-node",
        sidelinks: [],
      },
    ],
    [
      3,
      {
        id: 3,
        seed: "ml",
        kind: "review",
        title: "Independent review",
        status: "anchored",
        parent_id: 1,
        notebook_source: "print('review')",
        summary: "Reproduced the headline claim",
        slug: "independent-review",
        sidelinks: [],
      },
    ],
    [
      4,
      {
        id: 4,
        seed: "ml",
        kind: "review",
        title: "Review of the review",
        status: "anchored",
        parent_id: 3,
        notebook_source: "print('re-review')",
        summary: "The reproduction skipped the holdout",
        slug: "review-of-review",
        sidelinks: [],
      },
    ],
  ]);

  private readonly liveComments: TreeComment[] = [
    {
      id: 10,
      node_id: 1,
      author_agent_id: TEST_AGENT_SUMMARY.id,
      body_markdown: "Existing comment",
      body_plaintext: "Existing comment",
      status: "ready",
      inserted_at: createdAt(),
    },
  ];

  private readonly liveWatches = new Map<number, WatchRecord[]>();
  private readonly liveStars = new Map<number, NodeStarRecord[]>();
  private readonly liveActivityEvents: ActivityEvent[] = [
    {
      id: 2_001,
      subject_node_id: 1,
      actor_type: "agent",
      actor_ref: TEST_AGENT_SUMMARY.id,
      event_type: "comment_added",
      stream: "agent_inbox",
      payload: {
        seed: "ml",
        kind_filters: [],
      },
      inserted_at: createdAt(),
    },
  ];

  private nextNodeId = 100;
  private nextCommentId = 500;
  private nextWatchId = 800;
  private nextStarId = 900;
  private nextEventId = 2_002;
  private readonly liveScienceTasks = new Map<number, ScienceTaskDetail>();
  private readonly issuedNonces = new Map<string, IssuedNonceRecord>();
  private readonly issuedRegistrationIntents = new Map<string, RegistrationIntentRecord>();
  private readonly registeredIdentities = new Map<string, RegisteredIdentityRecord>();
  private readonly issuedIdentityNonces = new Map<string, IssuedIdentityNonceRecord>();
  private readonly consumedEnvelopeNonces = new Set<string>();
  private server: http.Server | null = null;

  constructor(options: TechtreeContractServerOptions = {}) {
    this.options = options;
    this.liveNodes.set(301, {
      id: 301,
      seed: "science",
      kind: "eval",
      title: "Cell atlas benchmark",
      status: "anchored",
      parent_id: 1,
      notebook_source: "print('science task')",
      summary: "Benchmark task for cell atlas curation.",
      slug: "cell-atlas-benchmark",
      sidelinks: [],
    });
    this.liveScienceTasks.set(
      301,
      this.makeScienceTaskDetail(301, {
        title: "Cell atlas benchmark",
        summary: "Benchmark task for cell atlas curation.",
        science_domain: "life-sciences",
        science_field: "biology",
        task_slug: "cell-atlas-benchmark",
        workflow_state: "submitted",
        harbor_pr_url: "https://harbor.example/pr/301",
        review_round_count: 1,
        open_reviewer_concerns_count: 1,
        latest_review_follow_up_note: "Addressed the first reviewer pass.",
      }),
    );
  }

  async start(): Promise<void> {
    this.server = http.createServer(async (req, res) => {
      try {
        await this.handle(req, res);
      } catch (error) {
        json(res, 500, {
          error: {
            code: "contract_server_error",
            message: error instanceof Error ? error.message : String(error),
          },
        });
      }
    });

    this.server.listen(0, "127.0.0.1");
    await once(this.server, "listening");

    const address = this.server.address() as AddressInfo;
    this.baseUrl = `http://127.0.0.1:${address.port}`;
  }

  async stop(): Promise<void> {
    if (!this.server) {
      return;
    }

    await new Promise<void>((resolve, reject) => {
      this.server?.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });

    this.server = null;
  }

  protectedRequests(): ContractRequestRecord[] {
    return this.requests.filter((request) => request.pathname.startsWith("/api/techtree/v1/tree/") || request.pathname.startsWith("/api/techtree/v1/agent/"));
  }

  private materializeNode(record: BaseNodeRecord): TreeNode {
    return {
      id: record.id,
      parent_id: record.parent_id,
      path: record.parent_id === null ? `${record.id}` : `${record.parent_id}.${record.id}`,
      depth: record.parent_id === null ? 0 : 1,
      seed: record.seed,
      kind: record.kind,
      title: record.title,
      slug: record.slug,
      summary: record.summary,
      status: record.status,
      manifest_cid: `bafyregentmanifest${record.id}`,
      manifest_uri: null,
      manifest_hash: null,
      notebook_cid: `bafyregentnode${record.id}`,
      skill_slug: null,
      skill_version: null,
      child_count: [...this.liveNodes.values()].filter((node) => node.parent_id === record.id).length,
      comment_count: this.liveComments.filter((comment) => comment.node_id === record.id).length,
      watcher_count: this.liveWatches.get(record.id)?.length ?? 0,
      activity_score: "1.0",
      comments_locked: false,
      inserted_at: createdAt(),
      updated_at: createdAt(),
      sidelinks: record.sidelinks.map((edge, index) => ({
        id: record.id * 100 + index + 1,
        src_node_id: record.id,
        dst_node_id: edge.node_id,
        tag: edge.tag,
        ordinal: edge.ordinal,
      })),
      creator_agent: TEST_AGENT_SUMMARY,
    };
  }

  private makeScienceTaskDetail(
    nodeId: number,
    overrides: Partial<ScienceTaskDetail> = {},
  ): ScienceTaskDetail {
    const node = overrides.node ?? (this.liveNodes.get(nodeId) ? this.materializeNode(this.liveNodes.get(nodeId) as BaseNodeRecord) : null);
    const title = overrides.title ?? node?.title ?? `Science task ${nodeId}`;
    const scienceDomain = overrides.science_domain ?? "life-sciences";
    const scienceField = overrides.science_field ?? "biology";
    const taskSlug = overrides.task_slug ?? `science-task-${nodeId}`;
    const packetFiles = overrides.packet_files ?? scienceTaskPacketFiles(taskSlug);

    return {
      node_id: nodeId,
      title,
      summary: overrides.summary ?? node?.summary ?? null,
      science_domain: scienceDomain,
      science_field: scienceField,
      task_slug: taskSlug,
      workflow_state: overrides.workflow_state ?? "authoring",
      export_target_path:
        overrides.export_target_path ?? scienceTaskExportTargetPath(scienceDomain, scienceField, taskSlug),
      harbor_pr_url: overrides.harbor_pr_url ?? null,
      review_round_count: overrides.review_round_count ?? 0,
      open_reviewer_concerns_count: overrides.open_reviewer_concerns_count ?? 0,
      current_files_match_latest_evidence: overrides.current_files_match_latest_evidence ?? true,
      latest_rerun_after_latest_fix: overrides.latest_rerun_after_latest_fix ?? false,
      inserted_at: overrides.inserted_at ?? createdAt(),
      updated_at: overrides.updated_at ?? createdAt(),
      node,
      structured_output_shape: overrides.structured_output_shape ?? null,
      claimed_expert_time: overrides.claimed_expert_time ?? "2 hours",
      threshold_rationale: overrides.threshold_rationale ?? "Thresholds are documented.",
      anti_cheat_notes: overrides.anti_cheat_notes ?? "Hidden answers stay out of the packet.",
      reproducibility_notes:
        overrides.reproducibility_notes ?? "Pinned dependencies make reruns stable enough for review.",
      dependency_pinning_status: overrides.dependency_pinning_status ?? "Pinned",
      canary_status: overrides.canary_status ?? "Present",
      destination_name: overrides.destination_name ?? "harbor",
      packet_hash: overrides.packet_hash ?? `sha256:science-task-${nodeId}`,
      evidence_packet_hash: overrides.evidence_packet_hash ?? `sha256:evidence-${nodeId}`,
      packet_files: packetFiles,
      checklist: overrides.checklist ?? defaultScienceTaskChecklist(),
      oracle_run:
        overrides.oracle_run ?? defaultScienceTaskRunEvidence("uv run oracle", "Oracle passes the task."),
      frontier_run:
        overrides.frontier_run ?? defaultScienceTaskRunEvidence("uv run frontier", "Frontier run fails on edge cases."),
      failure_analysis:
        overrides.failure_analysis ?? "The frontier run misses one required check in the final answer.",
      latest_review_follow_up_note: overrides.latest_review_follow_up_note ?? null,
      last_rerun_at: overrides.last_rerun_at ?? null,
      latest_fix_at: overrides.latest_fix_at ?? null,
      any_concern_unanswered: overrides.any_concern_unanswered ?? false,
    };
  }

  private scienceTaskSummary(detail: ScienceTaskDetail): ScienceTaskListResponse["data"][number] {
    return {
      node_id: detail.node_id,
      title: detail.title,
      summary: detail.summary,
      science_domain: detail.science_domain,
      science_field: detail.science_field,
      task_slug: detail.task_slug,
      workflow_state: detail.workflow_state,
      export_target_path: detail.export_target_path,
      harbor_pr_url: detail.harbor_pr_url,
      review_round_count: detail.review_round_count,
      open_reviewer_concerns_count: detail.open_reviewer_concerns_count,
      current_files_match_latest_evidence: detail.current_files_match_latest_evidence,
      latest_rerun_after_latest_fix: detail.latest_rerun_after_latest_fix,
      inserted_at: detail.inserted_at,
      updated_at: detail.updated_at,
    };
  }

  private scienceTaskMutation(detail: ScienceTaskDetail): ScienceTaskMutationResponse {
    return {
      data: {
        node_id: detail.node_id,
        workflow_state: detail.workflow_state,
        packet_hash: detail.packet_hash,
        export_target_path: detail.export_target_path,
      },
    };
  }

  private makeActivityEvent(subjectNodeId: number, eventType: string, payload: Record<string, unknown>): ActivityEvent {
    const eventId = this.nextEventId;
    this.nextEventId += 1;

    return {
      id: eventId,
      subject_node_id: subjectNodeId,
      actor_type: "agent",
      actor_ref: TEST_AGENT_SUMMARY.id,
      event_type: eventType,
      stream: "agent_inbox",
      payload,
      inserted_at: createdAt(),
    };
  }

  private appendActivityEvent(subjectNodeId: number, eventType: string, payload: Record<string, unknown>): ActivityEvent {
    const event = this.makeActivityEvent(subjectNodeId, eventType, payload);
    this.liveActivityEvents.push(event);
    return event;
  }

  private currentWatchRecords(nodeId: number): WatchRecord[] {
    return this.liveWatches.get(nodeId) ?? [];
  }

  private handleInbox(requestUrl: URL): AgentInboxResponse {
    const cursorParam = Number.parseInt(requestUrl.searchParams.get("cursor") ?? "", 10);
    const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
    const normalizedLimit = Number.isFinite(limit) && limit > 0 ? limit : 50;
    const hasCursor = Number.isSafeInteger(cursorParam) && cursorParam > 0;

    const filteredEvents = hasCursor
      ? this.liveActivityEvents.filter((event) => event.id > cursorParam)
      : this.liveActivityEvents;

    const events = hasCursor ? filteredEvents.slice(0, normalizedLimit) : filteredEvents.slice(-normalizedLimit);

    const nextCursor =
      events.length > 0
        ? events[events.length - 1]?.id ?? (hasCursor ? cursorParam : null)
        : hasCursor
          ? cursorParam
          : this.liveActivityEvents[this.liveActivityEvents.length - 1]?.id ?? null;

    return {
      events: events.map((event) => ({
        ...event,
        payload: {
          ...event.payload,
          seed: requestUrl.searchParams.get("seed") ?? "ml",
          kind_filters: requestUrl.searchParams.getAll("kind"),
        },
      })),
      next_cursor: nextCursor,
    };
  }

  private handleOpportunities(requestUrl: URL): AgentOpportunitiesResponse {
    const node = this.materializeNode(this.liveNodes.get(1) as BaseNodeRecord);
    return {
      opportunities: [
        {
          node_id: node.id,
          title: node.title,
          seed: node.seed,
          kind: node.kind,
          opportunity_type: requestUrl.searchParams.getAll("kind")[0] ?? "review",
          activity_score: String(node.activity_score),
        },
      ],
    };
  }

  private async handle(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    const method = req.method ?? "GET";
    const requestUrl = new URL(req.url ?? "/", this.baseUrl || "http://127.0.0.1");
    const headers = normalizeHeaders(req.headers);
    const body = await readJsonBody(req);

    this.requests.push({
      method,
      pathname: requestUrl.pathname,
      search: requestUrl.search,
      headers,
      body,
    });

    if (method === "GET" && requestUrl.pathname === "/health") {
      if (this.options.healthResponse) {
        json(res, this.options.healthResponse.statusCode, this.options.healthResponse.payload);
        return;
      }

      json(res, 200, { ok: true, service: "techtree-contract-server" });
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/shared/siwa/nonce") {
      if (this.options.nonceResponse) {
        json(res, this.options.nonceResponse.statusCode, this.options.nonceResponse.payload);
        return;
      }

      const payload = body as {
        wallet_address?: `0x${string}`;
        chain_id?: number;
        audience?: "platform" | "autolaunch" | "techtree" | "regent-services";
      };
      const walletAddress = payload.wallet_address ?? TEST_AGENT_WALLET;
      const chainId = payload.chain_id;
      const audience = payload.audience;

      if (!Number.isSafeInteger(chainId) || (chainId ?? 0) <= 0) {
        json(res, 422, {
          error: {
            code: "invalid_chain_id",
            message: "chain_id must be a positive integer",
          },
        });
        return;
      }

      if (!audience) {
        json(res, 422, {
          error: {
            code: "invalid_audience",
            message: "audience is required",
          },
        });
        return;
      }

      const nonce = `nonce-${walletAddress}-${Date.now()}`;
      this.issuedNonces.set(nonce, {
        walletAddress,
        chainId: chainId as number,
        audience,
        expiresAtUnixSeconds: currentUnixSeconds() + 300,
      });
      const response: SiwaNonceResponse = {
        code: "nonce_issued",
        data: {
          nonce,
          walletAddress,
          chainId: chainId as number,
          expiresAt: "2999-01-01T00:00:00.000Z",
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/shared/identity/status") {
      const payload = body as {
        network?: "base";
        address?: `0x${string}`;
        provider?: "coinbase-cdp";
      };
      const network = "base";
      const address = (payload.address ?? TEST_AGENT_WALLET).toLowerCase() as `0x${string}`;
      const registered = this.registeredIdentities.get(`${network}:${address}`);
      const response: IdentityStatusResponse = {
        ok: true,
        code: "identity_status_resolved",
        data: {
          network,
          address,
          provider: payload.provider ?? "coinbase-cdp",
          registered: registered !== undefined,
          verified: registered ? "onchain" : "unregistered",
          ...(registered
            ? {
                agent_id: registered.agentId,
                token_id: registered.tokenId,
                agent_registry: registered.agentRegistry,
                receipt_expires_at: "2999-01-01T00:00:00.000Z",
              }
            : {}),
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/shared/identity/registration-intents") {
      const payload = body as {
        network?: "base";
        address?: `0x${string}`;
        provider?: "coinbase-cdp";
      };
      const network = "base";
      const address = (payload.address ?? TEST_AGENT_WALLET).toLowerCase() as `0x${string}`;
      const intentId = `intent-${Date.now()}`;
      const message = `Register Regent identity for ${address} on ${network}`;
      this.issuedRegistrationIntents.set(intentId, {
        intentId,
        address,
        network,
        provider: payload.provider ?? "coinbase-cdp",
        message,
      });
      const response: IdentityRegistrationIntentResponse = {
        ok: true,
        code: "identity_registration_intent_created",
        data: {
          intent_id: intentId,
          intent_kind: "erc8004_registration",
          signing_payload: {
            message,
          },
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/shared/identity/registration-completions") {
      const payload = body as {
        intent_id?: string;
        address?: `0x${string}`;
        signature?: `0x${string}`;
        message?: string;
      };
      const intent = payload.intent_id ? this.issuedRegistrationIntents.get(payload.intent_id) : undefined;
      const issues: string[] = [];

      if (!intent) {
        issues.push("intent_id was not issued");
      }
      if (!payload.address) {
        issues.push("address is required");
      }
      if (!payload.signature || !/^0x[0-9a-fA-F]{130}$/.test(payload.signature)) {
        issues.push("signature is invalid");
      }
      if (intent && payload.address?.toLowerCase() !== intent.address.toLowerCase()) {
        issues.push("intent address binding mismatch");
      }
      if (intent && payload.message !== intent.message) {
        issues.push("registration message mismatch");
      }

      if (issues.length > 0) {
        json(res, 422, {
          error: {
            code: "registration_failed",
            message: "registration request failed validation",
            details: { issues },
          },
        });
        return;
      }

      this.issuedRegistrationIntents.delete(payload.intent_id as string);
      const agentRegistry = agentRegistryBinding(intent!.network);
      const registered: RegisteredIdentityRecord = {
        address: intent!.address,
        network: intent!.network,
        agentRegistry,
        tokenId: TEST_AGENT_TOKEN_ID,
        agentId: agentIdentityKey(agentRegistry, TEST_AGENT_TOKEN_ID),
      };
      this.registeredIdentities.set(`${registered.network}:${registered.address}`, registered);

      const response: IdentityRegistrationCompletionResponse = {
        ok: true,
        code: "identity_registration_completed",
        data: {
          registered: true,
          agent_id: registered.agentId,
          token_id: registered.tokenId,
          agent_registry: registered.agentRegistry,
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/shared/identity/siwa/nonce") {
      const payload = body as {
        network?: "base";
        address?: `0x${string}`;
        token_id?: string;
        agent_registry?: string;
      };
      const network = "base";
      const address = (payload.address ?? TEST_AGENT_WALLET).toLowerCase() as `0x${string}`;
      const nonceToken = `identity-nonce-${Date.now()}`;
      const tokenId = payload.token_id ?? TEST_AGENT_TOKEN_ID;
      const agentRegistry = payload.agent_registry ?? agentRegistryBinding();
      const agentId = agentIdentityKey(agentRegistry, tokenId);
      const message = [
        "Sign in with Regent",
        `Address: ${address}`,
        `Network: ${network}`,
        `Token ID: ${tokenId}`,
        `Agent Registry: ${agentRegistry}`,
        `Nonce: ${nonceToken}`,
      ].join("\n");

      this.issuedIdentityNonces.set(nonceToken, {
        nonceToken,
        address,
        network,
        agentId,
        tokenId,
        agentRegistry,
        expiresAtUnixSeconds: currentUnixSeconds() + 300,
      });

      const response: IdentitySiwaNonceResponse = {
        ok: true,
        code: "identity_siwa_nonce_issued",
        data: {
          nonce_token: nonceToken,
          message,
          address,
          agent_id: agentId,
          token_id: tokenId,
          agent_registry: agentRegistry,
          expires_at: "2999-01-01T00:00:00.000Z",
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/shared/identity/siwa/verify") {
      const payload = body as {
        network?: "base";
        address?: `0x${string}`;
        token_id?: string;
        agent_registry?: string;
        message?: string;
        signature?: `0x${string}`;
        nonce_token?: string;
      };
      const issued = payload.nonce_token ? this.issuedIdentityNonces.get(payload.nonce_token) : undefined;
      const issues: string[] = [];

      if (!issued) {
        issues.push("nonce_token was not issued");
      }
      if (!payload.message) {
        issues.push("message is required");
      }
      if (!payload.signature || !/^0x[0-9a-fA-F]{130}$/.test(payload.signature)) {
        issues.push("signature is invalid");
      }
      if (issued && payload.address?.toLowerCase() !== issued.address.toLowerCase()) {
        issues.push("address binding mismatch");
      }
      if (issued && payload.token_id !== issued.tokenId) {
        issues.push("token_id binding mismatch");
      }
      if (issued && payload.agent_registry !== issued.agentRegistry) {
        issues.push("agent_registry binding mismatch");
      }
      if (issued && payload.network !== issued.network) {
        issues.push("network binding mismatch");
      }
      if (issued && issued.expiresAtUnixSeconds <= currentUnixSeconds()) {
        issues.push("nonce token is expired");
      }
      if (issued && payload.message && !payload.message.includes(`Nonce: ${issued.nonceToken}`)) {
        issues.push("message does not include nonce token");
      }

      if (issues.length > 0) {
        json(res, 422, {
          error: {
            code: "siwa_verify_failed",
            message: "identity verify request failed validation",
            details: { issues },
          },
        });
        return;
      }

      this.issuedIdentityNonces.delete(payload.nonce_token as string);
      const receiptClaims: ReceiptClaims = {
        walletAddress: issued!.address,
        chainId: 8453,
        registryAddress: TEST_AGENT_REGISTRY,
        tokenId: issued!.tokenId,
        keyId: issued!.address.toLowerCase(),
        expiresAt: "2999-01-01T00:00:00.000Z",
      };
      const response: IdentitySiwaVerifyResponse = {
        ok: true,
        code: "identity_siwa_verified",
        data: {
          verified: "onchain",
          network: issued!.network,
          address: issued!.address,
          agent_id: issued!.agentId,
          token_id: issued!.tokenId,
          agent_registry: issued!.agentRegistry,
          signer_type: "evm_personal_sign",
          receipt: makeReceipt(receiptClaims),
          receipt_issued_at: "2026-03-10T00:00:00.000Z",
          receipt_expires_at: "2999-01-01T00:00:00.000Z",
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/shared/siwa/verify") {
      if (this.options.verifyResponse) {
        json(res, this.options.verifyResponse.statusCode, this.options.verifyResponse.payload);
        return;
      }

      const payload = body as {
        wallet_address?: `0x${string}`;
        chain_id?: number;
        audience?: string;
        nonce?: string;
        message?: string;
        signature?: `0x${string}`;
        registry_address?: `0x${string}`;
        token_id?: string;
      };

      const issues: string[] = [];
      if (!payload.wallet_address) {
        issues.push("wallet_address is required");
      }
      if (!Number.isSafeInteger(payload.chain_id) || (payload.chain_id ?? 0) <= 0) {
        issues.push("chain_id must be a positive integer");
      }
      if (!payload.nonce) {
        issues.push("nonce is required");
      }
      if (!payload.message) {
        issues.push("message is required");
      }
      if (!payload.signature) {
        issues.push("signature is required");
      }
      const issuedNonce = payload.nonce ? this.issuedNonces.get(payload.nonce) : undefined;
      if (!issuedNonce) {
        issues.push("nonce was not issued");
      } else {
        if (issuedNonce.walletAddress.toLowerCase() !== payload.wallet_address?.toLowerCase()) {
          issues.push("nonce wallet binding mismatch");
        }
        if (issuedNonce.chainId !== payload.chain_id) {
          issues.push("nonce chain binding mismatch");
        }
        if (issuedNonce.expiresAtUnixSeconds <= currentUnixSeconds()) {
          issues.push("nonce is expired");
        }
        if (payload.message && !payload.message.includes(`Sign in to ${issuedNonce.audience}.`)) {
          issues.push("message does not include audience statement");
        }
      }

      if (payload.message && payload.wallet_address && payload.chain_id && payload.nonce) {
        if (!payload.message.includes(`${payload.wallet_address}\n`)) {
          issues.push("message does not include wallet address");
        }
        if (!payload.message.includes(`Chain ID: ${payload.chain_id}`)) {
          issues.push("message does not include chain id");
        }
        if (!payload.message.includes(`Nonce: ${payload.nonce}`)) {
          issues.push("message does not include nonce");
        }
      }

      if (payload.signature && !/^0x[0-9a-fA-F]{130}$/.test(payload.signature)) {
        issues.push("signature is invalid");
      }

      if (issues.length > 0) {
        json(res, 422, {
          error: {
            code: "siwa_verify_invalid",
            message: "verify request failed validation",
            details: {
              issues,
            },
          },
        });
        return;
      }

      this.issuedNonces.delete(payload.nonce as string);
      const walletAddress = payload.wallet_address as `0x${string}`;
      const receiptClaims: ReceiptClaims = {
        walletAddress,
        chainId: payload.chain_id as number,
        keyId: walletAddress.toLowerCase(),
        expiresAt: "2999-01-01T00:00:00.000Z",
        ...(payload.registry_address ? { registryAddress: payload.registry_address } : {}),
        ...(payload.token_id ? { tokenId: payload.token_id } : {}),
      };
      const response: SiwaVerifyResponse = {
        code: "siwa_verified",
        data: {
          verified: true,
          walletAddress,
          chainId: payload.chain_id as number,
          registryAddress: payload.registry_address as `0x${string}`,
          tokenId: payload.token_id as string,
          nonce: payload.nonce as string,
          keyId: walletAddress.toLowerCase(),
          signatureScheme: "evm_personal_sign",
          receipt: makeReceipt(receiptClaims),
          receiptIssuedAt: "2026-03-10T00:00:00.000Z",
          receiptExpiresAt: "2999-01-01T00:00:00.000Z",
          audience: issuedNonce.audience,
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/api/techtree/v1/tree/nodes") {
      const seedFilter = requestUrl.searchParams.get("seed");
      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const data = [...this.liveNodes.values()]
        .filter((node) => node.status === "anchored")
        .map((node) => this.materializeNode(node))
        .filter((node) => !seedFilter || node.seed === seedFilter)
        .slice(0, Number.isFinite(limit) ? limit : 50);
      json(res, 200, { data });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+$/.test(requestUrl.pathname)) {
      const nodeId = Number.parseInt(requestUrl.pathname.split("/").pop() ?? "0", 10);
      const node = this.liveNodes.get(nodeId);
      if (!node || (node.status !== "anchored" && node.status !== "pinned")) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      json(res, 200, { data: this.materializeNode(node) });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/agent\/tree\/nodes\/\d+$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/").pop() ?? "0", 10);
      const node = this.liveNodes.get(nodeId);
      if (!node) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      json(res, 200, { data: this.materializeNode(node) });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/children$/.test(requestUrl.pathname)) {
      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const data = [...this.liveNodes.values()]
        .filter(
          (node) => node.parent_id === nodeId && (node.status === "anchored" || node.status === "pinned"),
        )
        .map((node) => this.materializeNode(node))
        .slice(0, Number.isFinite(limit) ? limit : 50);
      json(res, 200, { data });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/agent\/tree\/nodes\/\d+\/children$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[7] ?? "0", 10);
      const parent = this.liveNodes.get(nodeId);
      if (!parent) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const data = [...this.liveNodes.values()]
        .filter((node) => node.parent_id === nodeId)
        .map((node) => this.materializeNode(node))
        .slice(0, Number.isFinite(limit) ? limit : 50);
      json(res, 200, { data });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/reviews$/.test(requestUrl.pathname)) {
      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const node = this.liveNodes.get(nodeId);
      if (!node || node.status !== "anchored") {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      const buildThreads = (parentId: number): Array<Record<string, unknown>> =>
        [...this.liveNodes.values()]
          .filter(
            (candidate) =>
              candidate.parent_id === parentId &&
              candidate.kind === "review" &&
              candidate.status === "anchored",
          )
          .map((review) => {
            const replies = buildThreads(review.id);
            return {
              id: review.id,
              parent_id: parentId,
              kind: "review",
              title: review.title,
              summary: review.summary,
              status: review.status,
              depth: 1,
              creator_agent_id: TEST_AGENT_SUMMARY.id,
              creator_agent: TEST_AGENT_SUMMARY,
              inserted_at: createdAt(),
              reply_count: replies.length,
              replies,
            };
          });

      const threads = buildThreads(nodeId);
      const countThreads = (items: Array<Record<string, unknown>>): number =>
        items.reduce(
          (total, item) => total + 1 + countThreads(item.replies as Array<Record<string, unknown>>),
          0,
        );
      const maxDepth = (items: Array<Record<string, unknown>>): number =>
        items.length === 0
          ? 0
          : 1 + Math.max(...items.map((item) => maxDepth(item.replies as Array<Record<string, unknown>>)));

      json(res, 200, {
        data: {
          node_id: nodeId,
          total_reviews: countThreads(threads),
          direct_reviews: threads.length,
          max_depth: maxDepth(threads),
          truncated: false,
          threads,
        },
      });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/agents\/\d+$/.test(requestUrl.pathname)) {
      const agentId = Number.parseInt(requestUrl.pathname.split("/").pop() ?? "0", 10);
      if (agentId !== TEST_AGENT_SUMMARY.id) {
        json(res, 404, { error: { code: "agent_not_found", message: "agent not found" } });
        return;
      }

      const anchored = [...this.liveNodes.values()].filter((node) => node.status === "anchored");
      const byKind: Record<string, number> = {};
      for (const node of anchored) {
        byKind[node.kind] = (byKind[node.kind] ?? 0) + 1;
      }

      json(res, 200, {
        data: {
          agent: {
            id: TEST_AGENT_SUMMARY.id,
            label: TEST_AGENT_SUMMARY.label,
            wallet_address: TEST_AGENT_SUMMARY.wallet_address,
            chain_id: 8453,
            status: "active",
            first_seen_at: createdAt(),
            last_verified_at: createdAt(),
          },
          publications: {
            total: anchored.length,
            by_kind: byKind,
            recent: anchored.map((node) => this.materializeNode(node)),
            last_published_at: createdAt(),
          },
          review_activity: {
            reviews_authored: anchored.filter((node) => node.kind === "review").length,
            reviews_received: 0,
          },
        },
      });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/comments$/.test(requestUrl.pathname)) {
      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const node = this.liveNodes.get(nodeId);
      if (!node || (node.status !== "anchored" && node.status !== "pinned")) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const data = this.liveComments.filter((comment) => comment.node_id === nodeId).slice(0, Number.isFinite(limit) ? limit : 50);
      json(res, 200, { data });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/agent\/tree\/nodes\/\d+\/comments$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[7] ?? "0", 10);
      const node = this.liveNodes.get(nodeId);
      if (!node) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const data = this.liveComments.filter((comment) => comment.node_id === nodeId).slice(0, Number.isFinite(limit) ? limit : 50);
      json(res, 200, { data });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/sidelinks$/.test(requestUrl.pathname)) {
      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const node = this.liveNodes.get(nodeId);
      json(res, 200, { data: node ? this.materializeNode(node).sidelinks : [] });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/seeds\/[^/]+\/hot$/.test(requestUrl.pathname)) {
      const seed = decodeURIComponent(requestUrl.pathname.split("/")[6] ?? "");
      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const data = [...this.liveNodes.values()]
        .filter((node) => node.status === "anchored")
        .map((node) => this.materializeNode(node))
        .filter((node) => node.seed === seed)
        .slice(0, Number.isFinite(limit) ? limit : 50);
      json(res, 200, { data });
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/api/techtree/v1/tree/activity") {
      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const normalizedLimit = Number.isFinite(limit) && limit > 0 ? limit : 50;
      json(res, 200, {
        data: [
          this.makeActivityEvent(1, "node_created", { node_id: 1 }),
          this.makeActivityEvent(1, "comment_added", { node_id: 1, comment_id: 10 }),
        ].slice(0, normalizedLimit),
      });
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/api/techtree/v1/science-tasks") {
      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const stage = requestUrl.searchParams.get("stage");
      const scienceDomain = requestUrl.searchParams.get("science_domain");
      const scienceField = requestUrl.searchParams.get("science_field");
      const normalizedLimit = Number.isFinite(limit) && limit > 0 ? limit : 50;
      const data = [...this.liveScienceTasks.values()]
        .filter((detail) => !stage || detail.workflow_state === stage)
        .filter((detail) => !scienceDomain || detail.science_domain === scienceDomain)
        .filter((detail) => !scienceField || detail.science_field === scienceField)
        .map((detail) => this.scienceTaskSummary(detail))
        .slice(0, normalizedLimit);

      const response: ScienceTaskListResponse = { data };
      json(res, 200, response);
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/science-tasks\/\d+$/.test(requestUrl.pathname)) {
      const nodeId = Number.parseInt(requestUrl.pathname.split("/").pop() ?? "0", 10);
      const detail = this.liveScienceTasks.get(nodeId);
      if (!detail) {
        json(res, 404, { error: { code: "science_task_not_found", message: "science task not found" } });
        return;
      }

      const response: ScienceTaskDetailResponse = { data: detail };
      json(res, 200, response);
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/api/techtree/v1/tree/search") {
      const query = (requestUrl.searchParams.get("q") ?? "").toLowerCase();
      const limit = Number.parseInt(requestUrl.searchParams.get("limit") ?? "50", 10);
      const normalizedLimit = Number.isFinite(limit) && limit > 0 ? limit : 50;
      json(res, 200, {
        data: {
          nodes: [...this.liveNodes.values()]
            .filter((node) => node.status === "anchored")
            .map((node) => this.materializeNode(node))
            .filter((node) => query === "" || node.title.toLowerCase().includes(query))
            .slice(0, normalizedLimit),
          comments: this.liveComments
            .filter((comment) => (query === "" ? true : comment.body_markdown.toLowerCase().includes(query)))
            .slice(0, normalizedLimit),
        },
      });
      return;
    }

    if (method === "GET" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/work-packet$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const node = this.liveNodes.get(nodeId);
      if (!node) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      const response: { data: WorkPacketResponse } = {
        data: {
          node: this.materializeNode(node),
          comments: this.liveComments.filter((comment) => comment.node_id === nodeId),
          activity_events: this.liveActivityEvents.filter((event) => event.subject_node_id === nodeId),
        },
      };
      json(res, 200, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/techtree/v1/tree/nodes") {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const payload = body as {
        seed: string;
        kind: TreeNode["kind"];
        title: string;
        parent_id: number;
        notebook_source: string;
        sidelinks?: Array<{
          node_id: number;
          tag?: string;
          ordinal?: number;
        }>;
        summary?: string;
        slug?: string;
        idempotency_key: string;
      };

      if (!Number.isSafeInteger(payload.parent_id) || payload.parent_id <= 0) {
        json(res, 422, { error: { code: "parent_id_required", message: "parent_id is required" } });
        return;
      }

      const parentNode = this.liveNodes.get(payload.parent_id);
      if (!parentNode) {
        json(res, 404, { error: { code: "parent_not_found", message: "parent node not found" } });
        return;
      }

      if (parentNode.status !== "anchored") {
        json(res, 422, { error: { code: "parent_not_anchored", message: "parent node must be anchored" } });
        return;
      }

      const existing = this.createdNodes.get(payload.idempotency_key);
      if (existing) {
        json(res, 200, existing);
        return;
      }

      const nodeId = this.nextNodeId;
      this.nextNodeId += 1;
      this.liveNodes.set(nodeId, {
        id: nodeId,
        seed: payload.seed,
        kind: payload.kind,
        title: payload.title,
        status: "pinned",
        parent_id: payload.parent_id,
        notebook_source: payload.notebook_source,
        summary: payload.summary ?? null,
        slug: payload.slug ?? null,
        sidelinks: (payload.sidelinks ?? []).slice(0, 4).map((entry, index) => ({
          node_id: entry.node_id,
          tag: entry.tag ?? "related",
          ordinal: entry.ordinal ?? index + 1,
        })),
      });

      const response: NodeCreateResponse = {
        data: {
          node_id: nodeId,
          manifest_cid: `bafyregent${nodeId}`,
          status: "pinned",
          anchor_status: "pending",
        },
      };

      this.createdNodes.set(payload.idempotency_key, response);
      json(res, 201, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/techtree/v1/tree/comments") {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const payload = body as {
        node_id: number;
        body_markdown: string;
        body_plaintext?: string;
        idempotency_key: string;
      };

      if (!this.liveNodes.has(payload.node_id)) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      const existing = this.createdComments.get(payload.idempotency_key);
      if (existing) {
        json(res, 200, existing);
        return;
      }

      const response: CommentCreateResponse = {
        data: {
          comment_id: this.nextCommentId,
          node_id: payload.node_id,
          created_at: createdAt(),
        },
      };

      this.nextCommentId += 1;
      this.createdComments.set(payload.idempotency_key, response);
      this.liveComments.push({
        id: response.data.comment_id,
        node_id: payload.node_id,
        author_agent_id: TEST_AGENT_SUMMARY.id,
        body_markdown: payload.body_markdown,
        body_plaintext: payload.body_plaintext ?? payload.body_markdown,
        status: "ready",
        inserted_at: response.data.created_at,
      });
      this.appendActivityEvent(payload.node_id, "node.comment_created", {
        comment_id: response.data.comment_id,
      });
      json(res, 201, response);
      return;
    }

    if (method === "POST" && requestUrl.pathname === "/api/techtree/v1/agent/science-tasks") {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const payload = body as Partial<ScienceTaskDetail> & {
        title?: string;
        summary?: string | null;
        science_domain?: string;
        science_field?: string;
        task_slug?: string;
        structured_output_shape?: Record<string, unknown> | null;
        claimed_expert_time?: string;
        threshold_rationale?: string | null;
        anti_cheat_notes?: string;
        reproducibility_notes?: string;
        dependency_pinning_status?: string;
        canary_status?: string;
        failure_analysis?: string;
        packet_files?: Record<string, { encoding: "utf8" | "base64"; content: string }>;
      };

      const nodeId = this.nextNodeId;
      this.nextNodeId += 1;
      this.liveNodes.set(nodeId, {
        id: nodeId,
        seed: "science",
        kind: "eval",
        title: payload.title ?? `Science task ${nodeId}`,
        status: "anchored",
        parent_id: 1,
        notebook_source: "print('science task')",
        summary: payload.summary ?? null,
        slug: payload.task_slug ?? `science-task-${nodeId}`,
        sidelinks: [],
      });

      const detail = this.makeScienceTaskDetail(nodeId, {
        title: payload.title,
        summary: payload.summary ?? null,
        science_domain: payload.science_domain,
        science_field: payload.science_field,
        task_slug: payload.task_slug,
        structured_output_shape: payload.structured_output_shape ?? null,
        claimed_expert_time: payload.claimed_expert_time,
        threshold_rationale: payload.threshold_rationale ?? null,
        anti_cheat_notes: payload.anti_cheat_notes,
        reproducibility_notes: payload.reproducibility_notes,
        dependency_pinning_status: payload.dependency_pinning_status,
        canary_status: payload.canary_status,
        failure_analysis: payload.failure_analysis,
        packet_files: payload.packet_files,
        workflow_state: "authoring",
        packet_hash: `sha256:create-${nodeId}`,
        evidence_packet_hash: null,
        oracle_run: null,
        frontier_run: null,
      });
      this.liveScienceTasks.set(nodeId, detail);
      json(res, 200, this.scienceTaskMutation(detail));
      return;
    }

    if (method === "POST" && /^\/api\/techtree\/v1\/agent\/science-tasks\/\d+\/checklist$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const current = this.liveScienceTasks.get(nodeId);
      if (!current) {
        json(res, 404, { error: { code: "science_task_not_found", message: "science task not found" } });
        return;
      }

      const payload = body as Partial<ScienceTaskDetail> & {
        checklist?: Record<string, ScienceTaskChecklistEntry>;
        packet_files?: Record<string, { encoding: "utf8" | "base64"; content: string }>;
      };
      const next = this.makeScienceTaskDetail(nodeId, {
        ...current,
        title: payload.title ?? current.title,
        summary: payload.summary ?? current.summary,
        science_domain: payload.science_domain ?? current.science_domain,
        science_field: payload.science_field ?? current.science_field,
        task_slug: payload.task_slug ?? current.task_slug,
        claimed_expert_time: payload.claimed_expert_time ?? current.claimed_expert_time,
        threshold_rationale: payload.threshold_rationale ?? current.threshold_rationale,
        anti_cheat_notes: payload.anti_cheat_notes ?? current.anti_cheat_notes,
        reproducibility_notes: payload.reproducibility_notes ?? current.reproducibility_notes,
        dependency_pinning_status: payload.dependency_pinning_status ?? current.dependency_pinning_status,
        canary_status: payload.canary_status ?? current.canary_status,
        failure_analysis: payload.failure_analysis ?? current.failure_analysis,
        packet_files: payload.packet_files ?? current.packet_files,
        checklist: payload.checklist ?? current.checklist,
        workflow_state: "evidence_ready",
        updated_at: createdAt(),
      });
      this.liveScienceTasks.set(nodeId, next);
      json(res, 200, this.scienceTaskMutation(next));
      return;
    }

    if (method === "POST" && /^\/api\/techtree\/v1\/agent\/science-tasks\/\d+\/evidence$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const current = this.liveScienceTasks.get(nodeId);
      if (!current) {
        json(res, 404, { error: { code: "science_task_not_found", message: "science task not found" } });
        return;
      }

      const payload = body as Partial<ScienceTaskDetail> & {
        oracle_run?: ScienceTaskRunEvidence;
        frontier_run?: ScienceTaskRunEvidence;
        packet_files?: Record<string, { encoding: "utf8" | "base64"; content: string }>;
      };
      const next = this.makeScienceTaskDetail(nodeId, {
        ...current,
        title: payload.title ?? current.title,
        summary: payload.summary ?? current.summary,
        science_domain: payload.science_domain ?? current.science_domain,
        science_field: payload.science_field ?? current.science_field,
        task_slug: payload.task_slug ?? current.task_slug,
        claimed_expert_time: payload.claimed_expert_time ?? current.claimed_expert_time,
        threshold_rationale: payload.threshold_rationale ?? current.threshold_rationale,
        anti_cheat_notes: payload.anti_cheat_notes ?? current.anti_cheat_notes,
        reproducibility_notes: payload.reproducibility_notes ?? current.reproducibility_notes,
        dependency_pinning_status: payload.dependency_pinning_status ?? current.dependency_pinning_status,
        canary_status: payload.canary_status ?? current.canary_status,
        failure_analysis: payload.failure_analysis ?? current.failure_analysis,
        packet_files: payload.packet_files ?? current.packet_files,
        oracle_run: payload.oracle_run ?? current.oracle_run,
        frontier_run: payload.frontier_run ?? current.frontier_run,
        workflow_state: "evidence_ready",
        evidence_packet_hash: `sha256:evidence-${nodeId}`,
        updated_at: createdAt(),
      });
      this.liveScienceTasks.set(nodeId, next);
      json(res, 200, this.scienceTaskMutation(next));
      return;
    }

    if (method === "POST" && /^\/api\/techtree\/v1\/agent\/science-tasks\/\d+\/submit$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const current = this.liveScienceTasks.get(nodeId);
      if (!current) {
        json(res, 404, { error: { code: "science_task_not_found", message: "science task not found" } });
        return;
      }

      const payload = body as Partial<ScienceTaskDetail> & {
        harbor_pr_url?: string;
        latest_review_follow_up_note?: string | null;
        packet_files?: Record<string, { encoding: "utf8" | "base64"; content: string }>;
      };
      const next = this.makeScienceTaskDetail(nodeId, {
        ...current,
        title: payload.title ?? current.title,
        summary: payload.summary ?? current.summary,
        science_domain: payload.science_domain ?? current.science_domain,
        science_field: payload.science_field ?? current.science_field,
        task_slug: payload.task_slug ?? current.task_slug,
        claimed_expert_time: payload.claimed_expert_time ?? current.claimed_expert_time,
        threshold_rationale: payload.threshold_rationale ?? current.threshold_rationale,
        anti_cheat_notes: payload.anti_cheat_notes ?? current.anti_cheat_notes,
        reproducibility_notes: payload.reproducibility_notes ?? current.reproducibility_notes,
        dependency_pinning_status: payload.dependency_pinning_status ?? current.dependency_pinning_status,
        canary_status: payload.canary_status ?? current.canary_status,
        failure_analysis: payload.failure_analysis ?? current.failure_analysis,
        packet_files: payload.packet_files ?? current.packet_files,
        harbor_pr_url: payload.harbor_pr_url ?? current.harbor_pr_url,
        latest_review_follow_up_note:
          payload.latest_review_follow_up_note ?? current.latest_review_follow_up_note,
        review_round_count: Math.max(current.review_round_count, 1),
        workflow_state: "submitted",
        updated_at: createdAt(),
      });
      this.liveScienceTasks.set(nodeId, next);
      json(res, 200, this.scienceTaskMutation(next));
      return;
    }

    if (method === "POST" && /^\/api\/techtree\/v1\/agent\/science-tasks\/\d+\/review-update$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const current = this.liveScienceTasks.get(nodeId);
      if (!current) {
        json(res, 404, { error: { code: "science_task_not_found", message: "science task not found" } });
        return;
      }

      const payload = body as Partial<ScienceTaskDetail> & {
        harbor_pr_url?: string;
        latest_review_follow_up_note?: string | null;
        open_reviewer_concerns_count?: number;
        any_concern_unanswered?: boolean;
        latest_rerun_after_latest_fix?: boolean;
        latest_fix_at?: string | null;
        last_rerun_at?: string | null;
        packet_files?: Record<string, { encoding: "utf8" | "base64"; content: string }>;
      };
      const openConcerns = payload.open_reviewer_concerns_count ?? current.open_reviewer_concerns_count;
      const unanswered = payload.any_concern_unanswered ?? current.any_concern_unanswered;
      const rerunAfterFix =
        payload.latest_rerun_after_latest_fix ?? current.latest_rerun_after_latest_fix;
      const workflowState =
        openConcerns === 0 && !unanswered && rerunAfterFix ? "merge_ready" : "review_fix";
      const next = this.makeScienceTaskDetail(nodeId, {
        ...current,
        title: payload.title ?? current.title,
        summary: payload.summary ?? current.summary,
        science_domain: payload.science_domain ?? current.science_domain,
        science_field: payload.science_field ?? current.science_field,
        task_slug: payload.task_slug ?? current.task_slug,
        claimed_expert_time: payload.claimed_expert_time ?? current.claimed_expert_time,
        threshold_rationale: payload.threshold_rationale ?? current.threshold_rationale,
        anti_cheat_notes: payload.anti_cheat_notes ?? current.anti_cheat_notes,
        reproducibility_notes: payload.reproducibility_notes ?? current.reproducibility_notes,
        dependency_pinning_status: payload.dependency_pinning_status ?? current.dependency_pinning_status,
        canary_status: payload.canary_status ?? current.canary_status,
        failure_analysis: payload.failure_analysis ?? current.failure_analysis,
        packet_files: payload.packet_files ?? current.packet_files,
        harbor_pr_url: payload.harbor_pr_url ?? current.harbor_pr_url,
        latest_review_follow_up_note:
          payload.latest_review_follow_up_note ?? current.latest_review_follow_up_note,
        open_reviewer_concerns_count: openConcerns,
        any_concern_unanswered: unanswered,
        latest_rerun_after_latest_fix: rerunAfterFix,
        latest_fix_at: payload.latest_fix_at ?? current.latest_fix_at,
        last_rerun_at: payload.last_rerun_at ?? current.last_rerun_at,
        review_round_count: current.review_round_count + 1,
        workflow_state: workflowState,
        updated_at: createdAt(),
      });
      this.liveScienceTasks.set(nodeId, next);
      json(res, 200, this.scienceTaskMutation(next));
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/api/techtree/v1/agent/watches") {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      json(res, 200, {
        data: [...this.liveWatches.values()].flat(),
      });
      return;
    }

    if (method === "POST" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/watch$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      if (!this.liveNodes.has(nodeId)) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      const existing = this.currentWatchRecords(nodeId)[0];

      if (existing) {
        json(res, 200, { data: existing });
        return;
      }

      const watchRecord: WatchRecord = {
        id: this.nextWatchId,
        node_id: nodeId,
        watcher_type: "agent",
        watcher_ref: TEST_AGENT_SUMMARY.id,
        inserted_at: createdAt(),
      };

      this.nextWatchId += 1;
      this.liveWatches.set(nodeId, [...this.currentWatchRecords(nodeId), watchRecord]);
      json(res, 200, { data: watchRecord });
      return;
    }

    if (method === "DELETE" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/watch$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      if (!this.liveNodes.has(nodeId)) {
        json(res, 404, { error: { code: "node_not_found", message: "node not found" } });
        return;
      }

      this.liveWatches.delete(nodeId);
      json(res, 200, { ok: true });
      return;
    }

    if (method === "POST" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/star$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      const existing = (this.liveStars.get(nodeId) ?? [])[0];

      if (existing) {
        json(res, 200, { data: existing });
        return;
      }

      const starRecord: NodeStarRecord = {
        id: this.nextStarId,
        node_id: nodeId,
        actor_type: "agent",
        actor_ref: TEST_AGENT_SUMMARY.id,
        inserted_at: createdAt(),
      };

      this.nextStarId += 1;
      this.liveStars.set(nodeId, [starRecord]);
      this.appendActivityEvent(nodeId, "node.starred", {});
      json(res, 200, { data: starRecord });
      return;
    }

    if (method === "DELETE" && /^\/api\/techtree\/v1\/tree\/nodes\/\d+\/star$/.test(requestUrl.pathname)) {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      const nodeId = Number.parseInt(requestUrl.pathname.split("/")[6] ?? "0", 10);
      if ((this.liveStars.get(nodeId) ?? []).length > 0) {
        this.appendActivityEvent(nodeId, "node.unstarred", {});
      }
      this.liveStars.delete(nodeId);
      json(res, 200, { ok: true });
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/api/techtree/v1/agent/inbox") {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      if (this.options.inboxResponse) {
        json(res, this.options.inboxResponse.statusCode, this.options.inboxResponse.payload);
        return;
      }

      json(res, 200, this.handleInbox(requestUrl));
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/api/techtree/v1/agent/opportunities") {
      if (!(await this.ensureProtectedHeaders(res, method, requestUrl.pathname, headers))) {
        return;
      }

      if (this.options.opportunitiesResponse) {
        json(
          res,
          this.options.opportunitiesResponse.statusCode,
          this.options.opportunitiesResponse.payload,
        );
        return;
      }

      json(res, 200, this.handleOpportunities(requestUrl));
      return;
    }

    if (method === "GET" && requestUrl.pathname === "/skills/test-skill/latest/skill.md") {
      text(res, 200, "# test-skill\n");
      return;
    }

    json(res, 404, {
      error: {
        code: "route_not_found",
        message: `${method} ${requestUrl.pathname} not implemented in test contract server`,
      },
    });
  }

  private async ensureProtectedHeaders(
    res: http.ServerResponse,
    method: string,
    path: string,
    headers: Record<string, string>,
  ): Promise<boolean> {
    const verification = await this.verifyHttpEnvelope(method, path, headers);
    if (verification.statusCode === 200 && verification.payload.code === "http_envelope_valid") {
      return true;
    }

    json(res, verification.statusCode, {
      error: {
        code: verification.payload.code,
        message: verification.payload.message,
        ...(verification.payload.details === undefined ? {} : { details: verification.payload.details }),
      },
    });
    return false;
  }

  private async verifyHttpEnvelope(
    method: string,
    path: string,
    headers: Record<string, string>,
  ): Promise<{
    statusCode: number;
    payload:
      | { code: "http_envelope_valid"; details: Record<string, unknown> }
      | { code: "http_envelope_invalid"; message: string; details?: Record<string, unknown> };
  }> {
    for (const header of REQUIRED_AUTH_HEADERS) {
      if (!headers[header]) {
        return {
          statusCode: 401,
          payload: {
            code: "http_envelope_invalid",
            message: `missing required header: ${header}`,
          },
        };
      }
    }

    const receiptClaims = parseReceipt(headers["x-siwa-receipt"] ?? "");
    if (!receiptClaims) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "invalid SIWA receipt",
        },
      };
    }

    const receiptExpiry = Date.parse(receiptClaims.expiresAt);
    if (!Number.isFinite(receiptExpiry) || receiptExpiry <= Date.now()) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "SIWA receipt is expired",
        },
      };
    }

    if (headers["x-key-id"] !== receiptClaims.keyId) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "x-key-id is not bound to the SIWA receipt",
        },
      };
    }

    if (headers["x-agent-wallet-address"]?.toLowerCase() !== receiptClaims.walletAddress.toLowerCase()) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "x-agent-wallet-address does not match the SIWA receipt binding",
        },
      };
    }

    if (headers["x-agent-chain-id"] !== String(receiptClaims.chainId)) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "x-agent-chain-id does not match the SIWA receipt binding",
        },
      };
    }

    if (receiptClaims.registryAddress && headers["x-agent-registry-address"]?.toLowerCase() !== receiptClaims.registryAddress.toLowerCase()) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "x-agent-registry-address does not match the SIWA receipt binding",
        },
      };
    }

    if (receiptClaims.tokenId && headers["x-agent-token-id"] !== receiptClaims.tokenId) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "x-agent-token-id does not match the SIWA receipt binding",
        },
      };
    }

    const parsedSignatureInput = parseSignatureInputHeader(headers["signature-input"] ?? "");
    if (!parsedSignatureInput || parsedSignatureInput.label !== "sig1") {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "signature-input is malformed",
        },
      };
    }

    for (const component of REQUIRED_SIGNATURE_COMPONENTS) {
      if (!parsedSignatureInput.coveredComponents.includes(component)) {
        return {
          statusCode: 401,
          payload: {
            code: "http_envelope_invalid",
            message: `signature-input missing covered component: ${component}`,
          },
        };
      }
    }

    const created = parsedSignatureInput.params.created;
    const expires = parsedSignatureInput.params.expires;
    const nonce = parsedSignatureInput.params.nonce;
    const keyId = parsedSignatureInput.params.keyid;
    const timestamp = Number.parseInt(headers["x-timestamp"] ?? "", 10);
    if (
      created === undefined ||
      expires === undefined ||
      !nonce ||
      !keyId ||
      !Number.isFinite(timestamp)
    ) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "signature-input is missing replay-safety parameters",
        },
      };
    }

    if (created !== timestamp) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "signature-input created does not match x-timestamp",
        },
      };
    }

    if (keyId !== headers["x-key-id"]) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "signature-input keyid does not match x-key-id",
        },
      };
    }

    const nowUnix = currentUnixSeconds();
    if (expires <= created || expires <= nowUnix || Math.abs(nowUnix - created) > 300) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "signature timestamp is outside the accepted freshness window",
        },
      };
    }

    const replayKey = `${headers["x-key-id"]}:${nonce}`;
    if (this.consumedEnvelopeNonces.has(replayKey)) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "signature replay detected",
        },
      };
    }

    buildHttpSignatureSigningMessage({
      method,
      path,
      headers,
    });

    if (!parseSig1SignatureHeader(headers.signature ?? "")) {
      return {
        statusCode: 401,
        payload: {
          code: "http_envelope_invalid",
          message: "signature verification failed",
        },
      };
    }

    this.consumedEnvelopeNonces.add(replayKey);
    return {
      statusCode: 200,
      payload: {
        code: "http_envelope_valid",
        details: {
          walletAddress: receiptClaims.walletAddress,
          chainId: receiptClaims.chainId,
          registryAddress: receiptClaims.registryAddress,
          tokenId: receiptClaims.tokenId,
        },
      },
    };
  }
}
