import fs from "node:fs";
import path from "node:path";

import { CliUsageError } from "../cli-usage-error.js";
import {
  CLI_COMMANDS,
  CLI_COMMANDS_BY_TOP_LEVEL_GROUP,
  CLI_COMMAND_DETAILS_BY_COMMAND,
} from "../generated/cli-command-metadata.js";
import type { RegentConfig } from "../internal-types/index.js";
import { loadConfig } from "../internal-runtime/config.js";
import { defaultConfigPath, expandHome } from "../internal-runtime/paths.js";
import { getFlag, type ParsedCliArgs } from "../parse.js";

interface PackageMetadata {
  readonly name: string;
  readonly version: string;
}

interface AgentContextPayload {
  readonly schema_version: string;
  readonly package: PackageMetadata;
  readonly command_count: number;
  readonly command_groups: Readonly<Record<string, readonly string[]>>;
  readonly commands: Readonly<Record<string, unknown>>;
  readonly profile: ReturnType<typeof safeConfigSummary>;
  readonly conventions: {
    readonly json_flag: string;
    readonly no_input_flag: string;
    readonly value_movement: string;
    readonly aliases: string;
  };
}

const resolveConfigPath = (configPath?: string): string => {
  const expanded = expandHome(configPath ?? defaultConfigPath());
  return path.isAbsolute(expanded) ? path.normalize(expanded) : path.resolve(process.cwd(), expanded);
};

const readPackageMetadata = (): PackageMetadata => {
  try {
    const parsed = JSON.parse(
      fs.readFileSync(new URL("../../package.json", import.meta.url), "utf8"),
    ) as Partial<PackageMetadata>;
    return {
      name: typeof parsed.name === "string" ? parsed.name : "@regentslabs/cli",
      version: typeof parsed.version === "string" ? parsed.version : "0.0.0",
    };
  } catch {
    return {
      name: "@regentslabs/cli",
      version: "0.0.0",
    };
  }
};

const safeHarnesses = (config: RegentConfig) =>
  Object.fromEntries(
    Object.entries(config.agents.harnesses).map(([name, harness]) => [
      name,
      {
        enabled: harness.enabled,
        entrypoint: harness.entrypoint,
        workspace_root: harness.workspaceRoot,
        profiles: harness.profiles,
      },
    ]),
  );

const availableProfiles = (config: RegentConfig): readonly string[] =>
  Array.from(
    new Set(Object.values(config.agents.harnesses).flatMap((harness) => harness.profiles)),
  ).sort();

const safeConfigSummary = (configPath?: string) => {
  const resolvedConfigPath = resolveConfigPath(configPath);
  const configPresent = fs.existsSync(resolvedConfigPath);
  const config = loadConfig(resolvedConfigPath);

  return {
    config_path: resolvedConfigPath,
    config_present: configPresent,
    auth: {
      audience: config.auth.audience,
      default_chain_id: config.auth.defaultChainId,
    },
    services: Object.fromEntries(
      Object.entries(config.services).map(([name, service]) => [
        name,
        {
          base_url: service.baseUrl,
          request_timeout_ms: service.requestTimeoutMs,
        },
      ]),
    ),
    runtime: {
      state_dir: config.runtime.stateDir,
      socket_path: config.runtime.socketPath,
      log_level: config.runtime.logLevel,
    },
    wallet: {
      private_key_env: config.wallet.privateKeyEnv,
      keystore_configured: Boolean(config.wallet.keystorePath),
    },
    agents: {
      default_harness: config.agents.defaultHarness,
      harnesses: safeHarnesses(config),
    },
    available_profiles: availableProfiles(config),
  };
};

export interface AgentContextFilters {
  readonly area?: string;
  readonly command?: string;
}

const allCommandGroups = CLI_COMMANDS_BY_TOP_LEVEL_GROUP as unknown as Readonly<
  Record<string, readonly string[]>
>;
const allCommandDetails = CLI_COMMAND_DETAILS_BY_COMMAND as unknown as Readonly<
  Record<string, unknown>
>;

const filteredCommandNames = (filters: AgentContextFilters): readonly string[] => {
  if (filters.command !== undefined) {
    if (!(filters.command in allCommandDetails)) {
      throw new CliUsageError({
        code: "unknown_command",
        message: `No shipped command matches: ${filters.command}`,
        command: "regents agent-context",
        usage: 'regents agent-context [--area <name>] [--command "<command>"]',
        example: 'regents agent-context --command "techtree notebooks init"',
      });
    }

    return [filters.command];
  }

  if (filters.area !== undefined) {
    const areaCommands = allCommandGroups[filters.area];
    if (!areaCommands) {
      throw new CliUsageError({
        code: "invalid_flag_value",
        message: `Unknown area: ${filters.area}`,
        command: "regents agent-context",
        usage: 'regents agent-context [--area <name>] [--command "<command>"]',
        validValues: Object.keys(allCommandGroups),
        example: "regents agent-context --area techtree",
      });
    }

    return areaCommands;
  }

  return CLI_COMMANDS;
};

export const buildAgentContext = (
  configPath?: string,
  filters: AgentContextFilters = {},
): AgentContextPayload => {
  const commandNames = filteredCommandNames(filters);
  const commandNameSet = new Set(commandNames);
  const commandGroups = Object.fromEntries(
    Object.entries(allCommandGroups)
      .map(([groupName, groupCommands]) => [
        groupName,
        groupCommands.filter((command) => commandNameSet.has(command)),
      ])
      .filter(([, groupCommands]) => groupCommands.length > 0),
  );
  const commands = Object.fromEntries(
    commandNames.map((command) => [command, allCommandDetails[command]]),
  );

  return {
    schema_version: "1",
    package: readPackageMetadata(),
    command_count: commandNames.length,
    command_groups: commandGroups,
    commands,
    profile: safeConfigSummary(configPath),
    conventions: {
      json_flag: "--json",
      no_input_flag: "--no-input",
      value_movement: "prepare first; submit only with --submit",
      aliases: "none",
    },
  };
};

export async function runAgentContext(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const filters: AgentContextFilters = {
    area: getFlag(args, "area"),
    command: getFlag(args, "command"),
  };
  process.stdout.write(`${JSON.stringify(buildAgentContext(configPath, filters), null, 2)}\n`);
}
