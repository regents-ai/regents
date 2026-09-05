import fs from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { captureOutput } from "../../../test-support/test-helpers.js";
import { defaultConfig } from "../src/internal-runtime/config.js";
import { setupCliEntrypointHarness } from "./helpers/cli-entrypoint-support.js";

const harness = setupCliEntrypointHarness();

describe("CLI config flows", () => {
  it("writes initial config and directories without exposing overwrite semantics", async () => {
    const initPath = path.join(harness.tempDir, "nested", "regent.config.json");
    const originalHome = process.env.HOME;
    process.env.HOME = harness.tempDir;

    try {
      const output = await captureOutput(async () =>
        harness.runCliEntrypoint(["init", "--config", initPath]),
      );
      const payload = JSON.parse(output.stdout) as {
        config_path: string;
        config_created: boolean;
        directories: {
          state: string;
          socket: string;
          wallet: string;
          gossipsub: string;
        };
      };
      const writtenConfig = JSON.parse(fs.readFileSync(initPath, "utf8")) as ReturnType<typeof defaultConfig>;

      expect(output.result).toBe(0);
      expect(fs.existsSync(payload.config_path)).toBe(true);
      expect(payload.config_created).toBe(true);
      expect(writtenConfig.runtime.stateDir).toBe(path.join(harness.tempDir, "nested", "state"));
      expect(writtenConfig.runtime.socketPath).toBe(path.join(harness.tempDir, "nested", "run", "regent.sock"));
      expect(writtenConfig.wallet.keystorePath).toBe(path.join(harness.tempDir, "nested", "keys", "agent-wallet.json"));
      expect(writtenConfig.gossipsub.peerIdPath).toBe(path.join(harness.tempDir, "nested", "p2p", "peer-id.json"));
      expect(writtenConfig.services.platform.baseUrl).toBe("https://regents.sh");
      expect(writtenConfig.services.autolaunch.baseUrl).toBe("https://regents.sh");
      expect(payload.directories.socket).toBe(path.dirname(writtenConfig.runtime.socketPath));
      expect(payload.directories.wallet).toBe(path.dirname(writtenConfig.wallet.keystorePath));
      expect(payload.directories.gossipsub).toBe(path.dirname(writtenConfig.gossipsub.peerIdPath));
      expect(Object.values(payload.directories).every((directory) => fs.existsSync(directory))).toBe(true);
    } finally {
      process.env.HOME = originalHome;
    }
  });

  it("does not overwrite an existing config file during init", async () => {
    const initPath = path.join(harness.tempDir, "existing", "regent.config.json");
    const existing = {
      runtime: {
        socketPath: path.join(harness.tempDir, "custom-runtime", "socket.sock"),
        stateDir: path.join(harness.tempDir, "custom-state"),
        logLevel: "debug",
      },
      services: {
        platform: {
          baseUrl: "http://127.0.0.1:4999",
          requestTimeoutMs: 2500,
        },
      },
    };
    fs.mkdirSync(path.dirname(initPath), { recursive: true });
    fs.writeFileSync(initPath, JSON.stringify(existing), "utf8");
    const originalContents = fs.readFileSync(initPath, "utf8");

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["init", "--config", initPath]),
    );

    expect(output.result).toBe(0);
    expect(JSON.parse(output.stdout)).toMatchObject({
      ok: true,
      command: "init",
      config_path: initPath,
      config_created: false,
      directories: {
        state: path.join(harness.tempDir, "custom-state"),
        socket: path.join(harness.tempDir, "custom-runtime"),
      },
    });
    expect(fs.readFileSync(initPath, "utf8")).toBe(originalContents);
  });

  it("reads the normalized effective config", async () => {
    fs.writeFileSync(
      harness.configPath,
      JSON.stringify({
        services: { platform: { baseUrl: "http://127.0.0.1:4100" } },
        runtime: { logLevel: "debug" },
      }),
      "utf8",
    );

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["config", "get", "--config", harness.configPath]),
    );
    const config = JSON.parse(output.stdout) as ReturnType<typeof defaultConfig>;

    expect(output.result).toBe(0);
    expect(config.runtime).toEqual({
      socketPath: path.join(harness.tempDir, "run", "regent.sock"),
      stateDir: path.join(harness.tempDir, "state"),
      logLevel: "debug",
    });
    expect(config.services.platform.baseUrl).toBe("http://127.0.0.1:4100");
    expect(config.services.autolaunch.baseUrl).toBe("https://regents.sh");
    expect(config.agents.harnesses.codex.profiles).toEqual(["owner", "public", "group"]);
  });

  it("writes a validated replacement config from --input @file.json", async () => {
    const inputPath = path.join(harness.tempDir, "replacement.json");
    const replacement = defaultConfig(harness.configPath);
    replacement.runtime.logLevel = "warn";
    replacement.services.platform.baseUrl = "http://127.0.0.1:4999";
    replacement.services.platform.requestTimeoutMs = 2500;
    fs.writeFileSync(inputPath, JSON.stringify(replacement), "utf8");

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["config", "write", "--config", harness.configPath, "--input", `@${inputPath}`]),
    );
    const payload = JSON.parse(output.stdout) as {
      ok: boolean;
      configPath: string;
      config: ReturnType<typeof defaultConfig>;
    };

    expect(output.result).toBe(0);
    expect(payload.ok).toBe(true);
    expect(payload.configPath).toBe(harness.configPath);
    expect(payload.config.runtime.logLevel).toBe("warn");
    expect(payload.config.services.platform).toEqual({
      baseUrl: "http://127.0.0.1:4999",
      requestTimeoutMs: 2500,
    });
    expect(JSON.parse(fs.readFileSync(harness.configPath, "utf8"))).toEqual(payload.config);
  });

  it("returns a JSON error when init cannot create the config parent directory", async () => {
    const blockingFile = path.join(harness.tempDir, "blocked-parent");
    fs.writeFileSync(blockingFile, "not-a-directory\n", "utf8");

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["init", "--config", path.join(blockingFile, "regent.config.json")]),
    );

    expect(output.result).toBe(1);
    expect(output.stdout).toBe("");
    expect(JSON.parse(output.stderr)).toEqual({
      error: {
        code: "command_failed",
        message: expect.stringMatching(/EEXIST|ENOTDIR/),
        next_steps: ["regents status"],
      },
    });
  });

  it("returns JSON errors when config write input is not @file syntax", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["config", "write", "--config", harness.configPath, "--input", "replacement.json"]),
    );

    expect(output.result).toBe(2);
    expect(JSON.parse(output.stderr)).toEqual({
      error: expect.objectContaining({
        code: "invalid_flag_value",
        message: "--input must use @/absolute/or/relative/path.json syntax",
        example: "--input @./replacement.json",
      }),
    });
  });
});
