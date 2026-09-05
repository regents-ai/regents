import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { readContractMock, getBytecodeMock } = vi.hoisted(() => ({
  readContractMock: vi.fn(),
  getBytecodeMock: vi.fn(),
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: () => ({
    address: "0x00000000000000000000000000000000000000aa",
    signMessage: async () => "0xsigned",
  }),
}));

vi.mock("viem/chains", () => ({
  base: { id: 8453, name: "Base" },
  baseSepolia: { id: 84532, name: "Base Sepolia" },
  mainnet: { id: 1, name: "Ethereum" },
}));

vi.mock("viem", () => ({
  http: (url: string) => ({ url }),
  isAddress: (value: string) => /^0x[0-9a-fA-F]{40}$/u.test(value),
  isHex: (value: string) => /^0x[0-9a-fA-F]*$/u.test(value),
  createWalletClient: () => ({ sendTransaction: vi.fn() }),
  createPublicClient: () => ({
    readContract: readContractMock,
    getBytecode: getBytecodeMock,
    call: vi.fn(),
    estimateGas: vi.fn(),
    waitForTransactionReceipt: vi.fn(),
  }),
}));

interface CheckPayload {
  readonly item: string;
  readonly status: string;
  readonly detail: string;
  readonly reason?: string;
  readonly next?: string;
}

interface VerifyPayload {
  readonly ok: boolean;
  readonly command: string;
  readonly status: string;
  readonly checks: readonly CheckPayload[];
}

