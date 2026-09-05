import fs from "node:fs";
import path from "node:path";

import YAML from "yaml";

import { expandHome } from "./paths.js";

export type RegentAgentRuntime = "hermes" | "openclaw";
export type RegentAgentRuntimeSelector = RegentAgentRuntime | "auto";

export interface PluginRuntimeStatus {
  runtime: RegentAgentRuntime;
  installed: boolean;
  pluginPath: string;
  skillsPath: string;
}

export interface PluginStatusReport {
  ok: true;
  runtimes: PluginRuntimeStatus[];
  selectedRuntime: RegentAgentRuntimeSelector;
}

export interface PluginInstallReport {
  ok: true;
  runtime: RegentAgentRuntime;
  pluginPath: string;
  skillsPath: string;
  files: string[];
  hermesXaiOAuth?: HermesXaiOAuthSetup;
}

export interface HermesXaiOAuthSetup {
  providerId: "xai-oauth";
  displayName: "xAI Grok OAuth (SuperGrok Subscription)";
  authType: "Browser OAuth 2.0 PKCE";
  transport: "codex_responses";
  defaultModel: "grok-4.3";
  baseUrl: "https://api.x.ai/v1";
  authServer: "https://accounts.x.ai";
  requiresEnvVar: false;
  configPath: string;
  loginCommand: "hermes auth add xai-oauth";
  remoteLoginCommand: "hermes auth add xai-oauth --no-browser";
  logoutCommand: "hermes auth logout xai-oauth";
  providerAliases: readonly ["xai-oauth", "grok-oauth", "x-ai-oauth", "xai-grok-oauth"];
}

const HERMES_XAI_OAUTH_SETUP = {
  providerId: "xai-oauth",
  displayName: "xAI Grok OAuth (SuperGrok Subscription)",
  authType: "Browser OAuth 2.0 PKCE",
  transport: "codex_responses",
  defaultModel: "grok-4.3",
  baseUrl: "https://api.x.ai/v1",
  authServer: "https://accounts.x.ai",
  requiresEnvVar: false,
  loginCommand: "hermes auth add xai-oauth",
  remoteLoginCommand: "hermes auth add xai-oauth --no-browser",
  logoutCommand: "hermes auth logout xai-oauth",
  providerAliases: ["xai-oauth", "grok-oauth", "x-ai-oauth", "xai-grok-oauth"],
} as const;

export const REGENT_PLUGIN_TOOL_NAMES = [
  "regent_status",
  "regent_setup_status",
  "regent_runtime_start",
  "regent_runtime_stop",
  "regent_identity_ensure",
  "regent_agent_graph",
  "regent_workspace_pair",
  "regent_budget_status",
  "regent_x402_pay_guarded",
  "regent_receipt_create",
  "regent_receipt_share_draft",
] as const;

const homePath = (...parts: string[]): string =>
  path.join(process.env.HOME ?? process.env.USERPROFILE ?? "~", ...parts);

const runtimePaths = (runtime: RegentAgentRuntime): { pluginPath: string; skillsPath: string } => {
  if (runtime === "hermes") {
    return {
      pluginPath: homePath(".hermes", "plugins", "regent"),
      skillsPath: homePath(".hermes", "plugins", "regent", "skills"),
    };
  }

  return {
    pluginPath: homePath(".openclaw", "plugins", "regent"),
    skillsPath: homePath(".openclaw", "plugins", "regent", "skills"),
  };
};

export const selectedRuntimes = (runtime: RegentAgentRuntimeSelector): RegentAgentRuntime[] =>
  runtime === "auto" ? ["hermes", "openclaw"] : [runtime];

export type DetectableRuntime = RegentAgentRuntime | "claude" | "codex";

export interface RuntimeDetection {
  runtime: DetectableRuntime;
  detected: boolean;
  integration: "plugin" | "mcp";
  evidence: string | null;
}

const binaryOnPath = (name: string): string | null => {
  const pathEntries = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
  for (const entry of pathEntries) {
    const candidate = path.join(entry, name);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {
      // keep scanning
    }
  }
  return null;
};

const detectByHomeDirOrBinary = (dirName: string, binaryName: string): string | null => {
  const home = path.resolve(expandHome(homePath(dirName)));
  if (fs.existsSync(home)) {
    return home;
  }
  return binaryOnPath(binaryName);
};

