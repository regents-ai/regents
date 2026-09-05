import type {
  DoctorCheckResult,
  DoctorMode,
  DoctorReport,
  DoctorRunFullParams,
  DoctorRunParams,
  DoctorRunScopedParams,
  DoctorScope,
  DoctorStatus,
  RegentConfig,
} from "../../internal-types/index.js";
import type { SignerBackend } from "../agent/signer-backend.js";
import type { RuntimeContext } from "../runtime.js";
import type { SessionStore } from "../store/session-store.js";
import type { StateStore } from "../store/state-store.js";

export interface DoctorCheckOutcome {
  status: DoctorStatus;
  message: string;
  details?: Record<string, unknown>;
  remediation?: string;
  fixApplied?: boolean;
}

export interface DoctorCheckDefinition {
  id: string;
  scope: DoctorScope;
  title: string;
  run: (ctx: DoctorCheckContext) => Promise<DoctorCheckOutcome>;
}

export interface DoctorCheckContext {
  mode: DoctorMode;
  configPath: string;
  runtimeContext: RuntimeContext | null;
  config: RegentConfig | null;
  configLoadError: Error | null;
  stateStore: StateStore | null;
  sessionStore: SessionStore | null;
  signer: SignerBackend | null;
  fix: boolean;
  verbose: boolean;
  refreshConfig: () => void;
}

export type DoctorInvocation =
  | {
      mode: "default";
      configPath?: string;
      params?: DoctorRunParams;
      runtimeContext?: RuntimeContext;
    }
  | {
      mode: "scoped";
      configPath?: string;
      params: DoctorRunScopedParams;
      runtimeContext?: RuntimeContext;
    }
  | {
      mode: "full";
      configPath?: string;
      params?: DoctorRunFullParams;
      runtimeContext?: RuntimeContext;
    };

export type { DoctorCheckResult, DoctorMode, DoctorReport, DoctorScope, DoctorStatus };
