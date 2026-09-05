import fs from "node:fs";

import { readBudgetFile } from "../internal-runtime/budget-store.js";
import { loadConfig } from "../internal-runtime/config.js";
import { pluginStatus, REGENT_PLUGIN_TOOL_NAMES } from "../internal-runtime/plugin-bridge.js";
import { StateStore } from "../internal-runtime/store/state-store.js";
import { printJson } from "../printer.js";

export async function runRuntimeLocalStatus(configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const state = new StateStore(`${config.runtime.stateDir}/state.json`).read();
  const budgets = readBudgetFile(config).budgets;
  printJson({
    ok: true,
    socket_path: config.runtime.socketPath,
    state_dir: config.runtime.stateDir,
    identity: state.agent?.registryAddress && state.agent?.tokenId ? "ready" : "missing",
    agentic_wallet: "optional",
    budgets: {
      active: budgets.filter((budget) => budget.status === "active").length,
    },
    plugins: pluginStatus("auto").runtimes,
    runtime_socket_present: fs.existsSync(config.runtime.socketPath),
    next_steps: ["regents runtime tools --json"],
  });
  return 0;
}

export async function runRuntimeLocalTools(): Promise<number> {
  printJson({
    ok: true,
    tools: REGENT_PLUGIN_TOOL_NAMES,
    note: "Use typed Regent plugin tools. Do not call raw shell for Regent wallet or payment work.",
    next_steps: ["regents runtime policy --json"],
  });
  return 0;
}

export async function runRuntimeLocalPolicy(configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const budgets = readBudgetFile(config).budgets;
  printJson({
    ok: true,
    budget_model: "Regent-mediated policy, not custody isolation.",
    wallet_model: "Regent identity wallet is separate from Agentic Wallet spend.",
    autolaunch_model: "Operator approval is required.",
    active_budget_count: budgets.filter((budget) => budget.status === "active").length,
    next_steps: [],
  });
  return 0;
}
