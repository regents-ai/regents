import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const {
  writeContractMock,
  waitForReceiptMock,
  sendTransactionMock,
  callMock,
  estimateGasMock,
  safeInitMock,
  getSafeAddressFromDeploymentTxMock,
} = vi.hoisted(() => ({
  writeContractMock: vi.fn(),
  waitForReceiptMock: vi.fn(),
  sendTransactionMock: vi.fn(),
  callMock: vi.fn(),
  estimateGasMock: vi.fn(),
  safeInitMock: vi.fn(),
  getSafeAddressFromDeploymentTxMock: vi.fn(),
}));

const { buildAgentAuthHeadersMock, loadAgentAuthStateMock, requireAgentAuthStateMock } = vi.hoisted(() => ({
  buildAgentAuthHeadersMock: vi.fn(),
  loadAgentAuthStateMock: vi.fn(),
  requireAgentAuthStateMock: vi.fn(),
}));

const { questionMock, closePromptMock } = vi.hoisted(() => ({
  questionMock: vi.fn(),
  closePromptMock: vi.fn(),
}));

vi.mock("node:readline/promises", () => ({
  default: {
    createInterface: () => ({
      question: questionMock,
      close: closePromptMock,
    }),
  },
}));

vi.mock("../../src/commands/agent-auth.js", () => ({
  buildAgentAuthHeaders: buildAgentAuthHeadersMock,
  loadAgentAuthState: loadAgentAuthStateMock,
  requireAgentAuthState: requireAgentAuthStateMock,
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: (privateKey: string) => ({
    address:
      privateKey ===
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ? "0x00000000000000000000000000000000000000aa"
        : "0x00000000000000000000000000000000000000bb",
    signMessage: async () => "0xsigned",
  }),
}));

vi.mock("viem/chains", () => ({
  base: { id: 8453, name: "Base" },
  baseSepolia: { id: 84532, name: "Base Sepolia" },
}));

vi.mock("viem", () => ({
  http: (url: string) => ({ url }),
  isAddress: (value: string) => /^0x[0-9a-fA-F]{40}$/u.test(value),
  isHex: (value: string) => /^0x[0-9a-fA-F]*$/u.test(value),
  createWalletClient: () => ({
    writeContract: writeContractMock,
    sendTransaction: sendTransactionMock,
  }),
  createPublicClient: () => ({
    call: callMock,
    estimateGas: estimateGasMock,
    waitForTransactionReceipt: waitForReceiptMock,
  }),
  parseEventLogs: () => [
    {
      args: {
        agentId: 42n,
      },
    },
  ],
}));

vi.mock("@safe-global/protocol-kit", () => ({
  __esModule: true,
  default: {
    init: safeInitMock,
  },
  getSafeAddressFromDeploymentTx: getSafeAddressFromDeploymentTxMock,
}));

