import { renderPanel } from "./panel.js";
import { CLI_PALETTE, isHumanTerminal, tone } from "./palette.js";
import { renderKeyValuePanel, type KeyValueRow } from "./presenters.js";

let rawJsonOutput = false;

export function setRawJsonOutput(value: boolean): void {
  rawJsonOutput = value;
}

const highlightJsonLine = (line: string): string => {
  let highlighted = line;
  highlighted = highlighted.replace(/^(\s*)"([^"]+)":/u, (_, indent: string, key: string) =>
    `${indent}${tone(`"${key}"`, CLI_PALETTE.emphasis, true)}${tone(":", CLI_PALETTE.secondary)}`,
  );
  highlighted = highlighted.replace(/: ("(?:[^"\\]|\\.)*")/gu, (_match, value: string) => `: ${tone(value, CLI_PALETTE.primary)}`);
  highlighted = highlighted.replace(/: (-?\d+(?:\.\d+)?)/gu, (_match, value: string) => `: ${tone(value, CLI_PALETTE.accent, true)}`);
  highlighted = highlighted.replace(/: (true|false)\b/gu, (_match, value: string) => `: ${tone(value, CLI_PALETTE.emphasis, true)}`);
  highlighted = highlighted.replace(/: (null)\b/gu, (_match, value: string) => `: ${tone(value, CLI_PALETTE.secondary)}`);
  return highlighted;
};

const jsonTitle = (value: unknown): string => {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    if (record.error) {
      return "◆ REGENT ERROR DECK";
    }
    if (record.usage) {
      return "◆ REGENT COMMAND DECK";
    }
    if (record.data) {
      return "◆ REGENT DATA DECK";
    }
  }

  return "◆ REGENT OUTPUT DECK";
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const addUniqueStep = (steps: string[], value: unknown): void => {
  if (typeof value !== "string") {
    return;
  }

  const step = value.trim();
  if (step.length > 0 && !steps.includes(step)) {
    steps.push(step);
  }
};

const addStringArraySteps = (steps: string[], value: unknown): void => {
  if (!Array.isArray(value)) {
    return;
  }

  for (const entry of value) {
    addUniqueStep(steps, entry);
  }
};

const nextStepsFromRecord = (value: unknown): string[] => {
  if (!isRecord(value)) {
    return [];
  }

  const steps: string[] = [];
  addStringArraySteps(steps, value.next_steps);
  addStringArraySteps(steps, value.next);

  if (isRecord(value.next_action)) {
    addUniqueStep(steps, value.next_action.command);
  }

  if (Array.isArray(value.nextCommands)) {
    for (const entry of value.nextCommands) {
      if (isRecord(entry)) {
        addUniqueStep(steps, entry.command);
      }
    }
  }

  if (isRecord(value.fold)) {
    addStringArraySteps(steps, value.fold.next);
  }

  return steps;
};

