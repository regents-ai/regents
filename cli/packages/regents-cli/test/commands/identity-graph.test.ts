import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { readContractMock } = vi.hoisted(() => ({
  readContractMock: vi.fn(),
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: () => ({
    address: "0x00000000000000000000000000000000000000aa",
    signMessage: async () => "0xsigned",
  }),
}));

vi.mock("viem/chains", () => ({
  base: { id: 8453, name: "Base" },
  mainnet: { id: 1, name: "Ethereum" },
}));

vi.mock("viem", () => ({
  http: (url: string) => ({ url }),
  isAddress: (value: string) => /^0x[0-9a-fA-F]{40}$/u.test(value),
  isHex: (value: string) => /^0x[0-9a-fA-F]*$/u.test(value),
  createWalletClient: () => ({
    sendTransaction: vi.fn(),
  }),
  createPublicClient: () => ({
    readContract: readContractMock,
    call: vi.fn(),
    estimateGas: vi.fn(),
    waitForTransactionReceipt: vi.fn(),
  }),
}));

interface GraphCheckPayload {
  readonly item: string;
  readonly status: string;
  readonly detail: string;
  readonly reason?: string;
  readonly next?: string;
}

interface GraphPayload {
  readonly ok: boolean;
  readonly command: string;
  readonly status: string;
  readonly agent_id: string | null;
  readonly wallet_tuple: {
    readonly wallet_address: string;
    readonly chain_id: number;
    readonly registry_address: string;
    readonly token_id: string;
  } | null;
  readonly product_links: {
    readonly platform: Record<string, unknown> | null;
    readonly autolaunch: Record<string, unknown> | null;
    readonly mobile: null;
    readonly erc8004_agentbook: Record<string, unknown> | null;
  };
  readonly checks: readonly GraphCheckPayload[];
  readonly gaps: readonly string[];
}