describe("autolaunch CLI command group", () => {
  const expectedBaseUrl = "https://regents.sh";
  // Only mutate individual keys on process.env: replacing the whole object
  // detaches it from the real environment, and os.homedir() would keep
  // returning the real home directory instead of the per-test temp HOME.
  const touchedEnvKeys = [
    "HOME",
    "AUTOLAUNCH_SESSION_COOKIE",
    "AUTOLAUNCH_PRIVY_BEARER_TOKEN",
    "AUTOLAUNCH_DISPLAY_NAME",
    "AUTOLAUNCH_WALLET_ADDRESS",
    "AUTOLAUNCH_AGENT_PRIVATE_KEY",
    "REGENT_PRIVATE_KEY",
    "REGENT_WALLET_PRIVATE_KEY",
    "BASE_MAINNET_RPC_URL",
    "BASE_SEPOLIA_RPC_URL",
    "AUTOLAUNCH_ERC8004_SUBGRAPH_URL",
    "AUTOLAUNCH_IDENTITY_REGISTRY_ADDRESS",
    "NO_COLOR",
    "TERM",
  ] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  const originalStdoutIsTTY = process.stdout.isTTY;
  const fetchMock = vi.fn<typeof fetch>();
  const tempDirs: string[] = [];
  const expectedAgentWallet = "0x00000000000000000000000000000000000000aa";
  const pairingRegistryAddress = "0x3333333333333333333333333333333333333333";
  const configuredIdentityRegistryAddress = "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432";
  const pairingBaseSepoliaAgentId = `eip155:84532:${pairingRegistryAddress}:42`;
  const mainnetAgentId = `eip155:8453:${configuredIdentityRegistryAddress}:42`;
  const baseSepoliaLaunchableAgentId = `eip155:84532:${configuredIdentityRegistryAddress}:77`;
  const mainnetLaunchableAgentId = `eip155:8453:${configuredIdentityRegistryAddress}:88`;
  const preparedSubjectAction = (data: `0x${string}`, subjectId = "subject_123") => {
    const base = {
      action_id: `subject_${data.slice(2)}`,
      resource: "subject",
      resource_id: subjectId,
      action: "claim_usdc",
      chain_id: 84532,
      expected_signer: expectedAgentWallet,
      expires_at: "2999-01-01T00:00:00.000Z",
      idempotency_key: `idem_${data.slice(2)}`,
      risk_copy: "Claims available subject rewards.",
    } as const;

    return {
      ...base,
      wallet_action: {
        ...base,
        owner_product: "autolaunch",
        to: "0x5555555555555555555555555555555555555555",
        value: "0x0",
        data,
        simulation: { required: false, status: "not_required", block_number: null },
      },
    };
  };
  const preparedContractAction = (
    data: `0x${string}`,
    resource: string,
    action: string,
    resourceId = "job_123",
  ) => {
    const base = preparedSubjectAction(data, resourceId);
    return {
      ...base,
      resource,
      resource_id: resourceId,
      action,
      risk_copy: `Prepares ${action}.`,
      wallet_action: {
        ...base.wallet_action,
        resource,
        resource_id: resourceId,
        action,
        risk_copy: `Prepares ${action}.`,
      },
    };
  };
  const createConfigPath = () => {
    const tempDir = fs.mkdtempSync(
      path.join(os.tmpdir(), "regents-cli-autolaunch-"),
    );
    tempDirs.push(tempDir);

    const configPath = path.join(tempDir, "regent.config.json");
    writeInitialConfig(configPath);
    return configPath;
  };

  const writePlatformSession = (origin = expectedBaseUrl): string => {
    const homeDir = process.env.HOME;
    if (!homeDir) {
      throw new Error("HOME is not set for the test");
    }
    const sessionPath = path.join(homeDir, ".regent", "platform", "session.json");
    fs.mkdirSync(path.dirname(sessionPath), { recursive: true });
    fs.writeFileSync(
      sessionPath,
      JSON.stringify(
        {
          version: 1,
          origin,
          cookie: "_platform_phx_key=session-cookie",
          csrfToken: "csrf-token",
          savedAt: "2026-04-01T00:00:00.000Z",
        },
        null,
        2,
      ),
    );
    return sessionPath;
  };

  const setStdoutTty = (value: boolean | undefined): void => {
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
  const collapsePanelText = (value: string): string =>
    value.replace(/[│╭╮╰╯─]/gu, " ").replace(/\s+/g, " ").trim();

  const assertLaunchRequestBody = (
    body: unknown,
    expected: Record<string, unknown>,
  ) => {
    const payload = JSON.parse(String(body)) as Record<string, unknown>;

    const containsLegacyLaunchField = (value: unknown): boolean => {
      if (!value || typeof value !== "object") {
        return false;
      }

      if (Array.isArray(value)) {
        return value.some(containsLegacyLaunchField);
      }

      return Object.entries(value as Record<string, unknown>).some(
        ([key, nested]) =>
          key.includes("treasury") ||
          key.includes("recovery") ||
          containsLegacyLaunchField(nested),
      );
    };

    expect(payload).toMatchObject(expected);
    expect(containsLegacyLaunchField(payload)).toBe(false);
  };

  const assertAgentAuthHeaders = (headers: Headers | undefined) => {
    expect(headers?.get("x-siwa-receipt")).toBe("receipt_123");
    expect(headers?.get("x-key-id")).toBe(expectedAgentWallet);
    expect(headers?.get("x-agent-wallet-address")).toBe(expectedAgentWallet);
    expect(headers?.get("x-agent-chain-id")).toBe("84532");
    expect(headers?.get("x-agent-registry-address")).toBe(
      "0x3333333333333333333333333333333333333333",
    );
    expect(headers?.get("x-agent-token-id")).toBe("42");
    expect(headers?.get("signature")).toBe("sig1=:ZmFrZQ==:");
  };

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    for (const key of touchedEnvKeys) {
      savedEnv[key] = process.env[key];
    }
    // Commands that run without --config fall back to ~/.regent; point HOME
    // at a temp dir so those writes (plans, logs) never touch the real home.
    const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-autolaunch-home-"));
    tempDirs.push(homeDir);
    process.env.HOME = homeDir;
    delete process.env.AUTOLAUNCH_SESSION_COOKIE;
    delete process.env.AUTOLAUNCH_PRIVY_BEARER_TOKEN;
    delete process.env.AUTOLAUNCH_DISPLAY_NAME;
    delete process.env.AUTOLAUNCH_WALLET_ADDRESS;
    delete process.env.AUTOLAUNCH_AGENT_PRIVATE_KEY;
    delete process.env.REGENT_PRIVATE_KEY;
    delete process.env.REGENT_WALLET_PRIVATE_KEY;
    delete process.env.BASE_MAINNET_RPC_URL;
    delete process.env.BASE_SEPOLIA_RPC_URL;
    delete process.env.AUTOLAUNCH_ERC8004_SUBGRAPH_URL;
    delete process.env.AUTOLAUNCH_IDENTITY_REGISTRY_ADDRESS;
    fetchMock.mockReset();
    buildAgentAuthHeadersMock.mockReset();
    loadAgentAuthStateMock.mockReset();
    requireAgentAuthStateMock.mockReset();
    questionMock.mockReset();
    closePromptMock.mockReset();
    questionMock.mockResolvedValue("y");
    writeContractMock.mockReset();
    waitForReceiptMock.mockReset();
    sendTransactionMock.mockReset();
    callMock.mockReset();
    estimateGasMock.mockReset();
    safeInitMock.mockReset();
    getSafeAddressFromDeploymentTxMock.mockReset();

    sendTransactionMock.mockResolvedValue(
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    );
    waitForReceiptMock.mockResolvedValue({ status: "success", logs: [] });
    callMock.mockResolvedValue({ data: "0x" });
    estimateGasMock.mockResolvedValue(21_000n);
    getSafeAddressFromDeploymentTxMock.mockReturnValue(
      "0x4444444444444444444444444444444444444444",
    );
    process.env.AUTOLAUNCH_ERC8004_SUBGRAPH_URL =
      "https://erc8004.example/graphql";
    process.env.AUTOLAUNCH_IDENTITY_REGISTRY_ADDRESS = configuredIdentityRegistryAddress;
    buildAgentAuthHeadersMock.mockResolvedValue({
      "x-siwa-receipt": "receipt_123",
      "x-key-id": expectedAgentWallet,
      "x-agent-wallet-address": expectedAgentWallet,
      "x-agent-chain-id": "84532",
      "x-agent-registry-address": "0x3333333333333333333333333333333333333333",
      "x-agent-token-id": "42",
      "signature-input":
        'sig1=("@method" "@path");created=1700000000;expires=1700000120;nonce="sig-nonce-fixed";keyid="0x00000000000000000000000000000000000000aa"',
      signature: "sig1=:ZmFrZQ==:",
    });
    requireAgentAuthStateMock.mockReturnValue({
      config: {
        auth: {
          audience: "autolaunch",
          defaultChainId: 84532,
        },
        services: {
          siwa: {
            baseUrl: "http://127.0.0.1:4000",
            requestTimeoutMs: 10_000,
          },
        },
      },
      session: {
        receipt: "receipt_123",
        walletAddress: expectedAgentWallet,
        chainId: 84532,
        registryAddress: "0x3333333333333333333333333333333333333333",
        tokenId: "42",
        audience: "autolaunch",
      },
      identity: {
        walletAddress: expectedAgentWallet,
        chainId: 84532,
        registryAddress: "0x3333333333333333333333333333333333333333",
        tokenId: "42",
      },
    });
    loadAgentAuthStateMock.mockReturnValue({
      identity: {
        walletAddress: expectedAgentWallet,
        chainId: 84532,
        registryAddress: "0x3333333333333333333333333333333333333333",
        tokenId: "42",
        label: "Atlas Agent",
      },
    });
    safeInitMock.mockResolvedValue({
      getAddress: vi
        .fn()
        .mockResolvedValue("0x4444444444444444444444444444444444444444"),
      isSafeDeployed: vi.fn().mockResolvedValue(false),
      createSafeDeploymentTransaction: vi.fn().mockResolvedValue({
        to: "0x5555555555555555555555555555555555555555",
        data: "0xabcdef",
        value: "0x0",
      }),
      getContractVersion: vi.fn().mockReturnValue("1.4.1"),
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
    setStdoutTty(originalStdoutIsTTY);
    while (tempDirs.length > 0) {
      const dir = tempDirs.pop();
      if (dir) {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    }
  });

  it("pairs the local agent with an Autolaunch browser profile", async () => {
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          session: {
            session_id: "pair_123",
            status: "completed",
            pairing_code: null,
            agent: {
              agent_id: pairingBaseSepoliaAgentId,
              agent_wallet_address: expectedAgentWallet,
              agent_chain_id: 84532,
              agent_registry_address: pairingRegistryAddress,
              agent_token_id: "42",
              agent_label: "Atlas Agent",
              connected_at: "2026-05-06T14:30:00Z",
            },
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
        "autolaunch",
        "pair",
        "--code",
        "AL-ABC234-DEF56789",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/app/agent-pairings/complete`,
    );
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    const headers = requestInit?.headers as Headers;
    expect(headers.get("x-siwa-receipt")).toBeNull();
    expect(JSON.parse(String(requestInit?.body))).toMatchObject({
      pairing_code: "AL-ABC234-DEF56789",
      challenge_message: "Autolaunch agent pairing\n\nPairing: AL-ABC234\nNonce: ABC234",
      agent_wallet_address: expectedAgentWallet,
      agent_chain_id: 84532,
      agent_registry_address: "0x3333333333333333333333333333333333333333",
      agent_token_id: "42",
      agent_label: "Atlas Agent",
      signature_type: "evm_personal_sign",
      signature: "0xsigned",
    });
    expect(output.stdout).toContain("AUTOLAUNCH PAIRING COMPLETE");
    expect(output.stdout).toContain("completed");
    expect(output.stdout).toContain("pair_123");
    expect(output.stdout).toContain(`Atlas Agent (${pairingBaseSepoliaAgentId})`);
    expect(output.stdout).toContain("0x0000...00aa");
    expect(output.stdout).toContain("No private keys were shared and no funds moved.");
  });

  it("can print the Autolaunch pairing response as JSON", async () => {
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          session: {
            session_id: "pair_456",
            status: "completed",
            pairing_code: null,
            agent: {
              agent_id: pairingBaseSepoliaAgentId,
              agent_wallet_address: expectedAgentWallet,
              agent_chain_id: 84532,
              agent_registry_address: pairingRegistryAddress,
              agent_token_id: "42",
              agent_label: "Atlas Agent",
              connected_at: "2026-05-06T14:30:00Z",
            },
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
        "autolaunch",
        "pair",
        "--code",
        "AL-ABC234-DEF56789",
        "--json",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(parsePrintedJson<{ session: { session_id: string } }>(output.stdout)).toMatchObject({
      session: { session_id: "pair_456" },
    });
    expect(output.stdout).not.toContain("AUTOLAUNCH PAIRING COMPLETE");
  });

  it("starts a terminal-created profile connection as JSON", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          connection: {
            connection_id: "conn_123",
            status: "pending",
            connection_code: "AL-ABC234-DEF56789",
            connect_url: "/connect/AL-ABC234-DEF56789",
            expires_at: "2026-05-18T16:00:00Z",
            completed_at: null,
            plan_id: "plan_alpha",
            agent_id: pairingBaseSepoliaAgentId,
            agent_wallet_address: expectedAgentWallet,
            agent_chain_id: 84532,
            agent_registry_address: pairingRegistryAddress,
            agent_token_id: "42",
            agent_label: "Atlas Agent",
            human: null,
          },
        }),
        {
          status: 201,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "connect",
        "start",
        "--plan",
        "plan_alpha",
        "--label",
        "Atlas Agent",
        "--json",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/agent-connections`,
    );
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    assertAgentAuthHeaders(requestInit?.headers as Headers);
    expect(JSON.parse(String(requestInit?.body))).toMatchObject({
      plan_id: "plan_alpha",
      agent_label: "Atlas Agent",
    });
    expect(
      parsePrintedJson<{ connection: { connection_id: string; connection_code: string } }>(
        output.stdout,
      ),
    ).toMatchObject({
      connection: {
        connection_id: "conn_123",
        connection_code: "AL-ABC234-DEF56789",
      },
    });
  });

  it("prints a terminal panel for profile connection links", async () => {
    useHumanTerminal();
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          connection: {
            connection_id: "conn_456",
            status: "pending",
            connection_code: "AL-ABC234-DEF56789",
            connect_url: "/connect/AL-ABC234-DEF56789",
            expires_at: "2026-05-18T16:00:00Z",
            completed_at: null,
            plan_id: null,
            agent_id: pairingBaseSepoliaAgentId,
            agent_wallet_address: expectedAgentWallet,
            agent_chain_id: 84532,
            agent_registry_address: pairingRegistryAddress,
            agent_token_id: "42",
            agent_label: "Atlas Agent",
            human: null,
          },
        }),
        {
          status: 201,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "connect", "start"]),
    );

    expect(output.result).toBe(0);
    const text = collapsePanelText(stripAnsi(output.stdout));
    expect(text).toContain("AUTOLAUNCH PROFILE CONNECTION");
    expect(text).toContain("AL-ABC234-DEF56789");
    expect(text).toContain(`${expectedBaseUrl}/connect/AL-ABC234-DEF56789`);
    expect(text).toContain("Ask the human operator to open the URL");
  });

  it("lists active auctions via regents autolaunch", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          items: [
            {
              id: "auc_1",
              agent_id: pairingBaseSepoliaAgentId,
              agent_name: "Atlas",
              symbol: "ATLAS",
              chain: "base-sepolia",
              chain_id: 84532,
              status: "active",
              bidders: 2,
              current_clearing_price: "1000000",
              total_bid_volume: "5000000",
              trust: {
                erc8004: {
                  connected: true,
                  token_id: "42",
                  chain_id: 84532,
                },
                ens: {
                  connected: true,
                  name: "atlas.eth",
                },
                world: {
                  connected: false,
                  network: "world",
                  human_id: null,
                  launch_count: 0,
                },
                x: {
                  connected: true,
                  handle: "atlas_agent",
                  profile_url: "https://x.com/atlas_agent",
                  verified_at: "2026-03-29T12:00:00Z",
                },
              },
            },
          ],
          generated_at: "2026-03-29T12:00:00Z",
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "auctions",
        "list",
        "--status",
        "active",
        "--sort",
        "recently_launched",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/auctions?sort=recently_launched&status=active`,
    );
    assertAgentAuthHeaders(fetchMock.mock.calls[0]?.[1]?.headers as Headers);
    expect(
      parsePrintedJson<{
        items: Array<{ id: string; trust: { x: { handle: string | null } } }>;
      }>(output.stdout),
    ).toMatchObject({
      items: [{ id: "auc_1", trust: { x: { handle: "atlas_agent" } } }],
    });
  });

  it("supports non-numeric agent ids for autolaunch agent show/readiness routes", async () => {
    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ ok: true, agent: { id: "agent:alpha" } }),
          {
            status: 200,
            headers: { "content-type": "application/json" },
          },
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true, readiness: { ready: true } }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    const showOutput = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "agent", "agent:alpha"]),
    );
    const readinessOutput = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "agent", "readiness", "agent:alpha"]),
    );

    expect(showOutput.result).toBe(0);
    expect(readinessOutput.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/agents/agent%3Aalpha`,
    );
    expect(fetchMock.mock.calls[1]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/agents/agent%3Aalpha/readiness`,
    );
    assertAgentAuthHeaders(fetchMock.mock.calls[0]?.[1]?.headers as Headers);
    assertAgentAuthHeaders(fetchMock.mock.calls[1]?.[1]?.headers as Headers);
    expect(parsePrintedJson<{ ok: boolean }>(showOutput.stdout)).toMatchObject({
      ok: true,
    });
    expect(
      parsePrintedJson<{ ok: boolean }>(readinessOutput.stdout),
    ).toMatchObject({ ok: true });
  });

  it("plans an ENS link through the shared autolaunch API", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          plan: { verify_status: "ens_record_missing" },
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "ens",
        "plan",
        "--ens",
        "vitalik.eth",
        "--identity",
        "1:42",
        "--include-reverse",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/ens/link/plan`,
    );
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(JSON.parse(String(requestInit?.body))).toMatchObject({
      ens_name: "vitalik.eth",
      identity_id: "1:42",
      include_reverse: true,
    });
    expect(
      parsePrintedJson<{ ok: boolean; plan: { verify_status: string } }>(
        output.stdout,
      ),
    ).toEqual({
      ok: true,
      plan: { verify_status: "ens_record_missing" },
    });
  });

  it("prepares bidirectional ENS link transactions through autolaunch", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          prepared: {
            ensip25: { tx: { to: "0xresolver" } },
            erc8004: { tx: { to: "0xregistry" } },
            reverse: { tx: { to: "0xreverse" } },
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
        "autolaunch",
        "ens",
        "prepare-bidirectional",
        "--ens",
        "vitalik.eth",
        "--chain-id",
        "8453",
        "--agent-id",
        "42",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/ens/link/prepare-bidirectional`,
    );
    expect(
      parsePrintedJson<{
        ok: boolean;
        prepared: { ensip25: { tx: { to: string } } };
      }>(output.stdout),
    ).toMatchObject({
      ok: true,
      prepared: {
        ensip25: { tx: { to: "0xresolver" } },
      },
    });
  });

  it("shows subject revenue state through the shared autolaunch API", async () => {
    const configPath = createConfigPath();
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          subject: {
            subject_id: "0xabc",
            splitter_address: "0x9999999999999999999999999999999999999999",
            recognized_revenue_proof: {
              source: "onchain_splitter",
              chain_id: 84532,
              ingress: "0x7777777777777777777777777777777777777777",
              revsplit: "0x9999999999999999999999999999999999999999",
              block_number: 123456,
              amount: "125",
              recipient_lane: "subject_revenue",
              status: "fresh",
            },
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
        "autolaunch",
        "subjects",
        "get",
        "0xabc",
        "--config",
        configPath,
      ]),
    );

    expect(output.result, output.stderr).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/subjects/0xabc`,
    );
    expect(
      parsePrintedJson<{
        subject: {
          subject_id: string;
          recognized_revenue_proof: {
            source: string;
            chain_id: number;
            ingress: string;
            revsplit: string;
            block_number: number;
            amount: string;
            recipient_lane: string;
            status: string;
          };
        };
      }>(output.stdout),
    ).toMatchObject({
      subject: {
        subject_id: "0xabc",
        recognized_revenue_proof: {
          source: "onchain_splitter",
          chain_id: 84532,
          ingress: "0x7777777777777777777777777777777777777777",
          revsplit: "0x9999999999999999999999999999999999999999",
          block_number: 123456,
          amount: "125",
          recipient_lane: "subject_revenue",
          status: "fresh",
        },
      },
    });
  });

  it("uses the current subject revenue read routes", async () => {
    const configPath = createConfigPath();
    fetchMock
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true, token_address: "0xabc", subjects: [] }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true, subject_id: "subject_123", staking: {} }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ ok: true, subject_id: "subject_123", settlements: [] }),
          {
            status: 200,
            headers: { "content-type": "application/json" },
          },
        ),
      );

    const byToken = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "subjects",
        "by-token",
        "--token",
        "0xabc",
        "--config",
        configPath,
      ]),
    );
    const staking = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "subjects",
        "staking",
        "subject_123",
        "--config",
        configPath,
      ]),
    );
    const buybacks = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "subjects",
        "buybacks",
        "subject_123",
        "--config",
        configPath,
      ]),
    );
    expect(byToken.result, byToken.stderr).toBe(0);
    expect(staking.result, staking.stderr).toBe(0);
    expect(buybacks.result, buybacks.stderr).toBe(0);
    expect(fetchMock.mock.calls.map((call) => call[0])).toEqual([
      `${expectedBaseUrl}/api/autolaunch/v1/agent/subjects/by-token/0xabc`,
      `${expectedBaseUrl}/api/autolaunch/v1/agent/subjects/subject_123/staking`,
      `${expectedBaseUrl}/api/autolaunch/v1/agent/subjects/subject_123/buybacks`,
    ]);
  });

  it("renders prepared Autolaunch ingress sweeps as a concise human summary", async () => {
    useHumanTerminal();
    const configPath = createConfigPath();
    const ingressAddress = "0x7777777777777777777777777777777777777777";
    const prepared = preparedContractAction("0x7acb7757", "ingress_account", "sweep", "subject_123");
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          subject_id: "subject_123",
          prepared,
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "subjects",
        "sweep-ingress",
        "subject_123",
        "--address",
        ingressAddress,
        "--config",
        configPath,
      ]),
    );

    const text = collapsePanelText(stripAnsi(output.stdout));
    expect(output.result, output.stderr).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/contracts/subjects/subject_123/ingress_account/sweep/prepare`,
    );
    expect(JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))).toEqual({
      ingress_address: ingressAddress,
    });
    expect(text).toContain("AUTOLAUNCH WALLET ACTION");
    expect(text).toContain("sweep");
    expect(text).toContain("Review this request before submitting.");
    expect(text).toContain("Run the same command with --submit when ready.");
    expect(text).toContain("Nothing changes until the transaction is submitted and confirmed.");
  });

  it("submits a payment link create action from the nested prepared action", async () => {
    const configPath = createConfigPath();
    const salt = "0x1111111111111111111111111111111111111111111111111111111111111111";
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.BASE_SEPOLIA_RPC_URL = "https://base-sepolia.example";
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          subject_id: "subject_123",
          prepared: preparedContractAction("0x42852610", "payment_link_factory", "create", "subject_123"),
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "payment-links",
        "create",
        "--subject",
        "subject_123",
        "--label",
        "Invoice receiver",
        "--salt",
        salt,
        "--submit",
        "--config",
        configPath,
      ]),
    );

    expect(output.result, output.stderr).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/contracts/subjects/subject_123/payment_link_factory/create/prepare`,
    );
    expect(JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))).toEqual({
      canonical: false,
      label: "Invoice receiver",
      salt,
    });
    expect(sendTransactionMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0x5555555555555555555555555555555555555555",
        data: "0x42852610",
        value: 0n,
      }),
    );
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      tx_hash: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    });
  });

  it("prepares payment link canonical changes without prompting", async () => {
    const configPath = createConfigPath();
    const receiver = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          subject_id: "subject_123",
          prepared: preparedContractAction(
            "0x7acb7757",
            "payment_link_factory",
            "set_canonical",
            "subject_123",
          ),
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "payment-links",
        "set-canonical",
        "--subject",
        "subject_123",
        "--address",
        receiver,
        "--canonical",
        "true",
        "--config",
        configPath,
      ]),
    );

    expect(output.result, output.stderr).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/contracts/subjects/subject_123/payment_link_factory/set_canonical/prepare`,
    );
    expect(JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))).toEqual({
      canonical: "true",
      payment_link: receiver,
    });
    expect(questionMock).not.toHaveBeenCalled();
  });

  it("prepares strategy migration through the contracts API", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          prepared: preparedContractAction("0x8fd3ab80", "strategy", "migrate"),
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "strategy",
        "migrate",
        "--job",
        "job_123",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/contracts/jobs/job_123/strategy/migrate/prepare`,
    );
    expect(
      parsePrintedJson<{ prepared: { action: string } }>(output.stdout),
    ).toMatchObject({
      prepared: { action: "migrate" },
    });
  });

  it("prepares quote token sweeps through the strategy", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          prepared: preparedContractAction(
            "0x73d8b8d9",
            "strategy",
            "sweep_quote_token",
          ),
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "strategy",
        "sweep-quote-token",
        "--job",
        "job_123",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/contracts/jobs/job_123/strategy/sweep_quote_token/prepare`,
    );
    expect(JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))).toEqual({});
    expect(
      parsePrintedJson<{ prepared: { resource: string; action: string } }>(output.stdout),
    ).toMatchObject({
      prepared: {
        resource: "strategy",
        action: "sweep_quote_token",
      },
    });
  });

  it("prepares unused-token claims through the auction", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          prepared: preparedContractAction(
            "0x5dd13ca7",
            "auction",
            "claim_unused_tokens",
          ),
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "auction",
        "claim-unused-tokens",
        "--job",
        "job_123",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/contracts/jobs/job_123/auction/claim_unused_tokens/prepare`,
    );
    expect(JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body))).toEqual({});
    expect(
      parsePrintedJson<{ prepared: { resource: string; action: string } }>(output.stdout),
    ).toMatchObject({
      prepared: {
        resource: "auction",
        action: "claim_unused_tokens",
      },
    });
  });

  it("reads the contracts admin overview through the Regent web session", async () => {
    const configPath = createConfigPath();
    const sessionFile = writePlatformSession();
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          fee_vault_address: "0x5555555555555555555555555555555555555555",
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "contracts",
        "admin",
        "--config",
        configPath,
        "--session-file",
        sessionFile,
      ]),
    );

    expect(output.result, output.stderr).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/app/contracts/admin`,
    );
    expect((fetchMock.mock.calls[0]?.[1]?.headers as Headers).get("cookie")).toBe("_platform_phx_key=session-cookie");
    expect(parsePrintedJson<{ fee_vault_address: string }>(output.stdout)).toMatchObject({
      fee_vault_address: "0x5555555555555555555555555555555555555555",
    });
  });

  it("prepares factory authorized creator changes through the contracts API", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          prepared: preparedContractAction(
            "0xe1434f4e",
            "revenue_share_factory",
            "set_authorized_creator",
            "admin",
          ),
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "factory",
        "revenue-share",
        "set-authorized-creator",
        "--account",
        "0x00000000000000000000000000000000000000aa",
        "--enabled",
        "true",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/contracts/admin/revenue_share_factory/set_authorized_creator/prepare`,
    );
    expect(
      JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      account: "0x00000000000000000000000000000000000000aa",
      enabled: "true",
    });
    expect(
      parsePrintedJson<{ prepared: { resource: string } }>(output.stdout),
    ).toMatchObject({
      prepared: { resource: "revenue_share_factory" },
    });
  });

  it("lists ERC-8004 identities for a wallet owner", async () => {
    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            data: {
              agents: [
                {
                  chainId: "84532",
                  agentId: "77",
                  owner: "0x00000000000000000000000000000000000000aa",
                  operators: [],
                  agentWallet: null,
                  registrationFile: { name: "Owned Agent", active: true },
                },
              ],
            },
          }),
          {
            status: 200,
            headers: { "content-type": "application/json" },
          },
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ data: { agents: [] } }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ data: { agents: [] } }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "identities",
        "list",
        "--chain",
        "base-sepolia",
        "--owner",
        "0x00000000000000000000000000000000000000aa",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(
      parsePrintedJson<{ launchable: Array<{ agent_id: string }> }>(
        output.stdout,
      ),
    ).toMatchObject({
      ok: true,
      chain_id: 84532,
      owner_address: "0x00000000000000000000000000000000000000aa",
      launchable: [{ agent_id: baseSepoliaLaunchableAgentId }],
    });
  });

  it("mints an ERC-8004 identity and reports the new agent id", async () => {
    process.env.AUTOLAUNCH_AGENT_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.BASE_MAINNET_RPC_URL = "https://rpc.base.example";
    writeContractMock.mockResolvedValue("0xfeed");
    waitForReceiptMock.mockResolvedValue({
      status: "success",
      blockNumber: 123n,
      logs: [],
    });
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "identities",
        "mint",
        "--chain",
        "base-mainnet",
        "--agent-uri",
        "https://agents.example/alpha.json",
      ]),
    );

    expect(output.result).toBe(0);
    expect(writeContractMock).toHaveBeenCalledTimes(1);
    expect(
      parsePrintedJson<{ agent_id: string | null; chain_id: number }>(
        output.stdout,
      ),
    ).toMatchObject({
      ok: true,
      chain_id: 8453,
      agent_id: mainnetAgentId,
      owner_address: "0x00000000000000000000000000000000000000aa",
      agent_uri: "https://agents.example/alpha.json",
    });
  });

  it("does not report identity mint success when the receipt failed", async () => {
    process.env.AUTOLAUNCH_AGENT_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.BASE_MAINNET_RPC_URL = "https://rpc.base.example";
    writeContractMock.mockResolvedValue("0xfeed");
    waitForReceiptMock.mockResolvedValue({
      status: "reverted",
      blockNumber: 123n,
      logs: [],
    });

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "identities", "mint", "--chain", "base-mainnet"]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("The transaction was not confirmed successfully.");
  });

  it("does not read REGENT_PRIVATE_KEY for Autolaunch identity minting", async () => {
    delete process.env.REGENT_WALLET_PRIVATE_KEY;
    process.env.REGENT_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.BASE_MAINNET_RPC_URL = "https://rpc.base.example";

    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "identities", "mint", "--chain", "base-mainnet"]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain(
      "missing private key (--private-key, AUTOLAUNCH_AGENT_PRIVATE_KEY, or REGENT_WALLET_PRIVATE_KEY)",
    );
    expect(writeContractMock).not.toHaveBeenCalled();
  });

  it("runs the prelaunch wizard on Base mainnet", async () => {
    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_mainnet",
              state: "draft",
              agent_id: mainnetAgentId,
              metadata_draft: { title: "Atlas Coin" },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_mainnet",
              state: "launchable",
              validation_summary: { launchable: true },
            },
            validation: { launchable: true, blockers: [], warnings: [] },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--minimum-raise-quote",
        "10000",
        "--agent-safe-address",
        "0x1111111111111111111111111111111111111111",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(JSON.parse(String(requestInit?.body))).toMatchObject({
      agent_id: mainnetAgentId,
      token_name: "Atlas Coin",
      token_symbol: "ATLAS",
      minimum_raise_quote: "10000",
      agent_safe_address: "0x1111111111111111111111111111111111111111",
    });
  });

  it("can start profile connection during the prelaunch wizard", async () => {
    useHumanTerminal();
    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_connect",
              state: "draft",
              agent_id: mainnetAgentId,
              token_name: "Atlas Coin",
              metadata_draft: { title: "Atlas Coin" },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            connection: {
              connection_id: "conn_plan",
              status: "pending",
              connection_code: "AL-ABC234-DEF56789",
              connect_url: "/connect/AL-ABC234-DEF56789",
              expires_at: "2026-05-18T16:00:00Z",
              completed_at: null,
              plan_id: "plan_connect",
              agent_id: pairingBaseSepoliaAgentId,
              agent_wallet_address: expectedAgentWallet,
              agent_chain_id: 84532,
              agent_registry_address: pairingRegistryAddress,
              agent_token_id: "42",
              agent_label: "Atlas Coin",
              human: null,
            },
          }),
          { status: 201, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_connect",
              state: "launchable",
              validation_summary: { launchable: true },
            },
            validation: {
              launchable: true,
              blockers: [],
              warnings: ["Connect a human profile before publishing."],
              credibility: {
                agent_identity: {
                  label: "Agent identity",
                  status: "ready",
                  message: "Agent identity is ready.",
                },
                human_profile: {
                  label: "Profile connected",
                  status: "needs_action",
                  message: "Connect a human profile before publishing.",
                },
                ens: { label: "ENS name", status: "needs_action", message: "Link an ENS name." },
                erc8004_ensip25: {
                  label: "Agent record",
                  status: "needs_action",
                  message: "Complete the public agent record.",
                },
                world_agentbook: {
                  label: "World proof",
                  status: "pending",
                  message: "World proof can be completed during or after the auction.",
                },
                x: { label: "X", status: "skipped", message: "X is optional." },
                warnings: ["Connect a human profile before publishing."],
              },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--minimum-raise-quote",
        "10000",
        "--agent-safe-address",
        "0x1111111111111111111111111111111111111111",
        "--connect-profile",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls[1]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/agent-connections`,
    );
    expect(JSON.parse(String(fetchMock.mock.calls[1]?.[1]?.body))).toMatchObject({
      plan_id: "plan_connect",
      agent_label: "Atlas Coin",
    });
    const text = collapsePanelText(stripAnsi(output.stdout));
    expect(text).toContain("AUTOLAUNCH PROFILE CONNECTION");
    expect(text).toContain("CREDIBILITY");
    expect(text).toContain("Profile connected");
  });

  it("defaults the prelaunch minimum raise to zero", async () => {
    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_zero",
              state: "draft",
              agent_id: mainnetAgentId,
              metadata_draft: { title: "Atlas Coin" },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_zero",
              state: "validated",
              validation_summary: { launchable: false },
            },
            validation: { launchable: false, blockers: ["Add an image."], warnings: [] },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--agent-safe-address",
        "0x1111111111111111111111111111111111111111",
      ]),
    );

    expect(output.result).toBe(0);
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(JSON.parse(String(requestInit?.body))).toMatchObject({
      minimum_raise_quote: "0",
    });
  });

  it.each([
    { flag: "--name", value: "AT", error: "Token name must be 3 to 15 characters." },
    { flag: "--name", value: "Atlas Token Name", error: "Token name must be 3 to 15 characters." },
    { flag: "--symbol", value: "A", error: "Token symbol must be 2 to 10 characters." },
    { flag: "--symbol", value: "ATLASCOINXX", error: "Token symbol must be 2 to 10 characters." },
    { flag: "--minimum-raise-quote", value: "-1", error: "Minimum $REGENT raise must be 0 or greater, with up to 18 decimals." },
    { flag: "--minimum-raise-quote", value: "0.0000000000000000001", error: "Minimum $REGENT raise must be 0 or greater, with up to 18 decimals." },
  ])("rejects unsafe prelaunch input for $flag", async ({ flag, value, error }) => {
    const args = [
      "autolaunch",
      "prelaunch",
      "wizard",
      "--agent",
      mainnetAgentId,
      "--name",
      "Atlas Coin",
      "--symbol",
      "ATLAS",
      "--minimum-raise-quote",
      "0",
      "--agent-safe-address",
      "0x1111111111111111111111111111111111111111",
    ];
    const index = args.indexOf(flag);
    args[index + 1] = value;

    const output = await captureOutput(() => runCliEntrypoint(args));

    expect(output.result).toBe(2);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(output.stderr).toContain(error);
  });

  it("rejects unsupported prelaunch wizard flags before network calls", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--minimum-raise-quote",
        "0",
        "--agent-safe-address",
        "0x1111111111111111111111111111111111111111",
        "--unsupported-flag",
        "value",
      ]),
    );

    expect(output.result).toBe(2);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(output.stderr).toContain(
      "Unsupported flag for autolaunch prelaunch wizard: --unsupported-flag.",
    );
  });

  it("accepts decimal prelaunch minimum raises with REGENT precision", async () => {
    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_mainnet",
              state: "draft",
              agent_id: mainnetAgentId,
              metadata_draft: { title: "Atlas Coin" },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_mainnet",
              state: "launchable",
              validation_summary: { launchable: true },
            },
            validation: { launchable: true, blockers: [], warnings: [] },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--minimum-raise-quote",
        "1.500000000000000001",
        "--agent-safe-address",
        "0x1111111111111111111111111111111111111111",
      ]),
    );

    expect(output.result).toBe(0);
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    expect(JSON.parse(String(requestInit?.body))).toMatchObject({
      minimum_raise_quote: "1.500000000000000001",
    });
  });

  it("requires interactive confirmation for a high prelaunch minimum raise", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--minimum-raise-quote",
        "50001",
        "--agent-safe-address",
        "0x1111111111111111111111111111111111111111",
      ]),
    );

    expect(output.result).toBe(2);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(output.stderr).toContain("Minimum $REGENT raise above 50000 requires confirmation.");
  });

  it("shows the alpha funds warning at the start of the prelaunch wizard", async () => {
    useHumanTerminal();
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--no-input",
      ]),
    );

    expect(output.result).toBe(2);
    const humanOutput = collapsePanelText(stripAnsi(output.stdout));
    expect(humanOutput).toContain("ALPHA TESTING");
    expect(humanOutput).toContain(
      "Regents apps and the CLI are in ALPHA testing and funds are not guaranteed safe in any shape or form",
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects non-positive interval values for autolaunch jobs watch", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "jobs",
        "watch",
        "job_123",
        "--interval",
        "0",
      ]),
    );

    expect(output.result).toBe(1);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(
      parsePrintedJson<{ error: { message: string } }>(output.stderr),
    ).toEqual({
      error: {
        code: "command_failed",
        message: "--interval must be a positive number",
        next_steps: ["regents autolaunch --help"],
      },
    });
  });

  it("rejects autolaunch job watch requests without a signed-in session", async () => {
    buildAgentAuthHeadersMock.mockRejectedValueOnce(
      new Error("Run `regents identity ensure` before using this command."),
    );
    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "jobs", "watch", "job_123"]),
    );

    expect(output.result).toBe(1);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(output.stderr).toContain(
      "Run `regents identity ensure` before using this command.",
    );
  });

  it("attaches signed agent auth headers when watching an autolaunch job", async () => {
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          ok: true,
          job: { job_id: "job_123", status: "ready" },
          auction: { auction_id: "auc_123" },
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );
    const output = await captureOutput(() =>
      runCliEntrypoint(["autolaunch", "jobs", "watch", "job_123"]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/launch/jobs/job_123`,
    );
    expect(buildAgentAuthHeadersMock).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "GET",
        path: "/api/autolaunch/v1/agent/launch/jobs/job_123",
        audience: "autolaunch",
      }),
    );
    const [, requestInit] = fetchMock.mock.calls[0] ?? [];
    assertAgentAuthHeaders(requestInit?.headers as Headers);
    expect(
      parsePrintedJson<{ job: { job_id: string; status: string } }>(
        output.stdout,
      ),
    ).toMatchObject({
      job: { job_id: "job_123", status: "ready" },
    });
  });

  it("guides a prelaunch wizard flow and saves the local plan", async () => {
    const configPath = createConfigPath();

    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_alpha",
              state: "draft",
              agent_id: mainnetAgentId,
              metadata_draft: { title: "Atlas Launch" },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            asset: {
              asset_id: "asset_alpha",
              public_url: "/prelaunch-assets/asset_alpha.png",
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_alpha",
              state: "draft",
              metadata_draft: {
                title: "Atlas Launch",
                image_url: "/prelaunch-assets/asset_alpha.png",
                image_asset_id: "asset_alpha",
              },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_alpha",
              state: "launchable",
              validation_summary: { launchable: true },
            },
            validation: { launchable: true, blockers: [], warnings: [] },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--config",
        configPath,
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--minimum-raise-quote",
        "10000",
        "--agent-safe-address",
        "0x1111111111111111111111111111111111111111",
        "--title",
        "Atlas Launch",
        "--description",
        "Prepare the Atlas coin launch.",
        "--image-url",
        "https://cdn.example/atlas.png",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/prelaunch/plans`,
    );
    expect(fetchMock.mock.calls[1]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/prelaunch/assets`,
    );
    expect(fetchMock.mock.calls[3]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/prelaunch/plans/plan_alpha/validate`,
    );
    assertLaunchRequestBody(fetchMock.mock.calls[0]?.[1]?.body, {
      agent_id: mainnetAgentId,
      token_name: "Atlas Coin",
      token_symbol: "ATLAS",
      minimum_raise_quote: "10000",
      agent_safe_address: "0x1111111111111111111111111111111111111111",
      metadata_draft: {
        title: "Atlas Launch",
        description: "Prepare the Atlas coin launch.",
      },
    });

    const localPlan = JSON.parse(
      fs.readFileSync(
        path.join(
          path.dirname(configPath),
          "state",
          "autolaunch-plans",
          "plan_alpha.json",
        ),
        "utf8",
      ),
    ) as { plan_id: string; remote_plan: { state: string } };

    expect(localPlan.plan_id).toBe("plan_alpha");
    expect(localPlan.remote_plan.state).toBe("launchable");
    expect(
      parsePrintedJson<{ validation: { launchable: boolean } }>(output.stdout),
    ).toMatchObject({
      validation: { launchable: true },
    });
  });

  it("fails prelaunch wizard input clearly when prompts are disabled", async () => {
    const configPath = createConfigPath();

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--config",
        configPath,
        "--no-input",
      ]),
    );

    expect(output.result).toBe(2);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(output.stderr).toContain("Pass --agent <agent>.");
  });

  it("guides Safe setup and lets the operator wait for the website wallet", async () => {
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "safe",
        "wizard",
        "--config",
        configPath,
        "--backup-signer-address",
        "0x3333333333333333333333333333333333333333",
        "--wait-for-website-wallet",
      ]),
    );

    expect(output.result).toBe(0);
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      status: "waiting_for_website_wallet",
      launch_ready: false,
      threshold: "2-of-3",
      agent_safe_address: null,
      signers: {
        agent: {
          address: "0x00000000000000000000000000000000000000aa",
          source: "config",
        },
        website: {
          address: null,
          source: "missing",
        },
        backup: {
          address: "0x3333333333333333333333333333333333333333",
          source: "flag",
        },
      },
    });
  });

  it("guides Safe setup when all three signers and the Safe are ready", async () => {
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.AUTOLAUNCH_WALLET_ADDRESS =
      "0x2222222222222222222222222222222222222222";
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "safe",
        "wizard",
        "--config",
        configPath,
        "--backup-signer-address",
        "0x3333333333333333333333333333333333333333",
        "--agent-safe-address",
        "0x4444444444444444444444444444444444444444",
      ]),
    );

    expect(output.result).toBe(0);
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      status: "ready_for_launch",
      launch_ready: true,
      threshold: "2-of-3",
      agent_safe_address: "0x4444444444444444444444444444444444444444",
      signers: {
        agent: {
          address: "0x00000000000000000000000000000000000000aa",
          source: "config",
        },
        website: {
          address: "0x2222222222222222222222222222222222222222",
          source: "env",
        },
        backup: {
          address: "0x3333333333333333333333333333333333333333",
          source: "flag",
        },
      },
    });
  });

  it("explains the Agent Safe in human Safe setup output", async () => {
    useHumanTerminal();
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.AUTOLAUNCH_WALLET_ADDRESS =
      "0x2222222222222222222222222222222222222222";
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "safe",
        "wizard",
        "--config",
        configPath,
        "--backup-signer-address",
        "0x3333333333333333333333333333333333333333",
        "--agent-safe-address",
        "0x4444444444444444444444444444444444444444",
      ]),
    );

    expect(output.result).toBe(0);
    const humanOutput = collapsePanelText(stripAnsi(output.stdout));
    expect(humanOutput).toContain("ALPHA TESTING");
    expect(humanOutput).toContain(
      "Regents apps and the CLI are in ALPHA testing and funds are not guaranteed safe in any shape or form",
    );
    expect(humanOutput).toContain("AGENT SAFE");
    expect(humanOutput).toContain("shared control wallet");
    expect(humanOutput).toContain("2-of-3 Safe");
    expect(humanOutput).toContain("hardware wallet is best for mainnet");
  });

  it("creates a Safe on Base mainnet through the autolaunch CLI", async () => {
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.AUTOLAUNCH_WALLET_ADDRESS =
      "0x2222222222222222222222222222222222222222";
    process.env.BASE_MAINNET_RPC_URL = "https://rpc.base.example";
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "safe",
        "create",
        "--config",
        configPath,
        "--backup-signer-address",
        "0x3333333333333333333333333333333333333333",
        "--salt-nonce",
        "12345",
      ]),
    );

    expect(output.result).toBe(0);
    expect(safeInitMock).toHaveBeenCalledWith({
      provider: "https://rpc.base.example",
      signer:
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      predictedSafe: {
        safeAccountConfig: {
          owners: [
            "0x00000000000000000000000000000000000000aa",
            "0x2222222222222222222222222222222222222222",
            "0x3333333333333333333333333333333333333333",
          ],
          threshold: 2,
        },
        safeDeploymentConfig: {
          saltNonce: "12345",
        },
      },
    });
    expect(sendTransactionMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0x5555555555555555555555555555555555555555",
        data: "0xabcdef",
        value: 0n,
      }),
    );
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      status: "created",
      network: "base-mainnet",
      chain_id: 8453,
      threshold: "2-of-3",
      safe_address: "0x4444444444444444444444444444444444444444",
      deployment_tx_hash:
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    });
  });

  it("returns the existing Safe address if that Safe is already deployed", async () => {
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.AUTOLAUNCH_WALLET_ADDRESS =
      "0x2222222222222222222222222222222222222222";
    process.env.BASE_MAINNET_RPC_URL = "https://rpc.base.example";

    safeInitMock.mockResolvedValueOnce({
      getAddress: vi
        .fn()
        .mockResolvedValue("0x4444444444444444444444444444444444444444"),
      isSafeDeployed: vi.fn().mockResolvedValue(true),
      createSafeDeploymentTransaction: vi.fn(),
      getContractVersion: vi.fn().mockReturnValue("1.4.1"),
    });
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "safe",
        "create",
        "--config",
        configPath,
        "--backup-signer-address",
        "0x3333333333333333333333333333333333333333",
        "--salt-nonce",
        "12345",
      ]),
    );

    expect(output.result).toBe(0);
    expect(sendTransactionMock).not.toHaveBeenCalled();
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      status: "already_deployed",
      network: "base-mainnet",
      chain_id: 8453,
      safe_address: "0x4444444444444444444444444444444444444444",
      deployment_tx_hash: null,
    });
  });

  it("tells the launch wizard to use the Safe wizard first when no Safe is provided", async () => {
    const configPath = createConfigPath();
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "prelaunch",
        "wizard",
        "--config",
        configPath,
        "--agent",
        mainnetAgentId,
        "--name",
        "Atlas Coin",
        "--symbol",
        "ATLAS",
        "--minimum-raise-quote",
        "10000",
      ]),
    );

    expect(output.result).toBe(1);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(
      parsePrintedJson<{ error: { message: string } }>(output.stderr),
    ).toEqual({
      error: {
        code: "command_failed",
        message:
          "Agent Safe is required. Run `regents autolaunch safe wizard` first, then rerun with --agent-safe-address <safe>.",
        next_steps: ["Use `regents autolaunch jobs watch <job-id>`."],
      },
    });
  });

  it("runs a launch from a saved plan and watches the job once", async () => {
    const configPath = createConfigPath();
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    const planDir = path.join(
      path.dirname(configPath),
      "state",
      "autolaunch-plans",
    );
    fs.mkdirSync(planDir, { recursive: true });
    fs.writeFileSync(
      path.join(planDir, "plan_alpha.json"),
      `${JSON.stringify({
        plan_id: "plan_alpha",
        saved_at: "2026-03-27T00:00:00Z",
        remote_plan: {
          plan_id: "plan_alpha",
          fallback_operator_wallet:
            "0x00000000000000000000000000000000000000aa",
        },
      })}\n`,
      "utf8",
    );

    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_alpha",
              fallback_operator_wallet:
                "0x00000000000000000000000000000000000000aa",
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: { plan_id: "plan_alpha", state: "launchable" },
            validation: { launchable: true },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            code: "nonce_issued",
            data: {
              nonce: "nonce_alpha",
              walletAddress: "0x00000000000000000000000000000000000000aa",
              chainId: 84532,
              registryAddress: "0x3333333333333333333333333333333333333333",
              tokenId: "42",
              audience: "autolaunch",
              expiresAt: "2026-03-27T00:05:00Z",
            },
          }),
          {
            status: 200,
            headers: { "content-type": "application/json" },
          },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            plan: {
              plan_id: "plan_alpha",
              state: "launched",
              launch_job_id: "job_alpha",
            },
            launch: { job_id: "job_alpha" },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            job: { job_id: "job_alpha", status: "ready" },
            auction: { auction_id: "auc_alpha" },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    const output = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "launch",
        "run",
        "--config",
        configPath,
        "--plan",
        "plan_alpha",
      ]),
    );

    expect(output.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/prelaunch/plans/plan_alpha`,
    );
    expect(fetchMock.mock.calls[2]?.[0]).toBe(
      `https://siwa-server.fly.dev/api/shared/siwa/nonce`,
    );
    expect(requireAgentAuthStateMock).toHaveBeenCalledWith(configPath, {
      audience: "autolaunch",
    });
    const siwaNonceRequest = fetchMock.mock.calls[2]?.[1];
    expect(JSON.parse(String(siwaNonceRequest?.body))).toEqual({
      wallet_address: "0x00000000000000000000000000000000000000aa",
      chain_id: 8453,
      registry_address: "0x3333333333333333333333333333333333333333",
      token_id: "42",
      audience: "autolaunch",
    });
    expect(fetchMock.mock.calls[3]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/prelaunch/plans/plan_alpha/launch`,
    );
    expect(JSON.parse(String(fetchMock.mock.calls[3]?.[1]?.body))).toMatchObject({
      wallet_address: "0x00000000000000000000000000000000000000aa",
      registry_address: "0x3333333333333333333333333333333333333333",
      token_id: "42",
      nonce: "nonce_alpha",
    });
    expect(fetchMock.mock.calls[4]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/launch/jobs/job_alpha`,
    );
    expect(
      parsePrintedJson<{ job: { job_id: string; status: string } }>(
        output.stdout,
      ),
    ).toMatchObject({
      job: { job_id: "job_alpha", status: "ready" },
    });
  });

  it("shows lifecycle monitor, finalize, and vesting status through the new golden path", async () => {
    fetchMock
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            job: { job_id: "job_alpha", status: "ready" },
            recommended_action: "migrate",
            migrate_ready: true,
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            recommended_action: "migrate",
            prepared: preparedContractAction("0x8fd3ab80", "strategy", "migrate"),
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            job_id: "job_alpha",
            vesting_wallet_address:
              "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            release_ready: true,
            releasable_launch_token: 25,
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    const monitorOutput = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "launch",
        "monitor",
        "--job",
        "job_alpha",
      ]),
    );
    const finalizeOutput = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "launch",
        "finalize",
        "--job",
        "job_alpha",
      ]),
    );
    const vestingOutput = await captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "vesting",
        "status",
        "--job",
        "job_alpha",
      ]),
    );

    expect(monitorOutput.result).toBe(0);
    expect(finalizeOutput.result).toBe(0);
    expect(vestingOutput.result).toBe(0);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/lifecycle/jobs/job_alpha`,
    );
    expect(fetchMock.mock.calls[1]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/lifecycle/jobs/job_alpha/finalize/prepare`,
    );
    expect(fetchMock.mock.calls[2]?.[0]).toBe(
      `${expectedBaseUrl}/api/autolaunch/v1/agent/lifecycle/jobs/job_alpha/vesting`,
    );
    expect(
      parsePrintedJson<{ recommended_action: string }>(monitorOutput.stdout),
    ).toMatchObject({
      recommended_action: "migrate",
    });
    expect(
      parsePrintedJson<{ prepared: { action: string } }>(finalizeOutput.stdout),
    ).toMatchObject({
      prepared: { action: "migrate" },
    });
    expect(
      parsePrintedJson<{ release_ready: boolean }>(vestingOutput.stdout),
    ).toMatchObject({
      release_ready: true,
    });
  });
});
