import { describe, expect, it } from "vitest";

import type { LocalAgentIdentity, SiwaSession } from "../../src/internal-types/index.js";
import {
  defaultConfig,
  SERVICE_BASE_URL_ERROR,
} from "../../src/internal-runtime/config.js";

import {
  buildAuthenticatedFetchInit,
  buildProtectedAgentAuthDebugSnapshot,
} from "../../src/internal-runtime/siwa/request-builder.js";
import {
  buildSiwaMessage,
  SiwaClient,
  siwaAudienceStatement,
} from "../../src/internal-runtime/siwa/siwa.js";
import {
  coveredComponentsForAgentHeaders,
  buildHttpSignatureSigningMessage,
  buildSignatureInputString,
  buildSignedAgentHeaders,
  parseSignatureInputHeader,
} from "../../src/internal-runtime/siwa/signing.js";

describe("siwa message construction", () => {
  const messageInput = (baseUrl: string) => {
    const config = defaultConfig();
    config.services.platform.baseUrl = baseUrl;
    return {
      config,
      walletAddress: "0x1111111111111111111111111111111111111111",
      chainId: 8453,
      registryAddress: "0x2222222222222222222222222222222222222222",
      tokenId: "99",
      nonce: "12345678deadbeef",
      issuedAt: "2026-03-10T00:00:00.000Z",
    };
  };

  const completeMessage = (domain: string, uri: string): string =>
    [
      `${domain} wants you to sign in with your Agent account:`,
      "0x1111111111111111111111111111111111111111",
      "",
      "Sign in to Regents CLI.",
      "",
      `URI: ${uri}`,
      "Version: 1",
      "Agent ID: 99",
      "Agent Registry: eip155:8453:0x2222222222222222222222222222222222222222",
      "Chain ID: 8453",
      "Nonce: 12345678deadbeef",
      "Issued At: 2026-03-10T00:00:00.000Z",
    ].join("\n");

  it("builds the expected SIWA message", () => {
    const message = buildSiwaMessage({
      domain: "platform.example",
      uri: "https://platform.example/login",
      walletAddress: "0x1111111111111111111111111111111111111111",
      chainId: 8453,
      registryAddress: "0x2222222222222222222222222222222222222222",
      tokenId: "99",
      nonce: "12345678deadbeef",
      issuedAt: "2026-03-10T00:00:00.000Z",
      statement: "Sign in to Regents CLI.",
    });

    expect(message).toBe(
      [
        "platform.example wants you to sign in with your Agent account:",
        "0x1111111111111111111111111111111111111111",
        "",
        "Sign in to Regents CLI.",
        "",
        "URI: https://platform.example/login",
        "Version: 1",
        "Agent ID: 99",
        "Agent Registry: eip155:8453:0x2222222222222222222222222222222222222222",
        "Chain ID: 8453",
        "Nonce: 12345678deadbeef",
        "Issued At: 2026-03-10T00:00:00.000Z",
      ].join("\n"),
    );
  });

  it.each([
    {
      name: "path, query, and fragment",
      baseUrl: "https://regents.sh/a/path?next=https://evil.example#fragment",
      domain: "regents.sh",
      uri: "https://regents.sh",
    },
    {
      name: "non-default port",
      baseUrl: "https://preview.regents.example:8443/a/path",
      domain: "preview.regents.example:8443",
      uri: "https://preview.regents.example:8443",
    },
  ])("builds the complete canonical message for $name", ({ baseUrl, domain, uri }) => {
    expect(SiwaClient.defaultMessageInput(messageInput(baseUrl))).toBe(
      completeMessage(domain, uri),
    );
  });

  it.each([
    ["newline injection", "https://regents.sh/\nURI: https://evil.example"],
    ["carriage-return injection", "https://regents.sh/\rURI: https://evil.example"],
    ["NUL control-character injection", "https://regents.sh/\u0000URI:https://evil.example"],
    ["javascript scheme", "javascript:alert(1)"],
    ["FTP scheme", "ftp://regents.sh"],
    ["userinfo", "https://operator:secret@regents.sh"],
    ["empty username", "https://@regents.sh"],
    ["empty username and password", "https://:@regents.sh"],
  ])("rejects %s before constructing signed bytes", (_name, baseUrl) => {
    expect(() => SiwaClient.defaultMessageInput(messageInput(baseUrl))).toThrow(
      SERVICE_BASE_URL_ERROR,
    );
  });

  it("formats the shared service audience statement", () => {
    expect(siwaAudienceStatement("techtree")).toBe("Sign in to techtree.");
  });
});

