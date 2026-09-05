import path from "node:path";

import type {
  DoctorCheckResult,
  DoctorReport,
  DoctorRunFullParams,
  DoctorRunParams,
  DoctorRunScopedParams,
} from "../../internal-types/index.js";
import type { RuntimeContext } from "../runtime.js";

import { LocalKeySignerBackend } from "../agent/local-signer-backend.js";
import { loadConfig } from "../config.js";
import { DoctorInternalError, errorMessage } from "../errors.js";
import { defaultConfigPath, expandHome } from "../paths.js";
import { SessionStore } from "../store/session-store.js";
import { StateStore } from "../store/state-store.js";
import { authChecks } from "./checks/authChecks.js";
import { runtimeChecks } from "./checks/runtimeChecks.js";
import { transportChecks } from "./checks/transportChecks.js";
import { deriveNextSteps } from "./renderNextSteps.js";
import type {
  DoctorCheckContext,
  DoctorCheckDefinition,
  DoctorInvocation,
} from "./types.js";

const DEFAULT_CHECK_FACTORIES: Array<() => DoctorCheckDefinition[]> = [
  runtimeChecks,
  authChecks,
  transportChecks,
];

const createSigner = (config: DoctorCheckContext["config"]) => {
  if (!config) {
    throw new DoctorInternalError(
      "doctor config must be loaded before creating a signer",
    );
  }

  return new LocalKeySignerBackend({
    privateKeyEnv: config.wallet.privateKeyEnv,
    keystorePath: config.wallet.keystorePath,
  });
};

const resolveConfigPath = (configPath?: string): string =>
  path.resolve(expandHome(configPath ?? defaultConfigPath()));

function buildDoctorContext(invocation: DoctorInvocation): DoctorCheckContext {
  const runtimeContext = invocation.runtimeContext ?? null;
  const context: DoctorCheckContext = {
    mode: invocation.mode,
    configPath: resolveConfigPath(
      invocation.configPath ?? runtimeContext?.runtime.configPath,
    ),
    runtimeContext,
    config: runtimeContext?.config ?? null,
    configLoadError: null,
    stateStore: runtimeContext?.stateStore ?? null,
    sessionStore: runtimeContext?.sessionStore ?? null,
    signer: runtimeContext?.signer ?? null,
    fix: invocation.params?.fix ?? false,
    verbose: invocation.params?.verbose ?? false,
    refreshConfig: () => {
      if (runtimeContext) {
        context.config = runtimeContext.config;
        context.configLoadError = null;
        context.stateStore = runtimeContext.stateStore;
        context.sessionStore = runtimeContext.sessionStore;
        context.signer = runtimeContext.signer;
        return;
      }

      try {
        const config = loadConfig(context.configPath);
        const stateStore = new StateStore(
          path.join(config.runtime.stateDir, "runtime-state.json"),
        );
        context.config = config;
        context.configLoadError = null;
        context.stateStore = stateStore;
        context.sessionStore = new SessionStore(stateStore);
        context.signer = createSigner(config);
      } catch (error) {
        context.config = null;
        context.configLoadError =
          error instanceof Error ? error : new Error(String(error));
        context.stateStore = null;
        context.sessionStore = null;
        context.signer = null;
      }
    },
  };

  context.refreshConfig();
  return context;
}

const buildCheckResult = (
  check: DoctorCheckDefinition,
  outcome: Awaited<ReturnType<DoctorCheckDefinition["run"]>>,
  startedAtIso: string,
  startedMs: number,
): DoctorCheckResult => ({
  id: check.id,
  scope: check.scope,
  status: outcome.status,
  title: check.title,
  message: outcome.message,
  ...(outcome.details ? { details: outcome.details } : {}),
  ...(outcome.remediation ? { remediation: outcome.remediation } : {}),
  ...(outcome.fixApplied ? { fixApplied: outcome.fixApplied } : {}),
  startedAt: startedAtIso,
  finishedAt: new Date().toISOString(),
  durationMs: Date.now() - startedMs,
});

