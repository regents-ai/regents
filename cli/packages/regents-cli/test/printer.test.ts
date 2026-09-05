import { afterEach, describe, expect, it } from "vitest";

import { captureOutput } from "../../../test-support/test-helpers.js";

import { renderScopedHelp } from "../src/help.js";
import { JsonRpcError } from "../src/internal-runtime/index.js";
import { printError, printJson, renderTablePanel, renderUsageScreen, setRawJsonOutput } from "../src/printer.js";

const originalNoColor = process.env.NO_COLOR;
const originalTerm = process.env.TERM;
const originalIsTTY = process.stdout.isTTY;
const originalColumns = process.stdout.columns;

const setStdoutTty = (value: boolean): void => {
  Object.defineProperty(process.stdout, "isTTY", {
    configurable: true,
    value,
  });
};

const setStdoutColumns = (value: number | undefined): void => {
  Object.defineProperty(process.stdout, "columns", {
    configurable: true,
    value,
  });
};

afterEach(() => {
  if (originalNoColor === undefined) {
    delete process.env.NO_COLOR;
  } else {
    process.env.NO_COLOR = originalNoColor;
  }

  if (originalTerm === undefined) {
    delete process.env.TERM;
  } else {
    process.env.TERM = originalTerm;
  }

  setRawJsonOutput(false);
  setStdoutTty(Boolean(originalIsTTY));
  setStdoutColumns(originalColumns);
});

