import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { runCliEntrypoint } from "../src/index.js";
import { writeInitialConfig } from "../src/internal-runtime/config.js";
import { captureOutput } from "../../../test-support/test-helpers.js";

describe("agent-context", () => {
  it("prints the generated command surface and safe local profile summary as JSON", async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-agent-context-"));
    const configPath = path.join(tempDir, "config.json");
    writeInitialConfig(configPath, {
      wallet: {
        privateKeyEnv: "REGENT_AGENT_CONTEXT_PRIVATE_KEY",
      },
      agents: {
        defaultHarness: "hermes",
      },
    });
    process.env.REGENT_AGENT_CONTEXT_PRIVATE_KEY = "do-not-print-this-value";

    try {
      const output = await captureOutput(() =>
        runCliEntrypoint(["agent-context", "--config", configPath]),
      );

      expect(output.result).toBe(0);
      expect(output.stderr).toBe("");

      const payload = JSON.parse(output.stdout) as {
        schema_version: string;
        package: { name: string; version: string };
        command_count: number;
        command_groups: Record<string, readonly string[]>;
        commands: Record<string, { command: string; examples?: readonly string[]; agent_metadata?: unknown }>;
        profile: {
          config_path: string;
          config_present: boolean;
          wallet: { private_key_env: string; keystore_configured: boolean };
          agents: { default_harness: string; harnesses: Record<string, { profiles: readonly string[] }> };
          available_profiles: readonly string[];
        };
        conventions: { json_flag: string; no_input_flag: string; aliases: string };
      };

      expect(payload.schema_version).toBe("1");
      expect(payload.package).toEqual({
        name: "@regentslabs/cli",
        version: expect.any(String),
      });
      expect(payload.command_groups["agent-context"]).toContain("agent-context");
      expect(payload.commands["agent-context"].command).toBe("agent-context");
      expect(payload.commands.status.agent_metadata).toBeDefined();
      expect(payload.commands.status.examples).toContain("regents agent-context");
      expect(payload.profile.config_path).toBe(configPath);
      expect(payload.profile.config_present).toBe(true);
      expect(payload.profile.wallet.private_key_env).toBe("REGENT_AGENT_CONTEXT_PRIVATE_KEY");
      expect(payload.profile.wallet.keystore_configured).toBe(true);
      expect(payload.profile.agents.default_harness).toBe("hermes");
      expect(payload.profile.agents.harnesses.hermes.profiles).toContain("owner");
      expect(payload.profile.available_profiles).toContain("owner");
      expect(payload.conventions).toMatchObject({
        json_flag: "--json",
        no_input_flag: "--no-input",
        aliases: "none",
      });
      expect(output.stdout).not.toContain("do-not-print-this-value");
    } finally {
      delete process.env.REGENT_AGENT_CONTEXT_PRIVATE_KEY;
    }
  });

  it("reports a missing config without creating one", async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-agent-context-missing-"));
    const configPath = path.join(tempDir, "missing.json");

    const output = await captureOutput(() =>
      runCliEntrypoint(["agent-context", "--config", configPath]),
    );
    const payload = JSON.parse(output.stdout) as {
      profile: { config_path: string; config_present: boolean };
    };

    expect(output.result).toBe(0);
    expect(payload.profile).toMatchObject({
      config_path: configPath,
      config_present: false,
    });
    expect(fs.existsSync(configPath)).toBe(false);
  });
});
