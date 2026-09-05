import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { runConfigGet, runConfigWrite } from "../../src/commands/config.js";
import { defaultConfig } from "../../src/internal-runtime/config.js";
import { parseCliArgs } from "../../src/parse.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

describe("config commands", () => {
  it("prints the normalized effective config", async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-cli-config-read-"));
    const configPath = path.join(tempDir, "config.json");

    fs.writeFileSync(
      configPath,
      JSON.stringify({
        services: {
          platform: {
            baseUrl: "http://127.0.0.1:4100",
          },
        },
      }),
      "utf8",
    );

    const { stdout } = await captureOutput(() => runConfigGet(parseCliArgs(["--config", configPath])));
    const printed = parsePrintedJson<ReturnType<typeof defaultConfig>>(stdout);

    expect(printed.runtime.socketPath).toBe(path.join(tempDir, "run", "regent.sock"));
    expect(printed.runtime.stateDir).toBe(path.join(tempDir, "state"));
    expect(printed.runtime.logLevel).toBe("info");
    expect(printed.auth).toEqual({
      audience: "techtree",
      defaultChainId: 8453,
    });
    expect(printed.services.platform).toEqual({
      baseUrl: "http://127.0.0.1:4100",
      requestTimeoutMs: 10_000,
    });
    expect(printed.agents.defaultHarness).toBe("hermes");
    expect(printed.agents.harnesses.hermes.workspaceRoot).toBe(path.join(tempDir, "workspaces", "hermes"));
    expect(printed.agents.harnesses.codex.workspaceRoot).toBe(path.join(tempDir, "workspaces", "codex"));
  });

  it("writes a full validated replacement config from @file input", async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-cli-config-write-"));
    const configPath = path.join(tempDir, "config.json");
    const inputPath = path.join(tempDir, "replacement.json");
    const replacement = defaultConfig(configPath);

    replacement.runtime.logLevel = "error";
    replacement.services.platform.baseUrl = "http://127.0.0.1:4300";
    replacement.services.platform.requestTimeoutMs = 3500;
    fs.writeFileSync(inputPath, JSON.stringify(replacement), "utf8");

    const { stdout } = await captureOutput(() =>
      runConfigWrite(parseCliArgs(["--config", configPath, "--input", `@${inputPath}`])),
    );
    const printed = parsePrintedJson<{
      ok: boolean;
      configPath: string;
      config: ReturnType<typeof defaultConfig>;
    }>(stdout);

    expect(printed.ok).toBe(true);
    expect(printed.configPath).toBe(configPath);
    expect(printed.config.runtime.logLevel).toBe("error");
    expect(printed.config.agents.defaultHarness).toBe("hermes");
    expect(printed.config.auth).toEqual({
      audience: "techtree",
      defaultChainId: 8453,
    });
    expect(printed.config.services.platform).toEqual({
      baseUrl: "http://127.0.0.1:4300",
      requestTimeoutMs: 3500,
    });
    expect(JSON.parse(fs.readFileSync(configPath, "utf8"))).toEqual(printed.config);
  });
});
