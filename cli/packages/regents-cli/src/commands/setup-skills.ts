import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { getBooleanFlag, type ParsedCliArgs } from "../parse.js";
import { CLI_PALETTE, printJson, printText, renderPanel, tone } from "../printer.js";

const execFileAsync = promisify(execFile);

type SkillsInstallScope = "global" | "project";

export interface SkillsInstallerInput {
  readonly command: string;
  readonly args: readonly string[];
  readonly cwd: string;
  readonly env: NodeJS.ProcessEnv;
}

interface SkillsInstallerResult {
  readonly stdout: string;
  readonly stderr: string;
}

interface SetupSkillsDeps {
  readonly runInstaller?: (input: SkillsInstallerInput) => Promise<SkillsInstallerResult>;
  readonly skillsRoot?: string;
  readonly cwd?: string;
  readonly env?: NodeJS.ProcessEnv;
  readonly platform?: NodeJS.Platform;
}

interface SetupSkillsPayload {
  readonly ok: true;
  readonly command: "regents setup skills";
  readonly scope: SkillsInstallScope;
  readonly source: string;
  readonly skills: readonly string[];
  readonly installer: {
    readonly command: string;
    readonly args: readonly string[];
  };
  readonly next_steps: readonly string[];
}

const blockedEnvPrefixes = [
  "REGENT_",
  "CDP_",
  "COINBASE_",
  "PRIVY_",
  "SIWA_",
  "AUTOLAUNCH_",
  "TECHTREE_",
  "PLATFORM_",
] as const;

const allowedEnvNames = new Set([
  "PATH",
  "HOME",
  "USERPROFILE",
  "SYSTEMROOT",
  "APPDATA",
  "LOCALAPPDATA",
  "TMPDIR",
  "TEMP",
  "TMP",
  "TERM",
  "NO_COLOR",
  "CI",
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "NO_PROXY",
  "http_proxy",
  "https_proxy",
  "no_proxy",
]);

const defaultSkillsRoot = (): string =>
  path.resolve(fileURLToPath(new URL("../../skills", import.meta.url)));

const resolveNpxExecutable = (platform: NodeJS.Platform = process.platform): string =>
  platform === "win32" ? "npx.cmd" : "npx";

const isBlockedEnvName = (name: string): boolean =>
  blockedEnvPrefixes.some((prefix) => name.startsWith(prefix));

export const buildSkillsInstallerEnv = (baseEnv: NodeJS.ProcessEnv = process.env): NodeJS.ProcessEnv => {
  const env: NodeJS.ProcessEnv = {};

  for (const [name, value] of Object.entries(baseEnv)) {
    if (value === undefined || isBlockedEnvName(name) || !allowedEnvNames.has(name)) {
      continue;
    }

    env[name] = value;
  }

  return env;
};

const skillNameFromDirent = async (skillsRoot: string, name: string): Promise<string | undefined> => {
  const skillPath = path.join(skillsRoot, name, "SKILL.md");
  try {
    await fs.access(skillPath);
    return name;
  } catch {
    return undefined;
  }
};

export const listBundledSkills = async (skillsRoot: string = defaultSkillsRoot()): Promise<readonly string[]> => {
  const entries = await fs.readdir(skillsRoot, { withFileTypes: true });
  const skillNames = await Promise.all(
    entries
      .filter((entry) => entry.isDirectory())
      .map((entry) => skillNameFromDirent(skillsRoot, entry.name)),
  );

  return skillNames.filter((name): name is string => typeof name === "string").sort();
};

export const buildSkillsInstallCommand = (
  skillsRoot: string,
  scope: SkillsInstallScope,
  platform: NodeJS.Platform = process.platform,
): { readonly command: string; readonly args: readonly string[] } => ({
  command: resolveNpxExecutable(platform),
  args: [
    "-y",
    "skills",
    "add",
    skillsRoot,
    "--all",
    "--copy",
    "--full-depth",
    ...(scope === "global" ? ["--global"] : []),
  ],
});

const runSkillsInstaller = async (input: SkillsInstallerInput): Promise<SkillsInstallerResult> => {
  try {
    const result = await execFileAsync(input.command, [...input.args], {
      cwd: input.cwd,
      env: input.env,
      encoding: "utf8",
      windowsHide: true,
      maxBuffer: 1024 * 1024,
    });

    return {
      stdout: String(result.stdout),
      stderr: String(result.stderr),
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const stderr = typeof (error as { stderr?: unknown }).stderr === "string"
      ? (error as { stderr: string }).stderr.trim()
      : "";
    const detail = stderr ? `\n${stderr}` : "";

    throw new Error(`Could not install the Regents agent skills. Run the command again after npm is available.${detail || `\n${message}`}`);
  }
};

const renderSetupSkillsSummary = (payload: SetupSkillsPayload): string =>
  renderPanel(
    "◆ REGENTS AGENT SKILLS",
    [
      `${tone("installed", CLI_PALETTE.secondary)} ${tone(payload.skills.join(", "), CLI_PALETTE.primary, true)}`,
      `${tone("scope", CLI_PALETTE.secondary)} ${tone(payload.scope, CLI_PALETTE.primary, true)}`,
      `${tone("source", CLI_PALETTE.secondary)} ${tone(payload.source, CLI_PALETTE.primary)}`,
      "",
      `${tone("next", CLI_PALETTE.secondary)} ${tone(payload.next_steps[0] ?? "Open your agent client and use the Regents skills.", CLI_PALETTE.primary)}`,
    ],
    {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    },
  );

export async function runSetupSkills(
  args: ParsedCliArgs,
  deps: SetupSkillsDeps = {},
): Promise<void> {
  const scope: SkillsInstallScope = getBooleanFlag(args, "project") ? "project" : "global";
  const skillsRoot = path.resolve(deps.skillsRoot ?? defaultSkillsRoot());
  const skills = await listBundledSkills(skillsRoot);

  if (skills.length === 0) {
    throw new Error(`No bundled Regents agent skills were found at ${skillsRoot}.`);
  }

  const installer = buildSkillsInstallCommand(skillsRoot, scope, deps.platform);
  await (deps.runInstaller ?? runSkillsInstaller)({
    command: installer.command,
    args: installer.args,
    cwd: deps.cwd ?? process.cwd(),
    env: buildSkillsInstallerEnv(deps.env ?? process.env),
  });

  const payload: SetupSkillsPayload = {
    ok: true,
    command: "regents setup skills",
    scope,
    source: skillsRoot,
    skills,
    installer,
    next_steps: [
      "Open your agent client and use the Regents, Platform, Autolaunch, and Techtree skills.",
      "Run `regents agent-context` when an agent needs the current command surface.",
    ],
  };

  if (getBooleanFlag(args, "json")) {
    printJson(payload);
    return;
  }

  printText(renderSetupSkillsSummary(payload));
}
