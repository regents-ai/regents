import { afterEach, describe, expect, it } from "vitest";

import { gbrainRuntimeCapability, pluginRuntimeCapabilities, renderRuntimeRunScreen } from "../../src/commands/run.js";

const originalNoColor = process.env.NO_COLOR;
const originalTerm = process.env.TERM;
const originalIsTTY = process.stdout.isTTY;
const originalColumns = process.stdout.columns;
const originalRegentRunnerKind = process.env.REGENT_RUNNER_KIND;
const originalRegentControlRoomPath = process.env.REGENT_CONTROL_ROOM_PATH;
const originalGbrainToolRepoPath = process.env.GBRAIN_TOOL_REPO_PATH;
const originalGbrainBrainRepoPath = process.env.GBRAIN_BRAIN_REPO_PATH;
const originalGbrainSetupWarning = process.env.GBRAIN_SETUP_WARNING;

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

const stripAnsi = (value: string): string => value.replace(/\x1b\[[0-9;]*m/g, "");

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

  setStdoutTty(Boolean(originalIsTTY));
  setStdoutColumns(originalColumns);
  restoreEnv("REGENT_RUNNER_KIND", originalRegentRunnerKind);
  restoreEnv("REGENT_CONTROL_ROOM_PATH", originalRegentControlRoomPath);
  restoreEnv("GBRAIN_TOOL_REPO_PATH", originalGbrainToolRepoPath);
  restoreEnv("GBRAIN_BRAIN_REPO_PATH", originalGbrainBrainRepoPath);
  restoreEnv("GBRAIN_SETUP_WARNING", originalGbrainSetupWarning);
});

const restoreEnv = (name: string, value: string | undefined): void => {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
};

describe("regents run presenter", () => {
  it("reports Hermes and OpenClaw plugin readiness separately", () => {
    expect(pluginRuntimeCapabilities({
      ok: true,
      selectedRuntime: "auto",
      runtimes: [
        {
          runtime: "hermes",
          installed: true,
          pluginPath: "/Users/example/.hermes/plugins/regent",
          skillsPath: "/Users/example/.hermes/plugins/regent/skills",
        },
        {
          runtime: "openclaw",
          installed: false,
          pluginPath: "/Users/example/.openclaw/plugins/regent",
          skillsPath: "/Users/example/.openclaw/plugins/regent/skills",
        },
      ],
    })).toEqual([
      {
        state: "ready",
        label: "Hermes Regent tools installed",
        detail: "Hermes can see Regent tools at /Users/example/.hermes/plugins/regent.",
      },
      {
        state: "waiting",
        label: "OpenClaw Regent tools missing",
        detail: "Run regents plugin install --runtime openclaw. Checked /Users/example/.openclaw/plugins/regent.",
      },
    ]);
  });

  it("renders hosted GBrain readiness as a non-blocking wait state", () => {
    expect(gbrainRuntimeCapability({
      status: "needs_setup",
      hostedSprite: true,
      toolRepoPath: "~/gbrain",
      brainRepoPath: "/regent/company/BRAIN",
      warnings: [
        "Your Regent agent will be improved if you enable the recommended GBrain memory and search. This increases recall while reducing token spend.",
      ],
    })).toEqual({
      state: "waiting",
      label: "GBrain memory needs setup",
      detail:
        "Your Regent agent will be improved if you enable the recommended GBrain memory and search. This increases recall while reducing token spend.",
    });
  });

  it("explains what local Regent access makes available", () => {
    setStdoutTty(true);
    setStdoutColumns(88);
    delete process.env.NO_COLOR;
    process.env.TERM = "xterm-256color";

    const output = stripAnsi(
      renderRuntimeRunScreen({
        ok: true,
        configPath: "/tmp/regent/config.json",
        socketPath: "/tmp/regent/run/regent.sock",
        stateDir: "/tmp/regent/state",
        services: {
          siwa: "https://siwa.example",
          platform: "https://platform.example",
          autolaunch: "https://autolaunch.example",
        },
        gbrain: {
          status: "needs_setup",
          hostedSprite: true,
          toolRepoPath: "~/gbrain",
          brainRepoPath: "/regent/company/BRAIN",
          warnings: [
            "Your Regent agent will be improved if you enable the recommended GBrain memory and search. This increases recall while reducing token spend.",
          ],
        },
        capabilities: [
          {
            state: "ready",
            label: "Regent is running locally",
            detail: "Keep this terminal open.",
          },
          {
            state: "waiting",
            label: "GBrain memory needs setup",
            detail:
              "Your Regent agent will be improved if you enable the recommended GBrain memory and search. This increases recall while reducing token spend.",
          },
          {
            state: "waiting",
            label: "Agent identity checked",
            detail: "Run regents identity ensure after Regent is running.",
          },
          {
            state: "off",
            label: "Optional worker checked",
            detail: "Optional worker is off in config.",
          },
        ],
        nextCommands: [
          {
            label: "Shared services sign-in",
            command: "regents auth login --audience regent-services",
            when: "prepare shared Regent actions.",
          },
          {
            label: "Techtree notebook",
            command: "regents techtree notebooks init",
            when: "start a local research notebook.",
          },
        ],
        safetyNotes: [
          "It does not start hosted Regent.",
          "It does not move funds.",
        ],
        mode: "local_runtime",
        fold: null,
        agenticWallet: {
          required: false,
          whenNeeded: "Only paid x402 spend and earn flows need Agentic Wallet.",
        },
        autolaunch: {
          state: "locked",
          reason: "Launch readiness must be confirmed through Autolaunch.",
        },
      }),
    );

    expect(output).toContain("REGENT IS RUNNING");
    expect(output).toContain("Keep this terminal open. Use another terminal for Regent commands.");
    expect(output).toContain("WHAT IS READY");
    expect(output).toContain("GBrain memory needs setup");
    expect(output).toContain("recommended GBrain memory");
    expect(output).toContain("Agent identity checked");
    expect(output).toContain("RUN THESE IN ANOTHER TERMINAL");
    expect(output).toContain("regents auth login --audience regent-services");
    expect(output).toContain("regents techtree notebooks init");
    expect(output).toContain("It does not start hosted Regent.");
    expect(output).toContain("It does not move funds.");
    expect(output).not.toContain("local runtime");
  });
});
