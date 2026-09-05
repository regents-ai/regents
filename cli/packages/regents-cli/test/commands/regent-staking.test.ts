import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { EXPECTED_PLATFORM_CONTRACT_DIGEST } from "../../src/generated/platform-contract-digest.js";
import { writeInitialConfig } from "../../src/internal-runtime/config.js";
import { writeFakeCdp } from "../support/fake-cdp.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const isPlatformContractUrl = (input: unknown): boolean =>
  String(input).endsWith("/api-contract.openapiv3.yaml");

const { sendTransactionMock, waitForReceiptMock, callMock, estimateGasMock } = vi.hoisted(() => ({
  sendTransactionMock: vi.fn(),
  waitForReceiptMock: vi.fn(),
  callMock: vi.fn(),
  estimateGasMock: vi.fn(),
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
    sendTransaction: sendTransactionMock,
  }),
  createPublicClient: () => ({
    call: callMock,
    estimateGas: estimateGasMock,
    waitForTransactionReceipt: waitForReceiptMock,
  }),
}));

describe("regent-staking CLI command group", () => {
  const expectedBaseUrl = "http://127.0.0.1:4000";
  const testWallet = "0x1111111111111111111111111111111111111111";
  const submitWallet = "0x00000000000000000000000000000000000000aa";
  const testRegistry = "0x2222222222222222222222222222222222222222";
  const testAgentId = `eip155:8453:${testRegistry}:99`;
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
    "BASE_MAINNET_RPC_URL",
  ] as const;
  const savedEnv: Partial<Record<(typeof touchedEnvKeys)[number], string | undefined>> = {};
  const fetchMock = vi.fn<typeof fetch>();
  let homeDir = "";
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

  const walletAction = (data: string) => ({
    action_id: `staking_${data.slice(2)}`,
    owner_product: "platform",
    resource: "regent_staking",
    resource_id: "0x3333333333333333333333333333333333333333",
    action: "claim",
    chain_id: 8453,
    to: "0x3333333333333333333333333333333333333333",
    value: "0x0",
    data,
    expected_signer: submitWallet,
    expires_at: "2999-01-01T00:00:00.000Z",
    idempotency_key: `idem_${data.slice(2)}`,
    simulation: { required: false, status: "not_required", block_number: null },
    risk_copy: "Claims available staking rewards.",
  });

  const writeAgentAuthState = (platformBaseUrl = expectedBaseUrl) => {
    writeInitialConfig(configPath);
    const config = JSON.parse(fs.readFileSync(configPath, "utf8")) as {
      services: { siwa: { baseUrl: string }; platform: { baseUrl: string } };
    };
    config.services.siwa.baseUrl = "https://siwa.regents.test";
    config.services.platform.baseUrl = platformBaseUrl;
    fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, "utf8");

    const receiptPath = path.join(homeDir, ".regent", "identity", "receipt-v1.json");
    const statePath = path.join(homeDir, "state", "runtime-state.json");
    fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
    fs.mkdirSync(path.dirname(statePath), { recursive: true });
    fs.writeFileSync(
      receiptPath,
      JSON.stringify(
        {
          version: 1,
          regent_base_url: "http://127.0.0.1:4000",
          network: "base",
          provider: "coinbase-cdp",
          address: testWallet,
          agent_id: testAgentId,
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
            nonce: "staking-nonce",
            keyId: testWallet.toLowerCase(),
            receipt: "staking-receipt",
            receiptExpiresAt: "2999-01-01T00:00:00.000Z",
            audience: "regent-services",
            registryAddress: testRegistry,
            tokenId: "99",
          },
        },
        null,
        2,
      ),
    );
  };

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-staking-home-"));
    configPath = path.join(homeDir, "regent.config.json");
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
    process.env.BASE_MAINNET_RPC_URL = "https://base.example";
    fetchMock.mockReset();
    sendTransactionMock.mockReset();
    waitForReceiptMock.mockReset();
    callMock.mockReset();
    estimateGasMock.mockReset();
    questionMock.mockReset();
    closePromptMock.mockReset();
    questionMock.mockResolvedValue("y");
    sendTransactionMock.mockResolvedValue("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    waitForReceiptMock.mockResolvedValue({ status: "success", logs: [] });
    callMock.mockResolvedValue({ data: "0x" });
    estimateGasMock.mockResolvedValue(21_000n);
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

  it("shows the regent staking overview", async () => {
    writeAgentAuthState("https://staking.regents.sh/");
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, chain_id: 8453, treasury_residual_usdc: "150" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "get", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe("https://staking.regents.sh/api/shared/regent/staking");
    expect((productFetchCalls()[0]?.[1]?.headers as Headers).get("x-siwa-receipt")).toBe("staking-receipt");
    expect(parsePrintedJson<{ chain_id: number }>(output.stdout)).toMatchObject({ chain_id: 8453 });
  });

  it("shows a specific account", async () => {
    writeAgentAuthState();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, wallet_address: "0xabc", wallet_claimable_usdc: "12" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "account", "0xabc", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(`${expectedBaseUrl}/api/shared/regent/staking/account/0xabc`);
    expect((productFetchCalls()[0]?.[1]?.headers as Headers).get("x-siwa-receipt")).toBe("staking-receipt");
    expect(parsePrintedJson<{ wallet_address: string }>(output.stdout)).toMatchObject({
      wallet_address: "0xabc",
    });
  });

  it("requires a session for direct stake calls", async () => {
    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "stake", "--amount", "1.5", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("Run `regents auth login --audience regent-services` before using this command.");
  });

  it("builds the direct stake request when shared sign-in is present", async () => {
    writeAgentAuthState();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, staking: {}, wallet_action: walletAction("0x7acb7757") }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "stake", "--amount", "1.5", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(`${expectedBaseUrl}/api/shared/regent/staking/stake`);
    expect((productFetchCalls()[0]?.[1]?.headers as Headers).get("x-siwa-receipt")).toBe("staking-receipt");
    expect(parsePrintedJson<{ wallet_action: { data: string } }>(output.stdout)).toMatchObject({
      wallet_action: { data: "0x7acb7757" },
    });
  });

  it("builds the direct stake request with a receiver without prompting", async () => {
    writeAgentAuthState();
    const receiver = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, staking: {}, wallet_action: walletAction("0x7acb7757") }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "regent-staking",
        "stake",
        "--amount",
        "1.5",
        "--receiver",
        receiver,
        "--config",
        configPath,
      ]),
    );

    expect(output.result, output.stderr).toBe(0);
    expect(JSON.parse(String(productFetchCalls()[0]?.[1]?.body))).toEqual({
      amount: "1.5",
      receiver,
    });
    expect(questionMock).not.toHaveBeenCalled();
  });

  it("rejects malformed receiver addresses before preparing stake", async () => {
    writeAgentAuthState();

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "regent-staking",
        "stake",
        "--amount",
        "1.5",
        "--receiver",
        "0xabc",
        "--config",
        configPath,
      ]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("--receiver must be a 0x address with 40 hex characters.");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(questionMock).not.toHaveBeenCalled();
  });

  it("claims USDC through the shared sign-in flow", async () => {
    writeAgentAuthState();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, staking: {}, wallet_action: walletAction("0x42852610") }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "claim-usdc", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(productFetchCalls()[0]?.[0]).toBe(`${expectedBaseUrl}/api/shared/regent/staking/claim-usdc`);
    expect((productFetchCalls()[0]?.[1]?.headers as Headers).get("x-siwa-receipt")).toBe("staking-receipt");
    expect(parsePrintedJson<{ wallet_action: { data: string } }>(output.stdout)).toMatchObject({
      wallet_action: { data: "0x42852610" },
    });
  });

  it("simulates and estimates staking transactions before submit", async () => {
    writeAgentAuthState();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, staking: {}, wallet_action: walletAction("0x42852610") }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "claim-usdc", "--submit", "--config", configPath]),
    );

    expect(output.result).toBe(0);
    expect(callMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0x3333333333333333333333333333333333333333",
        data: "0x42852610",
        value: 0n,
      }),
    );
    expect(estimateGasMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0x3333333333333333333333333333333333333333",
        data: "0x42852610",
        value: 0n,
      }),
    );
    expect(sendTransactionMock).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "0x3333333333333333333333333333333333333333",
        data: "0x42852610",
        value: 0n,
      }),
    );
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true,
      submitted: true,
      tx_hash: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    });
  });

  it("does not submit expired staking wallet actions", async () => {
    writeAgentAuthState();
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          staking: {},
          wallet_action: {
            ...walletAction("0x42852610"),
            expires_at: "2020-01-01T00:00:00.000Z",
          },
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "claim-usdc", "--submit", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("This prepared wallet action has expired.");
    expect(callMock).not.toHaveBeenCalled();
    expect(estimateGasMock).not.toHaveBeenCalled();
    expect(sendTransactionMock).not.toHaveBeenCalled();
  });

  it("does not report staking submit success when the chain receipt failed", async () => {
    writeAgentAuthState();
    waitForReceiptMock.mockResolvedValue({ status: "reverted", logs: [] });
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, staking: {}, wallet_action: walletAction("0x42852610") }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "claim-usdc", "--submit", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("The transaction was not confirmed successfully.");
    expect(sendTransactionMock).toHaveBeenCalledTimes(1);
  });

  it("does not submit staking transactions prepared for another wallet", async () => {
    writeAgentAuthState();
    mockPlatformResponses(
      new Response(
        JSON.stringify({
          ok: true,
          staking: {},
          wallet_action: {
            ...walletAction("0x42852610"),
            expected_signer: testWallet,
          },
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "claim-usdc", "--submit", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("This prepared transaction is for a different wallet.");
    expect(callMock).not.toHaveBeenCalled();
    expect(estimateGasMock).not.toHaveBeenCalled();
    expect(sendTransactionMock).not.toHaveBeenCalled();
  });

  it("does not report staking submit success when the prepared transaction is missing", async () => {
    writeAgentAuthState();
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, staking: {} }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "claim-usdc", "--submit", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("This staking action did not include a transaction to submit.");
    expect(output.stdout.trim()).toBe("");
    expect(sendTransactionMock).not.toHaveBeenCalled();
  });

  it("rejects incomplete staking wallet actions before submit", async () => {
    writeAgentAuthState();
    const incompleteAction: Record<string, unknown> = { ...walletAction("0x42852610") };
    delete incompleteAction.owner_product;
    mockPlatformResponses(
      new Response(JSON.stringify({ ok: true, staking: {}, wallet_action: incompleteAction }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const output = await captureOutput(() =>
      runCliEntrypoint(["regent-staking", "claim-usdc", "--submit", "--config", configPath]),
    );

    expect(output.result).toBe(1);
    expect(output.stderr).toContain("prepared wallet_action.owner_product is missing or invalid");
    expect(sendTransactionMock).not.toHaveBeenCalled();
  });
});
