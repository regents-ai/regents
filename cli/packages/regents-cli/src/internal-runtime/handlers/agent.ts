import type {
  RegentAgentHarnessSummary,
  RegentAgentProfileKind,
  RegentAgentProfileSummary,
  RegentAgentRuntimeState,
  RegentAgentStatus,
  RegentConfig,
  RegentExecutorHarnessKind,
} from "../../internal-types/index.js";

import { getCurrentAgentIdentity } from "../agent/profile.js";
import type { RuntimeContext } from "../runtime.js";

const nowIso = (): string => new Date().toISOString();

const defaultState = (config: RegentConfig): RegentAgentRuntimeState => {
  const kind = config.agents.defaultHarness;
  const profile = "owner";
  const executorHarness = {
    kind,
    profile,
    entrypoint: config.agents.harnesses[kind]?.entrypoint ?? "regents agent init",
  };
  const origin = {
    kind: "local" as const,
    transport: "api" as const,
    session_id: null,
    trigger_ref: "regents agent init",
  };

  return {
    initializedAt: nowIso(),
    resolved_at: nowIso(),
    executor_harness: executorHarness,
    origin,
    executor_harness_kind: kind,
    executor_harness_profile: profile,
    origin_session_id: null,
  };
};

const profileKind = (name: string): RegentAgentProfileKind => {
  if (name === "owner" || name === "public" || name === "group") {
    return name;
  }
  return "custom";
};

const profileLabel = (name: string): string => {
  if (name === "owner") return "Owner agent profile";
  if (name === "public") return "Public agent profile";
  if (name === "group") return "Group agent profile";
  return "Custom agent profile";
};

const harnessLabel = (kind: RegentExecutorHarnessKind): string => {
  if (kind === "openclaw") return "OpenClaw executor harness";
  if (kind === "hermes") return "Hermes executor harness";
  if (kind === "claude_code") return "Claude Code executor harness";
  return "Custom executor harness";
};

const activeState = (ctx: RuntimeContext): RegentAgentRuntimeState =>
  ctx.stateStore.read().agentRuntime ?? defaultState(ctx.config);

const profileSummaries = (
  state: RegentAgentRuntimeState,
  config: RegentConfig,
): RegentAgentProfileSummary[] => {
  const names = Array.from(new Set([
    "owner",
    "public",
    "group",
    state.executor_harness.profile,
    ...Object.values(config.agents.harnesses).flatMap((harness) => harness.profiles),
  ]));

  return names.map((name) => ({
    name,
    kind: profileKind(name),
    label: profileLabel(name),
    active: state.executor_harness.profile === name,
    executor_harness_kind: state.executor_harness.kind,
    executor_harness_profile: name,
    origin_session_id: state.origin.session_id ?? null,
    executor_harness: {
      kind: state.executor_harness.kind,
      profile: name,
      entrypoint: state.executor_harness.entrypoint ?? null,
    },
    origin: {
      kind: state.origin.kind,
      transport: state.origin.transport ?? null,
      session_id: state.origin.session_id ?? null,
      trigger_ref: state.origin.trigger_ref ?? null,
    },
  }));
};

const harnessSummaries = (
  state: RegentAgentRuntimeState,
  config: RegentConfig,
): RegentAgentHarnessSummary[] =>
  Object.entries(config.agents.harnesses).map(([name, harness]) => {
    const kind = name as RegentExecutorHarnessKind;
    return {
      name,
      kind,
      label: harnessLabel(kind),
      active: state.executor_harness.kind === kind,
      executor_harness_kind: kind,
      executor_harness_profile: state.executor_harness.profile,
      origin_session_id: state.origin.session_id ?? null,
      executor_harness: {
        kind,
        profile: state.executor_harness.profile,
        entrypoint: harness.entrypoint,
      },
      origin: {
        kind: state.origin.kind,
        transport: state.origin.transport ?? null,
        session_id: state.origin.session_id ?? null,
        trigger_ref: state.origin.trigger_ref ?? null,
      },
    };
  });

const status = (ctx: RuntimeContext): RegentAgentStatus => {
  const storedState = ctx.stateStore.read().agentRuntime ?? null;
  const state = storedState ?? defaultState(ctx.config);
  const profiles = profileSummaries(state, ctx.config);
  const harnesses = harnessSummaries(state, ctx.config);

  return {
    initialized: storedState !== null,
    state: storedState,
    identity: getCurrentAgentIdentity(ctx.stateStore),
    currentProfile: profiles.find((profile) => profile.active) ?? null,
    currentHarness: harnesses.find((harness) => harness.active) ?? null,
    currentOrigin: state.origin,
    profiles,
    harnesses,
    resolvedMetadata: {
      resolved_at: state.resolved_at,
      executor_harness: { ...state.executor_harness },
      origin: { ...state.origin },
      executor_harness_kind: state.executor_harness_kind,
      executor_harness_profile: state.executor_harness_profile,
      origin_session_id: state.origin_session_id,
    },
  };
};

export async function handleAgentInit(ctx: RuntimeContext): Promise<RegentAgentStatus> {
  if (!ctx.stateStore.read().agentRuntime) {
    ctx.stateStore.patch({ agentRuntime: defaultState(ctx.config) });
  }
  return status(ctx);
}

export async function handleAgentStatus(ctx: RuntimeContext): Promise<RegentAgentStatus> {
  return status(ctx);
}

export async function handleAgentProfileList(
  ctx: RuntimeContext,
): Promise<{ data: RegentAgentProfileSummary[] }> {
  return { data: profileSummaries(activeState(ctx), ctx.config) };
}

export async function handleAgentProfileShow(
  ctx: RuntimeContext,
  params?: { profile?: string },
): Promise<{ data: RegentAgentProfileSummary }> {
  const profiles = profileSummaries(activeState(ctx), ctx.config);
  const name = params?.profile ?? profiles.find((profile) => profile.active)?.name ?? "owner";
  const profile = profiles.find((candidate) => candidate.name === name);
  if (!profile) {
    throw new Error(`unknown agent profile: ${name}`);
  }
  return { data: profile };
}

export async function handleAgentHarnessList(
  ctx: RuntimeContext,
): Promise<{ data: RegentAgentHarnessSummary[] }> {
  return { data: harnessSummaries(activeState(ctx), ctx.config) };
}
