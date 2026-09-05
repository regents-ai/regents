import type { RegentRpcMethod } from "../internal-types/index.js";

export type RegentMcpRiskClass = "read" | "write" | "prepare" | "simulate" | "submit";

export interface RegentMcpToolDefinition {
  name: string;
  title: string;
  description: string;
  riskClass: RegentMcpRiskClass;
  owner: "regents-cli" | "platform" | "techtree" | "autolaunch" | "shared-services";
  authMode: "none" | "agent-siwa" | "local";
  rpcMethod?: RegentRpcMethod;
}

export const REGENTS_MCP_TOOL_DEFINITIONS: readonly RegentMcpToolDefinition[] = [
  {
    name: "regents.runtime.identity.status",
    title: "Regents runtime identity status",
    description:
      "Read the locally saved Regent identity and signed-agent session status from the local runtime.",
    riskClass: "read",
    owner: "regents-cli",
    authMode: "local",
    rpcMethod: "auth.siwa.status",
  },
  {
    name: "regents.runtime.status",
    title: "Regents runtime status",
    description: "Read local Regent runtime and transport readiness.",
    riskClass: "read",
    owner: "regents-cli",
    authMode: "local",
    rpcMethod: "runtime.status",
  },
  {
    name: "regents.agentbook.status",
    title: "AgentBook status",
    description: "Read the saved human-backed AgentBook trust summary for the current Regent agent.",
    riskClass: "read",
    owner: "platform",
    authMode: "agent-siwa",
  },
  {
    name: "regents.agentbook.register_prepare",
    title: "Prepare AgentBook registration",
    description: "Create a hosted AgentBook registration session for human approval.",
    riskClass: "prepare",
    owner: "platform",
    authMode: "agent-siwa",
  },
  {
    name: "regents.wallet.action.policy",
    title: "Wallet-action preparation policy",
    description:
      "Return the local policy for generic wallet-action preparation. Returns policy text only and never creates an intent.",
    riskClass: "prepare",
    owner: "regents-cli",
    authMode: "local",
  },
  {
    name: "regents.wallet.action.simulate",
    title: "Simulate wallet action",
    description: "Return the current policy for wallet-action simulation.",
    riskClass: "simulate",
    owner: "regents-cli",
    authMode: "local",
  },
  {
    name: "regents.x402.details",
    title: "Read x402 payment details",
    description: "Inspect a protected URL and return the x402 payment terms without paying.",
    riskClass: "read",
    owner: "shared-services",
    authMode: "local",
    rpcMethod: "x402.details",
  },
  {
    name: "regents.x402.quote",
    title: "Quote x402 payment",
    description: "Select the Regent-supported x402 payment option without paying.",
    riskClass: "read",
    owner: "shared-services",
    authMode: "local",
    rpcMethod: "x402.quote",
  },
  {
    name: "regents.x402.intent.prepare",
    title: "Prepare x402 intent",
    description: "Prepare an x402 payment intent. This does not approve or pay.",
    riskClass: "prepare",
    owner: "shared-services",
    authMode: "local",
    rpcMethod: "x402.prepare",
  },
  {
    name: "regents.x402.fetch",
    title: "Fetch approved x402 resource",
    description: "Fetch an x402 resource only after a matching Regent x402 intent has already been approved.",
    riskClass: "write",
    owner: "shared-services",
    authMode: "local",
    rpcMethod: "x402.fetch",
  },
  {
    name: "regents.x402.refund",
    title: "Refund x402 channel",
    description: "Return unused funds from a batch-settlement x402 channel.",
    riskClass: "write",
    owner: "shared-services",
    authMode: "local",
    rpcMethod: "x402.refund",
  },
  {
    name: "regents.x402.receipt.get",
    title: "Read x402 receipt",
    description: "Read one saved local x402 receipt.",
    riskClass: "read",
    owner: "shared-services",
    authMode: "local",
    rpcMethod: "x402.receipts.get",
  },
  {
    name: "regents.x402.header.prepare",
    title: "Prepare x402 header",
    description: "Return the current policy for AgentKit/x402 header preparation.",
    riskClass: "prepare",
    owner: "shared-services",
    authMode: "agent-siwa",
  },
] as const;

export const REGENTS_MCP_SUBMIT_TOOLS: readonly RegentMcpToolDefinition[] = [];

export const regentsMcpToolsList = () => ({
  ok: true,
  submit_tools_enabled: false,
  tools: REGENTS_MCP_TOOL_DEFINITIONS,
});