export const detectRuntimes = (): RuntimeDetection[] => {
  const entries: Array<{ runtime: DetectableRuntime; integration: "plugin" | "mcp"; evidence: string | null }> = [
    { runtime: "hermes", integration: "plugin", evidence: detectByHomeDirOrBinary(".hermes", "hermes") },
    { runtime: "openclaw", integration: "plugin", evidence: detectByHomeDirOrBinary(".openclaw", "openclaw") },
    { runtime: "claude", integration: "mcp", evidence: detectByHomeDirOrBinary(".claude", "claude") },
    { runtime: "codex", integration: "mcp", evidence: detectByHomeDirOrBinary(".codex", "codex") },
  ];

  return entries.map((entry) => ({
    runtime: entry.runtime,
    detected: entry.evidence !== null,
    integration: entry.integration,
    evidence: entry.evidence,
  }));
};

export const installableRuntimes = (runtime: RegentAgentRuntimeSelector): RegentAgentRuntime[] => {
  if (runtime !== "auto") {
    return [runtime];
  }

  return detectRuntimes()
    .filter((entry) => entry.integration === "plugin" && entry.detected)
    .map((entry) => entry.runtime as RegentAgentRuntime);
};

export const pluginStatus = (runtime: RegentAgentRuntimeSelector = "auto"): PluginStatusReport => ({
  ok: true,
  selectedRuntime: runtime,
  runtimes: selectedRuntimes(runtime).map((entry) => {
    const paths = runtimePaths(entry);
    const pluginPath = path.resolve(expandHome(paths.pluginPath));
    const skillsPath = path.resolve(expandHome(paths.skillsPath));

    return {
      runtime: entry,
      installed: fs.existsSync(path.join(pluginPath, entry === "hermes" ? "plugin.yaml" : "openclaw.plugin.json")),
      pluginPath,
      skillsPath,
    };
  }),
});

export const installPlugin = (runtime: RegentAgentRuntime): PluginInstallReport => {
  const paths = runtimePaths(runtime);
  const pluginPath = path.resolve(expandHome(paths.pluginPath));
  const skillsPath = path.resolve(expandHome(paths.skillsPath));
  const files: string[] = [];

  fs.mkdirSync(skillsPath, { recursive: true });

  let hermesXaiOAuth: HermesXaiOAuthSetup | undefined;

  if (runtime === "hermes") {
    writeFile(path.join(pluginPath, "plugin.yaml"), hermesPluginYaml(), files);
    writeFile(path.join(pluginPath, "__init__.py"), hermesInitPy(), files);
    writeFile(path.join(pluginPath, "tools.py"), hermesToolsPy(), files);
    hermesXaiOAuth = writeHermesXaiOAuthSetup(pluginPath, files);
  } else {
    writeFile(path.join(pluginPath, "openclaw.plugin.json"), openclawPluginJson(), files);
    writeFile(path.join(pluginPath, "index.js"), openclawIndexJs(), files);
  }

  for (const skill of regentSkills()) {
    writeFile(path.join(skillsPath, skill.name, "SKILL.md"), skill.body, files);
  }

  return { ok: true, runtime, pluginPath, skillsPath, files, ...(hermesXaiOAuth ? { hermesXaiOAuth } : {}) };
};

const writeFile = (filePath: string, body: string, files: string[]): void => {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, body, "utf8");
  files.push(filePath);
};

const writeHermesXaiOAuthSetup = (pluginPath: string, files: string[]): HermesXaiOAuthSetup => {
  const configPath = path.resolve(expandHome(homePath(".hermes", "config.yaml")));
  const existing = readHermesConfig(configPath);
  const existingModel = isPlainObject(existing.model) ? existing.model : {};
  const nextConfig = {
    ...existing,
    model: {
      ...existingModel,
      default: HERMES_XAI_OAUTH_SETUP.defaultModel,
      provider: HERMES_XAI_OAUTH_SETUP.providerId,
      base_url: HERMES_XAI_OAUTH_SETUP.baseUrl,
    },
  };

  writeFile(configPath, YAML.stringify(nextConfig), files);
  writeFile(path.join(pluginPath, "xai-grok-oauth.md"), hermesXaiOAuthGuide(configPath), files);

  return {
    ...HERMES_XAI_OAUTH_SETUP,
    configPath,
  };
};

