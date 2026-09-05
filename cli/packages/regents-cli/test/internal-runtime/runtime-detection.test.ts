import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { detectRuntimes, installableRuntimes } from "../../src/internal-runtime/plugin-bridge.js";
import { codexConfigPath, registerClaudeMcp, registerCodexMcp } from "../../src/internal-runtime/mcp-register.js";

describe("agent runtime detection and MCP registration", () => {
  let originalHome: string | undefined;
  let originalPath: string | undefined;
  let tempHome = "";
  let tempBin = "";

  beforeEach(() => {
    originalHome = process.env.HOME;
    originalPath = process.env.PATH;
    tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "regents-detect-home-"));
    tempBin = fs.mkdtempSync(path.join(os.tmpdir(), "regents-detect-bin-"));
    process.env.HOME = tempHome;
    // Isolate PATH so detection only sees our shims.
    process.env.PATH = tempBin;
  });

  afterEach(() => {
    process.env.HOME = originalHome ?? "";
    process.env.PATH = originalPath ?? "";
  });

  const writeShim = (name: string, script: string): void => {
    const shimPath = path.join(tempBin, name);
    fs.writeFileSync(shimPath, `#!/bin/sh\n${script}\n`);
    fs.chmodSync(shimPath, 0o755);
  };

  it("detects nothing on a bare machine", () => {
    const detections = detectRuntimes();
    expect(detections).toHaveLength(4);
    expect(detections.every((entry) => !entry.detected)).toBe(true);
  });

  it("detects runtimes by home directory", () => {
    fs.mkdirSync(path.join(tempHome, ".hermes"));
    fs.mkdirSync(path.join(tempHome, ".codex"));

    const byRuntime = new Map(detectRuntimes().map((entry) => [entry.runtime, entry]));
    expect(byRuntime.get("hermes")?.detected).toBe(true);
    expect(byRuntime.get("hermes")?.integration).toBe("plugin");
    expect(byRuntime.get("codex")?.detected).toBe(true);
    expect(byRuntime.get("codex")?.integration).toBe("mcp");
    expect(byRuntime.get("openclaw")?.detected).toBe(false);
    expect(byRuntime.get("claude")?.detected).toBe(false);
  });

  it("detects runtimes by binary on PATH", () => {
    writeShim("claude", "exit 0");

    const claude = detectRuntimes().find((entry) => entry.runtime === "claude");
    expect(claude?.detected).toBe(true);
    expect(claude?.evidence).toBe(path.join(tempBin, "claude"));
  });

  it("auto install targets only detected plugin runtimes; explicit always wins", () => {
    fs.mkdirSync(path.join(tempHome, ".openclaw"));

    expect(installableRuntimes("auto")).toEqual(["openclaw"]);
    expect(installableRuntimes("hermes")).toEqual(["hermes"]);
  });

  it("registers the regents MCP server in the Codex config idempotently", () => {
    fs.mkdirSync(path.join(tempHome, ".codex"));
    fs.writeFileSync(codexConfigPath(), "model = \"gpt-5\"\n");

    const first = registerCodexMcp();
    expect(first.status).toBe("registered");

    const config = fs.readFileSync(codexConfigPath(), "utf8");
    expect(config).toContain("model = \"gpt-5\"");
    expect(config).toContain("[mcp_servers.regents]");
    expect(config).toContain("args = [\"mcp\", \"serve\", \"--transport\", \"stdio\"]");

    const second = registerCodexMcp();
    expect(second.status).toBe("already_registered");
    // No duplicate block appended.
    const updatedConfig = fs.readFileSync(codexConfigPath(), "utf8");
    expect(updatedConfig.split("[mcp_servers.regents]")).toHaveLength(2);
  });

  it("registers with Claude Code via the claude CLI and respects existing registration", () => {
    const logPath = path.join(tempBin, "claude-calls.log");

    // First call: `mcp get` fails (not registered), `mcp add` succeeds.
    writeShim(
      "claude",
      `echo "$@" >> "${logPath}"\ncase "$1 $2" in "mcp get") exit 1 ;; *) exit 0 ;; esac`,
    );

    const first = registerClaudeMcp();
    expect(first.status).toBe("registered");

    const calls = fs.readFileSync(logPath, "utf8").trim().split("\n");
    expect(calls[0]).toBe("mcp get regents");
    expect(calls[1]).toBe("mcp add --scope user regents -- regents mcp serve --transport stdio");

    // Second run: `mcp get` now succeeds — nothing is re-added.
    writeShim("claude", `echo "$@" >> "${logPath}"\nexit 0`);
    const second = registerClaudeMcp();
    expect(second.status).toBe("already_registered");
  });
});
