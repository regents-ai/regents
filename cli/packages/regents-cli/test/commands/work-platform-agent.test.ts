import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { EXPECTED_PLATFORM_CONTRACT_DIGEST } from "../../src/generated/platform-contract-digest.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { buildAgentAuthHeadersMock } = vi.hoisted(() => ({
  buildAgentAuthHeadersMock: vi.fn(),
}));

vi.mock("../../src/commands/agent-auth.js", () => ({
  buildAgentAuthHeaders: buildAgentAuthHeadersMock,
}));

const TIMESTAMP = "2026-04-01T00:00:00.000Z";
const originalIsTTY = process.stdout.isTTY;

const setStdoutTty = (value: boolean): void => {
  Object.defineProperty(process.stdout, "isTTY", {
    configurable: true,
    value,
  });
};

const useHumanTerminal = (): void => {
  setStdoutTty(true);
  delete process.env.NO_COLOR;
  process.env.TERM = "xterm-256color";
};

const stripAnsi = (value: string): string => value.replace(/\x1b\[[0-9;]*m/g, "");
const collapsePanelText = (value: string): string => value.replace(/[│╭╮╰╯─]/gu, " ").replace(/\s+/g, " ").trim();
const PLATFORM_CONTRACT_URL = "http://127.0.0.1:4010/api-contract.openapiv3.yaml";

const workItem = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 123,
  regent_id: 123,
  title: "Review launch notes",
  description: "Check the public launch notes.",
  status: "open",
  priority: "normal",
  visibility: "operator",
  desired_runner_kind: null,
  assigned_worker_id: null,
  assigned_agent_profile_id: null,
  created_at: TIMESTAMP,
  updated_at: TIMESTAMP,
  ...overrides,
});

const runRecord = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 456,
  regent_id: 123,
  work_item_id: 123,
  parent_run_id: null,
  root_run_id: null,
  worker_id: 789,
  runtime_profile_id: null,
  runner_kind: "openclaw_local_executor",
  status: "queued",
  visibility: "operator",
  summary: null,
  failure_reason: null,
  cost_usd: "0.00",
  created_at: TIMESTAMP,
  updated_at: TIMESTAMP,
  ...overrides,
});

const agentProfile = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 321,
  regent_id: 123,
  name: "OpenClaw desk",
  agent_kind: "openclaw",
  default_runner_kind: "openclaw_local_executor",
  status: "active",
  visibility: "operator",
  ...overrides,
});

const worker = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 789,
  regent_id: 123,
  agent_profile_id: 321,
  runtime_profile_id: null,
  name: "OpenClaw desk",
  agent_kind: "openclaw",
  worker_role: "executor",
  execution_surface: "local_bridge",
  runner_kind: "openclaw_local_executor",
  billing_mode: "user_local",
  trust_scope: "local_user_controlled",
  reported_usage_policy: "self_reported",
  status: "active",
  last_heartbeat_at: null,
  ...overrides,
});

const relationship = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 654,
  regent_id: 123,
  source_agent_profile_id: 321,
  target_agent_profile_id: 322,
  source_worker_id: null,
  target_worker_id: null,
  relationship_kind: "can_delegate_to",
  status: "active",
  max_parallel_runs: 1,
  ...overrides,
});

const runtime = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 44,
  regent_id: 123,
  platform_agent_id: 321,
  name: "Hosted Hermes",
  runner_kind: "hermes_hosted_manager",
  execution_surface: "hosted_sprite",
  billing_mode: "platform_hosted",
  status: "running",
  metadata: {},
  ...overrides,
});

const runtimeService = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 55,
  regent_id: 123,
  runtime_profile_id: 44,
  name: "Hermes agent",
  service_kind: "hermes_agent",
  status: "running",
  endpoint_url: null,
  metadata: {},
  ...overrides,
});

