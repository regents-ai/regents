import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { runPluginInstall } from "../../src/commands/plugin.js";
import { runSetup } from "../../src/commands/setup.js";
import { parseCliArgs } from "../../src/parse.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

describe("plugin setup commands", () => {
  let originalHome: string | undefined;
  let tempHome = "";

  beforeEach(() => {
    originalHome = process.env.HOME;
    tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "regents-plugin-command-"));
    process.env.HOME = tempHome;
  });

  afterEach(() => {
    fs.rmSync(tempHome, { recursive: true, force: true });

    if (originalHome === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
  });

  it("defaults to the auto runtime when --runtime is omitted", async () => {
    const output = await captureOutput(() => runPluginInstall(parseCliArgs([])));
    const payload = parsePrintedJson(output.stdout) as {
      selectedRuntime: string;
      installed_plugins: Array<{ runtime: string }>;
      next_steps: string[];
    };

    expect(payload.selectedRuntime).toBe("auto");
    expect(payload.installed_plugins.map((entry) => entry.runtime)).toEqual(["hermes", "openclaw"]);
    expect(payload.next_steps).toContain("regents plugin doctor");
  });

  it("defaults setup to the auto runtime when --runtime is omitted", async () => {
    const output = await captureOutput(() => runSetup(parseCliArgs([])));
    const payload = parsePrintedJson(output.stdout) as {
      runtime: string;
      plugin_status: { runtimes: Array<{ runtime: string }> };
    };

    expect(payload.runtime).toBe("auto");
    expect(payload.plugin_status.runtimes.map((entry) => entry.runtime)).toEqual(["hermes", "openclaw"]);
  });

  it("installs both runtime plugins when auto is selected", async () => {
    const output = await captureOutput(() => runPluginInstall(parseCliArgs(["--runtime", "auto"])));
    const payload = parsePrintedJson(output.stdout) as {
      selectedRuntime: string;
      installed_plugins: Array<{ runtime: string; hermesXaiOAuth?: { providerId: string; defaultModel: string } }>;
      next_steps: string[];
    };

    expect(payload.selectedRuntime).toBe("auto");
    expect(payload.installed_plugins.map((entry) => entry.runtime)).toEqual(["hermes", "openclaw"]);
    expect(payload.installed_plugins[0]?.hermesXaiOAuth?.providerId).toBe("xai-oauth");
    expect(payload.installed_plugins[0]?.hermesXaiOAuth?.defaultModel).toBe("grok-4.3");
    expect(payload.next_steps[0]).toBe("hermes auth add xai-oauth");
    expect(fs.existsSync(path.join(tempHome, ".hermes", "plugins", "regent", "plugin.yaml"))).toBe(true);
    expect(fs.readFileSync(path.join(tempHome, ".hermes", "config.yaml"), "utf8")).toContain("provider: xai-oauth");
    expect(fs.existsSync(path.join(tempHome, ".openclaw", "plugins", "regent", "openclaw.plugin.json"))).toBe(true);
  });

  it("keeps setup as a readiness report instead of an installer", async () => {
    const output = await captureOutput(() => runSetup(parseCliArgs(["--runtime", "hermes"])));
    const payload = parsePrintedJson(output.stdout) as {
      installed_plugins?: unknown;
      next: string[];
    };

    expect(payload.installed_plugins).toBeUndefined();
    expect(payload.next[0]).toBe("regents plugin install");
    expect(fs.existsSync(path.join(tempHome, ".hermes", "plugins", "regent"))).toBe(false);
  });

  it("keeps setup --runtime in report mode even when prompts are available", async () => {
    const output = await captureOutput(() =>
      runSetup({
        ...parseCliArgs(["--runtime", "hermes"]),
        stdin: { isTTY: true } as NodeJS.ReadStream,
      }),
    );
    const payload = parsePrintedJson(output.stdout) as {
      runtime: string;
      plugin_status: { runtimes: Array<{ runtime: string }> };
    };

    expect(payload.runtime).toBe("hermes");
    expect(payload.plugin_status.runtimes.map((entry) => entry.runtime)).toEqual(["hermes"]);
    expect(fs.existsSync(path.join(tempHome, ".hermes", "plugins", "regent"))).toBe(false);
  });
});
