import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { requireAgentAuthState } from "../../src/commands/agent-auth.js";
import { writeInitialConfig } from "../../src/internal-runtime/index.js";
import { SessionStore } from "../../src/internal-runtime/store/session-store.js";
import { StateStore } from "../../src/internal-runtime/store/state-store.js";
import type { SiwaSession } from "../../src/internal-types/index.js";

const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";
const TEST_WALLET = "0x1111111111111111111111111111111111111111";

const baseSession = (overrides: Partial<SiwaSession> = {}): SiwaSession => ({
  walletAddress: TEST_WALLET,
  chainId: 8453,
  nonce: "nonce",
  keyId: TEST_WALLET,
  receipt: "receipt",
  receiptExpiresAt: "2999-01-01T00:00:00.000Z",
  audience: "techtree",
  registryAddress: TEST_REGISTRY,
  tokenId: "99",
  ...overrides,
});

describe("requireAgentAuthState", () => {
  let tempDir: string;
  let configPath: string;
  let stateDir: string;
  let originalHome: string | undefined;

  const writeSession = (session: SiwaSession): void => {
    const stateStore = new StateStore(path.join(stateDir, "runtime-state.json"));
    new SessionStore(stateStore).setSiwaSession(session);
  };

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-agent-auth-"));
    configPath = path.join(tempDir, "regent.config.json");
    stateDir = path.join(tempDir, "state");
    originalHome = process.env.HOME;
    process.env.HOME = tempDir;

    writeInitialConfig(configPath, {
      runtime: {
        socketPath: path.join(tempDir, "runtime", "regent.sock"),
        stateDir,
        logLevel: "info",
      },
      auth: {
        audience: "techtree",
        defaultChainId: 8453,
      },
    });
  });

  afterEach(() => {
    if (originalHome === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("returns the session and identity when a matching sign-in is present", () => {
    writeSession(baseSession());

    const state = requireAgentAuthState(configPath, { audience: "techtree" });

    expect(state.session.walletAddress).toBe(TEST_WALLET);
    expect(state.identity.registryAddress).toBe(TEST_REGISTRY);
    expect(state.identity.tokenId).toBe("99");
  });

  it("asks the operator to sign in when no session exists", () => {
    expect(() => requireAgentAuthState(configPath, { audience: "techtree" })).toThrowError(
      /regents auth login --audience techtree/,
    );
  });

  it("rejects a session whose audience does not match the command", () => {
    writeSession(baseSession({ audience: "autolaunch" }));

    expect(() => requireAgentAuthState(configPath, { audience: "techtree" })).toThrowError(
      /Regent sign-in/,
    );
  });

  it("rejects an expired sign-in and points at re-login", () => {
    writeSession(baseSession({ receiptExpiresAt: "2000-01-01T00:00:00.000Z" }));

    expect(() => requireAgentAuthState(configPath, { audience: "techtree" })).toThrowError(
      /sign-in expired/,
    );
  });

  it("requires a saved Agent account when the session lacks registry details", () => {
    writeSession(baseSession({ registryAddress: undefined, tokenId: undefined }));

    expect(() => requireAgentAuthState(configPath, { audience: "techtree" })).toThrowError(
      /Run `regents identity ensure` first/,
    );
  });
});