const readHermesConfig = (configPath: string): Record<string, unknown> => {
  if (!fs.existsSync(configPath)) {
    return {};
  }

  const parsed = YAML.parse(fs.readFileSync(configPath, "utf8")) as unknown;

  if (parsed == null) {
    return {};
  }

  if (!isPlainObject(parsed)) {
    throw new Error(`Hermes config must be a YAML object: ${configPath}`);
  }

  return parsed;
};

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const hermesXaiOAuthGuide = (configPath: string): string => `# xAI Grok OAuth For Hermes

Regent configures Hermes to use xAI Grok OAuth with a SuperGrok subscription.

## Sign in

\`\`\`sh
${HERMES_XAI_OAUTH_SETUP.loginCommand}
\`\`\`

## Remote sign-in

Forward the callback port from your local machine, then start the no-browser login in the remote session.

\`\`\`sh
ssh -N -L 56121:127.0.0.1:56121 user@remote-host
${HERMES_XAI_OAUTH_SETUP.remoteLoginCommand}
\`\`\`

## Defaults

- Provider: ${HERMES_XAI_OAUTH_SETUP.providerId}
- Model: ${HERMES_XAI_OAUTH_SETUP.defaultModel}
- Endpoint: ${HERMES_XAI_OAUTH_SETUP.baseUrl}
- Sign-in server: ${HERMES_XAI_OAUTH_SETUP.authServer}
- Config file: ${configPath}

Hermes stores tokens in ~/.hermes/auth.json. Do not copy tokens into project files.
`;

const hermesPluginYaml = (): string => `name: regent
version: 0.3.0
description: Typed Regent bridge for Hermes
provides_tools:
${REGENT_PLUGIN_TOOL_NAMES.map((name) => `  - ${name}`).join("\n")}
`;

const hermesInitPy = (): string => `from .tools import *  # noqa: F401,F403
`;

const hermesToolsPy = (): string => `"""Typed Regent bridge for Hermes.

This bridge exposes specific Regent actions. It does not accept raw shell,
raw regents command strings, raw awal, raw curl, or raw npx input.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from typing import Any, Dict, List

REGENTS_BIN = "regents"

ALLOWED: Dict[str, List[str]] = {
    "regent_status": ["status", "--json"],
    "regent_setup_status": ["plugin", "status", "--runtime", "auto", "--json"],
    "regent_runtime_start": ["run", "--json"],
    "regent_runtime_stop": ["runtime", "status", "--json"],
    "regent_identity_ensure": ["identity", "ensure", "--json"],
    "regent_agent_graph": ["identity", "graph", "--json"],
    "regent_workspace_pair": ["techtree", "notebooks", "pair", "--json"],
    "regent_budget_status": ["budget", "status", "--json"],
    "regent_x402_pay_guarded": ["x402", "pay"],
    "regent_receipt_create": ["receipt", "create", "--json"],
    "regent_receipt_share_draft": ["receipt", "share-draft", "--json"],
}


def _redact(value: Any) -> Any:
    if isinstance(value, dict):
        redacted: Dict[str, Any] = {}
        for key, entry in value.items():
            lowered = str(key).lower()
            if any(part in lowered for part in ["secret", "private", "token", "otp", "payment", "header"]):
                redacted[key] = "[redacted]"
            else:
                redacted[key] = _redact(entry)
        return redacted
    if isinstance(value, list):
        return [_redact(entry) for entry in value]
    return value


def _run(argv: List[str]) -> Dict[str, Any]:
    if shutil.which(REGENTS_BIN) is None:
        return {"ok": False, "error": "Regents CLI is not installed. Run npm install -g @regentslabs/cli."}
    proc = subprocess.run([REGENTS_BIN, *argv], capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        return {"ok": False, "error": proc.stderr.strip() or proc.stdout.strip()}
    return _redact(json.loads(proc.stdout))


def _start(argv: List[str]) -> Dict[str, Any]:
    if shutil.which(REGENTS_BIN) is None:
        return {"ok": False, "error": "Regents CLI is not installed. Run npm install -g @regentslabs/cli."}
    proc = subprocess.Popen(
        [REGENTS_BIN, *argv],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"ok": True, "pid": proc.pid, "command": [REGENTS_BIN, *argv]}


def regent_status(_: Dict[str, Any] | None = None) -> Dict[str, Any]:
    return _run(ALLOWED["regent_status"])


def regent_setup_status(_: Dict[str, Any] | None = None) -> Dict[str, Any]:
    return _run(ALLOWED["regent_setup_status"])


def regent_runtime_start(_: Dict[str, Any] | None = None) -> Dict[str, Any]:
    return _start(ALLOWED["regent_runtime_start"])


def regent_runtime_stop(_: Dict[str, Any] | None = None) -> Dict[str, Any]:
    return {"ok": False, "error": "Stop Regent from the terminal where regents run is active."}


def regent_identity_ensure(_: Dict[str, Any] | None = None) -> Dict[str, Any]:
    return _run(ALLOWED["regent_identity_ensure"])


def regent_agent_graph(_: Dict[str, Any] | None = None) -> Dict[str, Any]:
    return _run(ALLOWED["regent_agent_graph"])


def regent_workspace_pair(params: Dict[str, Any] | None = None) -> Dict[str, Any]:
    params = params or {}
    return _run([*ALLOWED["regent_workspace_pair"], "--workspace-path", str(params["workspace_path"])])


def regent_budget_status(params: Dict[str, Any] | None = None) -> Dict[str, Any]:
    params = params or {}
    argv = list(ALLOWED["regent_budget_status"])
    if params.get("budget_id"):
        argv.extend(["--budget", str(params["budget_id"])])
    if params.get("agent_id"):
        argv.extend(["--agent", str(params["agent_id"])])
    return _run(argv)


def regent_x402_pay_guarded(params: Dict[str, Any] | None = None) -> Dict[str, Any]:
    params = params or {}
    argv = [
        *ALLOWED["regent_x402_pay_guarded"],
        str(params["url"]),
        "--budget", str(params["budget_id"]),
        "--max-usdc", str(params["max_usdc"]),
        "--rail", str(params.get("rail") or "agentic-wallet"),
        "--json",
    ]
    if params.get("approve"):
        argv.append("--approve")
    if params.get("receipt"):
        argv.append("--receipt")
    return _run(argv)


def regent_receipt_create(params: Dict[str, Any] | None = None) -> Dict[str, Any]:
    params = params or {}
    argv = list(ALLOWED["regent_receipt_create"])
    if params.get("x402_payment_id"):
        argv.extend(["--from-x402-payment", str(params["x402_payment_id"])])
    elif params.get("budget_entry"):
        argv.extend(["--from-budget-entry", str(params["budget_entry"])])
    return _run(argv)


def regent_receipt_share_draft(params: Dict[str, Any] | None = None) -> Dict[str, Any]:
    params = params or {}
    return _run([*ALLOWED["regent_receipt_share_draft"], "--receipt", str(params["receipt_id"])])
`;

