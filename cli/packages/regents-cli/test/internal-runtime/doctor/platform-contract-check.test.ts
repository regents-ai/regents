import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  EXPECTED_PLATFORM_CONTRACT_DIGEST,
  SUPPORTED_PLATFORM_CONTRACT_MAJOR,
} from "../../../src/generated/platform-contract-digest.js";
import { runtimeChecks } from "../../../src/internal-runtime/doctor/checks/runtimeChecks.js";
import type { DoctorCheckContext } from "../../../src/internal-runtime/doctor/types.js";
import type { RegentConfig } from "../../../src/internal-types/config.js";

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

const testContext = (root: string): DoctorCheckContext => ({
  mode: "default",
  configPath: path.join(root, "config.json"),
  runtimeContext: null,
  config: testConfig(root),
  configLoadError: null,
  stateStore: null,
  sessionStore: null,
  walletSecretSource: null,
  fix: false,
  verbose: false,
  cleanupCommentBodyPrefix: "regent-doctor-comment",
  fullState: {},
  refreshConfig: () => undefined,
});

const contractCheck = () => {
  const check = runtimeChecks().find((candidate) => candidate.id === "runtime.platform.contract");
  expect(check).toBeDefined();
  return check!;
};

const contractResponse = (headers: Record<string, string>, status = 200): Response =>
  new Response("openapi: 3.0.3\n", { status, headers });

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("platform contract doctor check", () => {
  it("passes when Platform serves the digest this CLI was built against", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        contractResponse({
          "x-regents-contract-major": SUPPORTED_PLATFORM_CONTRACT_MAJOR,
          "x-regents-contract-digest": EXPECTED_PLATFORM_CONTRACT_DIGEST,
        }),
      ),
    );

    const root = path.join(os.tmpdir(), "regent-platform-contract");
    const result = await contractCheck().run(testContext(root));

    expect(result.status).toBe("ok");
    expect(result.details).toMatchObject({
      digest: EXPECTED_PLATFORM_CONTRACT_DIGEST,
      major: SUPPORTED_PLATFORM_CONTRACT_MAJOR,
    });
  });

  it("fails with an update hint when the served digest differs", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        contractResponse({
          "x-regents-contract-major": SUPPORTED_PLATFORM_CONTRACT_MAJOR,
          "x-regents-contract-digest": "sha256:different",
        }),
      ),
    );

    const root = path.join(os.tmpdir(), "regent-platform-contract");
    const result = await contractCheck().run(testContext(root));

    expect(result.status).toBe("fail");
    expect(result.message).toContain("different contract versions");
    expect(result.remediation).toContain("regents update");
    expect(result.details).toMatchObject({
      expected: { digest: EXPECTED_PLATFORM_CONTRACT_DIGEST },
      served: { digest: "sha256:different" },
    });
  });

  it("warns instead of failing when Platform answers with an error status", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => contractResponse({}, 503)));

    const root = path.join(os.tmpdir(), "regent-platform-contract");
    const result = await contractCheck().run(testContext(root));

    expect(result.status).toBe("warn");
    expect(result.message).toContain("did not answer");
    expect(result.details).toMatchObject({ status: 503 });
  });

  it("warns when Platform is unreachable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("connect ECONNREFUSED");
      }),
    );

    const root = path.join(os.tmpdir(), "regent-platform-contract");
    const result = await contractCheck().run(testContext(root));

    expect(result.status).toBe("warn");
    expect(result.message).toContain("unreachable");
  });

  it("skips when config is unavailable", async () => {
    const root = path.join(os.tmpdir(), "regent-platform-contract");
    const result = await contractCheck().run({ ...testContext(root), config: null });

    expect(result.status).toBe("skip");
  });
});
