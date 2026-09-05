import {
  readIdentityReceipt,
  updateIdentityReceipt,
} from "../internal-runtime/identity/cache.js";
import { getBooleanFlag, requirePositional, type ParsedCliArgs } from "../parse.js";
import {
  CLI_PALETTE,
  isHumanTerminal,
  printJson,
  printJsonLine,
  printText,
  renderKeyValuePanel,
  renderPanel,
  tone,
} from "../printer.js";
import { parsePollingIntervalSeconds } from "./autolaunch/shared.js";
import { requireAgentAuthState } from "./agent-auth.js";
import { requestProductJson } from "./product-http.js";

interface CreateAgentbookTrustSessionRequest {
  source: string;
}

interface AgentbookTrustSummary {
  connected: boolean;
  world_human_id: string | null;
  unique_agent_count: number;
  connected_at: string | null;
  source: string | null;
}

interface AgentbookFrontendRequest {
  app_id: string;
  action: string;
  signal: string;
  rp_context: Record<string, unknown>;
}

interface AgentbookSessionPayload {
  session_id: string;
  status: string;
  wallet_address: string;
  chain_id: number;
  registry_address: string;
  token_id: string;
  network: string;
  source: string;
  approval_url: string | null;
  connector_uri: string | null;
  deep_link_uri: string | null;
  expires_at: string;
  error_text: string | null;
  frontend_request: AgentbookFrontendRequest | null;
  wallet_action: Record<string, unknown> | null;
  trust: AgentbookTrustSummary;
}

interface AgentbookSessionResponse {
  ok: boolean;
  session: AgentbookSessionPayload;
}

interface AgentbookLookupResult {
  wallet_address: string;
  chain_id: number;
  registry_address: string;
  token_id: string;
  connected: boolean;
  world_human_id: string | null;
  unique_agent_count: number;
  connected_at: string | null;
  source: string | null;
}

interface AgentbookLookupResponse {
  ok: boolean;
  result: AgentbookLookupResult;
}

const TERMINAL_SESSION_STATUSES = new Set(["registered", "failed"]);

const watchInterval = async (seconds: number): Promise<void> => {
  await new Promise((resolve) => setTimeout(resolve, seconds * 1000));
};

const shouldWatch = (args: ParsedCliArgs): boolean => getBooleanFlag(args, "watch");

const requestAgentbookJson = async <TResponse>(
  method: "GET" | "POST",
  endpointPath: string,
  input?: { body?: unknown; configPath?: string },
): Promise<TResponse> =>
  requestProductJson<TResponse>(method, endpointPath, {
    body: method === "POST" ? input?.body ?? {} : undefined,
    configPath: input?.configPath,
    requireAgentAuth: true,
    authAudience: "regent-services",
    service: "platform",
    commandName: "regents agentbook",
  });

export async function lookupAgentbookTrust(configPath?: string): Promise<AgentbookLookupResponse> {
  requireAgentAuthState(configPath, { audience: "regent-services" });

  return requestAgentbookJson<AgentbookLookupResponse>("GET", "/api/platform/agentbook/lookup", {
    configPath,
  });
}

export async function prepareAgentbookRegistration(
  configPath?: string,
  source = "regents-cli",
): Promise<AgentbookSessionResponse> {
  requireSavedIdentityReceipt();
  requireAgentAuthState(configPath, { audience: "regent-services" });

  const payload: CreateAgentbookTrustSessionRequest = {
    source,
  };

  const created = await requestAgentbookJson<AgentbookSessionResponse>("POST", "/api/platform/agentbook/sessions", {
    body: payload,
    configPath,
  });

  if (created.session) {
    syncWorldTrustFromSession(created.session);
  }

  return created;
}

const requireSavedIdentityReceipt = () => {
  const receipt = readIdentityReceipt();

  if (!receipt) {
    throw new Error("This machine does not have a saved Regent identity yet. Run `regents identity ensure` first.");
  }

  if (!receipt.agent_registry || !receipt.agent_id || !receipt.token_id) {
    throw new Error("This command needs a saved Regent identity. Run `regents identity ensure` again.");
  }

  return receipt;
};

