import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterAll, afterEach, beforeAll, beforeEach, vi } from "vitest";

export const TEST_WALLET = "0x1111111111111111111111111111111111111111";
export const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";

const cliMocks = vi.hoisted(() => ({
  daemonCallMock: vi.fn(),
  ensureIdentityMock: vi.fn(),
  coinbaseStatusMock: vi.fn(),
  setupCoinbaseWalletMock: vi.fn(),
  runDoctorMock: vi.fn(),
  runScopedDoctorMock: vi.fn(),
  runFullDoctorMock: vi.fn(),
}));

vi.mock("../../src/daemon-client.js", () => ({
  daemonCall: cliMocks.daemonCallMock,
}));

export const {
  daemonCallMock,
  ensureIdentityMock,
  coinbaseStatusMock,
  setupCoinbaseWalletMock,
  runDoctorMock,
  runScopedDoctorMock,
  runFullDoctorMock,
} = cliMocks;

export interface CommandCase {
  name: string;
  args: string[];
  expected: unknown;
}

export interface CliEntrypointHarness {
  readonly tempDir: string;
  readonly configPath: string;
  readonly runCliEntrypoint: typeof import("../../src/index.js").runCliEntrypoint;
}

const doctorReport = (mode: "default" | "scoped" | "full", scope?: string) => ({
  ok: true,
  mode,
  ...(scope ? { scope } : {}),
  summary: { ok: 1, warn: 0, fail: 0, skip: 0 },
  checks: [],
  nextSteps: [],
  generatedAt: "2026-03-11T00:00:00.000Z",
});

const resolveRunMetadataResponse = (metadata: Record<string, unknown>) => {
  const executorHarness =
    metadata.executor_harness && typeof metadata.executor_harness === "object"
      ? (metadata.executor_harness as Record<string, unknown>)
      : {};
  const origin =
    metadata.origin && typeof metadata.origin === "object"
      ? (metadata.origin as Record<string, unknown>)
      : {};

  return {
    resolved_at: "2026-03-20T00:00:00.000Z",
    executor_harness: {
      kind: String(executorHarness.kind ?? "custom"),
      profile: String(executorHarness.profile ?? "owner"),
      entrypoint:
        executorHarness.entrypoint === undefined ? null : (executorHarness.entrypoint as string | null),
    },
    origin: {
      kind: String(origin.kind ?? "local"),
      transport: origin.transport === undefined ? null : (origin.transport as string | null),
      session_id: origin.session_id === undefined ? null : (origin.session_id as string | null),
      trigger_ref: origin.trigger_ref === undefined ? null : (origin.trigger_ref as string | null),
    },
    executor_harness_kind: String(executorHarness.kind ?? "custom"),
    executor_harness_profile: String(executorHarness.profile ?? "owner"),
    origin_session_id: origin.session_id === undefined ? null : (origin.session_id as string | null),
  };
};

const defaultAgentState = () => ({
  initializedAt: "2026-03-20T00:00:00.000Z",
  resolved_at: "2026-03-20T00:00:00.000Z",
  executor_harness: {
    kind: "custom",
    profile: "owner",
    entrypoint: "regents agent init",
  },
  origin: {
    kind: "local",
    transport: "api",
    session_id: null,
    trigger_ref: "regents agent init",
  },
  executor_harness_kind: "custom",
  executor_harness_profile: "owner",
  origin_session_id: null,
});

const agentProfileSummary = (name: string, active: boolean) => ({
  name,
  kind: name === "owner" || name === "public" || name === "group" ? name : "custom",
  label:
    name === "owner"
      ? "Owner agent profile"
      : name === "public"
        ? "Public agent profile"
        : name === "group"
          ? "Group agent profile"
          : "Custom agent profile",
  active,
  executor_harness_kind: "custom",
  executor_harness_profile: name,
  origin_session_id: null,
  executor_harness: {
    kind: "custom",
    profile: name,
    entrypoint: "regents agent init",
  },
  origin: {
    kind: "local",
    transport: "api",
    session_id: null,
    trigger_ref: "regents agent init",
  },
});

const agentHarnessSummary = (kind: string, active: boolean, profile = "owner") => ({
  name: kind,
  kind,
  label:
    kind === "openclaw"
      ? "OpenClaw executor harness"
      : kind === "hermes"
        ? "Hermes executor harness"
        : kind === "claude_code"
          ? "Claude Code executor harness"
          : "Custom executor harness",
  active,
  executor_harness_kind: kind,
  executor_harness_profile: profile,
  origin_session_id: null,
  executor_harness: {
    kind,
    profile,
    entrypoint: "regents agent init",
  },
  origin: {
    kind: "local",
    transport: "api",
    session_id: null,
    trigger_ref: "regents agent init",
  },
});

