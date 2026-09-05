import { afterEach, describe, expect, it, vi } from "vitest";

import { runCommandsList } from "../../src/commands/commands-list.js";
import { CLI_COMMANDS } from "../../src/generated/cli-command-metadata.js";
import { parseCliArgs } from "../../src/parse.js";

const captureStdout = () => {
  const lines: string[] = [];
  const spy = vi.spyOn(process.stdout, "write").mockImplementation((chunk) => {
    lines.push(String(chunk));
    return true;
  });
  return { lines, restore: () => spy.mockRestore() };
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("commands list", () => {
  it("prints the full generated command index as JSON", async () => {
    const output = captureStdout();
    expect(await runCommandsList(parseCliArgs(["--json"]))).toBe(0);
    output.restore();

    const payload = JSON.parse(output.lines.join(""));
    expect(payload.ok).toBe(true);
    expect(payload.total).toBe(CLI_COMMANDS.length);
    expect(payload.commands).toHaveLength(CLI_COMMANDS.length);
    expect(payload.commands.map((entry: { command: string }) => entry.command)).toEqual([
      ...CLI_COMMANDS,
    ]);

    const listEntry = payload.commands.find(
      (entry: { command: string }) => entry.command === "commands list",
    );
    expect(listEntry).toMatchObject({
      command: "commands list",
      group: "operator",
      summary: expect.stringContaining("shipped Regents CLI command"),
      flags: expect.arrayContaining([
        expect.objectContaining({ name: "--search" }),
        expect.objectContaining({ name: "--json" }),
      ]),
    });
  });

  it("filters with --search over command names and summaries", async () => {
    const output = captureStdout();
    expect(await runCommandsList(parseCliArgs(["--json", "--search", "chat tail"]))).toBe(0);
    output.restore();

    const payload = JSON.parse(output.lines.join(""));
    expect(payload.search).toBe("chat tail");
    const names = payload.commands.map((entry: { command: string }) => entry.command);
    expect(names).toContain("autolaunch chat tail [scope...]");
    expect(names).not.toContain("version");
    expect(payload.total).toBe(names.length);
  });

  it("prints human-readable lines without --json", async () => {
    const output = captureStdout();
    expect(await runCommandsList(parseCliArgs(["--search", "commands list"]))).toBe(0);
    output.restore();

    const text = output.lines.join("");
    expect(text).toContain("regents commands list - ");
    expect(text).toContain('match "commands list"');
    expect(text).toContain("--json");
  });
});
