import fs from "node:fs";
import path from "node:path";

import type {
  AppSiwaSession,
  LocalAgentIdentity,
  RegentAgentRuntimeState,
  SiwaSession,
} from "../../internal-types/index.js";

import { writeJsonFileAtomicSync } from "../paths.js";

export interface PersistentState {
  siwa?: SiwaSession;
  appSiwaSessions?: Record<string, AppSiwaSession>;
  agent?: LocalAgentIdentity;
  agentRuntime?: RegentAgentRuntimeState;
}

const emptyState = (): PersistentState => ({});

export class StateStore {
  readonly stateFilePath: string;

  constructor(stateFilePath: string) {
    this.stateFilePath = path.resolve(stateFilePath);
  }

  read(): PersistentState {
    if (!fs.existsSync(this.stateFilePath)) {
      return emptyState();
    }

    const raw = fs.readFileSync(this.stateFilePath, "utf8");
    if (raw.trim() === "") {
      return emptyState();
    }

    const parsed = JSON.parse(raw) as PersistentState;
    return parsed && typeof parsed === "object" ? parsed : emptyState();
  }

  write(next: PersistentState): void {
    writeJsonFileAtomicSync(this.stateFilePath, next);
  }

  patch(patch: Partial<PersistentState>): void {
    const current = this.read();
    const next: PersistentState = {
      ...current,
      ...patch,
      agent: patch.agent === undefined ? current.agent : { ...(current.agent ?? {}), ...patch.agent },
      agentRuntime:
        patch.agentRuntime === undefined
          ? current.agentRuntime
          : { ...(current.agentRuntime ?? {}), ...patch.agentRuntime },
    };

    this.write(next);
  }

  clear(): void {
    this.write(emptyState());
  }
}
