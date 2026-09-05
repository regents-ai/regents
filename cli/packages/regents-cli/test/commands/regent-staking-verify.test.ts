import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { readContractMock, getBytecodeMock, readReceiptMock } = vi.hoisted(() => ({
  readContractMock: vi.fn(),
  getBytecodeMock: vi.fn(),
  readReceiptMock: vi.fn(),
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
  keccak256: (value: string) => `0x${value.slice(2, 66).padEnd(64, "0")}`,
  encodeAbiParameters: () => "0x00",
  createWalletClient: () => ({ sendTransaction: vi.fn() }),
  createPublicClient: () => ({
    readContract: readContractMock,
    getBytecode: getBytecodeMock,
    getTransactionReceipt: readReceiptMock,
    call: vi.fn(),
    estimateGas: vi.fn(),
    waitForTransactionReceipt: vi.fn(),
  }),
}));

vi.mock("../../src/internal-runtime/identity/cache.js", () => ({
  readIdentityReceipt: () => ({
    version: 1,
    network: "base",
    address: "0x1111111111111111111111111111111111111111",
    agent_id: "eip155:8453:0x2222222222222222222222222222222222222222:99",
    token_id: "99",
    agent_registry: "0x2222222222222222222222222222222222222222",
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
  readonly wallet: string | null;
  readonly checks: readonly CheckPayload[];
}

describe("regent-staking verify", () => {
  const identityWallet = "0x1111111111111111111111111111111111111111";
  const otherWallet = "0x9999999999999999999999999999999999999999";
  const contractAddress = "0x3333333333333333333333333333333333333333";
  const stakeToken = "0x4444444444444444444444444444444444444444";

  const touchedEnvKeys = [
    "HOME",
    "PATH",
    "CDP_KEY_ID",
    "CDP_KEY_SECRET",
    "CDP_WALLET_SECRET",
    "REGENT_WALLET_PRIVATE_KEY",
    "PLATFORM_BASE_URL",
    "BASE_MAINNET_RPC_URL",
    "BASE_RPC_URL",
    "BASE_SEPOLIA_RPC_URL",
  ] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  const fetchMock = vi.fn<typeof fetch>();
  let homeDir = "";
  let configPath = "";

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
    config.services.platform.baseUrl = "http://127.0.0.1:4030";
    config.services.autolaunch.baseUrl = "http://127.0.0.1:4010";
    fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");
  };

  const writeSession = (): void => {
    const statePath = path.join(homeDir, "state", "runtime-state.json");
    fs.mkdirSync(path.dirname(statePath), { recursive: true });
    fs.writeFileSync(
      statePath,
      JSON.stringify(
        {
          agent: {
            walletAddress: identityWallet,
            chainId: 8453,
            registryAddress: "0x2222222222222222222222222222222222222222",
            tokenId: "99",
          },
          siwa: {
            walletAddress: identityWallet,
            chainId: 8453,
            nonce: "verify-nonce",
            keyId: identityWallet.toLowerCase(),
            receipt: "verify-receipt",
            receiptExpiresAt: "2999-01-01T00:00:00.000Z",
            audience: "regent-services",
            registryAddress: "0x2222222222222222222222222222222222222222",
            tokenId: "99",
          },
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

  const stakingState = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
    ok: true,
    chain_id: 8453,
    contract_address: contractAddress,
    stake_token_address: stakeToken,
    usdc_address: "0x5555555555555555555555555555555555555555",
    paused: false,
    total_staked_raw: "1000",
    wallet_stake_balance_raw: "200",
    wallet_claimable_usdc_raw: "50",
    wallet_claimable_regent_raw: "30",
    wallet_token_balance_raw: "70",
    ...overrides,
  });

  const checkByItem = (payload: VerifyPayload, item: string): CheckPayload => {
    const check = payload.checks.find((candidate) => candidate.item === item);
    expect(check, `missing check row: ${item}`).toBeDefined();
    return check as CheckPayload;
  };

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-staking-verify-home-"));
    configPath = path.join(homeDir, "regent.config.json");
    for (const key of touchedEnvKeys) {
      savedEnv[key] = process.env[key];
    }
    process.env.HOME = homeDir;
    process.env.PATH = `${writeFakeCdp(homeDir, {
      accounts: [{ name: "main", address: identityWallet }],
    })}:${savedEnv.PATH ?? ""}`;
    process.env.CDP_KEY_ID = "test-key";
    process.env.CDP_KEY_SECRET = "test-secret";
    process.env.CDP_WALLET_SECRET = "test-wallet-secret";
    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
    process.env.PLATFORM_BASE_URL = "http://127.0.0.1:4030";
    delete process.env.BASE_MAINNET_RPC_URL;
    delete process.env.BASE_RPC_URL;
    delete process.env.BASE_SEPOLIA_RPC_URL;
    fetchMock.mockReset();
    readContractMock.mockReset();
    getBytecodeMock.mockReset();
    readReceiptMock.mockReset();
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

  const runVerify = async (extraArgs: readonly string[] = []) =>
    captureOutput(() =>
      runCliEntrypoint([
        "regent-staking",
        "verify",
        ...extraArgs,
        "--json",
        "--config",
        configPath,
      ]),
    );

  // Chain reads return values that match the stub staking state.
  const stubMatchingChain = (): void => {
    getBytecodeMock.mockResolvedValue("0x6080604052");
    readContractMock.mockImplementation(({ functionName }: { functionName: string }) => {
      switch (functionName) {
        case "totalStaked":
          return 1000n;
        case "stakedBalance":
          return 200n;
        case "previewClaimableUSDC":
          return 50n;
        case "previewClaimableRegent":
          return 30n;
        case "balanceOf":
          return 70n;
        case "paused":
          return false;
        default:
          return 0n;
      }
    });
  };

  it("reports MATCH for every staking row when API and chain agree", async () => {
    writeConfig();
    writeSession();
    process.env.BASE_MAINNET_RPC_URL = "https://base.example";
    fetchMock.mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("/api/shared/regent/staking/account/")) {
        return jsonResponse(stakingState());
      }
      if (url.includes("/api/shared/regent/staking")) {
        return jsonResponse(stakingState());
      }
      throw new Error(`unexpected fetch ${url}`);
    });
    stubMatchingChain();

    const output = await runVerify();

    expect(output.result, output.stderr).toBe(0);
    const payload = parsePrintedJson(output.stdout) as VerifyPayload;
    expect(payload.command).toBe("regent-staking verify");
    expect(payload.status).toBe("ready");
    for (const item of [
      "staking contract deployed",
      "total staked",
      "wallet staked balance",
      "wallet claimable USDC",
      "wallet claimable REGENT",
      "wallet REGENT balance",
      "paused flag",
    ]) {
      expect(checkByItem(payload, item).status, item).toBe("MATCH");
    }
  });

  it("defaults to the saved identity wallet when no address is passed", async () => {
    writeConfig();
    writeSession();
    process.env.BASE_MAINNET_RPC_URL = "https://base.example";
    fetchMock.mockImplementation(async () => jsonResponse(stakingState()));
    stubMatchingChain();

    const output = await runVerify();

    expect(output.result, output.stderr).toBe(0);
    const payload = parsePrintedJson(output.stdout) as VerifyPayload;
    expect(payload.wallet).toBe(identityWallet);
    expect(fetchMock.mock.calls.some(([input]) => String(input).includes(identityWallet))).toBe(true);
  });

  it("uses an explicit positional wallet over the saved identity", async () => {
    writeConfig();
    writeSession();
    process.env.BASE_MAINNET_RPC_URL = "https://base.example";
    fetchMock.mockImplementation(async () => jsonResponse(stakingState()));
    stubMatchingChain();

    const output = await runVerify([otherWallet]);

    expect(output.result, output.stderr).toBe(0);
    const payload = parsePrintedJson(output.stdout) as VerifyPayload;
    expect(payload.wallet).toBe(otherWallet);
    expect(fetchMock.mock.calls.some(([input]) => String(input).includes(otherWallet))).toBe(true);
  });

  it("exits 1 with the staking-wins next line when a claimable differs", async () => {
    writeConfig();
    writeSession();
    process.env.BASE_MAINNET_RPC_URL = "https://base.example";
    fetchMock.mockImplementation(async () => jsonResponse(stakingState()));
    getBytecodeMock.mockResolvedValue("0x6080604052");
    readContractMock.mockImplementation(({ functionName }: { functionName: string }) => {
      switch (functionName) {
        case "totalStaked":
          return 1000n;
        case "stakedBalance":
          return 200n;
        case "previewClaimableUSDC":
          return 999n; // diverges from the API's "50"
        case "previewClaimableRegent":
          return 30n;
        case "balanceOf":
          return 70n;
        case "paused":
          return false;
        default:
          return 0n;
      }
    });

    const output = await runVerify();

    expect(output.result).toBe(1);
    const payload = parsePrintedJson(output.stdout) as VerifyPayload;
    expect(payload.ok).toBe(false);
    expect(payload.status).toBe("mismatch");
    const usdcRow = checkByItem(payload, "wallet claimable USDC");
    expect(usdcRow.status).toBe("MISMATCH");
    expect(usdcRow.next).toContain("chain wins for staking");
    expect(usdcRow.next).toContain("staking_claims (owner: platform)");
  });

  it("marks chain rows UNVERIFIABLE when no RPC URL is configured", async () => {
    writeConfig();
    writeSession();
    fetchMock.mockImplementation(async () => jsonResponse(stakingState()));

    const output = await runVerify();

    expect(output.result, output.stderr).toBe(0);
    const payload = parsePrintedJson(output.stdout) as VerifyPayload;
    const row = checkByItem(payload, "total staked");
    expect(row.status).toBe("UNVERIFIABLE");
    expect(row.reason).toContain("BASE_MAINNET_RPC_URL");
    expect(getBytecodeMock).not.toHaveBeenCalled();
  });
});
