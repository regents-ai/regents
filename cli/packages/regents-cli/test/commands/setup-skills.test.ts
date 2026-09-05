import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { parseCliArgs } from "../../src/parse.js";
import {
  buildSkillsInstallCommand,
  buildSkillsInstallerEnv,
  listBundledSkills,
  runSetupSkills,
  type SkillsInstallerInput,
} from "../../src/commands/setup-skills.js";
import { captureOutput } from "../../../../test-support/test-helpers.js";

const tempDirs: string[] = [];

const makeSkillRoot = async (): Promise<string> => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "regents-skills-test-"));
  tempDirs.push(root);

  await fs.mkdir(path.join(root, "regents"));
  await fs.writeFile(path.join(root, "regents", "SKILL.md"), "---\nname: regents\n---\n");
  await fs.mkdir(path.join(root, "regents-autolaunch"));
  await fs.writeFile(path.join(root, "regents-autolaunch", "SKILL.md"), "---\nname: regents-autolaunch\n---\n");
  await fs.mkdir(path.join(root, "notes"));
  await fs.writeFile(path.join(root, "notes", "README.md"), "not a skill\n");

  return root;
};

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("setup skills command", () => {
  it("lists only bundled skill directories", async () => {
    const skillsRoot = await makeSkillRoot();

    await expect(listBundledSkills(skillsRoot)).resolves.toEqual([
      "regents",
      "regents-autolaunch",
    ]);
  });

  it("builds the global Agent Skills install command", () => {
    expect(buildSkillsInstallCommand("/tmp/regent-skills", "global", "darwin")).toEqual({
      command: "npx",
      args: [
        "-y",
        "skills",
        "add",
        "/tmp/regent-skills",
        "--all",
        "--copy",
        "--full-depth",
        "--global",
      ],
    });
  });

  it("installs the bundled skills globally by default and prints JSON when requested", async () => {
    const skillsRoot = await makeSkillRoot();
    let installerInput: SkillsInstallerInput | undefined;

    const output = await captureOutput(() =>
      runSetupSkills(parseCliArgs(["--json"]), {
        skillsRoot,
        cwd: "/tmp/research",
        env: {
          PATH: "/usr/bin",
          HOME: "/Users/example",
          REGENT_WALLET_PRIVATE_KEY: "secret",
          TECHTREE_API_TOKEN: "secret",
        },
        runInstaller: async (input) => {
          installerInput = input;
          return { stdout: "ignored", stderr: "" };
        },
      }),
    );

    expect(output.stderr).toBe("");
    expect(installerInput).toMatchObject({
      command: "npx",
      args: expect.arrayContaining(["skills", "add", skillsRoot, "--global", "--all", "--copy"]),
      cwd: "/tmp/research",
      env: {
        PATH: "/usr/bin",
        HOME: "/Users/example",
      },
    });
    expect(installerInput?.env.REGENT_WALLET_PRIVATE_KEY).toBeUndefined();
    expect(installerInput?.env.TECHTREE_API_TOKEN).toBeUndefined();

    const payload = JSON.parse(output.stdout) as {
      scope: string;
      skills: readonly string[];
      source: string;
      next_steps: readonly string[];
    };
    expect(payload.scope).toBe("global");
    expect(payload.source).toBe(skillsRoot);
    expect(payload.skills).toEqual(["regents", "regents-autolaunch"]);
    expect(payload.next_steps[0]).toContain("Open your agent client");
  });

  it("supports project-local skill installation", async () => {
    const skillsRoot = await makeSkillRoot();
    let installerInput: SkillsInstallerInput | undefined;

    await captureOutput(() =>
      runSetupSkills(parseCliArgs(["--project"]), {
        skillsRoot,
        runInstaller: async (input) => {
          installerInput = input;
          return { stdout: "", stderr: "" };
        },
      }),
    );

    expect(installerInput?.args).not.toContain("--global");
  });

  it("keeps only safe environment values for the installer", () => {
    const env = buildSkillsInstallerEnv({
      PATH: "/usr/bin",
      HOME: "/Users/example",
      HTTPS_PROXY: "http://proxy.example",
      npm_config_token: "secret",
      REGENT_WALLET_PRIVATE_KEY: "secret",
      CDP_KEY_SECRET: "secret",
      TECHTREE_API_TOKEN: "secret",
    });

    expect(env.PATH).toBe("/usr/bin");
    expect(env.HOME).toBe("/Users/example");
    expect(env.HTTPS_PROXY).toBe("http://proxy.example");
    expect(env.npm_config_token).toBeUndefined();
    expect(env.REGENT_WALLET_PRIVATE_KEY).toBeUndefined();
    expect(env.CDP_KEY_SECRET).toBeUndefined();
    expect(env.TECHTREE_API_TOKEN).toBeUndefined();
  });
});
