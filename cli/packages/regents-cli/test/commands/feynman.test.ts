import { EventEmitter } from "node:events";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  buildFeynmanChildEnv,
  feynmanArgsFromRawArgs,
  runFeynman,
  type FeynmanSpawnOptions,
  type SpawnedFeynmanProcess,
} from "../../src/commands/feynman.js";
import { runCliEntrypoint } from "../../src/index.js";

const originalPath = process.env.PATH;
const tempDirs: string[] = [];

afterEach(() => {
  if (originalPath === undefined) {
    delete process.env.PATH;
  } else {
    process.env.PATH = originalPath;
  }

  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

const closingSpawner = (
  code: number | null,
  signal: NodeJS.Signals | null = null,
) =>
  vi.fn((_: string, __: string[], ___: FeynmanSpawnOptions): SpawnedFeynmanProcess => {
    const child = new EventEmitter() as SpawnedFeynmanProcess;
    queueMicrotask(() => child.emit("close", code, signal));
    return child;
  });

const errorSpawner = (error: NodeJS.ErrnoException) =>
  vi.fn((_: string, __: string[], ___: FeynmanSpawnOptions): SpawnedFeynmanProcess => {
    const child = new EventEmitter() as SpawnedFeynmanProcess;
    queueMicrotask(() => child.emit("error", error));
    return child;
  });

const createFakeFeynmanOnPath = (): void => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-feynman-test-"));
  tempDirs.push(dir);

  const jsPath = path.join(dir, "feynman.js");
  fs.writeFileSync(
    jsPath,
    [
      "#!/usr/bin/env node",
      "const args = process.argv.slice(2);",
      "process.exit(args.length === 1 && args[0] === '--help' ? 17 : 19);",
      "",
    ].join("\n"),
  );

  if (process.platform === "win32") {
    fs.writeFileSync(path.join(dir, "feynman.cmd"), `@echo off\r\nnode "%~dp0\\feynman.js" %*\r\n`);
  } else {
    const executablePath = path.join(dir, "feynman");
    fs.writeFileSync(executablePath, `#!/usr/bin/env sh\nexec node "${jsPath}" "$@"\n`);
    fs.chmodSync(executablePath, 0o755);
  }

  process.env.PATH = `${dir}${path.delimiter}${originalPath ?? ""}`;
};

describe("feynman command wrapper", () => {
  it("passes Feynman arguments through unchanged", async () => {
    const spawnFeynman = closingSpawner(0);

    await expect(
      runFeynman(["doctor"], {
        spawnFeynman,
        cwd: "/tmp/research",
        dotenvConfigPath: "/tmp/regents-feynman-empty.env",
        env: {
          PATH: "/usr/bin",
          FEYNMAN_MODEL: "provider/model",
          REGENT_WALLET_PRIVATE_KEY: "secret",
        },
      }),
    ).resolves.toBe(0);

    expect(spawnFeynman).toHaveBeenCalledWith(
      "feynman",
      ["doctor"],
      expect.objectContaining({
        cwd: "/tmp/research",
        stdio: "inherit",
        shell: false,
        windowsHide: false,
        env: expect.objectContaining({
          PATH: "/usr/bin",
          FEYNMAN_MODEL: "provider/model",
          DOTENV_CONFIG_PATH: "/tmp/regents-feynman-empty.env",
          DOTENV_CONFIG_QUIET: "true",
        }),
      }),
    );

    const options = spawnFeynman.mock.calls[0]?.[2];
    expect(options?.env.REGENT_WALLET_PRIVATE_KEY).toBeUndefined();
  });

  it("returns child exit codes and terminal signal codes", async () => {
    await expect(runFeynman(["status"], { spawnFeynman: closingSpawner(42) })).resolves.toBe(42);
    await expect(runFeynman(["status"], { spawnFeynman: closingSpawner(null, "SIGINT") })).resolves.toBe(130);
    await expect(runFeynman(["status"], { spawnFeynman: closingSpawner(null, "SIGTERM") })).resolves.toBe(143);
  });

  it("shows a clear error when Feynman is not installed", async () => {
    const missing = Object.assign(new Error("spawn feynman ENOENT"), { code: "ENOENT" });

    await expect(runFeynman(["doctor"], { spawnFeynman: errorSpawner(missing) })).rejects.toMatchObject({
      code: "feynman_not_found",
      message: expect.stringContaining("The feynman command is not installed."),
    });
  });

  it("filters Regent local secrets and blocks project env loading", () => {
    const env = buildFeynmanChildEnv(
      {
        PATH: "/usr/bin",
        TERM: "xterm-256color",
        FEYNMAN_MODEL: "provider/model",
        REGENT_PLATFORM_ORIGIN: "https://platform.example",
        REGENT_WALLET_PRIVATE_KEY: "secret",
        CDP_KEY_SECRET: "secret",
        COINBASE_API_TOKEN: "secret",
      },
      "/tmp/empty-feynman.env",
    );

    expect(env.PATH).toBe("/usr/bin");
    expect(env.TERM).toBe("xterm-256color");
    expect(env.FEYNMAN_MODEL).toBe("provider/model");
    expect(env.DOTENV_CONFIG_PATH).toBe("/tmp/empty-feynman.env");
    expect(env.DOTENV_CONFIG_QUIET).toBe("true");
    expect(env.REGENT_PLATFORM_ORIGIN).toBeUndefined();
    expect(env.REGENT_WALLET_PRIVATE_KEY).toBeUndefined();
    expect(env.CDP_KEY_SECRET).toBeUndefined();
    expect(env.COINBASE_API_TOKEN).toBeUndefined();
  });

  it("extracts the exact arguments after the feynman command", () => {
    expect(feynmanArgsFromRawArgs(["feynman", "chat", "explain this paper"])).toEqual([
      "chat",
      "explain this paper",
    ]);
    expect(feynmanArgsFromRawArgs(["--config", "/tmp/regent.json", "feynman", "--help"])).toEqual([
      "--help",
    ]);
    expect(feynmanArgsFromRawArgs(["feynman", "--", "--help"])).toEqual(["--", "--help"]);
  });

  it("passes feynman --help to Feynman instead of Regent help", async () => {
    createFakeFeynmanOnPath();

    await expect(runCliEntrypoint(["feynman", "--help"])).resolves.toBe(17);
  });
});
