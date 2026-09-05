import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { authChecks } from "../../../src/internal-runtime/doctor/checks/authChecks.js";
import { runChecksSequentially } from "../../../src/internal-runtime/doctor/checkRunner.js";
import type { DoctorCheckContext } from "../../../src/internal-runtime/doctor/types.js";
import { SessionStore } from "../../../src/internal-runtime/store/session-store.js";
import { StateStore } from "../../../src/internal-runtime/store/state-store.js";
import type { RegentConfig } from "../../../src/internal-types/config.js";

const TEST_WALLET = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as const;
const TEST_REGISTRY = "0x2222222222222222222222222222222222222222" as const;
const VERIFY_URL = "http://127.0.0.1:4000/api/shared/siwa/verify";

const testConfig = (root: string): RegentConfig => ({
  runtime: {
    socketPath: path.join(root, "run", "regent.sock"),
    stateDir: path.join(root, "state"),
    logLevel: "info",
  },
  auth: {
    audience: "techtree",
    defaultChainId: 8453,
  },
  services: {
    siwa: { baseUrl: "http://127.0.0.1:4000", requestTimeoutMs: 1_000 },
    platform: { baseUrl: "http://127.0.0.1:4000", requestTimeoutMs: 1_000 },
    autolaunch: { baseUrl: "http://127.0.0.1:4010", requestTimeoutMs: 1_000 },
  },
  wallet: {
    privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
    keystorePath: path.join(root, "keys", "agent-wallet.json"),
  },
  gossipsub: {
    enabled: false,
    listenAddrs: [],
    bootstrap: [],
    peerIdPath: path.join(root, "p2p", "peer-id.json"),
  },
  agents: {
    defaultHarness: "hermes",
    harnesses: {},
  },
});

const buildContext = (root: string): { ctx: DoctorCheckContext; sessionStore: SessionStore } => {
  const stateStore = new StateStore(path.join(root, "runtime-state.json"));
  stateStore.write({
    agent: {
      walletAddress: TEST_WALLET,
      chainId: 8453,
      registryAddress: TEST_REGISTRY,
      tokenId: "99",
    },
  });
  const sessionStore = new SessionStore(stateStore);

  return {
    sessionStore,
    ctx: {
      mode: "scoped",
      configPath: path.join(root, "regent.config.json"),
      runtimeContext: null,
      config: testConfig(root),
      configLoadError: null,
      stateStore,
      sessionStore,
      walletSecretSource: null,
      fix: false,
      verbose: false,
      cleanupCommentBodyPrefix: "regent-doctor-comment",
      fullState: {},
      refreshConfig: () => undefined,
    },
  };
};

const runVerifyEndpointCheck = async (ctx: DoctorCheckContext) => {
  const [result] = await runChecksSequentially(
    authChecks().filter((check) => check.id === "auth.siwa.verify.endpoint"),
    ctx,
  );
  return result;
};

const runNonceEndpointCheck = async (ctx: DoctorCheckContext) => {
  const [result] = await runChecksSequentially(
    authChecks().filter((check) => check.id === "auth.siwa.nonce.endpoint"),
    ctx,
  );
  return result;
};

const jsonResponse = (status: number, body: unknown): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

describe("auth.siwa.verify.endpoint doctor check", () => {
  let savedHome: string | undefined;
  let tempRoot = "";

  beforeEach(() => {
    savedHome = process.env.HOME;
    tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "regent-doctor-auth-endpoint-"));
    process.env.HOME = path.join(tempRoot, "home");
    fs.mkdirSync(process.env.HOME, { recursive: true });
  });

  afterEach(() => {
    if (savedHome === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = savedHome;
    }
    vi.unstubAllGlobals();
    fs.rmSync(tempRoot, { recursive: true, force: true });
  });

  it("passes when the live endpoint rejects the deliberately invalid probe with a validation-class response", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      jsonResponse(422, {
        error: { code: "siwa_verification_failed", message: "signature is invalid" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const { ctx, sessionStore } = buildContext(tempRoot);

    const result = await runVerifyEndpointCheck(ctx);

    expect(result).toEqual(
      expect.objectContaining({
        id: "auth.siwa.verify.endpoint",
        status: "ok",
        details: expect.objectContaining({
          code: "siwa_verification_failed",
          status: 422,
        }),
      }),
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0]!;
    expect(String(url)).toBe(VERIFY_URL);
    expect(init?.method).toBe("POST");
    expect(sessionStore.getSiwaSession()).toBeNull();
  });

  it("identifies the SIWA service when the nonce endpoint is unreachable", async () => {
    vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockRejectedValue(new TypeError("fetch failed")));
    const { ctx } = buildContext(tempRoot);

    const result = await runNonceEndpointCheck(ctx);

    expect(result).toEqual(
      expect.objectContaining({
        id: "auth.siwa.nonce.endpoint",
        status: "fail",
        remediation: expect.stringContaining("SIWA service base URL"),
      }),
    );
  });

  it("fails when the endpoint is unreachable", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockRejectedValue(new TypeError("fetch failed"));
    vi.stubGlobal("fetch", fetchMock);
    const { ctx } = buildContext(tempRoot);

    const result = await runVerifyEndpointCheck(ctx);

    expect(result).toEqual(
      expect.objectContaining({
        id: "auth.siwa.verify.endpoint",
        status: "fail",
        remediation: expect.stringContaining("SIWA service base URL"),
        details: expect.objectContaining({
          code: "siwa_request_failed",
        }),
      }),
    );
  });

  it("fails when the verify route is missing", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      jsonResponse(404, { error: { code: "not_found", message: "no route" } }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const { ctx } = buildContext(tempRoot);

    const result = await runVerifyEndpointCheck(ctx);

    expect(result).toEqual(
      expect.objectContaining({
        id: "auth.siwa.verify.endpoint",
        status: "fail",
        remediation: expect.stringContaining("SIWA service base URL"),
        details: expect.objectContaining({
          status: 404,
        }),
      }),
    );
  });

  it("fails when the endpoint returns a server error", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      jsonResponse(500, { error: { code: "internal_error", message: "boom" } }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const { ctx } = buildContext(tempRoot);

    const result = await runVerifyEndpointCheck(ctx);

    expect(result).toEqual(
      expect.objectContaining({
        id: "auth.siwa.verify.endpoint",
        status: "fail",
        details: expect.objectContaining({
          status: 500,
        }),
      }),
    );
  });

  it("warns without persisting a session when the endpoint accepts the deliberately invalid probe", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      jsonResponse(200, {
        code: "siwa_verified",
        data: {
          verified: true,
          walletAddress: TEST_WALLET,
          chainId: 8453,
          registryAddress: TEST_REGISTRY,
          tokenId: "99",
          audience: "techtree",
          nonce: "doctor-nonce",
          keyId: TEST_WALLET.toLowerCase(),
          signatureScheme: "evm_personal_sign",
          receipt: "doctor-receipt",
          receiptIssuedAt: "2026-01-01T00:00:00.000Z",
          receiptExpiresAt: "2999-01-01T00:00:00.000Z",
        },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const { ctx, sessionStore } = buildContext(tempRoot);

    const result = await runVerifyEndpointCheck(ctx);

    expect(result).toEqual(
      expect.objectContaining({
        id: "auth.siwa.verify.endpoint",
        status: "warn",
        remediation: expect.stringContaining("SIWA service"),
      }),
    );
    expect(sessionStore.getSiwaSession()).toBeNull();
  });
});
