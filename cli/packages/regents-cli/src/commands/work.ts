import { getBooleanFlag, getFlag, parseIntegerFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { runLocalWorkerLoop, type LocalWorkerAssignment } from "../agents/bridge/local-worker-loop.js";
import { printJson } from "../printer.js";
import {
  printWorkCreateResult,
  printWorkListResult,
  printWorkRunResult,
  printWorkShowResult,
  printWorkWatchTimelineResult,
} from "./rwr-presenters.js";
import {
  loadResolvedPlatformSession,
  requestPlatformSessionJson,
} from "./platform.js";
import { requestProductJson } from "./product-http.js";

type JsonObject = Record<string, unknown>;

const regentId = (args: ParsedCliArgs): string => requireArg(getFlag(args, "regent-id"), "regent-id");

const positional = (args: ParsedCliArgs, index: number, name: string): string =>
  requireArg(args.positionals[index], name);

const requestWorkJson = async (
  args: ParsedCliArgs,
  input: { method: "GET" | "POST"; path: string; body?: JsonObject },
): Promise<{ origin: string; data: JsonObject }> => {
  const { origin, session } = await loadResolvedPlatformSession(args);
  const { data } = await requestPlatformSessionJson({
    origin,
    session,
    method: input.method,
    path: input.path,
    commandName: "regents work",
    configPath: getFlag(args, "config"),
    ...(input.body === undefined ? {} : { body: input.body }),
  });

  return { origin, data };
};

const sleep = async (ms: number): Promise<void> => {
  await new Promise((resolve) => setTimeout(resolve, ms));
};

const requestAgentWorkJson = async (
  args: ParsedCliArgs,
  input: { method: "GET" | "POST"; path: string; body?: JsonObject },
): Promise<JsonObject> => {
  const configPath = getFlag(args, "config");
  return requestProductJson<JsonObject>(input.method, input.path, {
    body: input.body,
    configPath,
    requireAgentAuth: true,
    authAudience: "platform",
    service: "platform",
    commandName: "regents work",
  });
};

export async function runWorkCreate(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const title = requireArg(getFlag(args, "title"), "title");
  const description = getFlag(args, "description") ?? null;
  const { origin, data } = await requestWorkJson(args, {
    method: "POST",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/work-items`,
    body: {
      regent_id: resolvedRegentId,
      title,
      description,
    },
  });

  printWorkCreateResult(args, { ok: true, command: "regents work create", origin, result: data });
}

export async function runWorkList(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const { origin, data } = await requestWorkJson(args, {
    method: "GET",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/work-items`,
  });

  printWorkListResult(args, { ok: true, command: "regents work list", origin, result: data });
}

export async function runWorkGet(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const workItemId = positional(args, 2, "work_item_id");
  const { origin, data } = await requestWorkJson(args, {
    method: "GET",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/work-items/${encodeURIComponent(workItemId)}`,
  });

  printWorkShowResult(args, { ok: true, command: "regents work get", origin, result: data });
}

export async function runWorkRun(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const workItemId = positional(args, 2, "work_item_id");
  const runnerKind = requireArg(getFlag(args, "runner"), "runner");
  const workerId = getFlag(args, "worker-id") ?? null;
  const instructions = getFlag(args, "instructions") ?? null;
  const { origin, data } = await requestWorkJson(args, {
    method: "POST",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/work-items/${encodeURIComponent(workItemId)}/runs`,
    body: {
      regent_id: resolvedRegentId,
      work_item_id: workItemId,
      runner_kind: runnerKind,
      worker_id: workerId,
      instructions,
    },
  });

  printWorkRunResult(args, { ok: true, command: "regents work run", origin, result: data });
}

export async function runWorkCancel(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runId = positional(args, 2, "run_id");
  const { origin, data } = await requestWorkJson(args, {
    method: "POST",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/runs/${encodeURIComponent(runId)}/cancel`,
  });

  printWorkRunResult(args, { ok: true, command: "regents work cancel", origin, result: data });
}

export async function runWorkRetry(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runId = positional(args, 2, "run_id");
  const { origin, data } = await requestWorkJson(args, {
    method: "POST",
    path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/runs/${encodeURIComponent(runId)}/retry`,
  });

  printWorkRunResult(args, { ok: true, command: "regents work retry", origin, result: data });
}

export async function runWorkWatch(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const runId = positional(args, 2, "run_id");
  const pollMs = parseIntegerFlag(args, "poll-ms") ?? 2_000;
  const maxPolls = getBooleanFlag(args, "once") ? 1 : parseIntegerFlag(args, "max-polls");
  let polls = 0;
  const seenEventKeys = new Set<string>();

  while (maxPolls === undefined || polls < maxPolls) {
    const { origin, data } = await requestWorkJson(args, {
      method: "GET",
      path: `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/runs/${encodeURIComponent(runId)}/events`,
    });

    printWorkWatchTimelineResult(args, { ok: true, command: "regents work watch", origin, result: data }, {
      seenEventKeys,
    });
    polls += 1;

    if (maxPolls !== undefined && polls >= maxPolls) {
      break;
    }

    await sleep(pollMs);
  }
}

export async function runWorkLocalLoop(args: ParsedCliArgs): Promise<void> {
  const resolvedRegentId = regentId(args);
  const workerId = requireArg(getFlag(args, "worker-id"), "worker-id");
  const once = getBooleanFlag(args, "once");
  let remaining = once ? 1 : Number.POSITIVE_INFINITY;
  const baseWorkerPath = `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/workers/${encodeURIComponent(workerId)}`;
  const assignmentPath = (assignmentId: string | number, action: string): string =>
    `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/assignments/${encodeURIComponent(String(assignmentId))}/${action}`;
  const runPath = (assignment: LocalWorkerAssignment, suffix: string): string =>
    `/api/platform/regents/${encodeURIComponent(resolvedRegentId)}/rwr/runs/${encodeURIComponent(String(assignment.work_run_id))}/${suffix}`;

  await runLocalWorkerLoop<LocalWorkerAssignment>({
    shouldContinue: () => remaining-- > 0,
    sleepMs: once ? 0 : Number(getFlag(args, "sleep-ms") ?? "5000"),
    heartbeat: async () => {
      await requestAgentWorkJson(args, { method: "POST", path: `${baseWorkerPath}/heartbeat` });
    },
    listAssignments: async () => {
      const data = await requestAgentWorkJson(args, { method: "GET", path: `${baseWorkerPath}/assignments` });
      return Array.isArray(data.assignments) ? (data.assignments as LocalWorkerAssignment[]) : [];
    },
    claimAssignment: async (assignment) => {
      const data = await requestAgentWorkJson(args, {
        method: "POST",
        path: assignmentPath(assignment.id, "claim"),
      });
      return (data.assignment as LocalWorkerAssignment | undefined) ?? null;
    },
    appendRunEvent: async (assignment, event) => {
      await requestAgentWorkJson(args, {
        method: "POST",
        path: runPath(assignment, "events"),
        body: {
          regent_id: resolvedRegentId,
          run_id: assignment.work_run_id,
          kind: event.kind,
          payload: event.payload ?? {},
          visibility: event.visibility ?? "operator",
          sensitivity: event.sensitivity ?? "normal",
        },
      });
    },
    uploadArtifact: async (assignment, artifact) => {
      await requestAgentWorkJson(args, {
        method: "POST",
        path: runPath(assignment, "artifacts"),
        body: {
          regent_id: resolvedRegentId,
          run_id: assignment.work_run_id,
          ...artifact,
        },
      });
    },
    requestDelegation: async (assignment, delegation) => {
      await requestAgentWorkJson(args, {
        method: "POST",
        path: runPath(assignment, "delegations"),
        body: {
          regent_id: resolvedRegentId,
          run_id: assignment.work_run_id,
          ...delegation,
        },
      });
    },
    releaseAssignment: async (assignment) => {
      await requestAgentWorkJson(args, { method: "POST", path: assignmentPath(assignment.id, "release") });
    },
    completeAssignment: async (assignment) => {
      await requestAgentWorkJson(args, { method: "POST", path: assignmentPath(assignment.id, "complete") });
    },
    handleAssignment: async () => ({
      events: [
        {
          kind: "local_worker_checked_assignment",
          payload: { worker_id: workerId },
          visibility: "operator",
          sensitivity: "normal",
        },
      ],
      artifacts:
        getFlag(args, "artifact-title") && getFlag(args, "artifact-body")
          ? [
              {
                artifact_type: "note",
                title: String(getFlag(args, "artifact-title")),
                body: String(getFlag(args, "artifact-body")),
                visibility: "operator",
              },
            ]
          : [],
      delegation: getFlag(args, "delegate-runner")
        ? {
            requested_runner_kind: String(getFlag(args, "delegate-runner")),
            tasks: [{ title: getFlag(args, "delegate-title") ?? "Delegated work" }],
          }
        : undefined,
      complete: true,
    }),
  });

  printJson({ ok: true, command: "regents work local-loop" });
}
