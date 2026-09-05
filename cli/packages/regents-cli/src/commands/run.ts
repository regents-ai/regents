import fs from "node:fs";
import { spawnSync } from "node:child_process";

import { readBudgetFile } from "../internal-runtime/budget-store.js";
import { RegentRuntime, defaultConfigPath } from "../internal-runtime/index.js";
import { pluginStatus, type PluginRuntimeStatus } from "../internal-runtime/plugin-bridge.js";
import type { RegentConfig } from "../internal-types/index.js";
import { getBooleanFlag, type ParsedCliArgs } from "../parse.js";
import { CLI_PALETTE, isHumanTerminal, printJson, printText, renderBanner, renderPanel, tone } from "../printer.js";

export type RuntimeCapabilityState = "ready" | "waiting" | "off";

export interface RuntimeCapability {
  readonly state: RuntimeCapabilityState;
  readonly label: string;
  readonly detail: string;
}

export interface RuntimeNextCommand {
  readonly label: string;
  readonly command: string;
  readonly when: string;
}

export type GBrainRuntimeStatus = "not_installed" | "installed" | "needs_setup" | "ready" | "warning";

export interface GBrainReadiness {
  readonly status: GBrainRuntimeStatus;
  readonly hostedSprite: boolean;
  readonly toolRepoPath: string | null;
  readonly brainRepoPath: string | null;
  readonly warnings: readonly string[];
}

export interface RuntimeRunReport {
  readonly ok: true;
  readonly configPath: string;
  readonly socketPath: string;
  readonly stateDir: string;
  readonly services: {
    readonly siwa: string;
    readonly platform: string;
    readonly autolaunch: string;
  };
  readonly gbrain: GBrainReadiness;
  readonly capabilities: readonly RuntimeCapability[];
  readonly plugin: ReturnType<typeof pluginStatus>;
  readonly nextCommands: readonly RuntimeNextCommand[];
  readonly safetyNotes: readonly string[];
  readonly mode: "local_runtime";
  readonly agenticWallet: {
    readonly required: false;
    readonly whenNeeded: string;
  };
  readonly autolaunch: {
    readonly state: "locked" | "evidence-ready";
    readonly reason: string;
  };
}

const capabilityGlyph = (state: RuntimeCapabilityState): string => {
  switch (state) {
    case "ready":
      return "✓";
    case "waiting":
      return "○";
    case "off":
      return "•";
  }
};

const capabilityColor = (state: RuntimeCapabilityState): string => {
  switch (state) {
    case "ready":
      return CLI_PALETTE.emphasis;
    case "waiting":
      return CLI_PALETTE.accent;
    case "off":
      return CLI_PALETTE.secondary;
  }
};

const capabilityLines = (capabilities: readonly RuntimeCapability[]): string[] =>
  capabilities.flatMap((capability) => {
    const color = capabilityColor(capability.state);
    return [
      `${tone(capabilityGlyph(capability.state), color, true)} ${tone(capability.label, CLI_PALETTE.primary, true)}`,
      `  ${tone(capability.detail, CLI_PALETTE.secondary)}`,
    ];
  });

const commandLines = (commands: readonly RuntimeNextCommand[]): string[] =>
  commands.flatMap((entry) => [
    `${tone("▶", CLI_PALETTE.accent, true)} ${tone(entry.command, CLI_PALETTE.primary, true)}`,
    `  ${tone(entry.label, CLI_PALETTE.secondary, true)} ${tone(entry.when, CLI_PALETTE.secondary)}`,
  ]);

const enabledHarnessNames = (config: RegentConfig): string[] =>
  Object.entries(config.agents.harnesses)
    .filter(([, harness]) => harness.enabled)
    .map(([name]) => name);

const runtimeDisplayName = (runtime: PluginRuntimeStatus["runtime"]): string =>
  runtime === "hermes" ? "Hermes" : "OpenClaw";

const GBRAIN_SETUP_WARNING =
  "Your Regent agent will be improved if you enable the recommended GBrain memory and search. This increases recall while reducing token spend.";

