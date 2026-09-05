import { writeOpenClawRegentsWorkSkill } from "../../agents/openclaw/connect.js";
import { CliUsageError } from "../../cli-usage-error.js";
import { loadConfig } from "../../internal-runtime/index.js";
import { productBaseUrl } from "../../internal-runtime/product-http-client.js";
import { getFlag, requireArg, type ParsedCliArgs } from "../../parse.js";
import {
  printAgentChatResult,
  printAgentConnectHostedHermesResult,
  printAgentConnectOpenClawResult,
  printAgentExecutionPoolResult,
  printAgentLinkResult,
} from "../rwr-presenters.js";
import {
  loadResolvedPlatformSession,
  requestPlatformSessionJson,
} from "../platform.js";
import { requestProductJson } from "../product-http.js";

type JsonObject = Record<string, unknown>;

const regentId = (args: ParsedCliArgs): string => requireArg(getFlag(args, "regent-id"), "regent-id");

const relationshipMember = (
  args: ParsedCliArgs,
  input: { agentFlag: string; workerFlag: string; label: string },
): { agentId?: string; workerId?: string; routeId: string } => {
  const agentId = getFlag(args, input.agentFlag);
  const workerId = getFlag(args, input.workerFlag);

  if (agentId && workerId) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: `use either --${input.agentFlag} or --${input.workerFlag} for the ${input.label}, not both`,
    });
  }

  if (!agentId && !workerId) {
    throw new CliUsageError({
      code: "missing_required_argument",
      message: `missing ${input.label}: pass --${input.agentFlag} or --${input.workerFlag}`,
      missing: [`--${input.agentFlag}`, `--${input.workerFlag}`],
    });
  }

  return {
    ...(agentId ? { agentId } : {}),
    ...(workerId ? { workerId } : {}),
    routeId: agentId ?? workerId ?? "",
  };
};

const writeSkillEnabled = (args: ParsedCliArgs): boolean => {
  const value = getFlag(args, "write-skill");
  return value === undefined || value === "true" || value === "1" || value === "yes";
};

const registeredWorkerId = (data: JsonObject): string => {
  const worker = data.worker;

  if (!worker || typeof worker !== "object" || Array.isArray(worker)) {
    throw new Error("Platform did not return a connected worker.");
  }

  const id = (worker as JsonObject).id;

  if (typeof id !== "string" && typeof id !== "number") {
    throw new Error("Platform did not return a worker id.");
  }

  return String(id);
};

const requestPlatformAgentJson = async (
  configPath: string | undefined,
  input: { method: "GET" | "POST"; path: string; body?: JsonObject },
): Promise<{ origin: string; data: JsonObject }> => {
  const data = await requestProductJson<JsonObject>(input.method, input.path, {
    body: input.body,
    configPath,
    requireAgentAuth: true,
    authAudience: "platform",
    service: "platform",
    commandName: "regents agent",
  });

  return { origin: productBaseUrl(loadConfig(configPath), "platform"), data };
};

const runtimePath = (resolvedRegentId: string, runtimeId: string): string =>
  `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/runtimes/${encodeURIComponent(runtimeId)}`;

const chatMessage = (args: ParsedCliArgs): string => {
  const message = args.positionals.slice(2).join(" ").trim();

  if (!message) {
    throw new CliUsageError({
      code: "missing_required_argument",
      message: "message is required.",
      missing: ["message"],
    });
  }

  if (message.length > 6_000) {
    throw new CliUsageError({
      code: "invalid_argument",
      message: "message must be 6000 characters or fewer.",
    });
  }

  return message;
};

const chatTimeoutSeconds = (args: ParsedCliArgs): number => {
  const raw = getFlag(args, "timeout-seconds");

  if (raw === undefined) {
    return 30;
  }

  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 5 || parsed > 60 || String(parsed) !== raw) {
    throw new CliUsageError({
      code: "invalid_flag_value",
      message: "--timeout-seconds must be a whole number from 5 to 60.",
    });
  }

  return parsed;
};

const recordString = (record: unknown, key: string): string | null => {
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    return null;
  }

  const value = (record as JsonObject)[key];
  return typeof value === "string" && value !== "" ? value : null;
};

const resolveAgentChatSlug = async (
  args: ParsedCliArgs,
  input: {
    origin: string;
    session: Awaited<ReturnType<typeof loadResolvedPlatformSession>>["session"];
    configPath?: string;
  },
): Promise<string> => {
  const explicitSlug = getFlag(args, "slug");
  if (explicitSlug) {
    return explicitSlug;
  }

  const { data } = await requestPlatformSessionJson({
    origin: input.origin,
    session: input.session,
    method: "GET",
    path: "/api/platform/auth/privy/profile",
    commandName: "regents agent chat",
    configPath: input.configPath,
  });

  const slugs = (Array.isArray(data.agents) ? data.agents : [])
    .map((agent) => recordString(agent, "slug"))
    .filter((slug): slug is string => Boolean(slug));

  if (slugs.length === 1) {
    return slugs[0] as string;
  }

  if (slugs.length > 1) {
    throw new CliUsageError({
      code: "missing_required_argument",
      message: "--slug is required when your saved session owns more than one regent.",
      missing: ["--slug"],
    });
  }

  throw new Error("No regent was found for the saved platform session.");
};

