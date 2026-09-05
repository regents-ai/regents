import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  defaultConfig,
  loadConfig,
  SERVICE_BASE_URL_ERROR,
  writeConfigReplacement,
  writeInitialConfig,
  writeInitialConfigIfMissing,
} from "../../src/internal-runtime/config.js";

describe("config loading", () => {
  it("returns config-relative defaults when a custom config file is missing", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-missing-config-"));
    const configPath = path.join(tempDir, "regent.config.json");
    const config = loadConfig(configPath);

    expect(config.auth).toEqual({ audience: "techtree", defaultChainId: 8453 });
    expect(config.runtime.stateDir).toBe(path.join(tempDir, "state"));
    expect(config.runtime.socketPath).toBe(path.join(tempDir, "run", "regent.sock"));
    expect(config.wallet.keystorePath).toBe(path.join(tempDir, "keys", "agent-wallet.json"));
    expect(config.gossipsub.peerIdPath).toBe(path.join(tempDir, "p2p", "peer-id.json"));
    expect(config.services.platform.baseUrl).toBe("https://regents.sh");
    expect(config.services.autolaunch.baseUrl).toBe("https://regents.sh");
  });

  it("merges partial config with defaults and normalizes paths", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-"));
    const configPath = path.join(tempDir, "config.json");

    fs.writeFileSync(
      configPath,
      JSON.stringify({
        services: {
          platform: {
            baseUrl: "http://127.0.0.1:4100",
          },
        },
        runtime: {
          logLevel: "debug",
        },
      }),
      "utf8",
    );

    const config = loadConfig(configPath);

    expect(config.services.platform.baseUrl).toBe("http://127.0.0.1:4100");
    expect(config.services.siwa.baseUrl).toBe("https://siwa-server.fly.dev");
    expect(config.runtime.logLevel).toBe("debug");
    expect(path.isAbsolute(config.runtime.socketPath)).toBe(true);
    expect(config.wallet.privateKeyEnv).toBe(defaultConfig().wallet.privateKeyEnv);
  });

  it("writes an initial config file and creates its directories", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-write-"));
    const configPath = path.join(tempDir, "config.json");

    writeInitialConfig(configPath, {
      services: {
        ...defaultConfig(configPath).services,
        platform: {
          ...defaultConfig(configPath).services.platform,
          baseUrl: "http://127.0.0.1:4200",
        },
      },
    });

    const written = JSON.parse(fs.readFileSync(configPath, "utf8")) as ReturnType<typeof defaultConfig>;
    expect(written.services.platform.baseUrl).toBe("http://127.0.0.1:4200");
    expect(written.runtime.stateDir).toBe(path.join(tempDir, "state"));
    expect(written.runtime.socketPath).toBe(path.join(tempDir, "run", "regent.sock"));
    expect(fs.existsSync(written.runtime.stateDir)).toBe(true);
    expect(fs.existsSync(path.dirname(written.runtime.socketPath))).toBe(true);
    expect(fs.existsSync(path.dirname(written.wallet.keystorePath))).toBe(true);
    expect(fs.existsSync(path.dirname(written.gossipsub.peerIdPath))).toBe(true);
  });

  it("writes a validated replacement config and normalizes relative paths", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-replacement-"));
    const configPath = path.join(tempDir, "config.json");
    const replacement = defaultConfig(configPath);

    replacement.runtime = {
      socketPath: "./run/custom.sock",
      stateDir: "./state-dir",
      logLevel: "warn",
    };
    replacement.wallet.keystorePath = "./keys/custom-wallet.json";
    replacement.gossipsub.peerIdPath = "./p2p/custom-peer-id.json";
    replacement.agents.harnesses.hermes.workspaceRoot = "./workspaces/hermes";
    replacement.agents.harnesses.codex.workspaceRoot = "./workspaces/codex";

    const written = writeConfigReplacement(configPath, replacement);

    expect(written.runtime.socketPath).toBe(path.join(tempDir, "run", "custom.sock"));
    expect(written.runtime.stateDir).toBe(path.join(tempDir, "state-dir"));
    expect(written.wallet.keystorePath).toBe(path.join(tempDir, "keys", "custom-wallet.json"));
    expect(written.gossipsub.peerIdPath).toBe(path.join(tempDir, "p2p", "custom-peer-id.json"));
    expect(written.agents.harnesses.hermes.workspaceRoot).toBe(path.join(tempDir, "workspaces", "hermes"));
    expect(written.agents.harnesses.codex.workspaceRoot).toBe(path.join(tempDir, "workspaces", "codex"));
    expect(fs.existsSync(path.dirname(written.runtime.socketPath))).toBe(true);
    expect(fs.existsSync(written.runtime.stateDir)).toBe(true);
    expect(fs.existsSync(path.dirname(written.wallet.keystorePath))).toBe(true);
    expect(fs.existsSync(path.dirname(written.gossipsub.peerIdPath))).toBe(true);
    expect(fs.existsSync(written.agents.harnesses.hermes.workspaceRoot)).toBe(true);
    expect(fs.existsSync(written.agents.harnesses.codex.workspaceRoot)).toBe(true);
  });

  it("only writes the initial config file when it is missing", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-write-if-missing-"));
    const configPath = path.join(tempDir, "config.json");
    const first = defaultConfig(configPath).services;
    const second = defaultConfig(configPath).services;
    first.platform.baseUrl = "http://127.0.0.1:4200";
    second.platform.baseUrl = "http://127.0.0.1:4300";

    writeInitialConfig(configPath, { services: first });
    const created = writeInitialConfigIfMissing(configPath, { services: second });

    expect(created).toBe(false);
    const written = JSON.parse(fs.readFileSync(configPath, "utf8")) as ReturnType<typeof defaultConfig>;
    expect(written.services.platform.baseUrl).toBe("http://127.0.0.1:4200");
  });

  it("writes the initial config file when it is missing", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-create-if-missing-"));
    const configPath = path.join(tempDir, "config.json");
    const services = defaultConfig(configPath).services;
    services.platform.baseUrl = "http://127.0.0.1:4400";

    const created = writeInitialConfigIfMissing(configPath, { services });

    expect(created).toBe(true);
    const written = JSON.parse(fs.readFileSync(configPath, "utf8")) as ReturnType<typeof defaultConfig>;
    expect(written.services.platform.baseUrl).toBe("http://127.0.0.1:4400");
  });

  it("fails fast on invalid JSON", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-invalid-json-"));
    const configPath = path.join(tempDir, "config.json");

    fs.writeFileSync(configPath, "{not-json", "utf8");

    expect(() => loadConfig(configPath)).toThrow(/invalid JSON/);
  });

  it("fails validation when override shape is invalid", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-invalid-shape-"));
    const configPath = path.join(tempDir, "config.json");

    fs.writeFileSync(
      configPath,
      JSON.stringify({
        services: {
          platform: {
            requestTimeoutMs: 0,
          },
        },
      }),
      "utf8",
    );

    expect(() => loadConfig(configPath)).toThrow(/config file failed validation/);
  });

  it.each([
    ["newline injection", "https://regents.sh/\nURI: https://evil.example"],
    ["tab injection", "https://regents.sh/\tURI:https://evil.example"],
    ["NUL control character", "https://regents.sh/\u0000URI:https://evil.example"],
    ["javascript scheme", "javascript:alert(1)"],
    ["FTP scheme", "ftp://regents.sh"],
    ["username", "https://operator@regents.sh"],
    ["username and password", "https://operator:secret@regents.sh"],
    ["empty username", "https://@regents.sh"],
    ["empty username and password", "https://:@regents.sh"],
  ])("rejects an unsafe service base URL: %s", (_name, baseUrl) => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-hostile-url-"));
    const configPath = path.join(tempDir, "config.json");
    fs.writeFileSync(
      configPath,
      JSON.stringify({ services: { platform: { baseUrl } } }),
      "utf8",
    );

    expect(() => loadConfig(configPath)).toThrow(SERVICE_BASE_URL_ERROR);
  });

  it("fails validation on unknown top-level config keys", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-unknown-key-"));
    const configPath = path.join(tempDir, "config.json");

    fs.writeFileSync(configPath, JSON.stringify({ retiredFeature: { enabled: false } }), "utf8");

    expect(() => loadConfig(configPath)).toThrow(/config file failed validation/);
  });

  it("fails fast instead of silently restoring an empty audience", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-empty-audience-"));
    const configPath = path.join(tempDir, "config.json");

    fs.writeFileSync(configPath, JSON.stringify({ auth: { audience: "" } }), "utf8");

    expect(() => loadConfig(configPath)).toThrow(/config file failed validation/);
  });

  it("fails replacement writes when the input is not a full valid config", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-config-invalid-replacement-"));
    const configPath = path.join(tempDir, "config.json");

    expect(() =>
      writeConfigReplacement(configPath, {
        services: {
          platform: {
            baseUrl: "http://127.0.0.1:4300",
          },
        },
      }),
    ).toThrow(/replacement config failed validation/);
  });
});