const syncWorldTrustFromSession = (session: AgentbookSessionPayload): void => {
  if (
    session.trust.connected !== true ||
    typeof session.trust.world_human_id !== "string" ||
    typeof session.trust.connected_at !== "string" ||
    typeof session.trust.source !== "string"
  ) {
    return;
  }

  const humanId = session.trust.world_human_id;
  const connectedAt = session.trust.connected_at;
  const source = session.trust.source;

  updateIdentityReceipt((receipt) => ({
    ...receipt,
    world: {
      human_id: humanId,
      connected_at: connectedAt,
      source,
      platform_session_id: session.session_id,
    },
  }));
};

const printApprovalHint = (session: AgentbookSessionPayload): void => {
  if (!process.stderr.isTTY) {
    return;
  }

  if (typeof session.approval_url === "string" && session.approval_url !== "") {
    process.stderr.write(
      `${renderPanel("◆ APPROVAL NEEDED", [
        `session ${tone(session.session_id, CLI_PALETTE.primary, true)}`,
        `expires ${tone(session.expires_at, CLI_PALETTE.secondary)}`,
        `open ${tone(session.approval_url, CLI_PALETTE.emphasis, true)}`,
      ], {
        borderColor: CLI_PALETTE.emphasis,
        titleColor: CLI_PALETTE.title,
      })}\n`,
    );
  }
};

const printSessionWatchUpdate = (args: ParsedCliArgs, payload: AgentbookSessionResponse): void => {
  if (isHumanTerminal() && !getBooleanFlag(args, "json")) {
    const session = payload.session;
    printText(
      renderKeyValuePanel("◆ TRUST SESSION", [
        { label: "session", value: session.session_id, valueColor: CLI_PALETTE.emphasis },
        { label: "status", value: session.status, valueColor: CLI_PALETTE.emphasis },
        { label: "chain", value: String(session.chain_id) },
        ...(session.error_text ? [{ label: "note", value: session.error_text }] : []),
        ...(session.trust.connected
          ? [{ label: "human check", value: "connected", valueColor: CLI_PALETTE.emphasis }]
          : []),
      ]),
    );
    return;
  }

  printJsonLine(payload);
};

export async function runAgentbookRegister(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const created = await prepareAgentbookRegistration(configPath);

  const createdSession = created.session;

  if (createdSession) {
    printApprovalHint(createdSession);
  }

  if (!shouldWatch(args)) {
    printJson(created);
    return;
  }

  if (!createdSession || typeof createdSession.session_id !== "string") {
    printJson(created);
    return;
  }

  const watched = await watchAgentbookSession(createdSession.session_id, args, configPath);
  const watchedSession = watched.session;

  if (watchedSession) {
    syncWorldTrustFromSession(watchedSession);
  }

  printJson(watched);
}

const watchAgentbookSession = async (
  sessionId: string,
  args: ParsedCliArgs,
  configPath?: string,
  onPoll?: (payload: AgentbookSessionResponse) => void,
): Promise<AgentbookSessionResponse> => {
  const intervalSeconds = parsePollingIntervalSeconds(args);

  for (;;) {
    const payload = await requestAgentbookJson<AgentbookSessionResponse>(
      "GET",
      `/api/platform/agentbook/sessions/${encodeURIComponent(sessionId)}`,
      { configPath },
    );

    const session = payload.session;

    if (session) {
      syncWorldTrustFromSession(session);
      onPoll?.(payload);
      const status = typeof session.status === "string" ? session.status : "";
      if (TERMINAL_SESSION_STATUSES.has(status)) {
        return payload;
      }
    }

    await watchInterval(intervalSeconds);
  }
};

export async function runAgentbookSessionsWatch(args: ParsedCliArgs, configPath?: string): Promise<void> {
  requireSavedIdentityReceipt();
  requireAgentAuthState(configPath, { audience: "regent-services" });

  const sessionId = requirePositional(args, 3, "session-id");
  await watchAgentbookSession(sessionId, args, configPath, (payload) => printSessionWatchUpdate(args, payload));
}

export async function runAgentbookLookup(_args: ParsedCliArgs, configPath?: string): Promise<void> {
  printJson(await lookupAgentbookTrust(configPath));
}
