import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

import { expandHome } from "./paths.js";

export type McpRuntime = "claude" | "codex";

export interface McpRegistration {
  runtime: McpRuntime;
  status: "registered" | "already_registered" | "failed";
  detail: string;
}

const homePath = (...parts: string[]): string =>
  path.join(process.env.HOME ?? process.env.USERPROFILE ?? "~", ...parts);

const MCP_SERVER_NAME = "regents";
const MCP_SERVE_ARGS = ["mcp", "serve", "--transport", "stdio"];

const runClaude = (args: string[]): { ok: boolean; output: string } => {
  const result = spawnSync("claude", args, { encoding: "utf8", timeout: 30_000 });
  if (result.error) {
    return { ok: false, output: result.error.message };
  }
  return {
    ok: result.status === 0,
    output: `${result.stdout ?? ""}${result.stderr ?? ""}`.trim(),
  };
};

export const registerClaudeMcp = (): McpRegistration => {
  const existing = runClaude(["mcp", "get", MCP_SERVER_NAME]);
  if (existing.ok) {
    return {
      runtime: "claude",
      status: "already_registered",
      detail: "Claude Code already has the regents MCP server.",
    };
  }

  const added = runClaude([
    "mcp",
    "add",
    "--scope",
    "user",
    MCP_SERVER_NAME,
    "--",
    "regents",
    ...MCP_SERVE_ARGS,
  ]);

  if (added.ok) {
    return {
      runtime: "claude",
      status: "registered",
      detail: "Registered the regents MCP server with Claude Code (user scope).",
    };
  }

  return {
    runtime: "claude",
    status: "failed",
    detail: added.output || "claude mcp add failed.",
  };
};

const CODEX_BLOCK = `
[mcp_servers.${MCP_SERVER_NAME}]
command = "regents"
args = ["${MCP_SERVE_ARGS.join('", "')}"]
`;

export const codexConfigPath = (): string =>
  path.resolve(expandHome(homePath(".codex", "config.toml")));

export const registerCodexMcp = (): McpRegistration => {
  const configPath = codexConfigPath();

  try {
    const current = fs.existsSync(configPath) ? fs.readFileSync(configPath, "utf8") : "";

    if (current.includes(`[mcp_servers.${MCP_SERVER_NAME}]`)) {
      return {
        runtime: "codex",
        status: "already_registered",
        detail: "Codex config already has the regents MCP server.",
      };
    }

    fs.mkdirSync(path.dirname(configPath), { recursive: true });
    const separator = current.length > 0 && !current.endsWith("\n") ? "\n" : "";
    fs.writeFileSync(configPath, `${current}${separator}${CODEX_BLOCK}`);

    return {
      runtime: "codex",
      status: "registered",
      detail: `Added the regents MCP server to ${configPath}.`,
    };
  } catch (error) {
    return {
      runtime: "codex",
      status: "failed",
      detail: error instanceof Error ? error.message : String(error),
    };
  }
};
