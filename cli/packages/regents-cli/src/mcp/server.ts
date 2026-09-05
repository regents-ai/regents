import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod/v4";

import { lookupAgentbookTrust, prepareAgentbookRegistration } from "../commands/agentbook.js";
import { regentsCliVersion } from "../internal-runtime/product-http-client.js";
import { RegentKernel } from "../internal-runtime/runtime.js";
import { redactRegentErrorMessage, redactRegentSecrets } from "./redact.js";
import { REGENTS_MCP_TOOL_DEFINITIONS, regentsMcpToolsList } from "./tool-registry.js";

type ToolResult = {
  content: { type: "text"; text: string }[];
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};

const textResult = (value: unknown): ToolResult => {
  const safeValue = redactRegentSecrets(value);

  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(safeValue, null, 2),
      },
    ],
    structuredContent:
      safeValue && typeof safeValue === "object" && !Array.isArray(safeValue)
        ? (safeValue as Record<string, unknown>)
        : { value: safeValue },
  };
};

const errorResult = (error: unknown): ToolResult => {
  const message = error instanceof Error ? error.message : String(error);

  return {
    content: [
      {
        type: "text" as const,
        text: redactRegentErrorMessage(message),
      },
    ],
    isError: true,
  };
};

// Every tool handler runs through this wrapper. A throwing tool becomes a
// redacted JSON-RPC tool error rather than reaching the MCP SDK's own error
// path, which would copy the raw thrown message (and any secret it carries)
// into the result without redaction. The wrapper also keeps the server alive
// across a single failing tool call and never leaks a stack trace.
const safeTool =
  <TArgs>(handler: (args: TArgs) => Promise<ToolResult>) =>
  async (args: TArgs): Promise<ToolResult> => {
    try {
      return await handler(args);
    } catch (error) {
      return errorResult(error);
    }
  };

const toolDefinition = (name: string) => {
  const definition = REGENTS_MCP_TOOL_DEFINITIONS.find((tool) => tool.name === name);
  if (!definition) {
    throw new Error(`Regents MCP tool is not registered: ${name}`);
  }
  return definition;
};

const toolAnnotations = (riskClass: string) => ({
  readOnlyHint: riskClass === "read",
  destructiveHint: false,
  idempotentHint: riskClass === "read",
});

export type RegentsMcpServerMode = "local-stdio" | "platform-http";

export interface CreateRegentsMcpServerOptions {
  configPath?: string;
  mode: RegentsMcpServerMode;
}