const expandHome = (value: string): string => {
  if (value === "~") {
    return process.env.HOME ?? value;
  }
  if (value.startsWith("~/")) {
    return `${process.env.HOME ?? "~"}${value.slice(1)}`;
  }
  return value;
};

const hostedHermesSprite = (): boolean =>
  process.env.REGENT_RUNNER_KIND === "hermes_hosted_manager" ||
  Boolean(process.env.REGENT_CONTROL_ROOM_PATH || process.env.GBRAIN_BRAIN_REPO_PATH);

const gbrainDoctorPasses = (brainRepoPath: string | null): boolean => {
  const result = spawnSync("gbrain", ["doctor", "--json"], {
    cwd: brainRepoPath ? expandHome(brainRepoPath) : process.cwd(),
    encoding: "utf8",
    timeout: 5_000,
    stdio: ["ignore", "pipe", "pipe"],
  });

  return result.status === 0;
};

const gbrainReadiness = (): GBrainReadiness => {
  const hostedSprite = hostedHermesSprite();

  if (!hostedSprite) {
    return {
      status: "not_installed",
      hostedSprite: false,
      toolRepoPath: null,
      brainRepoPath: null,
      warnings: [],
    };
  }

  const toolRepoPath = process.env.GBRAIN_TOOL_REPO_PATH ?? "~/gbrain";
  const brainRepoPath = process.env.GBRAIN_BRAIN_REPO_PATH ?? "/regent/company/BRAIN";
  const setupWarning = process.env.GBRAIN_SETUP_WARNING ?? GBRAIN_SETUP_WARNING;
  const expandedToolRepoPath = expandHome(toolRepoPath);
  const expandedBrainRepoPath = expandHome(brainRepoPath);
  const toolInstalled =
    fs.existsSync(expandedToolRepoPath) &&
    (fs.existsSync(`${expandedToolRepoPath}/package.json`) || fs.existsSync(`${expandedToolRepoPath}/bun.lock`));
  const brainRepoExists = fs.existsSync(expandedBrainRepoPath);

  if (!toolInstalled) {
    return {
      status: "not_installed",
      hostedSprite,
      toolRepoPath,
      brainRepoPath,
      warnings: [setupWarning],
    };
  }

  if (!brainRepoExists) {
    return {
      status: "installed",
      hostedSprite,
      toolRepoPath,
      brainRepoPath,
      warnings: [`GBrain is installed, but the brain repo is missing at ${brainRepoPath}.`],
    };
  }

  if (gbrainDoctorPasses(brainRepoPath)) {
    return {
      status: "ready",
      hostedSprite,
      toolRepoPath,
      brainRepoPath,
      warnings: [],
    };
  }

  return {
    status: "needs_setup",
    hostedSprite,
    toolRepoPath,
    brainRepoPath,
    warnings: [setupWarning],
  };
};

export const gbrainRuntimeCapability = (gbrain: GBrainReadiness): RuntimeCapability => {
  if (!gbrain.hostedSprite) {
    return {
      state: "off",
      label: "GBrain memory checked",
      detail: "GBrain is only automatic for hosted Hermes Sprites.",
    };
  }

  if (gbrain.status === "ready") {
    return {
      state: "ready",
      label: "GBrain memory ready",
      detail: `GBrain is ready at ${gbrain.brainRepoPath}.`,
    };
  }

  const warning = gbrain.warnings[0] ?? GBRAIN_SETUP_WARNING;
  return {
    state: "waiting",
    label: `GBrain memory ${gbrain.status.replaceAll("_", " ")}`,
    detail: warning,
  };
};

