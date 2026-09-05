import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { EXPECTED_PLATFORM_CONTRACT_DIGEST } from "../../src/generated/platform-contract-digest.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const isPlatformContractUrl = (input: unknown): boolean =>
  String(input).endsWith("/api-contract.openapiv3.yaml");

const { buildAgentAuthHeadersMock } = vi.hoisted(() => ({
  buildAgentAuthHeadersMock: vi.fn(),
}));

const { sendTransactionMock, waitForReceiptMock, callMock, estimateGasMock } = vi.hoisted(() => ({
  sendTransactionMock: vi.fn(),
  waitForReceiptMock: vi.fn(),
  callMock: vi.fn(),
  estimateGasMock: vi.fn(),
}));

vi.mock("../../src/commands/agent-auth.js", () => ({
  buildAgentAuthHeaders: buildAgentAuthHeadersMock,
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: () => ({
    address: "0x00000000000000000000000000000000000000aa",
    signMessage: async () => "0xsigned",
  }),
}));

vi.mock("viem/chains", () => ({
  mainnet: { id: 1, name: "Ethereum" },
  base: { id: 8453, name: "Base" },
  baseSepolia: { id: 84532, name: "Base Sepolia" },
}));

vi.mock("viem", () => ({
  http: (url: string) => ({ url }),
  isAddress: (value: string) => /^0x[0-9a-fA-F]{40}$/u.test(value),
  isHex: (value: string) => /^0x[0-9a-fA-F]*$/u.test(value),
  createWalletClient: () => ({
    sendTransaction: sendTransactionMock,
  }),
  createPublicClient: () => ({
    call: callMock,
    estimateGas: estimateGasMock,
    waitForTransactionReceipt: waitForReceiptMock,
  }),
}));

