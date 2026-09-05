import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { RegentKernel } from "../../src/internal-runtime/runtime.js";
import { runCliEntrypoint } from "../../src/index.js";
import { writeInitialConfig } from "../../src/internal-runtime/index.js";
import { startRegentsMcpHttpServer } from "../../src/mcp/http.js";
import { redactRegentErrorMessage, redactRegentSecrets } from "../../src/mcp/redact.js";
import { createRegentsMcpServer } from "../../src/mcp/server.js";
import { regentsMcpToolsList } from "../../src/mcp/tool-registry.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

describe("Regents MCP server", () => {
  let tempDir = "";
  let configPath = "";

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-mcp-"));
    configPath = path.join(tempDir, "regent.config.json");
    writeInitialConfig(configPath, {
      runtime: {
        socketPath: path.join(tempDir, "run", "regent.sock"),
        stateDir: path.join(tempDir, "state"),
      },
      services: {
        siwa: {
          baseUrl: "http://127.0.0.1:4100",
          requestTimeoutMs: 1_000,
        },
        platform: {
          baseUrl: "http://127.0.0.1:4100",
          requestTimeoutMs: 1_000,
        },
        autolaunch: {
          baseUrl: "http://127.0.0.1:4101",
          requestTimeoutMs: 1_000,
        },
      },
      wallet: {
        privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
        keystorePath: path.join(tempDir, "keys", "agent-wallet.json"),
      },
    });
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("lists curated tools and answers identity status through MCP", async () => {
    const mcp = await createRegentsMcpServer({ configPath, mode: "local-stdio" });
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "regents-mcp-test", version: "0.0.0" });

    await mcp.server.connect(serverTransport);
    await client.connect(clientTransport);

    try {
      const tools = await client.listTools();
      const toolNames = tools.tools.map((tool) => tool.name);

      expect(toolNames).toContain("regents.runtime.identity.status");
      expect(toolNames).toContain("regents.runtime.status");
      expect(toolNames).toContain("regents.x402.fetch");
      expect(toolNames).toContain("regents.x402.refund");
      for (const name of ["regents.x402.details", "regents.x402.quote", "regents.x402.intent.prepare", "regents.x402.fetch"]) {
        expect(tools.tools.find(tool => tool.name === name)?.annotations).toMatchObject({
          readOnlyHint: false, destructiveHint: true, idempotentHint: false,
        });
      }
      expect(toolNames).not.toContain("regents.wallet.action.submit");
      expect(toolNames.some((name) => name.startsWith("regents.techtree."))).toBe(false);
      expect(toolNames.some((name) => name.includes(".submit"))).toBe(false);

      const identity = await client.callTool({
        name: "regents.runtime.identity.status",
        arguments: {},
      });

      expect(identity.structuredContent).toEqual(
        expect.objectContaining({
          authenticated: false,
          session: null,
          protectedRoutesReady: false,
        }),
      );
    } finally {
      await client.close();
      await mcp.close();
    }
  });

  it("preserves public x402 offers and receipts through actual MCP results while excluding credentials", async () => {
    const raw = {x402Version: 2, accepts: [], extensions: {
      signedOffer: {signature: "public-offer-signature", receipt: "public-offer-receipt", token: "public-protocol-token"},
    }};
    const receipt = {receipt_id: "x402_receipt_public", intent_id: "x402_intent_public",
      payment_status: "settled", settlement: {success: true, transaction: `0x${"a".repeat(64)}`, network: "eip155:8453"}};
    const call = vi.spyOn(RegentKernel.prototype, "call").mockResolvedValue({
      ok: true, payment_required_response: raw, receipt,
      privateKey: "private", access_token: "private", "payment-signature": "private",
      headers: {authorization: "private", "x-siwa-receipt": "private"},
    } as never);
    const mcp = await createRegentsMcpServer({configPath, mode: "local-stdio"});
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    const client = new Client({name: "x402-evidence-test", version: "0.0.0"});
    await mcp.server.connect(serverTransport);
    await client.connect(clientTransport);
    try {
      for (const [name, args] of [
        ["regents.x402.details", {url: "https://example.test/paid"}],
        ["regents.x402.fetch", {url: "https://example.test/paid", intent_id: "x402_intent_public"}],
        ["regents.x402.receipt.get", {id: "x402_receipt_public"}],
      ] as const) {
        const result = await client.callTool({name, arguments: args});
        expect(result.isError).not.toBe(true);
        expect(result.structuredContent?.payment_required_response).toEqual(raw);
        expect(result.structuredContent?.receipt).toEqual(receipt);
        expect(result.structuredContent?.privateKey).toBe("[redacted]");
        expect(result.structuredContent?.access_token).toBe("[redacted]");
        expect(result.structuredContent?.["payment-signature"]).toBe("[redacted]");
        expect(result.structuredContent?.headers).toEqual({authorization: "[redacted]", "x-siwa-receipt": "[redacted]"});
        expect((result.content as Array<{text: string}>)[0].text).toContain("x402_receipt_public");
      }
    } finally {
      call.mockRestore(); await client.close(); await mcp.close();
    }
  });

  it("keeps submit tools unavailable in the exported policy", () => {
    const toolPolicy = regentsMcpToolsList();

    expect(toolPolicy.submit_tools_enabled).toBe(false);
    expect(toolPolicy.tools.map((tool) => tool.name)).not.toContain("regents.wallet.action.submit");
    expect(toolPolicy.tools.some((tool) => tool.riskClass === "submit")).toBe(false);
  });

  it("serves remote MCP over bearer-protected streamable HTTP", async () => {
    const running = await startRegentsMcpHttpServer({
      configPath,
      host: "127.0.0.1",
      port: 0,
      bearerToken: "test-mcp-token",
    });

    const client = new Client({ name: "regents-mcp-http-test", version: "0.0.0" });

    try {
      const unauthorized = await fetch(running.url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: {
            protocolVersion: "2025-06-18",
            capabilities: {},
            clientInfo: { name: "unauthorized-test", version: "0.0.0" },
          },
        }),
      });

      expect(unauthorized.status).toBe(401);

      await client.connect(
        new StreamableHTTPClientTransport(new URL(running.url), {
          requestInit: {
            headers: {
              authorization: "Bearer test-mcp-token",
            },
          },
        }),
      );

      const tools = await client.listTools();
      expect(tools.tools.map((tool) => tool.name)).toContain("regents.runtime.identity.status");
    } finally {
      await client.close().catch(() => undefined);
      await running.close();
    }
  });

  it("redacts receipts, keys, tokens, and auth headers from nested values", () => {
    expect(
      redactRegentSecrets({
        receipt: "siwa-receipt",
        signature: "0xsignature",
        privateKey: "0xprivate",
        access_token: "platform-token",
        headers: {
          authorization: "Bearer token",
          "x-key-id": "key-id",
        },
        identity: {
          token_id: "99",
          wallet_address: "0x1111111111111111111111111111111111111111",
        },
      }),
    ).toEqual({
      receipt: "[redacted]",
      signature: "[redacted]",
      privateKey: "[redacted]",
      access_token: "[redacted]",
      headers: {
        authorization: "[redacted]",
        "x-key-id": "[redacted]",
      },
      identity: {
        token_id: "99",
        wallet_address: "0x1111111111111111111111111111111111111111",
      },
    });
  });

  it("scrubs secret material from free-text error messages", () => {
    const privateKey = `0x${"a".repeat(64)}`;
    const signedTx = `0x${"b".repeat(140)}`;

    expect(redactRegentErrorMessage(`upstream failed with key ${privateKey}`)).toBe(
      "upstream failed with key [redacted]",
    );
    expect(redactRegentErrorMessage(`broadcast rejected raw tx ${signedTx}`)).toBe(
      "broadcast rejected raw tx [redacted]",
    );
    expect(
      redactRegentErrorMessage("401 from facilitator: Authorization Bearer abcdef0123456789"),
    ).toBe("401 from facilitator: Authorization [redacted]");
    expect(
      redactRegentErrorMessage("decode failed: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdEF12"),
    ).toBe("decode failed: [redacted]");
    expect(redactRegentErrorMessage("plain failure, no secrets")).toBe(
      "plain failure, no secrets",
    );
  });

  it("redacts mnemonics and seed phrases by key in success results", () => {
    expect(
      redactRegentSecrets({
        mnemonic: "legal winner thank year wave sausage worth useful legal winner thank yellow",
        seed_phrase: "abandon ability able about above absent",
        ok: true,
      }),
    ).toEqual({
      mnemonic: "[redacted]",
      seed_phrase: "[redacted]",
      ok: true,
    });
  });

  it("returns a redacted tool error and keeps the server alive when a tool throws", async () => {
    const mcp = await createRegentsMcpServer({ configPath, mode: "local-stdio" });
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "regents-mcp-error-test", version: "0.0.0" });

    await mcp.server.connect(serverTransport);
    await client.connect(clientTransport);

    try {
      // The protected URL has nothing listening, so the kernel call throws. The
      // wrapper must turn that into a clean isError result.
      const failed = await client.callTool({
        name: "regents.x402.details",
        arguments: { url: "http://127.0.0.1:9/protected" },
      });

      expect(failed.isError).toBe(true);
      const text = (failed.content as { type: string; text: string }[])[0]?.text ?? "";
      // No private key, mnemonic, or signed-tx payload may survive in the message.
      expect(text).not.toMatch(/0x[a-fA-F0-9]{64}/);
      // The server must still answer a subsequent call.
      const identity = await client.callTool({
        name: "regents.runtime.identity.status",
        arguments: {},
      });
      expect(identity.isError).toBeFalsy();
      expect(identity.structuredContent).toEqual(
        expect.objectContaining({ authenticated: false }),
      );
    } finally {
      await client.close();
      await mcp.close();
    }
  });

  it("rejects malformed tool input with a protocol error", async () => {
    const mcp = await createRegentsMcpServer({ configPath, mode: "local-stdio" });
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "regents-mcp-input-test", version: "0.0.0" });

    await mcp.server.connect(serverTransport);
    await client.connect(clientTransport);

    try {
      // x402 details requires a valid URL.
      const result = await client.callTool({
        name: "regents.x402.details",
        arguments: { url: "" },
      });
      expect(result.isError).toBe(true);
    } finally {
      await client.close();
      await mcp.close();
    }
  });

  it("exports Codex MCP config and local MCP diagnostics", async () => {
    const exportOutput = await captureOutput(() =>
      runCliEntrypoint(["mcp", "export", "codex", "--json", "--config", configPath]),
    );
    const toolsOutput = await captureOutput(() =>
      runCliEntrypoint(["mcp", "tools", "list", "--json", "--config", configPath]),
    );
    const doctorOutput = await captureOutput(() =>
      runCliEntrypoint(["mcp", "doctor", "--json", "--config", configPath]),
    );

    expect(exportOutput.result).toBe(0);
    expect(parsePrintedJson(exportOutput.stdout)).toEqual({
      ok: true,
      mcpServers: {
        regents: {
          command: "npx",
          args: ["-y", "@regentslabs/cli@latest", "mcp", "serve", "--transport", "stdio"],
          env_vars: ["REGENT_WALLET_PRIVATE_KEY"],
          startup_timeout_sec: 20,
          tool_timeout_sec: 120,
          enabled: true,
        },
      },
    });

    expect(toolsOutput.result).toBe(0);
    expect(parsePrintedJson(toolsOutput.stdout)).toEqual(
      expect.objectContaining({
        ok: true,
        submit_tools_enabled: false,
      }),
    );

    expect(doctorOutput.result).toBe(0);
    expect(parsePrintedJson(doctorOutput.stdout)).toEqual(
      expect.objectContaining({
        ok: true,
        submit_tools_enabled: false,
        transport: {
          stdio: true,
          streamable_http: true,
        },
      }),
    );
  });
});
