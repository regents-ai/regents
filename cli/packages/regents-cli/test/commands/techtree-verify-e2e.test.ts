import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { RegentRuntime } from "../../src/internal-runtime/runtime.js";
import type { TechtreeVerifyRunResult } from "../../src/internal-types/index.js";
import { captureOutput } from "../../../../test-support/test-helpers.js";

describe("techtree verify offline CLI e2e", () => {
  let runtime: RegentRuntime | undefined;
  let tempDir = "";
  const originalPath = process.env.PATH;

  afterEach(async () => {
    if (originalPath === undefined) delete process.env.PATH;
    else process.env.PATH = originalPath;
    await runtime?.stop();
    if (tempDir) fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("locks, resolves, emits a receipt set, and archives its uplift within two minutes", async () => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-verify-cli-e2e-"));
    const configPath = path.join(tempDir, "regent.config.json");
    writeInitialConfig(configPath, {
      runtime: {
        socketPath: path.join(tempDir, "runtime", "regent.sock"),
        stateDir: path.join(tempDir, "state"),
        logLevel: "error",
      },
    });
    runtime = new RegentRuntime(configPath);
    await runtime.start();

    const started = performance.now();
    const runOutput = await captureOutput(() => runCliEntrypoint([
      "techtree", "verify", "run", "--builtin", "--fixture", "--json", "--config", configPath,
    ]));
    expect(runOutput.result).toBe(0);
    const run = JSON.parse(runOutput.stdout) as TechtreeVerifyRunResult;
    expect(run).toMatchObject({ status: "completed", summary: { comparison_result: "positive" } });
    expect(run.summary.task_count).toBeGreaterThan(10);
    expect(run.receipts).toHaveLength(run.summary.task_count);

    const statusOutput = await captureOutput(() => runCliEntrypoint([
      "techtree", "verify", "status", "--comparison-id", run.comparison_id, "--json", "--config", configPath,
    ]));
    expect(JSON.parse(statusOutput.stdout)).toEqual(run);

    const receiptRecords: Array<{
      digest: string;
      receipt: {
        task_id: string;
        protocol: { matched_selections: Array<{ task_id: string; matched_order: number }> };
        runs: { baseline: { provenance: string }; candidate: { provenance: string } };
      };
    }> = [];
    for (const pointer of run.receipts) {
      const receiptOutput = await captureOutput(() => runCliEntrypoint([
        "techtree", "verify", "receipt", "show", "--digest", pointer.digest, "--json", "--config", configPath,
      ]));
      const shown = JSON.parse(receiptOutput.stdout) as typeof receiptRecords[number];
      receiptRecords.push(shown);
      expect(shown).toMatchObject({
        digest: pointer.digest,
        verified: true,
        receipt: { capsules: { baseline: {}, candidate: {} }, runs: { baseline: {}, candidate: {} } },
      });
    }
    const publicReference = receiptRecords.filter(({ receipt }) => receipt.runs.baseline.provenance === "public_reference");
    const heldOut = receiptRecords.filter(({ receipt }) => receipt.runs.baseline.provenance === "held_out");
    expect(publicReference).toHaveLength(10);
    expect(heldOut.length).toBeGreaterThanOrEqual(1);
    const lockedTaskIds = [...receiptRecords[0]!.receipt.protocol.matched_selections]
      .sort((left, right) => left.matched_order - right.matched_order)
      .map(({ task_id }) => task_id);
    const receiptTaskIds = receiptRecords.map(({ receipt }) => receipt.task_id);
    expect(new Set(receiptTaskIds).size).toBe(run.receipts.length);
    expect(receiptTaskIds.sort()).toEqual([...lockedTaskIds].sort());
    expect(receiptRecords.map(({ receipt }) => receipt.protocol.matched_selections.length)).toEqual(new Array(run.receipts.length).fill(run.summary.task_count));

    const upliftArgs = ["techtree", "uplift", "report"];
    for (const pointer of run.receipts) upliftArgs.push("--receipt-digest", pointer.digest);
    upliftArgs.push("--json", "--config", configPath);
    const upliftOutput = await captureOutput(() => runCliEntrypoint(upliftArgs));
    const uplift = JSON.parse(upliftOutput.stdout) as {
      status: string;
      report: {
        comparison: { receipt_digests: string[] };
        receipt_bindings: Array<{ task_id: string }>;
        calibration: { task_count: number; task_scores: Array<{ task_id: string }> } | null;
        scored_evaluation: { task_count: number; task_scores: Array<{ task_id: string }> };
        reproduction_status: string;
      };
      reproduction_package: { digest: string; path: string };
    };
    expect(uplift).toMatchObject({
      status: "completed",
      report: {
        outcome: "positive",
        evidence_class: "single_run",
        reproduction_status: "none",
        reproduction_package_status: "available",
        decision_sentence: "This skill improved held-out performance by 100 percentage points, ending at 100%, with no severe regressions.",
      },
      reproduction_package: { digest: expect.any(String) },
    });
    const reportReceiptDigests = uplift.report.comparison.receipt_digests;
    expect(reportReceiptDigests).toEqual([...reportReceiptDigests].sort());
    expect(reportReceiptDigests).toEqual(run.receipts.map(({ digest }) => digest).sort());
    expect(uplift.report.receipt_bindings.map(({ task_id }) => task_id)).toEqual(lockedTaskIds);
    expect(uplift.report.calibration?.task_count).toBe(10);
    expect(uplift.report.scored_evaluation.task_count).toBe(heldOut.length);
    expect(uplift.report.calibration?.task_scores).toHaveLength(publicReference.length);
    expect(uplift.report.scored_evaluation.task_scores).toHaveLength(heldOut.length);
    expect(uplift.report.calibration?.task_scores.map(({ task_id }) => task_id).sort()).toEqual(publicReference.map(({ receipt }) => receipt.task_id).sort());
    expect(uplift.report.scored_evaluation.task_scores.map(({ task_id }) => task_id).sort()).toEqual(heldOut.map(({ receipt }) => receipt.task_id).sort());
    const archivedPackage = JSON.parse(fs.readFileSync(uplift.reproduction_package.path, "utf8")) as {
      receipt_digests: string[];
      exact_commands: string[];
    };
    expect(archivedPackage.receipt_digests).toEqual(reportReceiptDigests);
    const archivedUpliftCommand = archivedPackage.exact_commands.find((command) => command.includes("techtree uplift report"));
    expect(archivedUpliftCommand?.match(/--receipt-digest/g)).toHaveLength(run.receipts.length);
    expect(performance.now() - started).toBeLessThanOrEqual(120_000);
  });

  it("prints actionable JSON envelopes for every Verify command failure boundary", async () => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-verify-cli-errors-"));
    const configPath = path.join(tempDir, "regent.config.json");
    writeInitialConfig(configPath, {
      runtime: {
        socketPath: path.join(tempDir, "runtime", "regent.sock"),
        stateDir: path.join(tempDir, "state"),
        logLevel: "error",
      },
    });
    runtime = new RegentRuntime(configPath);
    await runtime.start();

    const missingConfig = await captureOutput(() => runCliEntrypoint([
      "techtree", "verify", "run", "--builtin", "--json", "--config", configPath,
    ]));
    expect(JSON.parse(missingConfig.stderr)).toMatchObject({
      error: {
        code: "missing_verify_executor_configuration",
        next_steps: [expect.stringContaining("--fixture"), expect.stringContaining("--prime")],
      },
    });

    const missingReceipt = await captureOutput(() => runCliEntrypoint([
      "techtree", "verify", "receipt", "show", "--digest", "a".repeat(64), "--json", "--config", configPath,
    ]));
    expect(JSON.parse(missingReceipt.stderr)).toMatchObject({
      error: { code: "verify_record_not_found", next_steps: [expect.stringContaining("verify run")] },
    });

    const missingUpliftReceipts = await captureOutput(() => runCliEntrypoint([
      "techtree", "uplift", "report",
      "--receipt-digest", "a".repeat(64),
      "--receipt-digest", "b".repeat(64),
      "--json", "--config", configPath,
    ]));
    expect(JSON.parse(missingUpliftReceipts.stderr)).toMatchObject({
      error: { code: "uplift_receipt_not_found", next_steps: [expect.stringContaining("verify run")] },
    });

    const malformedBin = path.join(tempDir, "malformed-bin");
    fs.mkdirSync(malformedBin);
    const malformedPython = path.join(malformedBin, "python3");
    fs.writeFileSync(malformedPython, "#!/bin/sh\nif [ \"$1\" = \"-c\" ]; then echo 3.12; else echo malformed; fi\n");
    fs.chmodSync(malformedPython, 0o755);
    process.env.PATH = malformedBin;
    const malformedResult = await captureOutput(() => runCliEntrypoint([
      "techtree", "verify", "status", "--comparison-id", "comparison-missing", "--json", "--config", configPath,
    ]));
    expect(JSON.parse(malformedResult.stderr)).toMatchObject({
      error: { code: "verify_runtime_invalid_json", next_steps: [expect.stringContaining("verify run")] },
    });

    const unavailableBin = path.join(tempDir, "unavailable-bin");
    fs.mkdirSync(unavailableBin);
    process.env.PATH = unavailableBin;
    const unavailableRuntime = await captureOutput(() => runCliEntrypoint([
      "techtree", "verify", "status", "--comparison-id", "comparison-missing", "--json", "--config", configPath,
    ]));
    expect(JSON.parse(unavailableRuntime.stderr)).toMatchObject({
      error: { code: "verify_runtime_unavailable", next_steps: [expect.stringContaining("verify run")] },
    });
  });
});