describe("printer surface", () => {
  const stripAnsi = (value: string): string => value.replace(/\x1b\[[0-9;]*m/g, "");

  it("renders a framed usage screen", () => {
    const output = renderUsageScreen("/tmp/regent.json");

    expect(output).toContain("R E G E N T   C L I");
    expect(output).toContain("START HERE");
    expect(output).toContain("PRODUCT AREAS");
    expect(output).toContain("TECHTREE NOTEBOOKS");
    expect(output).toContain("COMMON NEXT STEPS");
    expect(output).toContain("direct control surface for Regent operators and agents");
    expect(output).toContain("Use regents.sh for guided browser setup.");
    expect(output).toContain("Use this CLI for local identity, runtime, notebooks, and Autolaunch work.");
    expect(output).toContain("Run `regents help <product>` or `regents <command> --help`.");
    expect(output).toContain("regents init");
    expect(output).toContain("regents status");
    expect(output).toContain("regents whoami");
    expect(output).toContain("regents run");
    expect(output).toContain("regents doctor");
    expect(output).toContain("regents platform auth login");
    expect(output).toContain("regents techtree notebooks init");
    expect(output).toContain("regents techtree notebooks pair");
    expect(output).toContain("regents autolaunch prelaunch wizard");
    expect(output).toContain("regents autolaunch launch run");
    expect(output).toContain("regents autolaunch safe wizard");
    expect(output).toContain("regents bug --summary");
    expect(output).toContain("regents security-report --summary");
  });

  it("wraps help panels inside narrow terminal widths", () => {
    setStdoutTty(true);
    setStdoutColumns(40);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = renderScopedHelp([], "/Users/sean/.regent/config.json");
    const visibleLines = stripAnsi(output).split("\n");

    expect(visibleLines.every((line) => line.length <= 40)).toBe(true);
    expect(output).toContain("REGENT CLI HELP");
    expect(output).toContain("/Users/sean/.regent/config.json");
  });

  it("keeps table panels readable in narrow terminals", () => {
    setStdoutTty(true);
    setStdoutColumns(48);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = renderTablePanel(
      "◆ ROUTES",
      [
        { header: "route", minWidth: 8 },
        { header: "description", minWidth: 12 },
      ],
      [
        {
          cells: [
            "/api/techtree/v1/runtime/validations/very-long-node-reference",
            "A very long description that should not stretch the table past the terminal.",
          ],
        },
      ],
    );
    const visibleLines = stripAnsi(output).split("\n");

    expect(visibleLines.every((line) => line.length <= 48)).toBe(true);
    expect(output).toContain("...");
  });

  it("keeps multi-column table panels inside narrow terminals", () => {
    setStdoutTty(true);
    setStdoutColumns(44);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = renderTablePanel(
      "◆ INBOX",
      [
        { header: "node", align: "right", minWidth: 4 },
        { header: "event", minWidth: 8 },
        { header: "actor", minWidth: 8 },
        { header: "stream", minWidth: 10 },
        { header: "time", minWidth: 10 },
      ],
      [
        {
          cells: [
            "42",
            "long-event-name",
            "agent:1234567890",
            "agent_inbox",
            "2026-06-19T00:00:00.000Z",
          ],
        },
      ],
    );
    const visibleLines = stripAnsi(output).split("\n");

    expect(visibleLines.every((line) => line.length <= 44)).toBe(true);
    expect(output).toContain("...");
  });

  it("renders a receipt-style summary for setup records", async () => {
    setStdoutTty(true);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = await captureOutput(async () => {
      printJson({
        ok: true,
        configPath: "/tmp/regent.json",
        configCreated: true,
        stateDir: "/tmp/state",
        socketPath: "/tmp/run/regent.sock",
      });
    });

    expect(output.stdout).toContain("REGENT SUMMARY");
    expect(output.stdout).toContain("config created");
    expect(output.stdout).toContain("state dir");
    expect(output.stdout).toContain("/tmp/regent.json");
    expect(output.stdout).toContain("REGENT OUTPUT DECK");
  });

  it("renders framed JSON output for human terminals", async () => {
    setStdoutTty(true);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = await captureOutput(async () => {
      printJson({
        data: {
          lane: "benchmark",
          entries: [],
        },
      });
    });

    expect(output.stdout).toContain("REGENT DATA DECK");
    expect(output.stdout).toContain("lane");
    expect(output.stdout).toContain("benchmark");
    expect(output.stdout).toContain("╭");
  });

  it("renders next-step hints at the end of human JSON output", async () => {
    setStdoutTty(true);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = await captureOutput(async () => {
      printJson({
        ok: true,
        created: true,
        next: ["regents techtree notebooks init --json"],
      });
    });

    const nextIndex = output.stdout.lastIndexOf("NEXT");
    expect(nextIndex).toBeGreaterThan(output.stdout.indexOf("REGENT OUTPUT DECK"));
    expect(output.stdout).toContain("regents techtree notebooks init --json");
  });

  it("renders a framed error for human terminals", async () => {
    setStdoutTty(true);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = await captureOutput(async () => {
      printError(new Error("operator shell failed"));
    });

    expect(output.stderr).toContain("REGENT ERROR");
    expect(output.stderr).toContain("operator shell failed");
    expect(output.stderr).toContain("╭");
  });

  it("prints a direct next step when the local runtime is not running", async () => {
    setStdoutTty(false);

    const output = await captureOutput(async () => {
      printError(
        new JsonRpcError("Regent local runtime is not running.", {
          code: "runtime_unavailable",
          details: {
            socket_path: "/tmp/regent/run/regent.sock",
          },
          nextSteps: ["Run `regents run` in another terminal.", "Retry this command."],
        }),
      );
    });

    expect(JSON.parse(output.stderr)).toEqual({
      error: {
        code: "runtime_unavailable",
        message: "Regent local runtime is not running.",
        socket_path: "/tmp/regent/run/regent.sock",
        next_steps: ["Run `regents run` in another terminal.", "Retry this command."],
      },
    });
  });

  it("escapes terminal control characters in human summaries", async () => {
    setStdoutTty(true);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = await captureOutput(async () => {
      printJson({
        ok: true,
        configPath: "/tmp/\x1b[31mred.json",
      });
    });

    const visible = stripAnsi(output.stdout);

    expect(visible).toContain("/tmp/\\u001b[31mred.json");
    expect(visible).not.toContain("/tmp/\x1b[31mred.json");
  });

  it("keeps plain JSON output for non-human terminals", async () => {
    setStdoutTty(false);
    delete process.env.NO_COLOR;

    const payload = {
      ok: true,
      configPath: "/tmp/regent.json",
    };
    const output = await captureOutput(async () => {
      printJson(payload);
    });

    expect(output.stdout).toBe(`${JSON.stringify(payload, null, 2)}\n`);
  });

  it("keeps plain JSON output whenever NO_COLOR is set", async () => {
    setStdoutTty(true);
    process.env.NO_COLOR = "0";

    const payload = { ok: true, mode: "no-color" };
    const output = await captureOutput(async () => {
      printJson(payload);
    });

    expect(output.stdout).toBe(`${JSON.stringify(payload, null, 2)}\n`);
  });

  it("keeps plain JSON output for dumb terminals", async () => {
    setStdoutTty(true);
    delete process.env.NO_COLOR;
    process.env.TERM = "dumb";

    const payload = { ok: true, mode: "dumb" };
    const output = await captureOutput(async () => {
      printJson(payload);
    });

    expect(output.stdout).toBe(`${JSON.stringify(payload, null, 2)}\n`);
  });

  it("keeps raw JSON output when script mode is requested", async () => {
    setStdoutTty(true);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";
    setRawJsonOutput(true);

    const payload = { ok: true, mode: "json" };
    const output = await captureOutput(async () => {
      printJson(payload);
    });

    expect(output.stdout).toBe(`${JSON.stringify(payload, null, 2)}\n`);
  });
});
