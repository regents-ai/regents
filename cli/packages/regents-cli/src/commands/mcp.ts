import type { ParsedCliArgs } from "../parse.js";

import { CliUsageError } from "../cli-usage-error.js";
import { RegentKernel } from "../internal-runtime/runtime.js";
import { runRegentsMcpHttp } from "../mcp/http.js";
import { runRegentsMcpStdio } from "../mcp/stdio.js";
import { regentsMcpToolsList } from "../mcp/tool-registry.js";
import { getFlag, parseIntegerFlag } from "../parse.js";
import { printJson } from "../printer.js";

export async function runMcpServe(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const transport = getFlag(args, "transport") ?? "stdio";

  if (transport === "stdio") {
    await runRegentsMcpStdio(configPath);
    return 0;
  }

  if (transport === "streamable-http") {
    await runRegentsMcpHttp({
      configPath,
      host: getFlag(args, "host") ?? "127.0.0.1",
      port: parseIntegerFlag(args, "port") ?? 7347,
      bearerToken: process.env.REGENTS_MCP_TOKEN ?? "",
    });
    return 0;
  }

  throw new CliUsageError({
    code: "unsupported_mcp_transport",
    message: "Regents MCP serve supports --transport stdio or --transport streamable-http.",
  });
}

export async function runMcpToolsList(): Promise<number> {
  printJson(regentsMcpToolsList());
  return 0;
}

export async function runMcpDoctor(_args: ParsedCliArgs, configPath?: string): Promise<number> {
  const kernel = new RegentKernel(configPath);

  printJson({
    ok: true,
    transport: {
      stdio: true,
      streamable_http: true,
    },
    submit_tools_enabled: false,
    config: {
      state_dir: kernel.config.runtime.stateDir,
      socket_path: kernel.config.runtime.socketPath,
      platform_base_url: kernel.config.services.platform.baseUrl,
    },
    tools: regentsMcpToolsList().tools,
  });

  await kernel.stop();
  return 0;
}

export async function runMcpExportCodex(): Promise<number> {
  printJson({
    ok: true,
    mcpServers: {
      regents: {
        command: "npx",
        args: [
          "-y",
          "@regentslabs/cli@latest",
          "mcp",
          "serve",
          "--transport",
          "stdio",
        ],
        env_vars: ["REGENT_WALLET_PRIVATE_KEY"],
        startup_timeout_sec: 20,
        tool_timeout_sec: 120,
        enabled: true,
      },
    },
  });
  return 0;
}
