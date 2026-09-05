import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { buildAgentAuthHeadersMock, loadAgentAuthStateMock, requireAgentAuthStateMock } = vi.hoisted(() => ({
  buildAgentAuthHeadersMock: vi.fn(),
  loadAgentAuthStateMock: vi.fn(),
  requireAgentAuthStateMock: vi.fn(),
}));

vi.mock("../../src/commands/agent-auth.js", () => ({
  buildAgentAuthHeaders: buildAgentAuthHeadersMock,
  loadAgentAuthState: loadAgentAuthStateMock,
  requireAgentAuthState: requireAgentAuthStateMock,
}));

const SUBJECT_ID = `0x${"1a".repeat(32)}`;
const TOKEN_SCOPE = `token:${SUBJECT_ID}`;
const SENDER_WALLET = "0x00000000000000000000000000000000000000aa";
const CREATOR_WALLET = "0x00000000000000000000000000000000000000cc";
const DM_SCOPE = `dm:${SENDER_WALLET}:${CREATOR_WALLET}`;

describe("autolaunch chat CLI commands", () => {
  const expectedBaseUrl = "https://regents.sh";
  const fetchMock = vi.fn<typeof fetch>();
  const tempDirs: string[] = [];

  const createConfigPath = () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-cli-autolaunch-chat-"));
    tempDirs.push(tempDir);

    const configPath = path.join(tempDir, "regent.config.json");
    writeInitialConfig(configPath);
    return configPath;
  };

  const jsonResponse = (payload: unknown, status = 200) =>
    new Response(JSON.stringify(payload), {
      status,
      headers: { "content-type": "application/json" },
    });

  const channelsPayload = () => ({
    data: [
      { scope: "system", kind: "system", name: "System", status: "active", last_message_at: null },
      { scope: TOKEN_SCOPE, kind: "token", name: "Token channel", status: "active", last_message_at: null },
    ],
  });

  const assertAgentAuthHeaders = (headers: Headers | undefined) => {
    expect(headers?.get("x-siwa-receipt")).toBe("receipt_123");
    expect(headers?.get("signature")).toBe("sig1=:ZmFrZQ==:");
  };

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
    buildAgentAuthHeadersMock.mockReset();
    loadAgentAuthStateMock.mockReset();
    requireAgentAuthStateMock.mockReset();

    buildAgentAuthHeadersMock.mockResolvedValue({
      "x-siwa-receipt": "receipt_123",
      signature: "sig1=:ZmFrZQ==:",
    });
    requireAgentAuthStateMock.mockReturnValue({
      identity: {
        walletAddress: SENDER_WALLET,
        chainId: 8453,
        registryAddress: "0x0000000000000000000000000000000000000abc",
        tokenId: "1",
      },
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    for (const tempDir of tempDirs.splice(0)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  it("lists chat channels without agent auth", async () => {
    const configPath = createConfigPath();
    fetchMock.mockResolvedValueOnce(jsonResponse(channelsPayload()));

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "chat", "list", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(`${expectedBaseUrl}/api/autolaunch/v1/chat/channels`);
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect((requestInit?.headers as Headers).get("x-siwa-receipt")).toBeNull();
    expect(buildAgentAuthHeadersMock).not.toHaveBeenCalled();
    expect(parsePrintedJson(output.stdout)).toEqual(channelsPayload());
  });

  it("reads a scope with forward cursor pagination flags", async () => {
    const configPath = createConfigPath();
    const payload = {
      data: [{ id: 7, scope: "system", body: "hello" }],
      pagination: { limit: 5, next_cursor: null },
    };
    fetchMock.mockResolvedValueOnce(jsonResponse(payload));

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "chat",
        "read",
        "system",
        "--after",
        "10",
        "--limit",
        "5",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/chat/messages?scope=system&after=10&limit=5`,
    );
    expect(parsePrintedJson(output.stdout)).toEqual(payload);
  });

  it("rejects conflicting chat read cursors before making a request", async () => {
    const configPath = createConfigPath();

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "chat",
        "read",
        "system",
        "--before",
        "10",
        "--after",
        "11",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(1);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(output.stderr).toContain("--before and --after cannot be used together");
  });

  it("sends to a channel scope over the agent HTTP route", async () => {
    const configPath = createConfigPath();
    const payload = { data: { id: 8, scope: "topic:cca", body: "Auction opens at noon" } };
    fetchMock.mockResolvedValueOnce(jsonResponse(payload, 201));

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "chat",
        "send",
        "topic:cca",
        "--message",
        "Auction opens at noon",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/chat/messages?scope=${encodeURIComponent("topic:cca")}`,
    );
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(requestInit?.method).toBe("POST");
    assertAgentAuthHeaders(requestInit?.headers as Headers);
    expect(JSON.parse(String(requestInit?.body))).toEqual({ body: "Auction opens at noon" });
    expect(parsePrintedJson(output.stdout)).toEqual(payload);
  });

  it("sends to a token scope over the agent HTTP route", async () => {
    const configPath = createConfigPath();
    const payload = { data: { id: 9, scope: TOKEN_SCOPE, body: "hi room" } };
    fetchMock.mockResolvedValueOnce(jsonResponse(payload, 201));

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "chat",
        "send",
        TOKEN_SCOPE,
        "--message",
        "hi room",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/chat/messages?scope=${encodeURIComponent(TOKEN_SCOPE)}`,
    );
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(requestInit?.method).toBe("POST");
    assertAgentAuthHeaders(requestInit?.headers as Headers);
    expect(JSON.parse(String(requestInit?.body))).toEqual({ body: "hi room" });
    expect(parsePrintedJson(output.stdout)).toEqual(payload);
  });

  it("DMs a subject creator wallet resolved from the revenue subject", async () => {
    const configPath = createConfigPath();
    const payload = { data: { id: 10, scope: DM_SCOPE, body: "Question about your token" } };
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ ok: true, subject: { subject_id: SUBJECT_ID, creator_address: CREATOR_WALLET } }),
    );
    fetchMock.mockResolvedValueOnce(jsonResponse(payload, 201));

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "dm",
        SUBJECT_ID,
        "--message",
        "Question about your token",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(`${expectedBaseUrl}/api/autolaunch/v1/app/subjects/${SUBJECT_ID}`);
    expect(fetchMock.mock.calls[1]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/chat/messages?scope=${encodeURIComponent(DM_SCOPE)}`,
    );
    const [, requestInit] = fetchMock.mock.calls[1] ?? [];
    expect(requestInit?.method).toBe("POST");
    assertAgentAuthHeaders(requestInit?.headers as Headers);
    expect(JSON.parse(String(requestInit?.body))).toEqual({ body: "Question about your token" });
    expect(parsePrintedJson(output.stdout)).toEqual(payload);
  });

  it("fails the DM when the revenue subject has no creator wallet", async () => {
    const configPath = createConfigPath();
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ ok: true, subject: { subject_id: SUBJECT_ID, creator_address: null } }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "dm", SUBJECT_ID, "--message", "hello", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(output.stderr).toContain("no creator wallet to DM");
  });

  it("DMs a wallet address directly without resolving a subject", async () => {
    const configPath = createConfigPath();
    const payload = { data: { id: 11, scope: DM_SCOPE, body: "hello" } };
    fetchMock.mockResolvedValueOnce(jsonResponse(payload, 201));

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "dm", CREATOR_WALLET, "--message", "hello", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/chat/messages?scope=${encodeURIComponent(DM_SCOPE)}`,
    );
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(requestInit?.method).toBe("POST");
    assertAgentAuthHeaders(requestInit?.headers as Headers);
    expect(JSON.parse(String(requestInit?.body))).toEqual({ body: "hello" });
    expect(parsePrintedJson(output.stdout)).toEqual(payload);
  });

  it("rejects DM targets that are neither subject ids nor wallet addresses", async () => {
    const configPath = createConfigPath();

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "dm", "not-a-target", "--message", "hello", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(output.stderr).toContain("invalid DM target");
  });

  it("lists server-stored DM scopes", async () => {
    const configPath = createConfigPath();
    const payload = { data: [{ scope: DM_SCOPE, counterpart_wallet_address: CREATOR_WALLET, last_message_at: null }] };
    fetchMock.mockResolvedValueOnce(jsonResponse(payload));

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "dm", "list", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(`${expectedBaseUrl}/api/autolaunch/v1/agent/chat/dms`);
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(requestInit?.method).toBe("GET");
    assertAgentAuthHeaders(requestInit?.headers as Headers);
    expect(parsePrintedJson(output.stdout)).toEqual(payload);
  });
});