const defaultDaemonResponse = async (method: string, params?: unknown) => {
  if (method === "agent.init" || method === "agent.status") {
    return {
      initialized: true,
      state: defaultAgentState(),
      identity: {
        walletAddress: TEST_WALLET,
        chainId: 8453,
        registryAddress: TEST_REGISTRY,
        tokenId: "99",
      },
      currentProfile: agentProfileSummary("owner", true),
      currentHarness: agentHarnessSummary("custom", true, "owner"),
      currentOrigin: defaultAgentState().origin,
      profiles: [
        agentProfileSummary("owner", true),
        agentProfileSummary("public", false),
        agentProfileSummary("group", false),
        agentProfileSummary("custom", false),
      ],
      harnesses: [
        agentHarnessSummary("openclaw", false),
        agentHarnessSummary("hermes", false),
        agentHarnessSummary("claude_code", false),
        agentHarnessSummary("custom", true, "owner"),
      ],
      resolvedMetadata: resolveRunMetadataResponse({
        executor_harness: defaultAgentState().executor_harness,
        origin: defaultAgentState().origin,
      }),
    };
  }

  if (method === "agent.profile.list") {
    return {
      data: [
        agentProfileSummary("owner", true),
        agentProfileSummary("public", false),
        agentProfileSummary("group", false),
        agentProfileSummary("custom", false),
      ],
    };
  }

  if (method === "agent.profile.show") {
    const profileName = typeof params === "object" && params && typeof (params as Record<string, unknown>).profile === "string"
      ? String((params as Record<string, unknown>).profile)
      : "owner";

    return {
      data: agentProfileSummary(profileName, true),
    };
  }

  if (method === "agent.harness.list") {
    return {
      data: [
        agentHarnessSummary("openclaw", false),
        agentHarnessSummary("hermes", false),
        agentHarnessSummary("claude_code", false),
        agentHarnessSummary("custom", true, "owner"),
      ],
    };
  }

  return params === undefined ? { method } : { method, params };
};

export function setupCliEntrypointHarness(): CliEntrypointHarness {
  let tempDir = "";
  let configPath = "";
  let runCliEntrypoint!: typeof import("../../src/index.js").runCliEntrypoint;

  beforeAll(async () => {
    vi.doMock("../../src/internal-runtime/index.js", async () => {
      const actual = await vi.importActual<typeof import("../../src/internal-runtime/index.js")>("../../src/internal-runtime/index.js");

      return {
        ...actual,
        ensureIdentity: ensureIdentityMock,
        coinbaseStatus: coinbaseStatusMock,
        setupCoinbaseWallet: setupCoinbaseWalletMock,
        runDoctor: runDoctorMock,
        runScopedDoctor: runScopedDoctorMock,
        runFullDoctor: runFullDoctorMock,
      };
    });

    vi.resetModules();
    ({ runCliEntrypoint } = await import("../../src/index.js"));
  });

  afterAll(() => {
    vi.doUnmock("../../src/internal-runtime/index.js");
    vi.resetModules();
  });

  beforeEach(async () => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-cli-dispatch-"));
    configPath = path.join(tempDir, "regent.config.json");

    const { operatorInitDeps } = await import("../../src/commands/operator.js");
    operatorInitDeps.callJsonRpc = (async () => ({ ok: true })) as typeof operatorInitDeps.callJsonRpc;
    operatorInitDeps.pluginStatus = (runtime = "auto") => ({
      ok: true,
      selectedRuntime: runtime,
      runtimes: [
        { runtime: "hermes", installed: true, pluginPath: path.join(tempDir, ".hermes"), skillsPath: path.join(tempDir, ".hermes", "skills") },
        { runtime: "openclaw", installed: true, pluginPath: path.join(tempDir, ".openclaw"), skillsPath: path.join(tempDir, ".openclaw", "skills") },
      ],
    });
    operatorInitDeps.runScopedDoctor = runScopedDoctorMock as typeof operatorInitDeps.runScopedDoctor;

    daemonCallMock.mockReset();
    daemonCallMock.mockImplementation(defaultDaemonResponse);

    ensureIdentityMock.mockReset();
    ensureIdentityMock.mockImplementation(async () => ({
      status: "ok",
      provider: "coinbase-cdp",
      network: "base",
      address: TEST_WALLET,
      agent_id: `eip155:8453:${TEST_REGISTRY}:99`,
      token_id: "99",
      agent_registry: TEST_REGISTRY,
      verified: "onchain",
      receipt_expires_at: "2999-01-01T00:00:00.000Z",
      cache_path: path.join(tempDir, "identity", "receipt-v1.json"),
    }));

    coinbaseStatusMock.mockReset();
    coinbaseStatusMock.mockImplementation(async () => ({
      ok: true,
      provider: "coinbase-cdp",
      cli_available: true,
      api_key_present: true,
      wallet_secret_present: true,
      account: {
        name: "main",
        address: TEST_WALLET,
      },
      identity_ready: true,
      receipt_expires_at: "2999-01-01T00:00:00.000Z",
    }));

    setupCoinbaseWalletMock.mockReset();
    setupCoinbaseWalletMock.mockImplementation(async () => ({
      ok: true,
      provider: "coinbase-cdp",
      wallet: {
        name: "main",
        address: TEST_WALLET,
      },
      created: false,
      state_path: path.join(tempDir, "state", "coinbase-wallet.json"),
    }));

    runDoctorMock.mockReset();
    runDoctorMock.mockImplementation(async () => doctorReport("default"));

    runScopedDoctorMock.mockReset();
    runScopedDoctorMock.mockImplementation(async (params?: { scope?: string }) =>
      doctorReport("scoped", params?.scope),
    );

    runFullDoctorMock.mockReset();
    runFullDoctorMock.mockImplementation(async () => doctorReport("full"));

  });

  afterEach(() => {
    daemonCallMock.mockClear();
    coinbaseStatusMock.mockClear();
    setupCoinbaseWalletMock.mockClear();
    runDoctorMock.mockClear();
    runScopedDoctorMock.mockClear();
    runFullDoctorMock.mockClear();
  });

  return {
    get tempDir() {
      return tempDir;
    },
    get configPath() {
      return configPath;
    },
    get runCliEntrypoint() {
      return runCliEntrypoint;
    },
  };
}