describe("ENS CLI command group", () => {
  const fetchMock = vi.fn<typeof fetch>();
  // Only mutate individual keys on process.env: replacing the whole object
  // detaches it from the real environment, and os.homedir() would keep
  // returning the real home directory instead of the per-test temp HOME.
  const touchedEnvKeys = ["REGENT_WALLET_PRIVATE_KEY", "ETH_MAINNET_RPC_URL"] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  let tempDir = "";
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
      if (isPlatformContractUrl(input)) {
        return platformContractResponse();
      }

      const response = pending.shift();
      if (!response) {
        throw new Error(`Unexpected fetch: ${String(input)}`);
      }

      return response;
    });
  };

  const productFetchCalls = () => fetchMock.mock.calls.filter(([input]) => !isPlatformContractUrl(input));

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    for (const key of touchedEnvKeys) {
      savedEnv[key] = process.env[key];
    }
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-ens-cli-"));
    configPath = path.join(tempDir, "regent.config.json");

    writeInitialConfig(configPath, {
      auth: {
        audience: "platform",
        defaultChainId: 8453,
      },
      services: {
        siwa: {
          baseUrl: "https://regent.example",
          requestTimeoutMs: 1_000,
        },
        platform: {
          baseUrl: "https://regent.example",
          requestTimeoutMs: 1_000,
        },
        autolaunch: {
          baseUrl: "http://127.0.0.1:4010",
          requestTimeoutMs: 1_000,
        },
      },
      wallet: {
        privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
        keystorePath: path.join(tempDir, "keys", "agent-wallet.json"),
      },
    });

    process.env.REGENT_WALLET_PRIVATE_KEY =
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    process.env.ETH_MAINNET_RPC_URL = "https://ethereum.example.invalid";

    fetchMock.mockReset();
    buildAgentAuthHeadersMock.mockReset();
    sendTransactionMock.mockReset();
    waitForReceiptMock.mockReset();
    callMock.mockReset();
    estimateGasMock.mockReset();

    buildAgentAuthHeadersMock.mockResolvedValue({
      "x-siwa-receipt": "receipt_123",
      "x-key-id": "0x00000000000000000000000000000000000000aa",
      "x-agent-wallet-address": "0x00000000000000000000000000000000000000aa",
      "x-agent-chain-id": "8453",
      signature: "sig1=:ZmFrZQ==:",
      "signature-input": "sig1=(\"@method\" \"@path\")",
    });

    sendTransactionMock.mockResolvedValue(
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    );
    waitForReceiptMock.mockResolvedValue({ status: "success" });
    callMock.mockResolvedValue({ data: "0x" });
    estimateGasMock.mockResolvedValue(21_000n);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    for (const key of touchedEnvKeys) {
      const saved = savedEnv[key];
      if (saved === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = saved;
      }
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  const preparedEnsResponse = (expiresAt = "2999-01-01T00:00:00.000Z") =>
    new Response(
      JSON.stringify({
        ok: true,
        prepared: {
          resource: "tempo.regent.eth",
          action: "set_primary_name",
          chain_id: 1,
          ens_name: "tempo.regent.eth",
          caller_wallet_address: "0x00000000000000000000000000000000000000aa",
          wallet_action: {
            action_id: "ens_primary_1",
            owner_product: "platform",
            resource: "ens",
            resource_id: "tempo.regent.eth",
            action: "set_primary_name",
            chain_id: 1,
            to: "0xa58e81fe9b61b5c3fe2afd33cf304c454abfc7cb",
            value: "0x0",
            data: "0x1234",
            expected_signer: "0x00000000000000000000000000000000000000aa",
            expires_at: expiresAt,
            idempotency_key: "idem_ens_primary_1",
            simulation: { required: false, status: "not_required", block_number: null },
            risk_copy: "Sets this wallet's primary ENS name.",
          },
        },
      }),
      {
        status: 200,
        headers: { "content-type": "application/json" },
      },
    );

  it("prints the prepared mainnet reverse-name transaction by default", async () => {
    mockPlatformResponses(preparedEnsResponse());

    const output = await captureOutput(async () =>
      runCliEntrypoint([
        "ens",
        "set-primary",
        "--ens",
        "tempo.regent.eth",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(callMock).not.toHaveBeenCalled();
    expect(estimateGasMock).not.toHaveBeenCalled();
    expect(sendTransactionMock).not.toHaveBeenCalled();
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      prepared: { wallet_action: { action_id: "ens_primary_1" } },
    });
  });

  it("requests the prepared mainnet reverse-name transaction and submits only with --submit", async () => {
    mockPlatformResponses(preparedEnsResponse());

    const output = await captureOutput(async () =>
      runCliEntrypoint([
        "ens",
        "set-primary",
        "--ens",
        "tempo.regent.eth",
        "--submit",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(buildAgentAuthHeadersMock).toHaveBeenCalledWith({
      method: "POST",
      path: "/api/platform/ens/prepare-primary",
      body: JSON.stringify({ ens_name: "tempo.regent.eth" }),
      configPath,
      audience: "platform",
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "https://regent.example/api/platform/ens/prepare-primary",
      expect.objectContaining({
        method: "POST",
      }),
    );

    const [, requestInit] = productFetchCalls()[0]!;
    expect(JSON.parse(String(requestInit?.body))).toEqual({ ens_name: "tempo.regent.eth" });

    expect(callMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0xa58e81fe9b61b5c3fe2afd33cf304c454abfc7cb",
        data: "0x1234",
        value: 0n,
      }),
    );
    expect(estimateGasMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0xa58e81fe9b61b5c3fe2afd33cf304c454abfc7cb",
        data: "0x1234",
        value: 0n,
      }),
    );
    expect(sendTransactionMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0xa58e81fe9b61b5c3fe2afd33cf304c454abfc7cb",
        data: "0x1234",
        value: 0n,
      }),
    );
    expect(waitForReceiptMock).toHaveBeenCalledWith({
      hash: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    });

    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      submitted: true,
      tx_hash: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    });
  });

  it("does not submit expired prepared ENS wallet actions", async () => {
    mockPlatformResponses(preparedEnsResponse("2020-01-01T00:00:00.000Z"));

    const output = await captureOutput(async () =>
      runCliEntrypoint([
        "ens",
        "set-primary",
        "--ens",
        "tempo.regent.eth",
        "--submit",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("This prepared wallet action has expired.");
    expect(callMock).not.toHaveBeenCalled();
    expect(estimateGasMock).not.toHaveBeenCalled();
    expect(sendTransactionMock).not.toHaveBeenCalled();
  });
});
