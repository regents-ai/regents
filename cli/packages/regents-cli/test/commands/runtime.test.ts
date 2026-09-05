import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { EXPECTED_PLATFORM_CONTRACT_DIGEST } from "../../src/generated/platform-contract-digest.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

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
const PLATFORM_CONTRACT_URL = "http://127.0.0.1:4010/api-contract.openapiv3.yaml";

const runtime = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 44,
  regent_id: 123,
  platform_agent_id: null,
  name: "Hosted manager",
  runner_kind: "hermes_hosted_manager",
  execution_surface: "hosted_sprite",
  billing_mode: "platform_hosted",
  status: "active",
  visibility: "operator",
  config: {},
  metadata: {},
  ...overrides,
});

const checkpoint = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: 88,
  regent_id: 123,
  runtime_profile_id: 44,
  work_run_id: null,
  checkpoint_ref: "before-release",
  status: "ready",
  protected: false,
  captured_at: TIMESTAMP,
  metadata: {},
  created_at: TIMESTAMP,
  updated_at: TIMESTAMP,
  ...overrides,
});

describe("runtime commands", () => {
  // Only mutate individual keys on process.env: replacing the whole object
  // detaches it from the real environment, and os.homedir() would keep
  // returning the real home directory instead of the per-test temp HOME.
  const touchedEnvKeys = ["HOME", "NO_COLOR", "TERM"] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  const fetchMock = vi.fn<typeof fetch>();
  let homeDir = "";
  let sessionFile = "";

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
    homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-runtime-home-"));
    sessionFile = path.join(homeDir, "platform-session.json");
    for (const key of touchedEnvKeys) {
      savedEnv[key] = process.env[key];
    }
    process.env.HOME = homeDir;
    fs.writeFileSync(
      sessionFile,
      JSON.stringify(
        {
          version: 1,
          origin: "http://127.0.0.1:4010",
          cookie: "_platform_phx_key=session-cookie",
          csrfToken: "csrf-token",
          savedAt: TIMESTAMP,
        },
        null,
        2,
      ),
    );
    fetchMock.mockReset();
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

  it("creates a runtime through the contracted route", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, runtime: runtime() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "create",
        "--regent-id",
        "regent_123",
        "--name",
        "Hosted manager",
        "--platform-agent-id",
        "agent_77",
        "--runner",
        "hermes_hosted_manager",
        "--execution-surface",
        "hosted_sprite",
        "--billing-mode",
        "platform_hosted",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes",
    );
    expect((productFetchCalls()[0]?.[1]?.headers as Headers).get("x-csrf-token")).toBe("csrf-token");
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        platform_agent_id: "agent_77",
        name: "Hosted manager",
        runner_kind: "hermes_hosted_manager",
        execution_surface: "hosted_sprite",
        billing_mode: "platform_hosted",
      }),
    );
    expect(parsePrintedJson<{ result: { runtime: { id: number } } }>(output.stdout).result.runtime.id).toBe(44);
  });

  it("saves a runtime checkpoint with the current request shape", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, checkpoint: checkpoint() }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "checkpoint",
        "runtime_44",
        "--regent-id",
        "regent_123",
        "--checkpoint-ref",
        "before-release",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/checkpoint",
    );
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        runtime_id: "runtime_44",
        checkpoint_ref: "before-release",
      }),
    );
    expect(parsePrintedJson<{ result: { checkpoint: { id: number } } }>(output.stdout).result.checkpoint.id).toBe(88);
  });

  it("restores a runtime checkpoint through the contracted route", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({ ok: true, runtime: runtime(), checkpoint: checkpoint(), restore: { status: "accepted" } }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "restore",
        "runtime_44",
        "--regent-id",
        "regent_123",
        "--checkpoint-id",
        "checkpoint_88",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/restore",
    );
    expect(productFetchCalls()[0]?.[1]?.body).toBe(
      JSON.stringify({
        regent_id: "regent_123",
        runtime_id: "runtime_44",
        checkpoint_id: "checkpoint_88",
      }),
    );
    expect(parsePrintedJson<{ result: { restore: { status: string } } }>(output.stdout).result.restore.status).toBe(
      "accepted",
    );
  });

  it("shows services and health without changing JSON output", async () => {
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          regent_id: 123,
          runtime_id: 44,
          services: [
            {
              id: 7,
              regent_id: 123,
              runtime_profile_id: 44,
              name: "Workspace",
              service_kind: "workspace",
              status: "active",
              endpoint_url: "https://workspace.example",
              metadata: {},
            },
          ],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
      new Response(
        JSON.stringify({
          ok: true,
          regent_id: 123,
          runtime_id: 44,
          health: {
            status: "healthy",
            available: true,
            metering_status: "active",
            control_room: {
              status: "expected",
              one_sprite: true,
              sprite_runtime_id: "sprite-44",
              workspace_service_name: "hermes-workspace",
              bridge_service_name: "regent-bridge",
              path: "/regent/control-room",
              registry_path: "/regent/control-room/agents.yaml",
              gbrain: {
                status: "needs_setup",
                tool_repo_path: "~/gbrain",
                brain_repo_path: "/regent/company/BRAIN",
                warnings: [
                  "Your Regent agent will be improved if you enable the recommended GBrain memory and search. This increases recall while reducing token spend.",
                ],
              },
            },
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const servicesOutput = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "services",
        "runtime_44",
        "--regent-id",
        "regent_123",
        "--session-file",
        sessionFile,
        "--json",
      ]),
    );
    const healthOutput = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "health",
        "runtime_44",
        "--regent-id",
        "regent_123",
        "--session-file",
        sessionFile,
        "--json",
      ]),
    );

    expect(servicesOutput.result).toBe(0);
    expect(healthOutput.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/services",
    );
    expect(productFetchCalls()[1]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/health",
    );
    expect(parsePrintedJson<{ result: { services: unknown[] } }>(servicesOutput.stdout).result.services).toHaveLength(1);
    expect(parsePrintedJson<{ result: { health: { available: boolean } } }>(healthOutput.stdout).result.health.available).toBe(
      true,
    );
  });

  it("renders readable runtime health for human terminals", async () => {
    useHumanTerminal();
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          regent_id: 123,
          runtime_id: 44,
          health: {
            status: "needs_attention",
            available: false,
            metering_status: "trialing",
            control_room: {
              status: "expected",
              one_sprite: true,
              sprite_runtime_id: "sprite-44",
              workspace_service_name: "hermes-workspace",
              bridge_service_name: "regent-bridge",
              path: "/regent/control-room",
              registry_path: "/regent/control-room/agents.yaml",
              gbrain: {
                status: "needs_setup",
                tool_repo_path: "~/gbrain",
                brain_repo_path: "/regent/company/BRAIN",
                warnings: [
                  "Your Regent agent will be improved if you enable the recommended GBrain memory and search. This increases recall while reducing token spend.",
                ],
              },
            },
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "health",
        "runtime_44",
        "--regent-id",
        "regent_123",
        "--session-file",
        sessionFile,
      ]),
    );

    const visible = stripAnsi(output.stdout);

    expect(output.result).toBe(0);
    expect(visible).toContain("RUNTIME HEALTH");
    expect(visible).toContain("runtime id");
    expect(visible).toContain("44");
    expect(visible).toContain("needs attention");
    expect(visible).toContain("available");
    expect(visible).toContain("no");
    expect(visible).toContain("HERMES CONTROL ROOM");
    expect(visible).toContain("one Sprite");
    expect(visible).toContain("hermes-workspace");
    expect(visible).toContain("GBrain");
    expect(visible).toContain("/regent/company/BRAIN");
  });

  it("pauses and resumes a runtime through the contracted routes", async () => {
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, runtime: runtime({ status: "paused" }) }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
      new Response(JSON.stringify({ ok: true, runtime: runtime({ status: "active" }) }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const pauseOutput = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "pause",
        "runtime_44",
        "--regent-id",
        "regent_123",
        "--session-file",
        sessionFile,
      ]),
    );
    const resumeOutput = await captureOutput(() =>
      runCliEntrypoint([
        "runtime",
        "resume",
        "runtime_44",
        "--regent-id",
        "regent_123",
        "--session-file",
        sessionFile,
      ]),
    );

    expect(pauseOutput.result).toBe(0);
    expect(resumeOutput.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/pause",
    );
    expect(productFetchCalls()[1]?.[0]).toBe(
      "http://127.0.0.1:4010/api/platform/regents/regent_123/rwr/runtimes/runtime_44/resume",
    );
  });
});