describe("work and platform agent commands", () => {
  // Only mutate individual keys on process.env: replacing the whole object
  // detaches it from the real environment, and os.homedir() would keep
  // returning the real home directory instead of the per-test temp HOME.
  const touchedEnvKeys = ["HOME", "NO_COLOR", "TERM"] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  const fetchMock = vi.fn<typeof fetch>();
  let homeDir = "";
  let sessionFile = "";
  let configPath = "";

  const platformContractResponse = (): Response =>
    new Response("openapi: 3.1.0\ninfo:\n  version: 0.1.0\n", {
      status: 200,
      headers: {
        "content-type": "application/yaml",
        "x-regents-contract-major": "0",
        "x-regents-contract-version": "0.1.0",
        "x-regents-contract-digest": EXPECTED_PLATFORM_CONTRACT_DIGEST,
      },
    });

  const mockPlatformResponses = (...responses: Response[]): void => {
    const pending = [...responses];

    fetchMock.mockImplementation(async (input) => {
      const url = String(input);
      if (url === PLATFORM_CONTRACT_URL) {
        return platformContractResponse();
      }

      const response = pending.shift();
      if (!response) {
        throw new Error(`Unexpected fetch: ${url}`);
      }

      return response;
    });
  };

  const productFetchCalls = () => fetchMock.mock.calls.filter(([input]) => String(input) !== PLATFORM_CONTRACT_URL);

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-work-agent-home-"));
    sessionFile = path.join(homeDir, "platform-session.json");
    configPath = path.join(homeDir, "regent.config.json");
    for (const key of touchedEnvKeys) {
      savedEnv[key] = process.env[key];
    }
    process.env.HOME = homeDir;
    fs.mkdirSync(path.dirname(sessionFile), { recursive: true });
    fs.writeFileSync(
      sessionFile,
      JSON.stringify(
        {
          version: 1,
          origin: "http://127.0.0.1:4010",
          cookie: "_platform_phx_key=session-cookie",
          csrfToken: "csrf-token",
          savedAt: "2026-04-01T00:00:00.000Z",
        },
        null,
        2,
      ),
    );
    writeInitialConfig(configPath, {
      auth: {
        audience: "platform",
        defaultChainId: 8453,
      },
      services: {
        siwa: {
          baseUrl: "http://127.0.0.1:4010",
          requestTimeoutMs: 1_000,
        },
        platform: {
          baseUrl: "http://127.0.0.1:4010",
          requestTimeoutMs: 1_000,
        },
        autolaunch: {
          baseUrl: "http://127.0.0.1:4010",
          requestTimeoutMs: 1_000,
        },
      },
    });
    fetchMock.mockReset();
    buildAgentAuthHeadersMock.mockReset();
    buildAgentAuthHeadersMock.mockResolvedValue({
      "x-siwa-receipt": "receipt_123",
      signature: "sig1=:signed:",
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    for (const key of touchedEnvKeys) {
      const saved = savedEnv[key];
      if (saved === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = saved;
      }
    }
    setStdoutTty(Boolean(originalIsTTY));
    fs.rmSync(homeDir, { recursive: true, force: true });
  });

  it("creates work through the current regent route", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, work_item: workItem() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "create",
        "--regent-id",
        "regent_123",
        "--title",
        "Review launch notes",
        "--description",
        "Check the public launch notes.",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/work-items",
    );
    expect((productFetchCalls()[0]?.[1]?.headers as Headers).get("x-csrf-token")).toBe("csrf-token");
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        title: "Review launch notes",
        description: "Check the public launch notes.",
      }),
    );
    expect(parsePrintedJson<{ result: { work_item: { id: number } } }>(output.stdout).result.work_item.id).toBe(123);
  });

  it("starts a run with the current run request shape", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, run: runRecord() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "run",
        "work_123",
        "--regent-id",
        "regent_123",
        "--runner",
        "openclaw_local_executor",
        "--worker-id",
        "worker_123",
        "--instructions",
        "Use the local workspace.",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/work-items/work_123/runs",
    );
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        work_item_id: "work_123",
        runner_kind: "openclaw_local_executor",
        worker_id: "worker_123",
        instructions: "Use the local workspace.",
      }),
    );
    expect(parsePrintedJson<{ result: { run: { id: number } } }>(output.stdout).result.run.id).toBe(456);
  });

  it("cancels a run through the run cancel route", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, run: runRecord() }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "cancel",
        "run_456",
        "--regent-id",
        "regent_123",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/run_456/cancel",
    );
    expect(productFetchCalls()[0]?.[1]?.method).toBe("POST");
    expect(parsePrintedJson<{ command: string; result: { run: { id: number } } }>(output.stdout)).toMatchObject({
      command: "regents work cancel",
    });
  });

  it("retries a run through the run retry route", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, run: runRecord() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "retry",
        "run_456",
        "--regent-id",
        "regent_123",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/run_456/retry",
    );
    expect(productFetchCalls()[0]?.[1]?.method).toBe("POST");
    expect(parsePrintedJson<{ command: string; result: { run: { id: number } } }>(output.stdout)).toMatchObject({
      command: "regents work retry",
    });
  });

  it("renders a readable work run summary for human terminals", async () => {
    useHumanTerminal();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, run: runRecord() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "run",
        "123",
        "--regent-id",
        "123",
        "--runner",
        "openclaw_local_executor",
        "--worker-id",
        "789",
        "--session-file",
        sessionFile,
      ]),
    );

    const visible = stripAnsi(output.stdout);

    expect(output.result).toBe(0);
    expect(visible).toContain("WORK STARTED");
    expect(visible).toContain("run id");
    expect(visible).toContain("456");
    expect(visible).toContain("regents work watch 456 --regent-id 123");
  });

  it("keeps raw JSON output when script mode is requested on a human terminal", async () => {
    useHumanTerminal();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, work_item: workItem() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "create",
        "--regent-id",
        "regent_123",
        "--title",
        "Review launch notes",
        "--session-file",
        sessionFile,
        "--json",
      ]),
    );

    expect(output.result).toBe(0);
    expect(output.stdout).not.toContain("WORK CREATED");
    expect(parsePrintedJson<{ result: { work_item: { id: number } } }>(output.stdout).result.work_item.id).toBe(123);
  });

  it("connects OpenClaw as a local worker and writes the skill", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, agent_profile: agentProfile(), worker: worker() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "connect",
        "openclaw",
        "--regent-id",
        "regent_123",
        "--role",
        "executor",
        "--name",
        "OpenClaw desk",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/workers",
    );
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        agent_kind: "openclaw",
        worker_role: "executor",
        execution_surface: "local_bridge",
        runner_kind: "openclaw_local_executor",
        billing_mode: "user_local",
        trust_scope: "local_user_controlled",
        reported_usage_policy: "self_reported",
        display_name: "OpenClaw desk",
        endpoint_url: null,
      }),
    );
    const printed = parsePrintedJson<{ openclaw: { skillFile: string } }>(output.stdout);
    expect(printed.openclaw.skillFile).toBe(path.join(homeDir, ".openclaw", "skills", "regents-work", "SKILL.md"));
    expect(fs.readFileSync(printed.openclaw.skillFile, "utf8")).toContain(
      "Do not upload secrets, private memory, inbox content, calendar content, chat content",
    );
    expect(fs.readFileSync(printed.openclaw.skillFile, "utf8")).toContain("--worker-id 789");
  });

  it("inspects hosted Hermes through runtime status, service, and health routes", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, runtime: runtime() }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
      new Response(JSON.stringify({ ok: true, regent_id: 123, runtime_id: 44, services: [runtimeService()] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
      new Response(
        JSON.stringify({
          ok: true,
          regent_id: 123,
          runtime_id: 44,
          health: {
            status: "healthy",
            available: true,
            metering_status: "active",
            control_room: {},
          },
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "connect",
        "hosted-hermes",
        "--regent-id",
        "regent_123",
        "--runtime-id",
        "runtime_44",
        "--session-file",
        sessionFile,
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls().map((call) => call[0])).toEqual([
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/services",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/health",
    ]);
    const printed = parsePrintedJson<{
      command: string;
      result: { runtime: { runner_kind: string }; services: unknown[]; health: { available: boolean } };
    }>(output.stdout);
    expect(printed.command).toBe("regents agent connect hosted-hermes");
    expect(printed.result.runtime.runner_kind).toBe("hermes_hosted_manager");
    expect(printed.result.services).toHaveLength(1);
    expect(printed.result.health.available).toBe(true);
  });

  it("sends a hosted agent chat message to the selected regent slug", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          slug: "startline",
          reply: "Launch checklist is ready.",
          run: {
            runtime_id: "sprite-runtime-1",
            exit_code: 0,
            elapsed_ms: 731,
            timeout_seconds: 12,
            output_truncated: false,
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "chat",
        "Check",
        "the",
        "launch",
        "checklist",
        "--slug",
        "startline",
        "--timeout-seconds",
        "12",
        "--session-file",
        sessionFile,
        "--config",
        configPath,
        "--json",
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe("http://127.0.0.1:4010/api/platform/sprites/startline/message");
    expect((productFetchCalls()[0]?.[1]?.headers as Headers).get("x-csrf-token")).toBe("csrf-token");
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        message: "Check the launch checklist",
        timeout_seconds: 12,
      }),
    );

    const printed = parsePrintedJson<{
      command: string;
      result: { slug: string; reply: string; run: { runtime_id: string } };
    }>(output.stdout);
    expect(printed.command).toBe("regents agent chat");
    expect(printed.result.slug).toBe("startline");
    expect(printed.result.reply).toBe("Launch checklist is ready.");
    expect(printed.result.run.runtime_id).toBe("sprite-runtime-1");
  });

  it("infers the hosted agent chat slug when the session owns one regent", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          authenticated: true,
          agents: [{ slug: "solo" }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
      new Response(
        JSON.stringify({
          ok: true,
          slug: "solo",
          reply: "Solo regent is ready.",
          run: {
            runtime_id: "sprite-runtime-solo",
            exit_code: 0,
            elapsed_ms: 220,
            timeout_seconds: 30,
            output_truncated: false,
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "chat",
        "Status?",
        "--session-file",
        sessionFile,
        "--config",
        configPath,
        "--json",
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls().map((call) => call[0])).toEqual([
      "http://127.0.0.1:4010/api/platform/auth/privy/profile",
      "http://127.0.0.1:4010/api/platform/sprites/solo/message",
    ]);
    expect(productFetchCalls()[1]?.[1]?.body).toBe(
      JSON.stringify({
        message: "Status?",
        timeout_seconds: 30,
      }),
    );
  });

  it("requires a hosted agent chat slug when the session owns multiple regents", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          authenticated: true,
          agents: [{ slug: "alpha" }, { slug: "beta" }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "chat",
        "Status?",
        "--session-file",
        sessionFile,
        "--config",
        configPath,
      ]),
    );

    expect(output.result).not.toBe(0);
    expect(output.stderr).toContain("--slug is required when your saved session owns more than one regent.");
    expect(productFetchCalls().map((call) => call[0])).toEqual([
      "http://127.0.0.1:4010/api/platform/auth/privy/profile",
    ]);
  });

  it("prints only the hosted agent reply on a human terminal", async () => {
    useHumanTerminal();
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          slug: "startline",
          reply: "The next step is to review bids.",
          run: {
            runtime_id: "sprite-runtime-1",
            exit_code: 0,
            elapsed_ms: 431,
            timeout_seconds: 30,
            output_truncated: false,
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "chat",
        "What",
        "next?",
        "--slug",
        "startline",
        "--session-file",
        sessionFile,
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(stripAnsi(output.stdout)).toBe("The next step is to review bids.\n");
  });

  it("renders OpenClaw connection details for human terminals", async () => {
    useHumanTerminal();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, agent_profile: agentProfile(), worker: worker() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "connect",
        "openclaw",
        "--regent-id",
        "regent_123",
        "--role",
        "executor",
        "--name",
        "OpenClaw desk",
        "--config",
        configPath,
      ]),
    );

    const visible = stripAnsi(output.stdout);

    expect(output.result).toBe(0);
    expect(visible).toContain("OPENCLAW CONNECTED");
    expect(visible).toContain("worker id");
    expect(visible).toContain("789");
    expect(visible).toContain(path.join(homeDir, ".openclaw", "skills", "regents-work", "SKILL.md"));
    expect(collapsePanelText(visible)).toContain(
      "regents work run <work-id> --regent-id 123 --runner openclaw_local_executor --worker-id 789",
    );
  });

  it("links a manager to an executor through the relationship route", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, relationship: relationship() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "link",
        "--regent-id",
        "regent_123",
        "--manager-agent-id",
        "agent_manager",
        "--executor-agent-id",
        "agent_executor",
        "--relationship",
        "can_delegate_to",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/agents/agent_manager/relationships",
    );
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        source_agent_profile_id: "agent_manager",
        target_agent_profile_id: "agent_executor",
        relationship_kind: "can_delegate_to",
        status: "active",
      }),
    );
    expect(parsePrintedJson<{ result: { relationship: { id: number } } }>(output.stdout).result.relationship.id).toBe(654);
  });

  it("links manager and executor workers through the relationship route", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          relationship: relationship({
            id: 655,
            source_agent_profile_id: null,
            target_agent_profile_id: null,
            source_worker_id: 789,
            target_worker_id: 790,
          }),
        }),
        {
          status: 201,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "link",
        "--regent-id",
        "regent_123",
        "--manager-worker-id",
        "worker_manager",
        "--executor-worker-id",
        "worker_executor",
        "--relationship",
        "can_delegate_to",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/agents/worker_manager/relationships",
    );
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        source_worker_id: "worker_manager",
        target_worker_id: "worker_executor",
        relationship_kind: "can_delegate_to",
        status: "active",
      }),
    );
    expect(parsePrintedJson<{ result: { relationship: { id: number } } }>(output.stdout).result.relationship.id).toBe(655);
  });

  it("watches run events through the current run events route", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          run_id: 456,
          events: [
            {
              id: 987,
              regent_id: 123,
              run_id: 456,
              sequence: 1,
              kind: "queued",
              actor_kind: "worker",
              actor_id: "789",
              visibility: "operator",
              sensitivity: "normal",
              payload: {},
              occurred_at: TIMESTAMP,
            },
          ],
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "watch",
        "run_123",
        "--regent-id",
        "regent_123",
        "--once",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/run_123/events",
    );
    expect(parsePrintedJson<{ result: { events: unknown[] } }>(output.stdout).result.events).toHaveLength(1);
  });

  it("keeps checking run events when asked to watch progress", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          run_id: 456,
          events: [{ id: 1, run_id: 456, sequence: 1, kind: "queued", payload: {}, occurred_at: TIMESTAMP }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
      new Response(
        JSON.stringify({
          ok: true,
          run_id: 456,
          events: [
            { id: 1, run_id: 456, sequence: 1, kind: "queued", payload: {}, occurred_at: TIMESTAMP },
            { id: 2, run_id: 456, sequence: 2, kind: "running", payload: {}, occurred_at: TIMESTAMP },
          ],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "watch",
        "run_123",
        "--regent-id",
        "regent_123",
        "--max-polls",
        "2",
        "--poll-ms",
        "1",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls().map((call) => call[0])).toEqual([
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/run_123/events",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/run_123/events",
    ]);
    const lines = output.stdout.trim().split("\n").map((line) => JSON.parse(line));
    expect(lines).toHaveLength(2);
    expect(lines[0]).toMatchObject({ command: "regents work watch", result: { events: [{ kind: "queued" }] } });
    expect(lines[1]).toMatchObject({ command: "regents work watch", result: { events: [{ kind: "queued" }, { kind: "running" }] } });
  });

  it("shows only new run updates in a terminal timeline", async () => {
    useHumanTerminal();
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          run_id: 456,
          events: [{ id: 1, run_id: 456, sequence: 1, kind: "queued", payload: {}, occurred_at: TIMESTAMP }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
      new Response(
        JSON.stringify({
          ok: true,
          run_id: 456,
          events: [
            { id: 1, run_id: 456, sequence: 1, kind: "queued", payload: {}, occurred_at: TIMESTAMP },
            { id: 2, run_id: 456, sequence: 2, kind: "running", payload: {}, occurred_at: TIMESTAMP },
          ],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "watch",
        "run_123",
        "--regent-id",
        "regent_123",
        "--max-polls",
        "2",
        "--poll-ms",
        "1",
        "--session-file",
        sessionFile,
      ]),
    );

    const visible = stripAnsi(output.stdout);
    expect(output.result).toBe(0);
    expect(visible).toContain("UPDATE TIMELINE");
    expect(visible.match(/queued/g)).toHaveLength(1);
    expect(visible.match(/running/g)).toHaveLength(1);
  });

  it("lets a local worker claim work, record updates, upload approved artifacts, delegate, and complete", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, worker: worker() }), { status: 200 }),
      new Response(
        JSON.stringify({
          ok: true,
          assignments: [{ id: 11, regent_id: 123, worker_id: 789, work_run_id: 456, status: "available" }],
        }),
        { status: 200 },
      ),
      new Response(
        JSON.stringify({
          ok: true,
          assignment: { id: 11, regent_id: 123, worker_id: 789, work_run_id: 456, status: "claimed" },
        }),
        { status: 200 },
      ),
      new Response(JSON.stringify({ ok: true, event: { id: 1 } }), { status: 201 }),
      new Response(JSON.stringify({ ok: true, artifact: { id: 2 } }), { status: 201 }),
      new Response(JSON.stringify({ ok: true, target_worker: worker({ id: 790 }), child_runs: [runRecord({ id: 457 })] }), {
        status: 201,
      }),
      new Response(
        JSON.stringify({
          ok: true,
          assignment: { id: 11, regent_id: 123, worker_id: 789, work_run_id: 456, status: "completed" },
        }),
        { status: 200 },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "work",
        "local-loop",
        "--regent-id",
        "regent_123",
        "--worker-id",
        "worker_123",
        "--once",
        "--artifact-title",
        "Approved note",
        "--artifact-body",
        "Only this approved note is uploaded.",
        "--delegate-runner",
        "codex_exec",
        "--delegate-title",
        "Review final answer",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls().map((call) => call[0])).toEqual([
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/workers/worker_123/heartbeat",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/workers/worker_123/assignments",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/assignments/11/claim",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/456/events",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/456/artifacts",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runs/456/delegations",
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/assignments/11/complete",
    ]);
    expect(productFetchCalls()[3]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        run_id: 456,
        kind: "local_worker_checked_assignment",
        payload: { worker_id: "worker_123" },
        visibility: "operator",
        sensitivity: "normal",
      }),
    );
    expect(productFetchCalls()[4]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        run_id: 456,
        artifact_type: "note",
        title: "Approved note",
        body: "Only this approved note is uploaded.",
        visibility: "operator",
      }),
    );
    expect(productFetchCalls()[5]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        run_id: 456,
        requested_runner_kind: "codex_exec",
        tasks: [{ title: "Review final answer" }],
      }),
    );
    expect(parsePrintedJson<{ ok: boolean; command: string }>(output.stdout)).toEqual({
      ok: true,
      command: "regents work local-loop",
    });
  });

  it("lists a manager execution pool through the current route", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          regent_id: 123,
          workers: [
            worker(),
            worker({
              id: 790,
              name: "Hermes desk",
              agent_kind: "hermes",
              worker_role: "manager",
              runner_kind: "hermes_hosted_manager",
              billing_mode: "platform_hosted",
              trust_scope: "platform_hosted",
              reported_usage_policy: "platform_metered",
              last_heartbeat_at: TIMESTAMP,
            }),
          ],
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "execution-pool",
        "--regent-id",
        "regent_123",
        "--manager",
        "agent_manager",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/agents/agent_manager/execution-pool",
    );
    expect(parsePrintedJson<{ result: { workers: unknown[] } }>(output.stdout).result.workers).toHaveLength(2);
  });

  it("renders the execution pool as a worker list for human terminals", async () => {
    useHumanTerminal();
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          regent_id: 123,
          workers: [worker(), worker({ id: 790, name: "Hermes desk", agent_kind: "hermes" })],
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "agent",
        "execution-pool",
        "--regent-id",
        "123",
        "--manager",
        "321",
        "--session-file",
        sessionFile,
      ]),
    );

    const visible = stripAnsi(output.stdout);

    expect(output.result).toBe(0);
    expect(visible).toContain("ASSIGNABLE WORKERS");
    expect(visible).toContain("WORKER LIST");
    expect(visible).toContain("OpenClaw desk");
    expect(visible).toContain("Hermes desk");
    expect(collapsePanelText(visible)).toContain(
      "regents work run <work-id> --regent-id 123 --runner <runner> --worker-id <worker-id>",
    );
  });
});
