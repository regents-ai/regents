import { getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import {
  printRuntimeCheckpointResult,
  printRuntimeHealthResult,
  printRuntimeRestoreResult,
  printRuntimeResult,
  printRuntimeServicesResult,
} from "./rwr-presenters.js";
import { loadResolvedPlatformSession, requestPlatformSessionJson } from "./platform.js";

type JsonObject = Record<string, unknown>;

const regentId = (args: ParsedCliArgs): string => requireArg(getFlag(args, "regent-id"), "regent-id");

const positional = (args: ParsedCliArgs, index: number, name: string): string =>
  requireArg(args.positionals[index], name);

const runtimePath = (resolvedRegentId: string, runtimeId?: string): string => {
  const base = `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/runtimes`;
  return runtimeId ? `${base}/${encodeURIComponent(runtimeId)}` : base;
};

const requestRuntimeJson = async (
  args: ParsedCliArgs,
  input: { method: "GET" | "POST"; path: string; body?: JsonObject },
): Promise<{ origin: string; data: JsonObject }> => {
  const { origin, session } = await loadResolvedPlatformSession(args);
  const { data } = await requestPlatformSessionJson({
    origin,
    session,
    method: input.method,
    path: input.path,
    ...(input.body === undefined ? {} : { body: input.body }),
  });

  return { origin, data };
};

export async function runRuntimeCreate(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const name = requireArg(getFlag(args, "name"), "name");
  const platformAgentId = getFlag(args, "platform-agent-id");
  const runnerKind = requireArg(getFlag(args, "runner"), "runner");
  const executionSurface = requireArg(getFlag(args, "execution-surface"), "execution-surface");
  const billingMode = requireArg(getFlag(args, "billing-mode"), "billing-mode");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "POST",
    path: runtimePath(resolvedRegentId),
    body: {
      regent_id: resolvedRegentId,
      ...(platformAgentId ? { platform_agent_id: platformAgentId } : {}),
      name,
      runner_kind: runnerKind,
      execution_surface: executionSurface,
      billing_mode: billingMode,
    },
  });

  printRuntimeResult(args, { ok: true, command: "regents runtime create", origin, result: data }, "created");
}

export async function runRuntimeGet(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = positional(args, 2, "runtime_id");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "GET",
    path: runtimePath(resolvedRegentId, runtimeId),
  });

  printRuntimeResult(args, { ok: true, command: "regents runtime get", origin, result: data }, "status");
}

export async function runRuntimeCheckpoint(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = positional(args, 2, "runtime_id");
  const checkpointRef = requireArg(getFlag(args, "checkpoint-ref"), "checkpoint-ref");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "POST",
    path: `${runtimePath(resolvedRegentId, runtimeId)}/checkpoint`,
    body: {
      regent_id: resolvedRegentId,
      runtime_id: runtimeId,
      checkpoint_ref: checkpointRef,
    },
  });

  printRuntimeCheckpointResult(args, { ok: true, command: "regents runtime checkpoint", origin, result: data });
}

export async function runRuntimeRestore(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = positional(args, 2, "runtime_id");
  const checkpointId = requireArg(getFlag(args, "checkpoint-id"), "checkpoint-id");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "POST",
    path: `${runtimePath(resolvedRegentId, runtimeId)}/restore`,
    body: {
      regent_id: resolvedRegentId,
      runtime_id: runtimeId,
      checkpoint_id: checkpointId,
    },
  });

  printRuntimeRestoreResult(args, { ok: true, command: "regents runtime restore", origin, result: data });
}

export async function runRuntimePause(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = positional(args, 2, "runtime_id");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "POST",
    path: `${runtimePath(resolvedRegentId, runtimeId)}/pause`,
  });

  printRuntimeResult(args, { ok: true, command: "regents runtime pause", origin, result: data }, "paused");
}

export async function runRuntimeResume(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = positional(args, 2, "runtime_id");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "POST",
    path: `${runtimePath(resolvedRegentId, runtimeId)}/resume`,
  });

  printRuntimeResult(args, { ok: true, command: "regents runtime resume", origin, result: data }, "resumed");
}

export async function runRuntimeServices(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = positional(args, 2, "runtime_id");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "GET",
    path: `${runtimePath(resolvedRegentId, runtimeId)}/services`,
  });

  printRuntimeServicesResult(args, { ok: true, command: "regents runtime services", origin, result: data });
}

export async function runRuntimeHealth(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runtimeId = positional(args, 2, "runtime_id");
  const { origin, data } = await requestRuntimeJson(args, {
    method: "GET",
    path: `${runtimePath(resolvedRegentId, runtimeId)}/health`,
  });

  printRuntimeHealthResult(args, { ok: true, command: "regents runtime health", origin, result: data });
}
