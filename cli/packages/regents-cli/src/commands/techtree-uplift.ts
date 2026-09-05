import { CliUsageError } from "../cli-usage-error.js";
import { daemonCall } from "../daemon-client.js";
import { getBooleanFlag, getFlag, getFlags, type ParsedCliArgs } from "../parse.js";
import { printJson, printText, renderPanel } from "../printer.js";

type JsonRecord = Record<string, unknown>;

const isRecord = (value: unknown): value is JsonRecord => Boolean(value) && typeof value === "object" && !Array.isArray(value);

const recordAt = (value: unknown, key: string): JsonRecord => {
  const record = isRecord(value) ? value[key] : undefined;
  return isRecord(record) ? record : {};
};

const stringAt = (value: unknown, key: string): string | undefined => {
  const result = isRecord(value) ? value[key] : undefined;
  return typeof result === "string" ? result : undefined;
};

const numberAt = (value: unknown, key: string): number | undefined => {
  const result = isRecord(value) ? value[key] : undefined;
  return typeof result === "number" && Number.isFinite(result) ? result : undefined;
};

const arrayAt = (value: unknown, key: string): readonly unknown[] => {
  const result = isRecord(value) ? value[key] : undefined;
  return Array.isArray(result) ? result : [];
};

const OUTCOME_LABELS: Readonly<Record<string, string>> = {
  positive: "Helped",
  null: "No measurable change",
  negative: "Hurt performance",
  inconclusive: "Could not tell",
  invalid: "Run invalid",
};

const percent = (value: unknown): string => {
  if (typeof value !== "number" || !Number.isFinite(value)) return "unavailable";
  const scaled = value / 10;
  return `${Number.isInteger(scaled) ? scaled : scaled.toFixed(1)}%`;
};

const percentagePoints = (value: unknown, signed = false): string => {
  if (typeof value !== "number" || !Number.isFinite(value)) return "unavailable";
  const scaled = Math.abs(value) / 10;
  const unit = scaled === 1 ? "percentage point" : "percentage points";
  const magnitude = `${Number.isInteger(scaled) ? scaled : scaled.toFixed(1)} ${unit}`;
  if (!signed) return magnitude;
  return value > 0 ? `+${magnitude}` : value < 0 ? `-${magnitude}` : magnitude;
};

const taskSummary = (section: JsonRecord): string => {
  const counts = new Map<string, number>();
  for (const entry of arrayAt(section, "task_scores")) {
    const classification = stringAt(entry, "classification") ?? "unavailable";
    counts.set(classification, (counts.get(classification) ?? 0) + 1);
  }
  if (counts.size === 0) return "no valid task scores";
  return ["improved", "regressed", "unchanged", "invalid"]
    .filter((classification) => counts.has(classification))
    .map((classification) => `${classification} ${counts.get(classification)}`)
    .join(", ");
};

const meanMetric = (value: unknown, key: string): string => {
  const distribution = recordAt(value, key);
  const mean = numberAt(distribution, "mean");
  return mean === undefined ? "unavailable" : String(mean);
};

const evidenceLine = (scored: JsonRecord, outcome: string | undefined): string => {
  if (outcome === "invalid") return "receipt-backed single-run; held-out result unavailable.";
  if (scored.claim_eligible === true) return "receipt-backed valid matched run; held-out result; single-run.";
  return "receipt-backed single-run; held-out result insufficient for a claim.";
};

const taskMatrixLine = (value: unknown): string => {
  const task = isRecord(value) ? value : {};
  const taskId = stringAt(task, "task_id") ?? "unavailable";
  const baseline = `${stringAt(task, "baseline_status") ?? "unavailable"} / ${percent(task.baseline_score_millis)}`;
  const treatment = `${stringAt(task, "candidate_status") ?? "unavailable"} / ${percent(task.candidate_score_millis)}`;
  return `${taskId}: baseline ${baseline}; treatment ${treatment}; classification ${stringAt(task, "classification") ?? "unavailable"}`;
};

