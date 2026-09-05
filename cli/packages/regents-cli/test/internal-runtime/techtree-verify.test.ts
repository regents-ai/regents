import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  handleTechtreeVerifyReceiptShow,
  handleTechtreeVerifyRun,
  handleTechtreeVerifyStatus,
} from "../../src/internal-runtime/handlers/techtree/verify.js";

describe("Techtree Verify runtime launcher", () => {
  const temporaryDirectories: string[] = [];

  afterEach(() => {
    for (const directory of temporaryDirectories.splice(0)) {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });

  it("runs, reads status, and verifies the offline fixture receipt set", async () => {
    const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-verify-handler-"));
    temporaryDirectories.push(stateDir);
    const started = performance.now();
    const result = await handleTechtreeVerifyRun(stateDir, {
      builtin: true,
      executor: "fixture",
    });
    expect(performance.now() - started).toBeLessThanOrEqual(120_000);
    expect(result).toMatchObject({
      schema_version: 1,
      status: "completed",
      summary: { comparison_result: "positive", task_count: 11, total_cost_usd_cents: 0 },
      policy: { attempts_per_task: 1, max_task_wall_seconds: 600, max_comparison_spend_usd_cents: 1000 },
    });
    expect(result.receipts).toHaveLength(11);
    await expect(handleTechtreeVerifyStatus(stateDir, {
      comparison_id: result.comparison_id,
    })).resolves.toEqual(result);
    for (const pointer of result.receipts) {
      await expect(handleTechtreeVerifyReceiptShow(stateDir, {
        digest: pointer.digest,
      })).resolves.toMatchObject({ digest: pointer.digest, verified: true });
    }
  });
});