const openclawPluginJson = (): string => `${JSON.stringify({
  name: "regent",
  version: "0.3.0",
  description: "Typed Regent bridge for OpenClaw",
  tools: [...REGENT_PLUGIN_TOOL_NAMES],
}, null, 2)}
`;

const openclawIndexJs = (): string => `export const tools = {
  regent_status: ["status", "--json"],
  regent_setup_status: ["plugin", "status", "--runtime", "auto", "--json"],
  regent_runtime_start: ["run", "--json"],
  regent_runtime_stop: ["runtime", "status", "--json"],
  regent_identity_ensure: ["identity", "ensure", "--json"],
  regent_agent_graph: ["identity", "graph", "--json"],
  regent_workspace_pair: ["techtree", "notebooks", "pair", "--json"],
  regent_budget_status: ["budget", "status", "--json"],
  regent_x402_pay_guarded: ["x402", "pay"],
  regent_receipt_create: ["receipt", "create", "--json"],
  regent_receipt_share_draft: ["receipt", "share-draft", "--json"],
};
`;

const regentSkills = (): Array<{ name: string; body: string }> => [
  {
    name: "regent-runtime",
    body: `# Regent Runtime

Use Regent plugin tools. Do not run raw shell, raw regents, raw awal, raw curl, or raw npx.
Start with regent_setup_status, then regent_runtime_start.
`,
  },
  {
    name: "regent-notebooks",
    body: `# Regent Notebooks

Use regent_workspace_pair to pair an initialized marimo notebook workspace.
Keep paper notebooks tied to their arXiv or alphaXiv source when available.
`,
  },
  {
    name: "regent-wallet-budget",
    body: `# Regent Wallet Budget

Use Regent budget tools for spend checks. Do not call raw AWAL, raw wallet commands, or payment commands.
Budgets are Regent policy for this runtime, not a place to keep funds.
`,
  },
  {
    name: "regent-x402",
    body: `# Regent x402

Use regent_x402_pay_guarded for paid calls. Every payment needs a budget id and max USDC amount.
Do not bypass Regent budgets with raw curl, raw npx, raw AWAL, or raw shell.
`,
  },
  {
    name: "regent-receipts",
    body: `# Regent Receipts

Use regent_receipt_create and regent_receipt_share_draft after x402 or budget activity.
Share copy is a draft. Do not claim revenue unless the receipt proves recognized revenue.
`,
  },
];
