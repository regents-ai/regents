import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runUpdate } from "../../src/commands/update.js";
import { runVersion } from "../../src/commands/version.js";
import { parseCliArgs } from "../../src/parse.js";

const captureStdout = () => {
  const lines: string[] = [];
  const spy = vi.spyOn(process.stdout, "write").mockImplementation((chunk) => {
    lines.push(String(chunk));
    return true;
  });
  return { lines, restore: () => spy.mockRestore() };
};

describe("version and update commands", () => {
  let originalPath: string | undefined;
  let stubBin = "";

  beforeEach(() => {
    originalPath = process.env.PATH;
    stubBin = fs.mkdtempSync(path.join(os.tmpdir(), "regents-update-stub-"));
  });

  afterEach(() => {
    process.env.PATH = originalPath ?? "";
    vi.restoreAllMocks();
  });

  const stubNpm = (script: string): string => {
    const logPath = path.join(stubBin, "npm-calls.log");
    fs.writeFileSync(path.join(stubBin, "npm"), `#!/bin/sh\necho "$@" >> "${logPath}"\n${script}\n`);
    fs.chmodSync(path.join(stubBin, "npm"), 0o755);
    process.env.PATH = `${stubBin}:${process.env.PATH ?? ""}`;
    return logPath;
  };

  it("prints the package version, plain and as JSON", async () => {
    const plain = captureStdout();
    expect(await runVersion(parseCliArgs([]))).toBe(0);
    plain.restore();
    expect(plain.lines.join("")).toMatch(/^\d+\.\d+\.\d+/);

    const json = captureStdout();
    expect(await runVersion(parseCliArgs(["--json"]))).toBe(0);
    json.restore();
    const payload = JSON.parse(json.lines.join(""));
    expect(payload.ok).toBe(true);
    expect(payload.name).toBe("@regentslabs/cli");
    expect(payload.version).toMatch(/^\d+\.\d+\.\d+/);
  });

  it("update runs npm install -g against the requested version", async () => {
    const logPath = stubNpm("exit 0");
    const output = captureStdout();

    expect(await runUpdate(parseCliArgs(["--json", "--version", "9.9.9"]))).toBe(0);
    output.restore();

    expect(fs.readFileSync(logPath, "utf8").trim()).toBe("install -g @regentslabs/cli@9.9.9");
    const payload = JSON.parse(output.lines.join(""));
    expect(payload.ok).toBe(true);
    expect(payload.target).toBe("9.9.9");
    expect(payload.next).toContain("regents setup --quick");
  });

  it("update --check reports installed vs latest without installing anything", async () => {
    const logPath = stubNpm('echo "9.9.9"');
    const output = captureStdout();

    expect(await runUpdate(parseCliArgs(["--check", "--json"]))).toBe(0);
    output.restore();

    expect(fs.readFileSync(logPath, "utf8").trim()).toBe("view @regentslabs/cli version");
    const payload = JSON.parse(output.lines.join(""));
    expect(payload.ok).toBe(true);
    expect(payload.check).toBe(true);
    expect(payload.installed_version).toMatch(/^\d+\.\d+\.\d+/);
    expect(payload.latest_version).toBe("9.9.9");
    expect(payload.up_to_date).toBe(false);
    expect(payload.next).toEqual(["regents update"]);
  });

  it("update --check prints plain text when JSON is not requested", async () => {
    const logPath = stubNpm('echo "9.9.9"');
    const output = captureStdout();

    expect(await runUpdate(parseCliArgs(["--check"]))).toBe(0);
    output.restore();

    expect(fs.readFileSync(logPath, "utf8").trim()).toBe("view @regentslabs/cli version");
    const text = output.lines.join("");
    expect(text).toContain("9.9.9 is available");
    expect(text).toContain("regents update");
  });

  it("update --check reports the up-to-date state", async () => {
    const { cliVersion } = await import("../../src/printer.js");
    stubNpm(`echo "${cliVersion()}"`);
    const output = captureStdout();

    expect(await runUpdate(parseCliArgs(["--check", "--json"]))).toBe(0);
    output.restore();

    const payload = JSON.parse(output.lines.join(""));
    expect(payload.up_to_date).toBe(true);
    expect(payload.next).toEqual([]);
  });

  it("update --check fails cleanly when the registry cannot be read", async () => {
    stubNpm("echo unreachable >&2; exit 1");
    const output = captureStdout();

    expect(await runUpdate(parseCliArgs(["--check", "--json"]))).toBe(1);
    output.restore();

    const payload = JSON.parse(output.lines.join(""));
    expect(payload.ok).toBe(false);
    expect(payload.latest_version).toBeNull();
    expect(payload.detail).toContain("could not be read");
  });

  it("update reports failure with a manual fallback", async () => {
    stubNpm("echo boom >&2; exit 1");
    const output = captureStdout();

    expect(await runUpdate(parseCliArgs(["--json"]))).toBe(1);
    output.restore();

    const payload = JSON.parse(output.lines.join(""));
    expect(payload.ok).toBe(false);
    expect(payload.next[0]).toContain("npm install -g @regentslabs/cli@latest");
  });
});
