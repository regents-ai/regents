import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { installPlugin } from "../../src/internal-runtime/plugin-bridge.js";

describe("Regent plugin bridge installer", () => {
  let originalHome: string | undefined;
  let tempHome = "";

  beforeEach(() => {
    originalHome = process.env.HOME;
    tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "regents-plugin-bridge-"));
    process.env.HOME = tempHome;
  });

  afterEach(() => {
    if (originalHome === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
  });

  it("installs the typed local-runtime bridge", () => {
    const report = installPlugin("hermes");

    const toolsPath = path.join(tempHome, ".hermes", "plugins", "regent", "tools.py");
    const tools = fs.readFileSync(toolsPath, "utf8");
    expect(tools).toContain("regent_runtime_start");
    expect(tools).toContain("regent_workspace_pair");
    expect(tools).toContain("regent_x402_pay_guarded");
    expect(tools).not.toContain("regent_techtree_fold");

    const skillNames = fs.readdirSync(path.join(tempHome, ".hermes", "plugins", "regent", "skills")).sort();
    expect(skillNames).toEqual([
      "regent-notebooks",
      "regent-receipts",
      "regent-runtime",
      "regent-wallet-budget",
      "regent-x402",
    ]);

    const config = fs.readFileSync(path.join(tempHome, ".hermes", "config.yaml"), "utf8");
    expect(config).toContain("default: grok-4.3");
    expect(config).toContain("provider: xai-oauth");
    expect(config).toContain("base_url: https://api.x.ai/v1");
    expect(report.hermesXaiOAuth?.loginCommand).toBe("hermes auth add xai-oauth");
    expect(report.files).toContain(path.join(tempHome, ".hermes", "plugins", "regent", "xai-grok-oauth.md"));
  });
});