export async function runAgentChat(args: ParsedCliArgs): Promise<void> {
  const message = chatMessage(args);
  const timeoutSeconds = chatTimeoutSeconds(args);
  const configPath = getFlag(args, "config");
  const { origin, session } = await loadResolvedPlatformSession(args);
  const slug = await resolveAgentChatSlug(args, { origin, session, configPath });
  const { data } = await requestPlatformSessionJson({
    origin,
    session,
    method: "POST",
    path: `/api/platform/sprites/${encodeURIComponent(slug)}/message`,
    body: {
      message,
      timeout_seconds: timeoutSeconds,
    },
    commandName: "regents agent chat",
    configPath,
    timeoutMs: (timeoutSeconds + 5) * 1000,
  });

  printAgentChatResult(args, {
    ok: true,
    command: "regents agent chat",
    origin,
    result: data,
  });
}

export async function runAgentConnectHostedHermes(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = requireArg(getFlag(args, "runtime-id"), "runtime-id");
  const { origin, session } = await loadResolvedPlatformSession(args);
  const configPath = getFlag(args, "config");
  const requestHostedJson = async (path: string): Promise<JsonObject> => {
    const { data } = await requestPlatformSessionJson({
      origin,
      session,
      method: "GET",
      path,
      commandName: "regents agent connect hosted-hermes",
      configPath,
    });

    return data;
  };
  const basePath = runtimePath(resolvedRegentId, runtimeId);
  const runtime = await requestHostedJson(basePath);
  const services = await requestHostedJson(`${basePath}/services`);
  const health = await requestHostedJson(`${basePath}/health`);

  printAgentConnectHostedHermesResult(args, {
    ok: true,
    command: "regents agent connect hosted-hermes",
    origin,
    result: {
      regent_id: resolvedRegentId,
      runtime_id: runtimeId,
      runtime: runtime.runtime,
      services: services.services,
      health: health.health,
    },
  });
}

export async function runAgentConnectOpenClaw(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const resolvedRegentId = regentId(args);
  const role = requireArg(getFlag(args, "role"), "role");
  const displayName = getFlag(args, "name") ?? "OpenClaw local worker";
  const runnerKind = role === "manager" ? "openclaw_local_manager" : "openclaw_local_executor";
  const { origin, data } = await requestPlatformAgentJson(configPath, {
    method: "POST",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/workers`,
    body: {
      regent_id: resolvedRegentId,
      agent_kind: "openclaw",
      worker_role: role,
      execution_surface: "local_bridge",
      runner_kind: runnerKind,
      billing_mode: "user_local",
      trust_scope: "local_user_controlled",
      reported_usage_policy: "self_reported",
      display_name: displayName,
      endpoint_url: null,
    },
  });
  const skill = writeSkillEnabled(args)
    ? await writeOpenClawRegentsWorkSkill({
        regentId: resolvedRegentId,
        workerId: registeredWorkerId(data),
        workerName: displayName,
      })
    : null;

  printAgentConnectOpenClawResult(args, {
    ok: true,
    command: "regents agent connect openclaw",
    origin,
    result: data,
    openclaw: {
      skillFile: skill?.skillPath ?? null,
    },
  });
}

export async function runAgentLink(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const manager = relationshipMember(args, {
    agentFlag: "manager-agent-id",
    workerFlag: "manager-worker-id",
    label: "manager",
  });
  const executor = relationshipMember(args, {
    agentFlag: "executor-agent-id",
    workerFlag: "executor-worker-id",
    label: "executor",
  });
  const relationship = requireArg(getFlag(args, "relationship"), "relationship");
  const { origin, session } = await loadResolvedPlatformSession(args);
  const { data } = await requestPlatformSessionJson({
    origin,
    session,
    method: "POST",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/agents/${encodeURIComponent(manager.routeId)}/relationships`,
    body: {
      regent_id: resolvedRegentId,
      ...(manager.agentId ? { source_agent_profile_id: manager.agentId } : {}),
      ...(manager.workerId ? { source_worker_id: manager.workerId } : {}),
      ...(executor.agentId ? { target_agent_profile_id: executor.agentId } : {}),
      ...(executor.workerId ? { target_worker_id: executor.workerId } : {}),
      relationship_kind: relationship,
      status: "active",
    },
  });

  printAgentLinkResult(args, { ok: true, command: "regents agent link", origin, result: data });
}

export async function runAgentExecutionPool(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const manager = requireArg(getFlag(args, "manager"), "manager");
  const { origin, session } = await loadResolvedPlatformSession(args);
  const { data } = await requestPlatformSessionJson({
    origin,
    session,
    method: "GET",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/agents/${encodeURIComponent(manager)}/execution-pool`,
  });

  printAgentExecutionPoolResult(args, { ok: true, command: "regents agent execution-pool", origin, result: data });
}