const summarizeRecord = (value: unknown): KeyValueRow[] => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return [];
  }

  const record = value as Record<string, unknown>;
  const rows: KeyValueRow[] = [];
  const addRow = (label: string, raw: unknown, options?: { labelColor?: string; valueColor?: string }): void => {
    if (raw === undefined || raw === null) {
      return;
    }

    rows.push({
      label,
      value: typeof raw === "string" ? raw : JSON.stringify(raw),
      ...(options?.labelColor ? { labelColor: options.labelColor } : {}),
      ...(options?.valueColor ? { valueColor: options.valueColor } : {}),
    });
  };

  if (typeof record.ok === "boolean") {
    addRow("ok", record.ok ? "yes" : "no", {
      valueColor: record.ok ? CLI_PALETTE.emphasis : CLI_PALETTE.error,
    });
  }
  addRow("status", typeof record.status === "string" ? record.status : undefined, {
    valueColor:
      record.status === "error" || record.status === "failed"
        ? CLI_PALETTE.error
        : record.status === "ready" || record.status === "ok"
          ? CLI_PALETTE.emphasis
          : CLI_PALETTE.primary,
  });
  addRow("mode", typeof record.mode === "string" ? record.mode : undefined);
  addRow("scope", typeof record.scope === "string" ? record.scope : undefined);
  addRow("state", typeof record.state === "string" ? record.state : undefined);
  addRow("network", typeof record.network === "string" ? record.network : undefined);
  addRow("provider", typeof record.provider === "string" ? record.provider : undefined);
  addRow("address", typeof record.address === "string" ? record.address : undefined);
  addRow("state dir", typeof record.stateDir === "string" ? record.stateDir : undefined);
  addRow("socket", typeof record.socketPath === "string" ? record.socketPath : undefined);
  addRow("socket dir", typeof record.socketDir === "string" ? record.socketDir : undefined);
  addRow("config", typeof record.configPath === "string" ? record.configPath : undefined);
  addRow("config created", typeof record.configCreated === "boolean" ? (record.configCreated ? "yes" : "no") : undefined);
  addRow("keystore dir", typeof record.keystoreDir === "string" ? record.keystoreDir : undefined);
  addRow("gossipsub dir", typeof record.gossipsubDir === "string" ? record.gossipsubDir : undefined);
  addRow("dev file", typeof record.devFile === "string" ? record.devFile : undefined);
  addRow("session", typeof record.session_id === "string" ? record.session_id : undefined);
  addRow("registry", typeof record.registry_address === "string" ? record.registry_address : undefined);
  addRow("token", typeof record.token_id === "string" ? record.token_id : undefined);
  addRow("chain", typeof record.chain_id === "number" ? String(record.chain_id) : undefined);
  addRow("tx", typeof record.tx_hash === "string" ? record.tx_hash : undefined);
  addRow("export", typeof record.export === "string" ? record.export : undefined);
  addRow("generated", typeof record.generated_at === "string" ? record.generated_at : undefined);
  addRow("created", typeof record.created_at === "string" ? record.created_at : undefined);

  if (record.summary && typeof record.summary === "object" && !Array.isArray(record.summary)) {
    const summary = record.summary as Record<string, unknown>;
    addRow("summary ok", typeof summary.ok === "number" ? String(summary.ok) : undefined);
    addRow("summary warn", typeof summary.warn === "number" ? String(summary.warn) : undefined);
    addRow("summary fail", typeof summary.fail === "number" ? String(summary.fail) : undefined);
    addRow("summary skip", typeof summary.skip === "number" ? String(summary.skip) : undefined);
  }

  if (Array.isArray(record.next_steps) && record.next_steps.length > 0) {
    addRow("next", String(record.next_steps[0]));
  }

  if (record.next_action && typeof record.next_action === "object" && !Array.isArray(record.next_action)) {
    const nextAction = record.next_action as Record<string, unknown>;
    if (typeof nextAction.command === "string") {
      addRow("next", nextAction.command);
    }
    if (typeof nextAction.reason === "string") {
      addRow("reason", nextAction.reason, { labelColor: CLI_PALETTE.secondary });
    }
  }

  if (record.session && typeof record.session === "object" && !Array.isArray(record.session)) {
    const session = record.session as Record<string, unknown>;
    addRow("session status", typeof session.status === "string" ? session.status : undefined);
    addRow("session id", typeof session.session_id === "string" ? session.session_id : undefined);
    addRow("session approval", typeof session.approval_url === "string" ? session.approval_url : undefined);
    addRow("session expires", typeof session.expires_at === "string" ? session.expires_at : undefined);
  }

  if (record.error && typeof record.error === "object" && !Array.isArray(record.error)) {
    const error = record.error as Record<string, unknown>;
    addRow("error code", typeof error.code === "string" ? error.code : undefined, {
      valueColor: CLI_PALETTE.error,
    });
    addRow("error message", typeof error.message === "string" ? error.message : undefined, {
      valueColor: CLI_PALETTE.error,
    });
  }

  return rows;
};

const humanJson = (value: unknown): string => {
  const raw = JSON.stringify(value, null, 2).split("\n");
  const lines = raw.map((line) => (line.length > 0 ? highlightJsonLine(line) : ""));
  const summaryRows = summarizeRecord(value);
  const summaryPanel = summaryRows.length > 0 ? renderKeyValuePanel("◆ REGENT SUMMARY", summaryRows) : undefined;
  const payloadPanel = renderPanel(jsonTitle(value), lines, {
    borderColor: CLI_PALETTE.chrome,
    titleColor: CLI_PALETTE.title,
  });
  const nextSteps = nextStepsFromRecord(value);
  const nextPanel = nextSteps.length > 0
    ? renderPanel("◆ NEXT", nextSteps, {
        borderColor: CLI_PALETTE.chrome,
        titleColor: CLI_PALETTE.title,
      })
    : undefined;

  return [summaryPanel, payloadPanel, nextPanel].filter(Boolean).join("\n\n");
};

export function printJson(value: unknown): void {
  if (isHumanTerminal() && !rawJsonOutput) {
    process.stdout.write(`${humanJson(value)}\n`);
    return;
  }

  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

export function printJsonLine(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}
