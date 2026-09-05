import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";

import { RegentError } from "../internal-runtime/index.js";

export interface SpawnedFeynmanProcess {
  once(event: "error", listener: (error: NodeJS.ErrnoException) => void): this;
  once(event: "close", listener: (code: number | null, signal: NodeJS.Signals | null) => void): this;
}

export interface FeynmanSpawnOptions {
  cwd: string;
  env: NodeJS.ProcessEnv;
  stdio: "inherit";
  shell: false;
  windowsHide: false;
}

export type FeynmanSpawner = (
  command: string,
  args: string[],
  options: FeynmanSpawnOptions,
) => SpawnedFeynmanProcess;

interface FeynmanRunnerDeps {
  readonly spawnFeynman?: FeynmanSpawner;
  readonly cwd?: string;
  readonly env?: NodeJS.ProcessEnv;
  readonly dotenvConfigPath?: string;
  readonly platform?: NodeJS.Platform;
}

const blockedRegentEnvPrefixes = [
  "REGENT_",
  "CDP_",
  "COINBASE_",
  "PRIVY_",
  "SIWA_",
  "AUTOLAUNCH_",
  "TECHTREE_",
  "PLATFORM_",
] as const;

const feynmanInstallMessage = [
  "The feynman command is not installed.",
  "Install it with `npm install -g @companion-ai/feynman`, then run `regents feynman setup`.",
].join("\n");

const spawnExternalFeynman: FeynmanSpawner = (command, args, options) =>
  spawn(command, args, options) as SpawnedFeynmanProcess;

export const resolveFeynmanExecutable = (platform: NodeJS.Platform = process.platform): string =>
  platform === "win32" ? "feynman.cmd" : "feynman";

const safeDotenvConfigPath = (): string =>
  path.join(tmpdir(), `regents-feynman-empty-${process.pid}.env`);

const isBlockedRegentEnvName = (name: string): boolean =>
  blockedRegentEnvPrefixes.some((prefix) => name.startsWith(prefix));

export const buildFeynmanChildEnv = (
  baseEnv: NodeJS.ProcessEnv = process.env,
  dotenvConfigPath: string = safeDotenvConfigPath(),
): NodeJS.ProcessEnv => {
  const env: NodeJS.ProcessEnv = {};

  for (const [name, value] of Object.entries(baseEnv)) {
    if (value === undefined || isBlockedRegentEnvName(name)) {
      continue;
    }

    env[name] = value;
  }

  env.DOTENV_CONFIG_PATH = dotenvConfigPath;
  env.DOTENV_CONFIG_QUIET = "true";
  return env;
};

export const feynmanArgsFromRawArgs = (rawArgs: readonly string[]): string[] => {
  for (let index = 0; index < rawArgs.length; index += 1) {
    const token = rawArgs[index];
    if (token === undefined) {
      continue;
    }

    if (token === "--") {
      const feynmanIndex = rawArgs.slice(index + 1).indexOf("feynman");
      return feynmanIndex >= 0 ? rawArgs.slice(index + feynmanIndex + 2) : [];
    }

    if (token.startsWith("--")) {
      const next = rawArgs[index + 1];
      if (!token.includes("=") && next !== undefined && !next.startsWith("--")) {
        index += 1;
      }
      continue;
    }

    if (token === "feynman") {
      return rawArgs.slice(index + 1);
    }
  }

  return [];
};

export const feynmanCloseExitCode = (
  code: number | null,
  signal: NodeJS.Signals | null,
): number => {
  if (typeof code === "number") {
    return code;
  }

  if (signal === "SIGINT") {
    return 130;
  }

  if (signal === "SIGTERM") {
    return 143;
  }

  return 1;
};

const isMissingFeynmanError = (error: NodeJS.ErrnoException): boolean =>
  error.code === "ENOENT";

export const runFeynman = async (
  args: readonly string[],
  deps: FeynmanRunnerDeps = {},
): Promise<number> =>
  new Promise((resolve, reject) => {
    const child = (deps.spawnFeynman ?? spawnExternalFeynman)(
      resolveFeynmanExecutable(deps.platform),
      [...args],
      {
        cwd: deps.cwd ?? process.cwd(),
        env: buildFeynmanChildEnv(deps.env ?? process.env, deps.dotenvConfigPath),
        stdio: "inherit",
        shell: false,
        windowsHide: false,
      },
    );
    let settled = false;

    child.once("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      reject(
        isMissingFeynmanError(error)
          ? new RegentError("feynman_not_found", feynmanInstallMessage, error)
          : error,
      );
    });

    child.once("close", (code, signal) => {
      if (settled) {
        return;
      }
      settled = true;
      resolve(feynmanCloseExitCode(code, signal));
    });
  });