describe("http signing", () => {
  it("formats signature-input exactly", () => {
    const signatureInput = buildSignatureInputString({
      coveredComponents: coveredComponentsForAgentHeaders({
        includeContentDigest: false,
      }),
      created: 1_700_000_000,
      expires: 1_700_000_120,
      nonce: "sig-nonce-fixed",
      keyId: "0xabc",
    });

    expect(signatureInput).toBe(
      'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" "x-timestamp" "x-agent-wallet-address" "x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id");created=1700000000;expires=1700000120;nonce="sig-nonce-fixed";keyid="0xabc"',
    );
  });

  it("builds the canonical signing message", () => {
    const signingMessage = buildHttpSignatureSigningMessage({
      method: "POST",
      path: "/api/techtree/v1/tree/nodes",
      headers: {
        "x-siwa-receipt": "receipt-token",
        "x-key-id": "0xabc",
        "x-timestamp": "1700000000",
        "x-agent-wallet-address": "0x1111111111111111111111111111111111111111",
        "x-agent-chain-id": "8453",
        "x-agent-registry-address": "0x2222222222222222222222222222222222222222",
        "x-agent-token-id": "99",
        "signature-input":
          'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" "x-timestamp" "x-agent-wallet-address" "x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id");created=1700000000;expires=1700000120;nonce="sig-nonce-fixed";keyid="0xabc"',
      },
    });

    expect(signingMessage).toBe(
      [
        '"@method": post',
        '"@path": /api/techtree/v1/tree/nodes',
        '"x-siwa-receipt": receipt-token',
        '"x-key-id": 0xabc',
        '"x-timestamp": 1700000000',
        '"x-agent-wallet-address": 0x1111111111111111111111111111111111111111',
        '"x-agent-chain-id": 8453',
        '"x-agent-registry-address": 0x2222222222222222222222222222222222222222',
        '"x-agent-token-id": 99',
        '"@signature-params": ("@method" "@path" "x-siwa-receipt" "x-key-id" "x-timestamp" "x-agent-wallet-address" "x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id");created=1700000000;expires=1700000120;nonce="sig-nonce-fixed";keyid="0xabc"',
      ].join("\n"),
    );
  });

  it("keeps the query string in the signed path", () => {
    const signingMessage = buildHttpSignatureSigningMessage({
      method: "GET",
      path: "/api/autolaunch/v1/agent/agents?launchable=true",
      headers: {
        "x-siwa-receipt": "receipt-token",
        "x-key-id": "0xabc",
        "x-timestamp": "1700000000",
        "x-agent-wallet-address": "0x1111111111111111111111111111111111111111",
        "x-agent-chain-id": "8453",
        "x-agent-registry-address": "0x2222222222222222222222222222222222222222",
        "x-agent-token-id": "99",
        "signature-input":
          'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" "x-timestamp" "x-agent-wallet-address" "x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id");created=1700000000;expires=1700000120;nonce="sig-nonce-fixed";keyid="0xabc"',
      },
    });

    expect(signingMessage).toContain('"@path": /api/autolaunch/v1/agent/agents?launchable=true');
  });

  it("parses the signature-input parameters used by shared SIWA verification", () => {
    const parsed = parseSignatureInputHeader(
      'sig1=("@method" "@path" "x-siwa-receipt" "x-key-id" "x-timestamp" "x-agent-wallet-address" "x-agent-chain-id" "x-agent-registry-address" "x-agent-token-id");created=1700000000;expires=1700000120;nonce="sig-nonce-fixed";keyid="0xabc"',
    );

    expect(parsed).toEqual({
      label: "sig1",
      coveredComponents: [
        "@method",
        "@path",
        "x-siwa-receipt",
        "x-key-id",
        "x-timestamp",
        "x-agent-wallet-address",
        "x-agent-chain-id",
        "x-agent-registry-address",
        "x-agent-token-id",
      ],
      params: {
        created: 1700000000,
        expires: 1700000120,
        nonce: "sig-nonce-fixed",
        keyid: "0xabc",
      },
    });
  });

  it("generates signed agent headers", async () => {
    const headers = await buildSignedAgentHeaders({
      method: "POST",
      path: "/api/techtree/v1/tree/nodes",
      walletAddress: "0x1111111111111111111111111111111111111111",
      chainId: 8453,
      registryAddress: "0x2222222222222222222222222222222222222222",
      tokenId: "99",
      receipt: "receipt-token",
      privateKey: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
      nowUnixSeconds: 1_700_000_000,
      nonce: "sig-nonce-fixed",
    });

    expect(headers["x-key-id"]).toBe("0x1111111111111111111111111111111111111111");
    expect(headers["signature-input"]).toContain('nonce="sig-nonce-fixed"');
    expect(headers.signature).toMatch(/^sig1=:[A-Za-z0-9+/=]+:$/);
  });

  it("builds a stable protected auth debug snapshot", async () => {
    const session: SiwaSession = {
      walletAddress: "0x1111111111111111111111111111111111111111",
      chainId: 8453,
      nonce: "nonce-fixed",
      keyId: "0x1111111111111111111111111111111111111111",
      receipt: "receipt-token",
      receiptExpiresAt: "2999-01-01T00:00:00.000Z",
      audience: "techtree",
      registryAddress: "0x2222222222222222222222222222222222222222",
      tokenId: "99",
    };
    const agentIdentity: LocalAgentIdentity = {
      walletAddress: "0x1111111111111111111111111111111111111111",
      chainId: 8453,
      registryAddress: "0x2222222222222222222222222222222222222222",
      tokenId: "99",
    };

    const request = await buildAuthenticatedFetchInit({
      method: "POST",
      path: "/api/techtree/v1/tree/nodes",
      body: {
        seed: "ml",
        kind: "hypothesis",
        title: "Debug snapshot",
      },
      session,
      agentIdentity,
      privateKey: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
    });

    expect(
      buildProtectedAgentAuthDebugSnapshot({
        method: "POST",
        signedPath: request.urlPath,
        finalUrl: "https://techtree.example/api/techtree/v1/tree/nodes",
        serializedJsonBody: request.serializedJsonBody,
        headers: request.init.headers,
      }),
    ).toMatchObject({
      method: "POST",
      signedPath: "/api/techtree/v1/tree/nodes",
      finalUrl: "https://techtree.example/api/techtree/v1/tree/nodes",
      serializedJsonBody: JSON.stringify({
        seed: "ml",
        kind: "hypothesis",
        title: "Debug snapshot",
      }),
      authHeaders: {
        "content-type": "application/json",
        "x-siwa-receipt": "receipt-token",
        "x-key-id": "0x1111111111111111111111111111111111111111",
        "x-agent-wallet-address": "0x1111111111111111111111111111111111111111",
        "x-agent-chain-id": "8453",
        "x-agent-registry-address": "0x2222222222222222222222222222222222222222",
        "x-agent-token-id": "99",
      },
    });

    const headers = request.init.headers as Record<string, string>;
    expect(headers["x-regents-client"]).toBeUndefined();
    expect(headers["x-regents-cli-version"]).toBeUndefined();
  });
});