describe("identity graph command", () => {
  const testWallet = "0x1111111111111111111111111111111111111111";
  const testRegistry = "0x2222222222222222222222222222222222222222";
  const testToken = "0x4444444444444444444444444444444444444444";
  const platformOrigin = "https://platform.regents.test";
  // Only mutate individual keys on process.env: replacing the whole object
  // detaches it from the real environment, and os.homedir() would keep
  // returning the real home directory instead of the per-test temp HOME.
  const touchedEnvKeys = [
    "HOME",
    "PATH",
    "CDP_KEY_ID",
    "CDP_KEY_SECRET",
    "CDP_WALLET_SECRET",
    "REGENT_WALLET_PRIVATE_KEY",
    "AUTOLAUNCH_BASE_URL",
    "REGENT_PLATFORM_ORIGIN",
    "BASE_MAINNET_RPC_URL",
    "BASE_RPC_URL",
    "BASE_SEPOLIA_RPC_URL",
  ] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  const fetchMock = vi.fn<typeof fetch>();
  let homeDir = "";
  let configPath = "";
  let sessionFile = "";

  const writeConfig = (): void => {
    writeInitialConfig(configPath);
    const config = JSON.parse(fs.readFileSync(configPath, "utf8")) as {
      services: {
        siwa: { baseUrl: string };
        platform: { baseUrl: string };
        autolaunch: { baseUrl: string };
        techtree: { baseUrl: string };
      };
    };
    config.services.siwa.baseUrl = "https://siwa.regents.test";
    config.services.platform.baseUrl = platformOrigin;
    config.services.autolaunch.baseUrl = "http://127.0.0.1:4010";
    fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");
  };

  const writeReceipt = (): void => {
    const receiptPath = path.join(homeDir, ".regent", "identity", "receipt-v1.json");
    fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
    fs.writeFileSync(
      receiptPath,
      JSON.stringify(
        {
          version: 1,
          regent_base_url: "http://127.0.0.1:4000",
          network: "base",
          provider: "coinbase-cdp",
          address: testWallet,
          agent_id: `eip155:8453:${testRegistry}:99`,
          token_id: "99",
          agent_registry: testRegistry,
          signer_type: "evm_personal_sign",
          verified: "onchain",
          receipt: "identity-receipt",
          receipt_issued_at: "2026-04-01T00:00:00.000Z",
          receipt_expires_at: "2999-01-01T00:00:00.000Z",
          cached_at: "2026-04-01T00:00:00.000Z",
          wallet_hint: "main",
        },
        null,
        2,
      ),
    );
  };

  const writeSiwaSession = (audience: "autolaunch" | "regent-services"): void => {
    const statePath = path.join(homeDir, "state", "runtime-state.json");
    fs.mkdirSync(path.dirname(statePath), { recursive: true });
    fs.writeFileSync(
      statePath,
      JSON.stringify(
        {
          agent: {
            walletAddress: testWallet,
            chainId: 8453,
            registryAddress: testRegistry,
            tokenId: "99",
          },
          siwa: {
            walletAddress: testWallet,
            chainId: 8453,
            nonce: "graph-nonce",
            keyId: testWallet.toLowerCase(),
            receipt: "graph-receipt",
            receiptExpiresAt: "2999-01-01T00:00:00.000Z",
            audience,
            registryAddress: testRegistry,
            tokenId: "99",
          },
        },
        null,
        2,
      ),
    );
  };

  const writePlatformSession = (): void => {
    fs.mkdirSync(path.dirname(sessionFile), { recursive: true });
    fs.writeFileSync(
      sessionFile,
      JSON.stringify(
        {
          version: 1,
          origin: platformOrigin,
          cookie: "regent_session=graph-cookie",
          csrfToken: "graph-csrf",
          savedAt: "2026-04-01T00:00:00.000Z",
        },
        null,
        2,
      ),
    );
  };

  const jsonResponse = (payload: unknown): Response =>
    new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "content-type": "application/json" },
    });

  const stubProductApis = (): void => {
    fetchMock.mockImplementation(async (input) => {
      const url = String(input);

      if (url.includes("/api/platform/projection")) {
        return jsonResponse({
          ok: true,
          projection: {
            public_profiles: [
              {
                id: "pp_1",
                slug: "agent-x",
                claimed_label: "Agent X",
                wallet_address: testWallet,
              },
            ],
            regents: [{ regent: { id: "co_1", sprite_service_name: "sprite-agent-x" } }],
            identity_links: {
              techtree: {
                profile_id: "tt_profile_1",
                node_ids: ["node_1"],
                bbh_run_ids: [],
                review_ids: ["review_1"],
              },
            },
          },
        });
      }

      if (url.includes("/api/autolaunch/v1/agent/agents")) {
        return jsonResponse({
          ok: true,
          items: [
            {
              agent_id: `eip155:8453:${testRegistry}:99`,
              owner_address: testWallet,
              registry_address: testRegistry,
              existing_token: { token_address: testToken, auction_id: "auc_1" },
            },
          ],
        });
      }

      if (url.includes("/api/autolaunch/v1/agent/subjects/by-token/")) {
        return jsonResponse({ ok: true, subjects: [{ subject_id: "subj_1" }] });
      }

      throw new Error(`unexpected fetch ${url}`);
    });
  };

  const runGraph = async () =>
    captureOutput(() =>
      runCliEntrypoint([
        "identity",
        "graph",
        "--json",
        "--config",
        configPath,
        "--session-file",
        sessionFile,
      ]),
    );

  const checkByItem = (graph: GraphPayload, item: string): GraphCheckPayload => {
    const check = graph.checks.find((candidate) => candidate.item === item);
    expect(check, `missing check row: ${item}`).toBeDefined();
    return check as GraphCheckPayload;
  };

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-identity-graph-home-"));
    configPath = path.join(homeDir, "regent.config.json");
    sessionFile = path.join(homeDir, "platform-session.json");
    for (const key of touchedEnvKeys) {
      savedEnv[key] = process.env[key];
    }
    process.env.HOME = homeDir;
    process.env.PATH = `${writeFakeCdp(homeDir, {
      accounts: [{ name: "main", address: testWallet }],
    })}:${savedEnv.PATH ?? ""}`;
    process.env.CDP_KEY_ID = "test-key";
    process.env.CDP_KEY_SECRET = "test-secret";
    process.env.CDP_WALLET_SECRET = "test-wallet-secret";
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
    process.env.AUTOLAUNCH_BASE_URL = "http://127.0.0.1:4010";
    delete process.env.REGENT_PLATFORM_ORIGIN;
    delete process.env.BASE_MAINNET_RPC_URL;
    delete process.env.BASE_RPC_URL;
    delete process.env.BASE_SEPOLIA_RPC_URL;
    fetchMock.mockReset();
    readContractMock.mockReset();
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
    fs.rmSync(homeDir, { recursive: true, force: true });
  });

  it("reports waiting with null tuple and links when no receipt exists", async () => {
    writeConfig();

    const output = await runGraph();

    expect(output.result, `${output.stdout}\n${output.stderr}`).toBe(1);
    const graph = parsePrintedJson(output.stdout) as GraphPayload;
    expect(graph).toMatchObject({
      ok: false,
      command: "identity graph",
      status: "waiting",
      agent_id: null,
      wallet_tuple: null,
      product_links: {
        platform: null,
        autolaunch: null,
        mobile: null,
        erc8004_agentbook: null,
      },
      checks: [],
    });
    expect(graph.gaps[0]).toContain("regents identity ensure");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(readContractMock).not.toHaveBeenCalled();
  });

  it("exits 0 with every check UNVERIFIABLE when no RPC URL and no product sessions exist", async () => {
    writeConfig();
    writeReceipt();

    const output = await runGraph();

    expect(output.result, output.stderr).toBe(0);
    const graph = parsePrintedJson(output.stdout) as GraphPayload;
    expect(graph.ok).toBe(true);
    expect(graph.status).toBe("ready");
    expect(graph.agent_id).toBe(`eip155:8453:${testRegistry}:99`);
    expect(graph.wallet_tuple).toEqual({
      wallet_address: testWallet,
      chain_id: 8453,
      registry_address: testRegistry,
      token_id: "99",
    });
    expect(graph.checks).toHaveLength(4);
    for (const check of graph.checks) {
      expect(check.status).toBe("UNVERIFIABLE");
      expect(check.reason).toBeTruthy();
    }
    expect(checkByItem(graph, "registry ownership (chain)").reason).toContain(
      "BASE_MAINNET_RPC_URL",
    );
    expect(checkByItem(graph, "platform link").reason).toContain("platform auth login");
    expect(checkByItem(graph, "autolaunch link").reason).toContain(
      "regents auth login --audience autolaunch",
    );
    expect(graph.product_links.platform).toBeNull();
    expect(graph.product_links.autolaunch).toBeNull();
    expect(graph.product_links.mobile).toBeNull();
    expect(graph.product_links.erc8004_agentbook).toEqual({
      agent_id: `eip155:8453:${testRegistry}:99`,
      registry_address: testRegistry,
      token_id: "99",
    });
    expect(readContractMock).not.toHaveBeenCalled();
  });

  it("reports MATCH rows and populated product links when chain and product APIs agree", async () => {
    writeConfig();
    writeReceipt();
    writeSiwaSession("autolaunch");
    writePlatformSession();
    stubProductApis();
    process.env.BASE_MAINNET_RPC_URL = "https://base.example";
    readContractMock.mockResolvedValue(testWallet);

    const output = await runGraph();

    expect(output.result, output.stderr).toBe(0);
    const graph = parsePrintedJson(output.stdout) as GraphPayload;
    expect(graph.ok).toBe(true);
    expect(graph.status).toBe("ready");
    expect(readContractMock).toHaveBeenCalledWith(
      expect.objectContaining({
        address: testRegistry,
        functionName: "ownerOf",
        args: [99n],
      }),
    );
    expect(checkByItem(graph, "registry ownership (chain)").status).toBe("MATCH");
    expect(checkByItem(graph, "platform link").status).toBe("MATCH");
    expect(checkByItem(graph, "autolaunch link").status).toBe("MATCH");
    expect(graph.product_links.platform).toEqual({
      platform_agent_id: "pp_1",
      regent_id: "co_1",
      public_slug: "agent-x",
      claimed_name: "Agent X",
      hosted_runtime_id: "sprite-agent-x",
      techtree: {
        profile_id: "tt_profile_1",
        node_ids: ["node_1"],
        bbh_run_ids: [],
        review_ids: ["review_1"],
      },
    });
    expect(graph.product_links.autolaunch).toEqual({
      subject_id: "subj_1",
      launch_id: null,
      auction_id: "auc_1",
    });
    expect(checkByItem(graph, "mobile link").status).toBe("UNVERIFIABLE");
  });

  it("exits 1 with a chain-wins next step when the registry owner differs from the saved wallet", async () => {
    writeConfig();
    writeReceipt();
    process.env.BASE_MAINNET_RPC_URL = "https://base.example";
    readContractMock.mockResolvedValue("0x000000000000000000000000000000000000dEaD");

    const output = await runGraph();

    expect(output.result).toBe(1);
    const graph = parsePrintedJson(output.stdout) as GraphPayload;
    expect(graph.ok).toBe(false);
    expect(graph.status).toBe("mismatch");
    const registryCheck = checkByItem(graph, "registry ownership (chain)");
    expect(registryCheck.status).toBe("MISMATCH");
    expect(registryCheck.detail).toContain("0x000000000000000000000000000000000000dEaD");
    expect(registryCheck.next).toContain("Chain wins for ownership.");
    expect(registryCheck.next).toContain("regents identity ensure");
  });
});