export const pluginRuntimeCapabilities = (
  plugin: ReturnType<typeof pluginStatus>,
): readonly RuntimeCapability[] =>
  plugin.runtimes.map((runtime) => {
    const name = runtimeDisplayName(runtime.runtime);

    return {
      state: runtime.installed ? "ready" : "waiting",
      label: `${name} Regent tools ${runtime.installed ? "installed" : "missing"}`,
      detail: runtime.installed
        ? `${name} can see Regent tools at ${runtime.pluginPath}.`
        : `Run regents plugin install --runtime ${runtime.runtime}. Checked ${runtime.pluginPath}.`,
    };
  });

const buildRuntimeRunReport = (runtime: RegentRuntime): RuntimeRunReport => {
  const config = runtime.config;
  const state = runtime.stateStore.read();
  const identity = state.agent;
  const session = runtime.sessionStore.getSiwaSession();
  const sessionReady = Boolean(session && !runtime.sessionStore.isReceiptExpired());
  const walletEnvSet = Boolean(process.env[config.wallet.privateKeyEnv]);
  const walletFileExists = fs.existsSync(config.wallet.keystorePath);
  const harnesses = enabledHarnessNames(config);
  const plugin = pluginStatus("auto");
  const budgets = readBudgetFile(config).budgets;
  const activeBudgetCount = budgets.filter((budget) => budget.status === "active").length;
  const gbrain = gbrainReadiness();

  return {
    ok: true,
    configPath: runtime.configPath ?? defaultConfigPath(),
    socketPath: config.runtime.socketPath,
    stateDir: config.runtime.stateDir,
    services: {
      siwa: config.services.siwa.baseUrl,
      platform: config.services.platform.baseUrl,
      autolaunch: config.services.autolaunch.baseUrl,
    },
    gbrain,
    mode: "local_runtime",
    plugin,
    capabilities: [
      {
        state: "ready",
        label: "Regent is running locally",
        detail: `Keep this terminal open. Other terminals can now connect at ${config.runtime.socketPath}.`,
      },
      {
        state: "ready",
        label: "Local records opened",
        detail: `Regent notes, Agent identity, and saved sign-ins live under ${config.runtime.stateDir}.`,
      },
      gbrainRuntimeCapability(gbrain),
      {
        state: walletEnvSet || walletFileExists ? "ready" : "waiting",
        label: "Wallet source checked",
        detail: walletEnvSet
          ? `${config.wallet.privateKeyEnv} is set for this process.`
          : walletFileExists
            ? `Local wallet file is present at ${config.wallet.keystorePath}.`
            : `Run regents wallet setup or set ${config.wallet.privateKeyEnv} before signing.`,
      },
      {
        state: identity?.registryAddress && identity.tokenId ? "ready" : "waiting",
        label: "Agent identity checked",
        detail: identity?.registryAddress && identity.tokenId
          ? `Agent token ${identity.tokenId} is saved for chain ${identity.chainId}.`
          : "Run regents identity ensure after Regent is running.",
      },
      {
        state: sessionReady ? "ready" : "waiting",
        label: "Saved Agent sign-in checked",
        detail: sessionReady && session
          ? `${session.audience} sign-in is saved until ${session.receiptExpiresAt}.`
          : "Run regents auth login --audience <platform|autolaunch|techtree|regent-services>.",
      },
      ...pluginRuntimeCapabilities(plugin),
      {
        state: activeBudgetCount > 0 ? "ready" : "waiting",
        label: "Research budget checked",
        detail: activeBudgetCount > 0
          ? `${activeBudgetCount} active Regent budget ${activeBudgetCount === 1 ? "is" : "are"} saved.`
          : "A budget is optional until an agent needs paid x402 access.",
      },
      {
        state: "waiting",
        label: "Agentic Wallet checked",
        detail: "Agentic Wallet is optional and needed only for paid x402 spend or earn flows.",
      },
      {
        state: "waiting",
        label: "Autolaunch readiness checked",
        detail: "Autolaunch remains operator-approved.",
      },
      {
        state: harnesses.length > 0 ? "ready" : "waiting",
        label: "Local agent runners checked",
        detail: harnesses.length > 0
          ? `Enabled harnesses: ${harnesses.join(", ")}.`
          : "No local agent harness is enabled yet.",
      },
    ],
    nextCommands: [
      {
        label: "Readiness",
        command: "regents status",
        when: "see wallet, identity, and local runtime readiness.",
      },
      {
        label: "Account",
        command: "regents whoami",
        when: "show the active wallet, Agent identity, chain, and saved sign-in.",
      },
      {
        label: "Shared services sign-in",
        command: "regents auth login --audience regent-services",
        when: "prepare bug reports, security reports, and shared Regent actions.",
      },
      {
        label: "Platform sign-in",
        command: "regents auth login --audience platform",
        when: "prepare local worker connections to Platform.",
      },
      {
        label: "Autolaunch sign-in",
        command: "regents auth login --audience autolaunch",
        when: "prepare Autolaunch agent, Safe, prelaunch, and launch commands.",
      },
      {
        label: "Diagnostics",
        command: "regents doctor runtime",
        when: "check local command access if a command cannot connect.",
      },
    ],
    safetyNotes: [
      "This lets Regent commands work from this machine.",
      "It does not start hosted Regent.",
      "It does not move funds.",
      "Wallet and transaction commands still require their own explicit signing or submit step.",
      "Stop this process with Ctrl-C when you no longer need Regent commands on this machine.",
    ],
    agenticWallet: {
      required: false,
      whenNeeded: "Only paid x402 spend and earn flows need Agentic Wallet.",
    },
    autolaunch: {
      state: "locked",
      reason: "An operator must approve a launch.",
    },
  };
};

