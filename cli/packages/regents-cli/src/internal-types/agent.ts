import type { LocalAgentIdentity } from "./runtime.js";

export type RegentExecutorHarnessKind = "openclaw" | "hermes" | "claude_code" | "codex" | "custom";
export type RegentOriginKind =
  | "local"
  | "gossipsub"
  | "api"
  | "watched_node"
  | "scheduled"
  | "other";
export type RegentOriginTransport = "gossipsub" | "api" | "other";
export type RegentAgentProfileKind = "owner" | "public" | "group" | "custom";

export interface RegentRunExecutorHarness {
  kind: RegentExecutorHarnessKind;
  profile: string;
  entrypoint?: string | null;
}

export interface RegentRunOrigin {
  kind: RegentOriginKind;
  transport?: RegentOriginTransport | null;
  session_id?: string | null;
  trigger_ref?: string | null;
}

export interface RegentRunMetadata {
  executor_harness: RegentRunExecutorHarness;
  origin: RegentRunOrigin;
}

export interface RegentResolvedRunMetadata extends RegentRunMetadata {
  resolved_at: string;
  executor_harness_kind: RegentExecutorHarnessKind;
  executor_harness_profile: string;
  origin_session_id: string | null;
}

export interface RegentAgentRuntimeState extends RegentResolvedRunMetadata {
  initializedAt: string;
}

export interface RegentAgentProfileSummary {
  name: string;
  kind: RegentAgentProfileKind;
  label: string;
  active: boolean;
  executor_harness_kind: RegentExecutorHarnessKind;
  executor_harness_profile: string;
  origin_session_id: string | null;
  executor_harness: RegentRunExecutorHarness;
  origin: RegentRunOrigin;
}

export interface RegentAgentHarnessSummary {
  name: string;
  kind: RegentExecutorHarnessKind;
  label: string;
  active: boolean;
  executor_harness_kind: RegentExecutorHarnessKind;
  executor_harness_profile: string;
  origin_session_id: string | null;
  executor_harness: RegentRunExecutorHarness;
  origin: RegentRunOrigin;
}

export interface RegentAgentStatus {
  initialized: boolean;
  state: RegentAgentRuntimeState | null;
  identity: LocalAgentIdentity | null;
  currentProfile: RegentAgentProfileSummary | null;
  currentHarness: RegentAgentHarnessSummary | null;
  currentOrigin: RegentRunOrigin | null;
  profiles: RegentAgentProfileSummary[];
  harnesses: RegentAgentHarnessSummary[];
  resolvedMetadata: RegentResolvedRunMetadata | null;
}