const buildCrashedCheckResult = (
  check: DoctorCheckDefinition,
  error: unknown,
  startedAtIso: string,
  startedMs: number,
): DoctorCheckResult => ({
  id: check.id,
  scope: check.scope,
  status: "fail",
  title: check.title,
  message: "Doctor check crashed before it could return a result",
  details: {
    internal: true,
    code: "doctor_check_crashed",
    error: errorMessage(error),
    ...(error instanceof Error && error.stack ? { stack: error.stack } : {}),
  },
  remediation: "Inspect the failing doctor check implementation and retry",
  startedAt: startedAtIso,
  finishedAt: new Date().toISOString(),
  durationMs: Date.now() - startedMs,
});

export async function runChecksSequentially(
  checks: DoctorCheckDefinition[],
  ctx: DoctorCheckContext,
): Promise<DoctorCheckResult[]> {
  const results: DoctorCheckResult[] = [];
  for (const check of checks) {
    const startedAtIso = new Date().toISOString();
    const startedMs = Date.now();
    try {
      results.push(
        buildCheckResult(
          check,
          await check.run(ctx),
          startedAtIso,
          startedMs,
        ),
      );
    } catch (error) {
      results.push(
        buildCrashedCheckResult(check, error, startedAtIso, startedMs),
      );
    }
  }
  return results;
}

export function summarizeChecks(
  results: DoctorCheckResult[],
): DoctorReport["summary"] {
  return results.reduce<DoctorReport["summary"]>(
    (summary, check) => {
      summary[check.status] += 1;
      return summary;
    },
    { ok: 0, warn: 0, fail: 0, skip: 0 },
  );
}

export function computeReportOk(
  results: DoctorCheckResult[],
): boolean {
  return results.every((check) => check.status !== "fail");
}

const defaultChecks = (): DoctorCheckDefinition[] =>
  DEFAULT_CHECK_FACTORIES.flatMap((factory) => factory());

function selectChecks(invocation: DoctorInvocation): DoctorCheckDefinition[] {
  const checks = defaultChecks();
  return invocation.mode === "scoped"
    ? checks.filter((check) => check.scope === invocation.params.scope)
    : checks;
}

export async function runDoctorInvocation(
  invocation: DoctorInvocation,
): Promise<DoctorReport> {
  try {
    const results = await runChecksSequentially(
      selectChecks(invocation),
      buildDoctorContext(invocation),
    );
    return {
      ok: computeReportOk(results),
      mode: invocation.mode,
      ...(invocation.mode === "scoped"
        ? { scope: invocation.params.scope }
        : {}),
      summary: summarizeChecks(results),
      checks: results,
      nextSteps: deriveNextSteps(results),
      generatedAt: new Date().toISOString(),
    };
  } catch (error) {
    if (error instanceof DoctorInternalError) {
      throw error;
    }
    throw new DoctorInternalError(
      "doctor execution failed before a report could be produced",
      error,
    );
  }
}

const runDoctorByMode = (
  mode: DoctorInvocation["mode"],
  params:
    | DoctorRunParams
    | DoctorRunScopedParams
    | DoctorRunFullParams
    | undefined,
  options?: { configPath?: string; runtimeContext?: RuntimeContext },
): Promise<DoctorReport> => {
  if (mode === "scoped") {
    return runDoctorInvocation({
      mode,
      params: params as DoctorRunScopedParams,
      configPath: options?.configPath,
      runtimeContext: options?.runtimeContext,
    });
  }
  if (mode === "full") {
    return runDoctorInvocation({
      mode,
      params: params as DoctorRunFullParams | undefined,
      configPath: options?.configPath,
      runtimeContext: options?.runtimeContext,
    });
  }
  return runDoctorInvocation({
    mode,
    params: params as DoctorRunParams | undefined,
    configPath: options?.configPath,
    runtimeContext: options?.runtimeContext,
  });
};

export async function runDoctor(
  params?: DoctorRunParams,
  options?: { configPath?: string; runtimeContext?: RuntimeContext },
): Promise<DoctorReport> {
  return runDoctorByMode("default", params, options);
}

export async function runScopedDoctor(
  params: DoctorRunScopedParams,
  options?: { configPath?: string; runtimeContext?: RuntimeContext },
): Promise<DoctorReport> {
  return runDoctorByMode("scoped", params, options);
}

export async function runFullDoctor(
  params?: DoctorRunFullParams,
  options?: { configPath?: string; runtimeContext?: RuntimeContext },
): Promise<DoctorReport> {
  return runDoctorByMode("full", params, options);
}
