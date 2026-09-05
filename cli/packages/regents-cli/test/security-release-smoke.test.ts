import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../src/index.js";
import type { SignerBackend } from "../src/internal-runtime/agent/signer-backend.js";
import { RegentX402Client } from "../src/internal-runtime/x402/client.js";
import { hashValue } from "../src/internal-runtime/x402/hash.js";
import type { PaymentBindingV1 } from "../src/internal-types/index.js";
import { EXPECTED_PLATFORM_CONTRACT_DIGEST } from "../src/generated/platform-contract-digest.js";
import { captureOutput } from "./helpers/output.js";
import { privateKeyToAccount } from "viem/accounts";

const PRIVATE_KEY = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const USDC_BASE = "0x833589fcd6edb6e08f4c7c32d4f71b54bdA02913";
const PAY_TO = "0x1111111111111111111111111111111111111111";

const encodeHeader = (value: unknown): string =>
  Buffer.from(JSON.stringify(value), "utf8").toString("base64");

const createSigner = (): SignerBackend => {
  const account = privateKeyToAccount(PRIVATE_KEY);
  return {
    address: async () => account.address,
    signMessage: async (message) => account.signMessage({ message }),
    signTypedData: async (data) => account.signTypedData(data),
    signTransaction: async (tx) => account.signTransaction(tx),
    toViemAccount: async () => account,
  };
};

const createPaymentBinding = (
  amount: string,
  overrides: Partial<Omit<PaymentBindingV1, "version" | "binding_hash">> = {},
): PaymentBindingV1 => {
  const withoutHash = {
    version: "PaymentBindingV1" as const,
    resource_id: "techtree_node_payload:node-1:bundle-1",
    buyer_agent_id: null,
    seller_agent_id: "123",
    network: "eip155:8453",
    asset: USDC_BASE,
    amount_atomic: amount,
    pay_to: PAY_TO,
    expires_at: null,
    nonce: "listing-1",
    ...overrides,
  };

  return {
    ...withoutHash,
    binding_hash: hashValue(withoutHash),
  };
};

const createPaymentRequired = (url: string, amount: string, binding: PaymentBindingV1) => ({
  x402Version: 2,
  resource: {
    id: binding.resource_id,
    url,
    description: "Techtree paid payload",
    mimeType: "application/json",
    serviceName: "techtree",
    bindingHash: binding.binding_hash,
  },
  accepts: [
    {
      scheme: "exact",
      network: "eip155:8453",
      asset: USDC_BASE,
      amount,
      payTo: PAY_TO,
      maxTimeoutSeconds: 60,
      extra: {
        name: "USDC",
        version: "2",
        regentPaymentBindingV1: binding,
      },
    },
  ],
});

describe("local security release smoke", () => {
  let originalHome: string | undefined;
  let homeDir = "";
  let sessionFile = "";
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-security-smoke-"));
    sessionFile = path.join(homeDir, "platform-session.json");
    originalHome = process.env.HOME;
    process.env.HOME = homeDir;
    fetchMock.mockReset();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    if (originalHome === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    fs.rmSync(homeDir, { recursive: true, force: true });
  });

  it("uses a saved Platform session for an authenticated write", async () => {
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
      "utf8",
    );

    fetchMock
      .mockResolvedValueOnce(
        new Response("openapi: 3.1.0\ninfo:\n  version: 0.1.0\n", {
          status: 200,
          headers: {
            "content-type": "application/yaml",
            "x-regents-contract-major": "0",
            "x-regents-contract-version": "0.1.0",
            "x-regents-contract-digest": EXPECTED_PLATFORM_CONTRACT_DIGEST,
          },
        }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ok: true,
            billing_account: { runtime_monthly_limit_usd_cents: 10_000 },
            usage: { runtime_monthly_remaining_usd_cents: 10_000 },
          }),
          {
            status: 200,
            headers: { "content-type": "application/json" },
          },
        ),
      );

    vi.stubGlobal("fetch", fetchMock);

    const output = await captureOutput(() =>
      runCliEntrypoint([
        "platform",
        "billing",
        "spend-controls",
        "set",
        "--origin",
        "http://127.0.0.1:4010",
        "--session-file",
        sessionFile,
        "--runtime-monthly-limit-usd",
        "100",
        "--model-usage-monthly-limit-usd",
        "50",
        "--runtime-auto-topup-enabled",
        "--runtime-auto-topup-amount-usd",
        "25",
        "--runtime-auto-topup-threshold-usd",
        "10",
      ]),
    );

    const writeRequest = fetchMock.mock.calls[1];
    const headers = writeRequest?.[1]?.headers as Headers;

    expect(output.result).toBe(0);
    expect(writeRequest?.[0]).toBe("http://127.0.0.1:4010/api/platform/billing/spend-controls");
    expect(writeRequest?.[1]?.method).toBe("PUT");
    expect(headers.get("cookie")).toBe("_platform_phx_key=session-cookie");
    expect(headers.get("x-csrf-token")).toBe("csrf-token");
  });

  it("rejects an x402 payment binding that changes the server amount", async () => {
    const url = "https://example.test/paid";
    const stateDir = fs.mkdtempSync(path.join(homeDir, "x402-"));
    const binding = createPaymentBinding("2000");

    const client = new RegentX402Client({
      stateDir,
      signer: createSigner(),
      fetch: async () =>
        new Response("{}", {
          status: 402,
          headers: {
            "payment-required": encodeHeader(createPaymentRequired(url, "1000", binding)),
          },
        }),
    });

    await expect(client.prepare({ url, approve: true })).rejects.toMatchObject({
      code: "x402_payment_binding_changed",
    });
  });
});
