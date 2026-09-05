import { CliUsageError } from "../cli-usage-error.js";
import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../parse.js";
import { printJson, printText, renderPanel } from "../printer.js";
import {
  detectRuntimes,
  installPlugin,
  pluginStatus,
  type RegentAgentRuntime,
  type RegentAgentRuntimeSelector,
  type RuntimeDetection,
} from "../internal-runtime/plugin-bridge.js";
import {
  registerClaudeMcp,
  registerCodexMcp,
  type McpRegistration,
} from "../internal-runtime/mcp-register.js";
import { createPromptBoundary, promptInputAllowed, type PromptBoundary } from "../terminal/prompts.js";

const parseRuntime = (value: string | undefined): RegentAgentRuntimeSelector => {
  const runtime = value ?? "auto";
  if (runtime === "auto" || runtime === "hermes" || runtime === "openclaw") {
    return runtime;
  }
  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--runtime must be auto, hermes, or openclaw.",
  });
};

interface WizardActionResult {
  runtime: string;
  action: "installed" | "refreshed" | "registered" | "kept" | "skipped" | "failed";
  detail: string;
}

const pluginInstalled = (runtime: RegentAgentRuntime): boolean =>
  pluginStatus(runtime).runtimes.every((entry) => entry.installed);

export async function runSetup(args: ParsedCliArgs): Promise<number> {
  const runtimeFlag = getFlag(args, "runtime");
  const runtime = parseRuntime(runtimeFlag);
  const quick = getBooleanFlag(args, "quick");
  const wantsJson = getBooleanFlag(args, "json");

  // Agents and scripts keep the stable JSON status report; the wizard is the
  // interactive human path. `--quick` runs the wizard without prompts, so it
  // also works from non-interactive callers such as the install script.
  if (runtimeFlag !== undefined || wantsJson || (!quick && !promptInputAllowed(args))) {
    printJson({
      ok: true,
      runtime,
      detected_runtimes: detectRuntimes(),
      plugin_status: pluginStatus(runtime),
      next: [
        "regents plugin install",
        "regents identity ensure",
        "regents run",
      ],
    });
    return 0;
  }

  return runSetupWizard(args, { quick });
}

async function runSetupWizard(args: ParsedCliArgs, options: { quick: boolean }): Promise<number> {
  const boundary = createPromptBoundary(args);
  const detections = detectRuntimes();
  const results: WizardActionResult[] = [];

  printText(
    renderPanel("Regents Setup Wizard", [
      "Let's wire Regents into the agent runtimes on this machine.",
      options.quick
        ? "Quick mode: only missing pieces are installed, nothing is asked."
        : "Press Ctrl+C at any time to exit.",
    ]),
  );

  printText(renderPanel("Detected agent runtimes", detections.map(describeDetection)));

  for (const detection of detections) {
    if (!detection.detected) {
      continue;
    }

    if (detection.integration === "plugin") {
      results.push(await setUpPluginRuntime(detection.runtime as RegentAgentRuntime, boundary, options));
    } else {
      results.push(await setUpMcpRuntime(detection, boundary, options));
    }
  }

  if (results.length === 0) {
    printText(
      renderPanel("Nothing to set up", [
        "No agent runtimes were detected on this machine.",
        "Install Hermes, OpenClaw, Claude Code, or Codex first, then re-run:",
        "  regents setup",
      ]),
    );
    return 0;
  }

  printText(
    renderPanel("Setup summary", [
      ...results.map((result) => `${result.runtime}: ${result.action} — ${result.detail}`),
      "",
      "Next steps:",
      "  regents identity ensure",
      "  regents doctor",
      "  regents run",
    ]),
  );

  return results.some((result) => result.action === "failed") ? 1 : 0;
}

const describeDetection = (detection: RuntimeDetection): string => {
  const label = detection.runtime.padEnd(8);
  if (!detection.detected) {
    return `${label} not found — skipping`;
  }
  const how = detection.integration === "plugin" ? "native plugin" : "MCP server";
  return `${label} found (${detection.evidence}) — integrates via ${how}`;
};

async function setUpPluginRuntime(
  runtime: RegentAgentRuntime,
  boundary: PromptBoundary,
  options: { quick: boolean },
): Promise<WizardActionResult> {
  const installed = pluginInstalled(runtime);

  if (installed && options.quick) {
    return { runtime, action: "kept", detail: "Regent plugin already installed." };
  }

  if (!options.quick) {
    const question = installed
      ? `Reinstall the Regent plugin for ${runtime}? (already installed)`
      : `Install the Regent plugin for ${runtime}?`;

    const proceed = await boundary.confirm(question, {
      unavailableMessage: "Interactive input is required for the setup wizard.",
    });

    if (!proceed) {
      return installed
        ? { runtime, action: "kept", detail: "Regent plugin already installed." }
        : { runtime, action: "skipped", detail: "Skipped at your request." };
    }
  }

  try {
    const report = installPlugin(runtime);
    return {
      runtime,
      action: installed ? "refreshed" : "installed",
      detail: `Regent plugin at ${report.pluginPath}.`,
    };
  } catch (error) {
    return {
      runtime,
      action: "failed",
      detail: error instanceof Error ? error.message : String(error),
    };
  }
}

async function setUpMcpRuntime(
  detection: RuntimeDetection,
  boundary: PromptBoundary,
  options: { quick: boolean },
): Promise<WizardActionResult> {
  const runtime = detection.runtime as "claude" | "codex";
  const displayName = runtime === "claude" ? "Claude Code" : "Codex";

  if (!options.quick) {
    const proceed = await boundary.confirm(`Register the regents MCP server with ${displayName}?`, {
      unavailableMessage: "Interactive input is required for the setup wizard.",
    });

    if (!proceed) {
      return { runtime, action: "skipped", detail: "Skipped at your request." };
    }
  }

  const registration: McpRegistration = runtime === "claude" ? registerClaudeMcp() : registerCodexMcp();

  const action =
    registration.status === "registered"
      ? "registered"
      : registration.status === "already_registered"
        ? "kept"
        : "failed";

  return { runtime, action, detail: registration.detail };
}
