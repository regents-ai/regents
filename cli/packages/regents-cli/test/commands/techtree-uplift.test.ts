import { beforeEach, describe, expect, it, vi } from "vitest";

import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { daemonCallMock } = vi.hoisted(() => ({ daemonCallMock: vi.fn() }));

vi.mock("../../src/daemon-client.js", () => ({ daemonCall: daemonCallMock }));

describe("techtree uplift report command", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    daemonCallMock.mockResolvedValue({ schema_version: 1, status: "completed" });
  });

  it("passes a receipt set and a nullable tolerance to the daemon", async () => {
    const { runTechtreeUpliftReport } = await import("../../src/commands/techtree-uplift.js");
    const { parseCliArgs } = await import("../../src/parse.js");
    const first = "a".repeat(64);
    const second = "b".repeat(64);
    const third = "c".repeat(64);
    const output = await captureOutput(() => runTechtreeUpliftReport(parseCliArgs([
      "--receipt-digest", first,
      "--receipt-digest", second,
      "--receipt-digest", third,
      "--reproduction-tolerance-json", '{"score_millis":25}',
      "--json",
    ]), "/tmp/regent.config.json"));
    expect(daemonCallMock).toHaveBeenCalledWith("techtree.uplift.report", {
      receipt_digests: [first, second, third],
      tolerance: { score_millis: 25 },
    }, "/tmp/regent.config.json");
    expect(parsePrintedJson(output.stdout)).toEqual({ schema_version: 1, status: "completed" });
  });

  it("rejects missing, repeated-count, and malformed tolerance input", async () => {
    const { runTechtreeUpliftReport } = await import("../../src/commands/techtree-uplift.js");
    const { parseCliArgs } = await import("../../src/parse.js");
    const digest = "a".repeat(64);
    await expect(runTechtreeUpliftReport(parseCliArgs([]))).rejects.toThrow("supplied at least once");
    await expect(runTechtreeUpliftReport(parseCliArgs([
      "--receipt-digest", digest,
      "--receipt-digest", digest,
      "--reproduction-tolerance-json", "[]",
    ]))).rejects.toThrow("JSON object or null");
  });

  it("renders the human result with A2 wording and keeps internals in inspect", async () => {
    daemonCallMock.mockResolvedValue({
      schema_version: 1,
      status: "completed",
      report: {
        comparison: { receipt_digests: ["a".repeat(64), "b".repeat(64)], protocol_id: "protocol-1" },
        outcome: "positive",
        decision_sentence: "This skill improved held-out performance by 18 percentage points, ending at 72%, with no severe regressions.",
        final_capability_level: { candidate: 720 },
        measured_change: { absolute_delta_millis: 180 },
        scored_evaluation: {
          claim_eligible: true,
          task_scores: [{
            task_id: "contract-drift-validation-1",
            baseline_status: "completed",
            baseline_score_millis: 540,
            candidate_status: "completed",
            candidate_score_millis: 720,
            classification: "improved",
          }],
        },
        calibration: {
          task_scores: [{
            task_id: "contract-drift-untouched-1",
            baseline_status: "completed",
            baseline_score_millis: 800,
            candidate_status: "completed",
            candidate_score_millis: 800,
            classification: "unchanged",
          }],
        },
        regressions: { severe_count: 0 },
        cost_latency: {
          baseline: { cost_usd_cents: { mean: 3 }, wall_time_ms: { mean: 100 } },
          candidate: { cost_usd_cents: { mean: 4 }, wall_time_ms: { mean: 120 } },
        },
        disclosures: { execution: { adapter: { baseline: "fixture", candidate: "fixture" } }, search_optimizer: { method: "manual", candidate_count: 1 } },
        reproduction_package_status: "available",
      },
    });
    const { runTechtreeUpliftReport } = await import("../../src/commands/techtree-uplift.js");
    const { parseCliArgs } = await import("../../src/parse.js");
    const output = await captureOutput(() => runTechtreeUpliftReport(parseCliArgs([
      "--receipt-digest", "a".repeat(64),
      "--receipt-digest", "b".repeat(64),
    ])));
    expect(output.stdout).toContain("Did it help: Helped");
    expect(output.stdout.indexOf("Decision:")).toBeGreaterThan(output.stdout.indexOf("◆ TECHTREE UPLIFT"));
    expect(output.stdout.indexOf("Decision:")).toBeLessThan(output.stdout.indexOf("Did it help:"));
    expect(output.stdout).toContain("Single run. Reproduction package included.");
    expect(output.stdout).toContain("Final capability / measured change: 72% / +18 percentage points");
    expect(output.stdout).toContain("Evidence strength: receipt-backed valid matched run; held-out result; single-run.");
    expect(output.stdout).toContain("◆ INSPECT");
    expect(output.stdout).toContain("Adapters: baseline=fixture, candidate=fixture");
    expect(output.stdout).toContain("contract-drift-validation-1: baseline completed / 54%; treatment completed / 72%; classification improved");
    expect(output.stdout).toContain("contract-drift-untouched-1: baseline completed / 80%; treatment completed / 80%; classification unchanged");
    expect(output.stdout).toContain("Treatment: predeclared (single candidate)");
    expect(output.stdout).not.toContain("Optimizer:");
    expect(output.stdout.slice(0, output.stdout.indexOf("◆ INSPECT"))).not.toContain("a".repeat(64));
  });

  it.each([
    { name: "predeclared", method: "manual", candidateCount: 1, expected: "Treatment: predeclared (single candidate)", absent: "Treatment: searched" },
    { name: "searched", method: "manual", candidateCount: 3, expected: "Treatment: searched (3 candidates)", absent: "Treatment: predeclared" },
    { name: "label-edit-resistant", method: "not_used", candidateCount: 3, expected: "Treatment: searched (3 candidates)", absent: "Treatment: predeclared" },
  ])("renders the $name treatment disclosure from candidate count", async ({ method, candidateCount, expected, absent }) => {
    const { renderUpliftHuman } = await import("../../src/commands/techtree-uplift.js");
    const output = renderUpliftHuman({
      report: {
        outcome: "positive",
        scored_evaluation: { claim_eligible: true, task_scores: [] },
        regressions: {},
        cost_latency: { baseline: {}, candidate: {} },
        disclosures: { search_optimizer: { method, candidate_count: candidateCount } },
        reproduction_package_status: "absent",
      },
    });
    expect(output).toContain(expected);
    expect(output).not.toContain(absent);
    expect(output).not.toContain("Optimizer:");
  });

  it("maps every canonical JSON outcome to the A2 human label", async () => {
    const { renderUpliftHuman } = await import("../../src/commands/techtree-uplift.js");
    const labels = {
      positive: "Helped",
      null: "No measurable change",
      negative: "Hurt performance",
      inconclusive: "Could not tell",
      invalid: "Run invalid",
    } as const;
    for (const [outcome, label] of Object.entries(labels)) {
      expect(renderUpliftHuman({
        report: {
          outcome,
          decision_sentence: "This single-run comparison could not tell whether the skill produced a measured improvement on the held-out result.",
          final_capability_level: { candidate: null },
          measured_change: { absolute_delta_millis: null },
          scored_evaluation: { claim_eligible: false, task_scores: [] },
          regressions: { severe_count: 0 },
          cost_latency: { baseline: {}, candidate: {} },
          disclosures: {},
          reproduction_package_status: "absent",
        },
      })).toContain(`Did it help: ${label}`);
    }
  });

  it("uses singular percentage point at the one-point capability boundary", async () => {
    const { renderUpliftHuman } = await import("../../src/commands/techtree-uplift.js");
    const output = renderUpliftHuman({
      report: {
        outcome: "positive",
        decision_sentence: "This skill improved held-out performance by 1 percentage point, ending at 51%, with no severe regressions.",
        final_capability_level: { candidate: 510 },
        measured_change: { absolute_delta_millis: 10 },
        scored_evaluation: { claim_eligible: true, task_scores: [{ classification: "improved" }] },
        regressions: { severe_count: 0 },
        cost_latency: { baseline: {}, candidate: {} },
        disclosures: {},
        reproduction_package_status: "absent",
      },
    });
    expect(output).toContain("Final capability / measured change: 51% / +1 percentage point");
    expect(output).not.toContain("+1 percentage points");
  });
});
