export type DoctorStatus = "ok" | "warn" | "fail" | "skip";
export type DoctorScope = "runtime" | "auth" | "transports";
export type DoctorMode = "default" | "scoped" | "full";

export interface DoctorCheckResult {
  id: string;
  scope: DoctorScope;
  status: DoctorStatus;
  title: string;
  message: string;
  details?: Record<string, unknown>;
  remediation?: string;
  fixApplied?: boolean;
  startedAt: string;
  finishedAt: string;
  durationMs: number;
}

export interface DoctorSummary {
  ok: number;
  warn: number;
  fail: number;
  skip: number;
}

export interface DoctorReport {
  ok: boolean;
  mode: DoctorMode;
  scope?: DoctorScope;
  summary: DoctorSummary;
  checks: DoctorCheckResult[];
  nextSteps: string[];
  generatedAt: string;
}

export interface DoctorRunParams {
  json?: boolean;
  verbose?: boolean;
  fix?: boolean;
  quiet?: boolean;
  onlyFailures?: boolean;
  ci?: boolean;
}

export interface DoctorRunScopedParams extends DoctorRunParams {
  scope: DoctorScope;
}

export interface DoctorRunFullParams extends DoctorRunParams {
  knownParentId?: number;
  cleanupCommentBodyPrefix?: string;
}