describe("autolaunch verify commands", () => {
  const testWallet = "0x1111111111111111111111111111111111111111";
  const testRegistry = "0x2222222222222222222222222222222222222222";
  const tokenAddress = "0x3333333333333333333333333333333333333333";
  const splitterAddress = "0x4444444444444444444444444444444444444444";
  const ingressAddress = "0x5555555555555555555555555555555555555555";
  const usdcAddress = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
  const ownerAddress = "0x6666666666666666666666666666666666666666";

  const touchedEnvKeys = [
    "HOME",
    "PATH",
    "CDP_KEY_ID",
    "CDP_KEY_SECRET",
    "CDP_WALLET_SECRET",
    "REGENT_WALLET_PRIVATE_KEY",
    "AUTOLAUNCH_BASE_URL",
    "BASE_MAINNET_RPC_URL",
    "BASE_RPC_URL",
    "BASE_SEPOLIA_RPC_URL",
  ] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  const fetchMock = vi.fn<typeof fetch>();
  let homeDir = "";
  let configPath = "";
  let platformSessionFile = "";

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
    config.services.platform.baseUrl = "https://platform.regents.test";
    config.services.autolaunch.baseUrl = "http://127.0.0.1:4010";
    fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");
  };

  const writeAutolaunchSession = (audience: "autolaunch" | "techtree"): void => {
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
            nonce: "verify-nonce",
            keyId: testWallet.toLowerCase(),
            receipt: "verify-receipt",
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

  const writePlatformSession = (origin = "http://127.0.0.1:4010"): void => {
    const sessionPath = platformSessionFile;
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
  };

  const jsonResponse = (payload: unknown): Response =>
    new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "content-type": "application/json" },
    });

  const checkByItem = (payload: VerifyPayload, item: string): CheckPayload => {
    const check = payload.checks.find((candidate) => candidate.item === item);
    expect(check, `missing check row: ${item}`).toBeDefined();
    return check as CheckPayload;
  };

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-autolaunch-verify-home-"));
    configPath = path.join(homeDir, "regent.config.json");
    platformSessionFile = path.join(homeDir, "platform-session.json");
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
    delete process.env.BASE_MAINNET_RPC_URL;
    delete process.env.BASE_RPC_URL;
    delete process.env.BASE_SEPOLIA_RPC_URL;
    fetchMock.mockReset();
    readContractMock.mockReset();
    getBytecodeMock.mockReset();
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

  const runContractsVerify = async (extraArgs: readonly string[] = []) =>
    captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "contracts",
        "verify",
        ...extraArgs,
        "--json",
        "--config",
        configPath,
        "--session-file",
        platformSessionFile,
      ]),
    );

  const runSubjectsVerify = async (subjectId: string, extraArgs: readonly string[] = []) =>
    captureOutput(() =>
      runCliEntrypoint([
        "autolaunch",
        "subjects",
        "verify",
        subjectId,
        ...extraArgs,
        "--json",
        "--config",
        configPath,
      ]),
    );

  describe("contracts verify", () => {
    it("reports MATCH for deployed addresses and the untyped-overview gap row", async () => {
      writeConfig();
      writePlatformSession();
      process.env.BASE_MAINNET_RPC_URL = "https://base.example";
      fetchMock.mockImplementation(async (input) => {
        const url = String(input);
        if (url.includes("/api/autolaunch/v1/app/contracts/admin")) {
          return jsonResponse({ ok: true, fee_vault_address: splitterAddress, registry_address: testRegistry });
        }
        throw new Error(`unexpected fetch ${url}`);
      });
      getBytecodeMock.mockResolvedValue("0x6080604052");
      readContractMock.mockImplementation(({ functionName }: { functionName: string }) =>
        functionName === "owner" ? ownerAddress : false,
      );

      const output = await runContractsVerify();

      expect(output.result, output.stderr).toBe(0);
      expect((fetchMock.mock.calls[0]?.[1]?.headers as Headers).get("cookie")).toBe("_platform_phx_key=session-cookie");
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      expect(payload.command).toBe("autolaunch contracts verify");
      expect(payload.status).toBe("ready");
      expect(payload.checks.filter((check) => check.item.startsWith("deployed code")).length).toBe(2);
      for (const check of payload.checks.filter((c) => c.item.startsWith("deployed code"))) {
        expect(check.status).toBe("MATCH");
      }
      const gapRow = payload.checks.find((check) => check.item.startsWith("owner / paused"));
      expect(gapRow?.status).toBe("UNVERIFIABLE");
      expect(gapRow?.reason).toContain("Autolaunch contracts overview is untyped");
    });

    it("exits 1 with a chain-wins next line when a published address has no bytecode", async () => {
      writeConfig();
      writePlatformSession();
      process.env.BASE_MAINNET_RPC_URL = "https://base.example";
      fetchMock.mockImplementation(async (input) => {
        const url = String(input);
        if (url.includes("/api/autolaunch/v1/app/contracts/admin")) {
          return jsonResponse({ ok: true, fee_vault_address: splitterAddress });
        }
        throw new Error(`unexpected fetch ${url}`);
      });
      getBytecodeMock.mockResolvedValue("0x");

      const output = await runContractsVerify();

      expect(output.result).toBe(1);
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      expect(payload.ok).toBe(false);
      expect(payload.status).toBe("mismatch");
      const codeRow = payload.checks.find((check) => check.item.startsWith("deployed code"));
      expect(codeRow?.status).toBe("MISMATCH");
      expect(codeRow?.next).toContain("Chain wins.");
      expect(codeRow?.next).toContain("billing/launch_deployment");
    });

    it("marks chain rows UNVERIFIABLE when no RPC URL is configured", async () => {
      writeConfig();
      writePlatformSession();
      fetchMock.mockImplementation(async (input) => {
        const url = String(input);
        if (url.includes("/api/autolaunch/v1/app/contracts/admin")) {
          return jsonResponse({ ok: true, fee_vault_address: splitterAddress });
        }
        throw new Error(`unexpected fetch ${url}`);
      });

      const output = await runContractsVerify();

      expect(output.result, output.stderr).toBe(0);
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      const codeRow = payload.checks.find((check) => check.item.startsWith("deployed code"));
      expect(codeRow?.status).toBe("UNVERIFIABLE");
      expect(codeRow?.reason).toContain("BASE_MAINNET_RPC_URL");
      expect(getBytecodeMock).not.toHaveBeenCalled();
    });

    it("reports UNVERIFIABLE when there is no autolaunch session", async () => {
      writeConfig();
      process.env.BASE_MAINNET_RPC_URL = "https://base.example";

      const output = await runContractsVerify();

      expect(output.result, output.stderr).toBe(0);
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      const overviewRow = checkByItem(payload, "admin contracts overview");
      expect(overviewRow.status).toBe("UNVERIFIABLE");
      expect(overviewRow.reason).toContain("regents platform auth login");
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });

  describe("subjects verify", () => {
    const subjectId = "subj_1";

    const stubSubjectApis = (): void => {
      fetchMock.mockImplementation(async (input) => {
        const url = String(input);
        if (url.includes(`/api/autolaunch/v1/agent/subjects/${subjectId}/staking`)) {
          return jsonResponse({ ok: true, subject: {} });
        }
        if (url.includes(`/api/autolaunch/v1/agent/subjects/${subjectId}/ingress`)) {
          return jsonResponse({
            ok: true,
            subject: {
              current_unswept_usdc_raw: 1234567,
              ingress_usdc_token_address: usdcAddress,
              money_read_sources: moneyReadSources(),
            },
          });
        }
        if (url.includes(`/api/autolaunch/v1/agent/subjects/${subjectId}/buybacks`)) {
          return jsonResponse({
            ok: true,
            subject_id: subjectId,
            buybacks: {
              pending_buyback_usdc_raw: 2500000,
              pending_buyback_usdc: "2.5",
              money_read_sources: moneyReadSources(),
            },
          });
        }
        if (url.includes(`/api/autolaunch/v1/agent/subjects/${subjectId}`)) {
          return jsonResponse({
            ok: true,
            subject: {
              subject_id: subjectId,
              token_address: tokenAddress,
              splitter_address: splitterAddress,
              default_ingress_address: ingressAddress,
              ingress_usdc_token_address: usdcAddress,
              current_unswept_usdc_raw: 1234567,
              pending_buyback_usdc_raw: 2500000,
              splitter_accounted_usdc_raw: 9900000,
              money_read_sources: moneyReadSources(),
              subject_kind: "existing_token",
              team_shared_status: "private",
            },
          });
        }
        throw new Error(`unexpected fetch ${url}`);
      });
    };

    const moneyReadSources = () => ({
      ingress_usdc_token_address: {
        contract_address: usdcAddress,
        read_source: "configured_base_usdc_token",
        token_address: null,
        account_address: null,
      },
      current_unswept_usdc_raw: {
        contract_address: usdcAddress,
        read_source: "erc20_balance_of",
        token_address: usdcAddress,
        account_address: ingressAddress,
      },
      pending_buyback_usdc_raw: {
        contract_address: splitterAddress,
        read_source: "revenue_splitter_treasury_buyback_usdc",
        token_address: null,
        account_address: null,
      },
      splitter_accounted_usdc_raw: {
        contract_address: splitterAddress,
        read_source: "revenue_splitter_total_usdc_received",
        token_address: null,
        account_address: null,
      },
    });

    it("reports MATCH token, splitter, ingress, and current money rows", async () => {
      writeConfig();
      writeAutolaunchSession("autolaunch");
      process.env.BASE_MAINNET_RPC_URL = "https://base.example";
      stubSubjectApis();
      getBytecodeMock.mockResolvedValue("0x6080604052");
      readContractMock.mockImplementation(({ functionName }: { functionName: string }) => {
        if (functionName === "symbol") {
          return "TKN";
        }
        if (functionName === "totalSupply") {
          return 1000n;
        }
        if (functionName === "balanceOf") {
          return 1234567n;
        }
        throw new Error(`unexpected read ${functionName}`);
      });

      const output = await runSubjectsVerify(subjectId);

      expect(output.result, output.stderr).toBe(0);
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      expect(payload.command).toBe("autolaunch subjects verify");
      expect(checkByItem(payload, "token deployed").status).toBe("MATCH");
      expect(checkByItem(payload, "splitter deployed").status).toBe("MATCH");
      expect(checkByItem(payload, "ingress deployed").status).toBe("MATCH");
      expect(checkByItem(payload, "token symbol / supply").status).toBe("MATCH");
      expect(checkByItem(payload, "subject kind").status).toBe("MATCH");
      expect(checkByItem(payload, "team shared status").status).toBe("MATCH");

      const ingressRow = checkByItem(payload, "ingress balance vs unswept");
      expect(ingressRow.status).toBe("MATCH");
      expect(ingressRow.detail).toContain("current_unswept_usdc_raw");

      expect(checkByItem(payload, "pending buyback current state").status).toBe("MATCH");
      expect(checkByItem(payload, "splitter accounted current state").status).toBe("MATCH");

      const auctionRow = checkByItem(payload, "live auction state");
      expect(auctionRow.status).toBe("UNVERIFIABLE");
      expect(auctionRow.reason).toContain("launch job or auction id");
    });

    it("exits 1 with a chain-wins next line when a published address has no bytecode", async () => {
      writeConfig();
      writeAutolaunchSession("autolaunch");
      process.env.BASE_MAINNET_RPC_URL = "https://base.example";
      stubSubjectApis();
      getBytecodeMock.mockImplementation(async ({ address }: { address: string }) =>
        address.toLowerCase() === ingressAddress.toLowerCase() ? "0x" : "0x6080604052",
      );
      readContractMock.mockImplementation(({ functionName }: { functionName: string }) =>
        functionName === "symbol" ? "TKN" : 1000n,
      );

      const output = await runSubjectsVerify(subjectId);

      expect(output.result).toBe(1);
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      expect(payload.status).toBe("mismatch");
      const ingressDeployed = checkByItem(payload, "ingress deployed");
      expect(ingressDeployed.status).toBe("MISMATCH");
      expect(ingressDeployed.next).toContain("Chain wins.");
      expect(ingressDeployed.next).toContain("billing/launch_deployment");
    });

    it("marks chain rows UNVERIFIABLE when no RPC URL is configured", async () => {
      writeConfig();
      writeAutolaunchSession("autolaunch");
      stubSubjectApis();

      const output = await runSubjectsVerify(subjectId);

      expect(output.result, output.stderr).toBe(0);
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      expect(checkByItem(payload, "token deployed").reason).toContain("BASE_MAINNET_RPC_URL");
      expect(getBytecodeMock).not.toHaveBeenCalled();
    });

    it("reports UNVERIFIABLE when there is no autolaunch session", async () => {
      writeConfig();
      process.env.BASE_MAINNET_RPC_URL = "https://base.example";

      const output = await runSubjectsVerify(subjectId);

      expect(output.result, output.stderr).toBe(0);
      const payload = parsePrintedJson(output.stdout) as VerifyPayload;
      const subjectRow = checkByItem(payload, "subject record");
      expect(subjectRow.status).toBe("UNVERIFIABLE");
      expect(subjectRow.reason).toContain("regents auth login --audience autolaunch");
    });
  });
});