export async function createRegentsMcpServer(options: CreateRegentsMcpServerOptions) {
  const kernel = new RegentKernel(options.configPath);
  const server = new McpServer(
    {
      name: "regents",
      version: regentsCliVersion,
    },
    {
      instructions: [
        "Use Regents tools as the operator surface for Regent agents.",
        "Prefer read, prepare, and simulate tools before product writes.",
        "Do not treat Codex as wallet custody.",
        "Submit tools are intentionally absent until a Regent approval has been recorded.",
      ].join("\n"),
    },
  );

  const identityStatus = toolDefinition("regents.runtime.identity.status");
  server.registerTool(
    identityStatus.name,
    {
      title: identityStatus.title,
      description: identityStatus.description,
      inputSchema: {},
      annotations: toolAnnotations(identityStatus.riskClass),
    },
    safeTool(async () => textResult(await kernel.call("auth.siwa.status"))),
  );

  const runtimeStatus = toolDefinition("regents.runtime.status");
  server.registerTool(
    runtimeStatus.name,
    {
      title: runtimeStatus.title,
      description: runtimeStatus.description,
      inputSchema: {},
      annotations: toolAnnotations(runtimeStatus.riskClass),
    },
    safeTool(async () => textResult(await kernel.call("runtime.status"))),
  );

  const agentbookStatus = toolDefinition("regents.agentbook.status");
  server.registerTool(
    agentbookStatus.name,
    {
      title: agentbookStatus.title,
      description: agentbookStatus.description,
      inputSchema: {},
      annotations: toolAnnotations(agentbookStatus.riskClass),
    },
    safeTool(async () => textResult(await lookupAgentbookTrust(options.configPath))),
  );

  const agentbookRegisterPrepare = toolDefinition("regents.agentbook.register_prepare");
  server.registerTool(
    agentbookRegisterPrepare.name,
    {
      title: agentbookRegisterPrepare.title,
      description: agentbookRegisterPrepare.description,
      inputSchema: {},
      annotations: toolAnnotations(agentbookRegisterPrepare.riskClass),
    },
    safeTool(async () => textResult(await prepareAgentbookRegistration(options.configPath, "regents-cli-mcp"))),
  );

  const walletPrepare = toolDefinition("regents.wallet.action.policy");
  server.registerTool(
    walletPrepare.name,
    {
      title: walletPrepare.title,
      description: walletPrepare.description,
      inputSchema: {
        owner_product: z.enum(["platform", "autolaunch", "techtree", "shared-services", "ios", "regents-cli"]),
        resource: z.string().min(1),
        action: z.string().min(1),
        payload: z.record(z.string(), z.unknown()).optional(),
      },
      annotations: toolAnnotations(walletPrepare.riskClass),
    },
    safeTool(async (input) =>
      textResult({
        ok: false,
        code: "product_prepare_required",
        submit_tools_enabled: false,
        message:
          "Use the owning product's Regent command or MCP tool to prepare a WalletAction. Generic wallet submission is not exposed.",
        requested: input,
      }),
    ),
  );

  const walletSimulate = toolDefinition("regents.wallet.action.simulate");
  server.registerTool(
    walletSimulate.name,
    {
      title: walletSimulate.title,
      description: walletSimulate.description,
      inputSchema: {
        wallet_action: z.record(z.string(), z.unknown()),
      },
      annotations: toolAnnotations(walletSimulate.riskClass),
    },
    safeTool(async (input) =>
      textResult({
        ok: false,
        code: "simulation_not_configured",
        submit_tools_enabled: false,
        message:
          "Wallet simulation must run through the owning product or the configured local chain client before any submit path is enabled.",
        requested: input,
      }),
    ),
  );

  const x402Details = toolDefinition("regents.x402.details");
  server.registerTool(
    x402Details.name,
    {
      title: x402Details.title,
      description: x402Details.description,
      inputSchema: {
        url: z.string().url(),
        method: z.enum(["GET", "POST", "PUT", "PATCH", "DELETE"]).optional(),
        headers: z.record(z.string(), z.string()).optional(),
        body: z.string().optional(),
      },
      annotations: toolAnnotations(x402Details.riskClass),
    },
    safeTool(async (input) => textResult(await kernel.call("x402.details", input))),
  );

  const x402Quote = toolDefinition("regents.x402.quote");
  server.registerTool(
    x402Quote.name,
    {
      title: x402Quote.title,
      description: x402Quote.description,
      inputSchema: {
        url: z.string().url(),
        method: z.enum(["GET", "POST", "PUT", "PATCH", "DELETE"]).optional(),
        headers: z.record(z.string(), z.string()).optional(),
        body: z.string().optional(),
        max_amount: z.string().regex(/^\d+$/).optional(),
        max_deposit_amount: z.string().regex(/^\d+$/).optional(),
      },
      annotations: toolAnnotations(x402Quote.riskClass),
    },
    safeTool(async (input) => textResult(await kernel.call("x402.quote", input))),
  );

  const x402IntentPrepare = toolDefinition("regents.x402.intent.prepare");
  server.registerTool(
    x402IntentPrepare.name,
    {
      title: x402IntentPrepare.title,
      description: x402IntentPrepare.description,
      inputSchema: {
        url: z.string().url(),
        method: z.enum(["GET", "POST", "PUT", "PATCH", "DELETE"]).optional(),
        headers: z.record(z.string(), z.string()).optional(),
        body: z.string().optional(),
        max_amount: z.string().regex(/^\d+$/).optional(),
        max_deposit_amount: z.string().regex(/^\d+$/).optional(),
      },
      annotations: toolAnnotations(x402IntentPrepare.riskClass),
    },
    safeTool(async (input) => textResult(await kernel.call("x402.prepare", { ...input, approve: false }))),
  );

  const x402Fetch = toolDefinition("regents.x402.fetch");
  server.registerTool(
    x402Fetch.name,
    {
      title: x402Fetch.title,
      description: x402Fetch.description,
      inputSchema: {
        intent_id: z.string().min(1),
        url: z.string().url(),
        method: z.enum(["GET", "POST", "PUT", "PATCH", "DELETE"]).optional(),
        headers: z.record(z.string(), z.string()).optional(),
        body: z.string().optional(),
      },
      annotations: toolAnnotations(x402Fetch.riskClass),
    },
    safeTool(async (input) => textResult(await kernel.call("x402.fetch", input))),
  );

  const x402Refund = toolDefinition("regents.x402.refund");
  server.registerTool(
    x402Refund.name,
    {
      title: x402Refund.title,
      description: x402Refund.description,
      inputSchema: {
        url: z.string().url(),
        headers: z.record(z.string(), z.string()).optional(),
        amount: z.string().regex(/^\d+$/).optional(),
      },
      annotations: toolAnnotations(x402Refund.riskClass),
    },
    safeTool(async (input) => textResult(await kernel.call("x402.refund", input))),
  );

  const x402ReceiptGet = toolDefinition("regents.x402.receipt.get");
  server.registerTool(
    x402ReceiptGet.name,
    {
      title: x402ReceiptGet.title,
      description: x402ReceiptGet.description,
      inputSchema: {
        id: z.string().min(1),
      },
      annotations: toolAnnotations(x402ReceiptGet.riskClass),
    },
    safeTool(async (input) => textResult(await kernel.call("x402.receipts.get", input))),
  );

  const x402HeaderPrepare = toolDefinition("regents.x402.header.prepare");
  server.registerTool(
    x402HeaderPrepare.name,
    {
      title: x402HeaderPrepare.title,
      description: x402HeaderPrepare.description,
      inputSchema: {
        resource_uri: z.string().url(),
        chain_id: z.number().int().positive().optional(),
      },
      annotations: toolAnnotations(x402HeaderPrepare.riskClass),
    },
    safeTool(async (input) =>
      textResult({
        ok: false,
        code: "regent_x402_wrapper_required",
        submit_tools_enabled: false,
        message:
          "AgentKit/x402 headers are only exposed through Regent wrappers. Codex should not hand-write signed payment headers.",
        requested: input,
      }),
    ),
  );

  return {
    server,
    tools: regentsMcpToolsList(),
    close: async () => {
      await kernel.stop();
    },
  };
}
