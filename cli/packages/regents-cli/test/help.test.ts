import { describe, expect, it } from "vitest";

import { CLI_COMMANDS } from "../src/command-registry.js";
import { renderScopedHelp } from "../src/help.js";
import { runCliEntrypoint } from "../src/index.js";
import { captureOutput } from "../../../test-support/test-helpers.js";

describe("scoped CLI help", () => {
  it("renders global help with agent skills as a first-run path", async () => {
    const output = await captureOutput(() => runCliEntrypoint(["--help"]));

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("REGENT CLI HELP");
    expect(output.stdout).toContain("regents setup skills");
  });

  it("distinguishes provider discovery from Coinbase status and local signing", async () => {
    const setup = await captureOutput(() => runCliEntrypoint(["wallet", "setup", "--help"]));
    expect(setup.stdout).toContain("--provider");
    expect(setup.stdout).toContain("without creating a wallet");
    const status = await captureOutput(() => runCliEntrypoint(["wallet", "status", "--help"]));
    expect(status.stdout).toContain("Coinbase CDP");
    expect(status.stdout).toContain("not a local-key or external-wallet check");
  });

  it("exposes both payment rails, original request flags and recovery guidance", async () => {
    const output = await captureOutput(() => runCliEntrypoint(["x402", "pay", "--help"]));
    expect(output.result).toBe(0);
    for (const flag of ["agentic-wallet|regent-wallet", "--method", "--body", "--header", "--approve"]) {
      expect(output.stdout).toContain(flag);
    }
    expect(output.stdout).toContain("payment_status");
    expect(output.stdout).toContain("provider_correlation_id");
    expect(output.stdout).toContain("do not automatically pay again");
    const details = await captureOutput(() => runCliEntrypoint(["x402", "details", "--help"]));
    expect(details.stdout).toContain("payment_required_response");
    expect(details.stdout).toContain("may execute if no payment is required");
    expect(details.stdout).not.toContain("wallet agentic status");
  });

  it("renders command-level help", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint(["work", "watch", "--help"]),
    );

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("WORK WATCH HELP");
    expect(output.stdout).toContain("regents work watch <run-id>");
    expect(output.stdout).toContain("--regent-id <id>");
  });

  it("renders prerequisite and failure guidance for common work commands", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint(["work", "run", "--help"]),
    );

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("WORK RUN HELP");
    expect(output.stdout).toContain("BEFORE YOU RUN THIS");
    expect(output.stdout).toContain("regents platform auth login");
    expect(output.stdout).toContain("IF THIS FAILS");
    expect(output.stdout).toContain("regents work watch <run-id> --regent-id <id>");
  });

  it("renders setup skills help", async () => {
    const output = await captureOutput(() => runCliEntrypoint(["setup", "skills", "--help"]));

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("SETUP SKILLS HELP");
    expect(output.stdout).toContain("regents setup skills [--project]");
    expect(output.stdout).toContain("--project");
  });

  it("overexplains runtime plugin install choices", async () => {
    const output = await captureOutput(() => runCliEntrypoint(["plugin", "install", "--help"]));

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("PLUGIN INSTALL HELP");
    expect(output.stdout).toContain("regents plugin install [--runtime <auto|hermes|openclaw>]");
    expect(output.stdout).toContain("--runtime auto (default) installs both sets of tools");
    expect(output.stdout).toContain("--runtime hermes installs the Hermes tools and selects xAI Grok OAuth");
    expect(output.stdout).toContain("--runtime openclaw installs only the OpenClaw tools");
    expect(output.stdout).toContain("hermes auth add xai-oauth");
  });

  it("prefers the more specific help entry when commands share a prefix", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint(["doctor", "workspace", "--help"]),
    );

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("DOCTOR WORKSPACE HELP");
    expect(output.stdout).toContain("regents doctor workspace");
  });

  it("shows the required platform sign-in flags", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint(["platform", "auth", "login", "--help"]),
    );

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("PLATFORM AUTH LOGIN HELP");
    expect(output.stdout).toContain("--access-token <token>");
    expect(output.stdout).toContain("--session-file <path>");
    expect(output.stdout).toContain("regents platform formation status");
  });

  it("distinguishes owner service commands from buyer x402 commands", async () => {
    const init = await captureOutput(() => runCliEntrypoint(["service", "init", "--help"]));
    const resume = await captureOutput(() => runCliEntrypoint(["service", "resume", "--help"]));
    const logs = await captureOutput(() => runCliEntrypoint(["service", "logs", "--help"]));

    expect(init.result).toBe(0);
    expect(init.stdout).toContain("SERVICE INIT HELP");
    expect(init.stdout).toContain("--kind");
    expect(init.stdout).toContain("--skill-package");
    expect(init.stdout).toContain("--skill-package-version");

    expect(resume.result).toBe(0);
    expect(resume.stdout).toContain("SERVICE RESUME HELP");
    expect(resume.stdout).toContain("Use these commands only for a service you own or administer.");
    expect(resume.stdout).toContain("Buyers use `regents x402 details`, `quote`, `prepare`, `fetch`, or `pay`");

    expect(logs.result).toBe(0);
    expect(logs.stdout).toContain("SERVICE LOGS HELP");
    expect(logs.stdout).toContain("Needs a saved Regent website session from `regents platform auth login`.");
    expect(logs.stdout).toContain("If a buyer needs to call the service, use the existing `regents x402` commands instead.");
  });

  it("renders Regent worker help for hosted Hermes and execution pools", async () => {
    const hostedHermes = await captureOutput(() =>
      runCliEntrypoint(["agent", "connect", "hosted-hermes", "--help"]),
    );

    expect(hostedHermes.result).toBe(0);
    expect(hostedHermes.stdout).toContain("AGENT CONNECT HOSTED-HERMES HELP");
    expect(hostedHermes.stdout).toContain("regents agent connect hosted-hermes --regent-id <id> --runtime-id <id>");
    expect(hostedHermes.stdout).toContain("Needs a saved Regent website session from `regents platform auth login`.");

    const pool = await captureOutput(() =>
      runCliEntrypoint(["agent", "execution-pool", "--help"]),
    );

    expect(pool.result).toBe(0);
    expect(pool.stdout).toContain("AGENT EXECUTION-POOL HELP");
    expect(pool.stdout).toContain("regents agent execution-pool --regent-id <id>");
  });

  it("keeps local runtime status help free of website sign-in instructions", async () => {
    const output = await captureOutput(() => runCliEntrypoint(["runtime", "status", "--help"]));

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("RUNTIME STATUS HELP");
    expect(output.stdout).toContain("No saved sign-in is needed.");
    expect(output.stdout).not.toContain("regents platform auth login");
  });

  it("renders platform SIWA auth for local work loops", async () => {
    const output = await captureOutput(() => runCliEntrypoint(["work", "local-loop", "--help"]));

    expect(output.result).toBe(0);
    expect(output.stdout).toContain("WORK LOCAL-LOOP HELP");
    expect(output.stdout).toContain("regents auth login --audience platform");
    expect(output.stdout).not.toContain("Needs a saved Regent website session");
  });

  it("renders Regent work help with concise output guidance", async () => {
    const run = await captureOutput(() => runCliEntrypoint(["work", "run", "--help"]));

    expect(run.result).toBe(0);
    expect(run.stdout).toContain("WORK RUN HELP");
    expect(run.stdout).toContain("Shows the run id, selected worker, current status, and watch command.");

    const openclaw = await captureOutput(() =>
      runCliEntrypoint(["agent", "connect", "openclaw", "--help"]),
    );

    expect(openclaw.result).toBe(0);
    expect(openclaw.stdout).toContain("Shows the worker id and the local Regents Work skill path.");
  });

  it("renders non-empty metadata-driven help for every shipped command", () => {
    const helpless: string[] = [];

    for (const command of CLI_COMMANDS) {
      const help = renderScopedHelp(command.split(" "), "/tmp/regent.json");
      const heading = `◆ ${command.toUpperCase()} HELP`;
      if (!help.includes(heading) || !help.includes("usage") || !help.includes("◆ FLAGS")) {
        helpless.push(command);
      }
    }

    expect(helpless).toEqual([]);
  });

  it("keeps command help stable", () => {
    expect(renderScopedHelp(["work", "watch"], "/tmp/regent.json")).toMatchInlineSnapshot(`
      "◆ WORK WATCH HELP
      Show updates for one Regent work run.

      usage regents work watch <run-id> --regent-id <id>
      auth Needs a saved Regent website session from \`regents platform auth login\`.
      output Shows recent run updates with sequence, update name, actor, and time.
      next Run the command again when you need the latest updates.

      ◆ BEFORE YOU RUN THIS
      Run \`regents platform auth login\` with a Regent website access token.
      Use the correct regent id or slug from the Regent website.

      ◆ FLAGS
      --regent-id <id>
      --origin <url>
      --session-file <path>

      ◆ EXAMPLES
      regents work watch <run-id> --regent-id <id>

      ◆ IF THIS FAILS
      If the command says no saved platform session exists, run \`regents platform auth login\`.
      If a regent, runtime, worker, or work id is not found, copy it again from the Regent website or the previous command output."
    `);
  });
});
