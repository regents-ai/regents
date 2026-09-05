import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import type { RegentConfig } from "../../src/internal-types/index.js";
import {
  appendStructuredLog,
  structuredLogPath,
} from "../../src/internal-runtime/structured-log.js";

const configFor = (homeDir: string): RegentConfig => ({
  runtime: {
    socketPath: path.join(homeDir, ".regent", "run", "regent.sock"),
    stateDir: path.join(homeDir, ".regent", "state"),
    logLevel: "info",
  },
  auth: {
    audience: "techtree",
    defaultChainId: 8453,
  },
  services: {
    siwa: { baseUrl: "http://127.0.0.1:4000", requestTimeoutMs: 1000 },
    platform: { baseUrl: "http://127.0.0.1:4000", requestTimeoutMs: 1000 },
    autolaunch: { baseUrl: "http://127.0.0.1:4010", requestTimeoutMs: 1000 },
  },
  wallet: {
    privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
    keystorePath: path.join(homeDir, ".regent", "keys", "agent-wallet.json"),
  },
  gossipsub: {
    enabled: false,
    listenAddrs: [],
    bootstrap: [],
    peerIdPath: path.join(homeDir, ".regent", "p2p", "peer-id.json"),
  },
  agents: {
    defaultHarness: "hermes",
    harnesses: {},
  },
});

const mode = (filePath: string): number => fs.statSync(filePath).mode & 0o777;

describe("structured Regent logs", () => {
  const tempDirs: string[] = [];

  afterEach(() => {
    for (const tempDir of tempDirs.splice(0)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  it("writes redacted JSON lines with private permissions", () => {
    const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-structured-log-"));
    tempDirs.push(homeDir);
    const config = configFor(homeDir);

    appendStructuredLog(config, {
      timestamp: "2026-04-01T00:00:00.000Z",
      level: "info",
      event: "product_http_request",
      command: "regents agentbook",
      service: "platform",
      method: "GET",
      path: "/api/platform/agentbook/sessions/sess_1?token=secret&access_token=platform-secret&cursor=1",
      status: 200,
      ok: true,
      requestId: "req_1",
      durationMs: 12,
      chainId: 8453,
      redacted: true,
    });

    const logPath = structuredLogPath(config);
    const [line] = fs.readFileSync(logPath, "utf8").trim().split("\n");
    expect(JSON.parse(line)).toMatchObject({
      command: "regents agentbook",
      path:
        "/api/platform/agentbook/sessions/sess_1?token=%5Bredacted%5D&access_token=%5Bredacted%5D&cursor=1",
      requestId: "req_1",
      durationMs: 12,
      chainId: 8453,
      redacted: true,
    });
    expect(mode(logPath)).toBe(0o600);
    expect(mode(path.dirname(logPath))).toBe(0o700);
  });
});