export const renderRuntimeRunScreen = (report: RuntimeRunReport): string =>
  [
    renderBanner(),
    renderPanel("◆ REGENT IS RUNNING", [
      "Regent is running on this machine.",
      "Keep this terminal open. Use another terminal for Regent commands.",
      "Stop this with Ctrl-C.",
      "",
      `${tone("settings", CLI_PALETTE.secondary, true)} ${report.configPath}`,
      `${tone("records", CLI_PALETTE.secondary, true)} ${report.stateDir}`,
    ], {
      borderColor: CLI_PALETTE.emphasis,
      titleColor: CLI_PALETTE.title,
    }),
    renderPanel("◆ WHAT IS READY", capabilityLines(report.capabilities), {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
    renderPanel("◆ RUN THESE IN ANOTHER TERMINAL", commandLines(report.nextCommands), {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
    renderPanel("◆ SAFETY NOTES", [...report.safetyNotes], {
      borderColor: CLI_PALETTE.accent,
      titleColor: CLI_PALETTE.title,
    }),
  ]
    .filter(Boolean)
    .join("\n\n");

const renderRuntimeStoppedScreen = (): string =>
  renderPanel("◆ REGENT STOPPED", [
    "Regent has stopped on this machine.",
    "Commands that need it will ask you to run regents run again.",
  ], {
    borderColor: CLI_PALETTE.accent,
    titleColor: CLI_PALETTE.title,
  });

export async function runRuntime(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const runtime = new RegentRuntime(configPath);
  await runtime.start();
  const report = buildRuntimeRunReport(runtime);
  const humanOutput = isHumanTerminal() && !getBooleanFlag(args, "json");
  if (humanOutput) {
    printText(renderRuntimeRunScreen(report));
  } else {
    printJson(report);
  }

  await new Promise<void>((resolve, reject) => {
    let settled = false;

    const onSignal = (): void => {
      void stop();
    };

    const finish = (error?: unknown): void => {
      if (settled) {
        return;
      }

      settled = true;
      process.off("SIGINT", onSignal);
      process.off("SIGTERM", onSignal);

      if (error) {
        reject(error);
        return;
      }

      resolve();
    };

    const stop = async (): Promise<void> => {
      try {
        await runtime.stop();
        if (humanOutput) {
          printText(renderRuntimeStoppedScreen());
        }
        finish();
      } catch (error) {
        finish(error);
      }
    };

    process.once("SIGINT", onSignal);
    process.once("SIGTERM", onSignal);
  });
}