export const renderUpliftHuman = (value: unknown): string => {
  const result = isRecord(value) ? value : {};
  const report = recordAt(result, "report");
  const comparison = recordAt(report, "comparison");
  const scored = recordAt(report, "scored_evaluation");
  const calibration = recordAt(report, "calibration");
  const outcome = stringAt(report, "outcome");
  const outcomeLabel = outcome === undefined ? "Run invalid" : OUTCOME_LABELS[outcome] ?? "Run invalid";
  const finalCapability = recordAt(report, "final_capability_level");
  const measuredChange = recordAt(report, "measured_change");
  const regressions = recordAt(report, "regressions");
  const costLatency = recordAt(report, "cost_latency");
  const disclosures = recordAt(report, "disclosures");
  const execution = recordAt(disclosures, "execution");
  const optimizer = recordAt(disclosures, "search_optimizer");
  const packageStatus = stringAt(report, "reproduction_package_status");
  const inspectLines = [
    `Receipt digests: ${arrayAt(comparison, "receipt_digests").filter((digest): digest is string => typeof digest === "string").join(", ") || "unavailable"}`,
    `Protocol: ${stringAt(comparison, "protocol_id") ?? "unavailable"}`,
    `Adapters: baseline=${stringAt(recordAt(execution, "adapter"), "baseline") ?? "unavailable"}, candidate=${stringAt(recordAt(execution, "adapter"), "candidate") ?? "unavailable"}`,
  ];
  const taskScores = [...arrayAt(scored, "task_scores"), ...arrayAt(calibration, "task_scores")];
  if (taskScores.length > 0) {
    inspectLines.push("Task results (status / score):", ...taskScores.map(taskMatrixLine));
  }
  const optimizerMethod = stringAt(optimizer, "method");
  const candidateCount = numberAt(optimizer, "candidate_count");
  if (candidateCount === 1) {
    inspectLines.push("Treatment: predeclared (single candidate)");
  } else if (candidateCount !== undefined && candidateCount > 1) {
    inspectLines.push(`Treatment: searched (${candidateCount} candidates)`);
  }
  if (optimizerMethod !== undefined && !["manual", "none", "not_used"].includes(optimizerMethod)) {
    inspectLines.push(`Optimizer: ${optimizerMethod} (${candidateCount ?? "unknown"} candidates)`);
  }
  return [
    renderPanel("◆ TECHTREE UPLIFT", [
      `Decision: ${stringAt(report, "decision_sentence") ?? "No decision sentence was available."}`,
      `Did it help: ${outcomeLabel}`,
      `Final capability / measured change: ${percent(finalCapability.candidate)} / ${percentagePoints(measuredChange.absolute_delta_millis, true)}`,
      `What got better/worse: measured improvement ${outcome === "positive" ? "recorded" : "not established"}; ${taskSummary(scored)}; severe regressions ${numberAt(regressions, "severe_count") ?? "unavailable"}.`,
      `Cost: baseline ${meanMetric(costLatency.baseline, "cost_usd_cents")} cents / ${meanMetric(costLatency.baseline, "wall_time_ms")} ms; candidate ${meanMetric(costLatency.candidate, "cost_usd_cents")} cents / ${meanMetric(costLatency.candidate, "wall_time_ms")} ms.`,
      `Evidence strength: ${evidenceLine(scored, outcome)}`,
      packageStatus === "available" ? "Single run. Reproduction package included." : "Single run. Reproduction package absent.",
    ]),
    renderPanel("◆ INSPECT", inspectLines),
  ].join("\n\n");
};

const parseTolerance = (value: string | undefined): Record<string, unknown> | null => {
  if (value === undefined) {
    return null;
  }
  try {
    const parsed: unknown = JSON.parse(value);
    if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
    if (parsed === null) {
      return null;
    }
  } catch {
    // Keep malformed JSON on the stable CLI usage-error path.
  }
  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--reproduction-tolerance-json must be a JSON object or null.",
  });
};

export async function runTechtreeUpliftReport(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const receiptDigests = getFlags(args, "receipt-digest");
  if (receiptDigests.length === 0) {
    throw new CliUsageError({
      code: receiptDigests.length === 0 ? "missing_required_argument" : "invalid_flag_value",
      message: "--receipt-digest must be supplied at least once.",
      missing: receiptDigests.length === 0 ? ["--receipt-digest"] : [],
    });
  }
  const result = await daemonCall("techtree.uplift.report", {
    receipt_digests: receiptDigests,
    tolerance: parseTolerance(getFlag(args, "reproduction-tolerance-json")),
  }, configPath);
  if (getBooleanFlag(args, "json")) printJson(result);
  else printText(renderUpliftHuman(result));
}
