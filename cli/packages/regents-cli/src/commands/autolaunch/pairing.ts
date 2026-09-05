import { loadAgentAuthState } from "../agent-auth.js";
import type { LocalAgentIdentity } from "../../internal-types/index.js";
import { getBooleanFlag, getFlag, requireArg, type ParsedCliArgs } from "../../parse.js";
import {
  CLI_PALETTE,
  printJson,
  printText,
  renderKeyValueLines,
  renderPanel,
  tone,
  type KeyValueRow,
} from "../../printer.js";
import {
  baseUrl,
  configuredSigner,
  parsePollingIntervalSeconds,
  requestTypedJson,
  type JsonObject,
} from "./shared.js";

const PAIRING_CODE_REGEX = /^AL-([A-Z2-9]{6})-[A-Z2-9]{8}$/u;

const requirePairingCode = (args: ParsedCliArgs): { code: string; nonce: string } => {
  const code = requireArg(getFlag(args, "code"), "code");
  const match = PAIRING_CODE_REGEX.exec(code);
  if (!match?.[1]) {
    throw new Error("Pairing code is invalid.");
  }

  return { code, nonce: match[1] };
};

const challengeMessage = (nonce: string): string =>
  `Autolaunch agent pairing\n\nPairing: AL-${nonce}\nNonce: ${nonce}`;

interface AgentPairingAgent {
  readonly agent_id: string;
  readonly agent_wallet_address: string;
  readonly agent_chain_id: number;
  readonly agent_registry_address: string;
  readonly agent_token_id: string;
  readonly agent_label?: string | null;
}

interface AgentPairingSession {
  readonly session_id: string;
  readonly status: "pending" | "completed" | "expired";
  readonly agent: AgentPairingAgent | null;
}

interface AgentPairingSessionEnvelope {
  readonly ok: true;
  readonly session: AgentPairingSession;
}

export interface AgentConnectionHuman {
  readonly id: number;
  readonly privy_user_id: string;
  readonly display_name?: string | null;
  readonly wallet_address?: string | null;
}

export interface AgentConnectionSession {
  readonly connection_id: string;
  readonly status: "pending" | "completed" | "expired";
  readonly connection_code?: string | null;
  readonly connect_url?: string | null;
  readonly expires_at: string;
  readonly completed_at?: string | null;
  readonly plan_id?: string | null;
  readonly agent_id: string;
  readonly agent_wallet_address: string;
  readonly agent_chain_id: number;
  readonly agent_registry_address: string;
  readonly agent_token_id: string;
  readonly agent_label?: string | null;
  readonly human?: AgentConnectionHuman | null;
}

export interface AgentConnectionSessionEnvelope {
  readonly ok: true;
  readonly connection: AgentConnectionSession;
}

const requireIdentity = (identity: LocalAgentIdentity | null): Required<LocalAgentIdentity> => {
  if (
    !identity?.walletAddress ||
    typeof identity.chainId !== "number" ||
    !identity.registryAddress ||
    !identity.tokenId
  ) {
    throw new Error("This machine does not have a saved Regent agent yet. Run `regents identity ensure` first.");
  }

  return {
    walletAddress: identity.walletAddress,
    chainId: identity.chainId,
    registryAddress: identity.registryAddress,
    tokenId: identity.tokenId,
    label: identity.label ?? "",
  };
};

const assertSigningWalletMatchesIdentity = (
  signingWalletAddress: string,
  identityWalletAddress: string,
): void => {
  if (signingWalletAddress.toLowerCase() !== identityWalletAddress.toLowerCase()) {
    throw new Error("The saved Regent agent wallet does not match the configured signing key.");
  }
};

const requirePairedAgent = (session: AgentPairingSession): AgentPairingAgent => {
  if (!session.agent) {
    throw new Error("Autolaunch did not return the connected agent for this pairing.");
  }

  return session.agent;
};

const shortAddress = (address: string): string =>
  /^0x[0-9a-fA-F]{40}$/u.test(address) ? `${address.slice(0, 6)}...${address.slice(-4)}` : address;

const fullConnectUrl = (connectUrl: string | null | undefined, configPath?: string): string | null => {
  if (!connectUrl) {
    return null;
  }

  if (/^https?:\/\//iu.test(connectUrl)) {
    return connectUrl;
  }

  return `${baseUrl(configPath)}${connectUrl.startsWith("/") ? "" : "/"}${connectUrl}`;
};

const renderPairingReceipt = (payload: AgentPairingSessionEnvelope): string => {
  const session = payload.session;
  const pairedAgent = requirePairedAgent(session);
  const label = pairedAgent.agent_label?.trim();
  const rows: KeyValueRow[] = [
    {
      label: "status",
      value: session.status,
      valueColor: session.status === "completed" ? CLI_PALETTE.emphasis : CLI_PALETTE.accent,
    },
    { label: "session", value: session.session_id },
    {
      label: "agent",
      value: label ? `${label} (${pairedAgent.agent_id})` : pairedAgent.agent_id,
      valueColor: CLI_PALETTE.primary,
    },
    { label: "chain", value: String(pairedAgent.agent_chain_id) },
    { label: "wallet", value: shortAddress(pairedAgent.agent_wallet_address) },
    { label: "registry", value: shortAddress(pairedAgent.agent_registry_address) },
    { label: "token", value: pairedAgent.agent_token_id },
  ];

  return renderPanel(
    "AUTOLAUNCH PAIRING COMPLETE",
    [
      ...renderKeyValueLines(rows),
      "",
      tone("No private keys were shared and no funds moved.", CLI_PALETTE.secondary),
      tone("Open your Autolaunch profile to review the connected agent.", CLI_PALETTE.secondary),
    ],
    {
      borderColor: CLI_PALETTE.emphasis,
      titleColor: CLI_PALETTE.title,
    },
  );
};

export const renderConnectionStartReceipt = (
  payload: AgentConnectionSessionEnvelope,
  configPath?: string,
): string => {
  const connection = payload.connection;
  const label = connection.agent_label?.trim();
  const connectUrl = fullConnectUrl(connection.connect_url, configPath);
  const rows: KeyValueRow[] = [
    {
      label: "status",
      value: connection.status,
      valueColor: connection.status === "completed" ? CLI_PALETTE.emphasis : CLI_PALETTE.accent,
    },
    { label: "connection", value: connection.connection_id },
    {
      label: "agent",
      value: label ? `${label} (${connection.agent_id})` : connection.agent_id,
      valueColor: CLI_PALETTE.primary,
    },
    { label: "chain", value: String(connection.agent_chain_id) },
    { label: "wallet", value: shortAddress(connection.agent_wallet_address) },
    { label: "registry", value: shortAddress(connection.agent_registry_address) },
    { label: "token", value: connection.agent_token_id },
    { label: "code", value: connection.connection_code ?? "shown only when started" },
    { label: "url", value: connectUrl ?? "confirmed" },
    { label: "expires", value: connection.expires_at },
  ];

  const nextLine =
    connection.status === "completed"
      ? "The profile connection is complete."
      : "Ask the human operator to open the URL and confirm this agent.";

  return renderPanel(
    "AUTOLAUNCH PROFILE CONNECTION",
    [
      ...renderKeyValueLines(rows),
      "",
      tone(nextLine, CLI_PALETTE.secondary),
      tone("No private keys are shared and no funds move.", CLI_PALETTE.secondary),
    ],
    {
      borderColor: connection.status === "completed" ? CLI_PALETTE.emphasis : CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    },
  );
};

export const createAutolaunchAgentConnection = async (
  body: JsonObject,
  configPath?: string,
): Promise<AgentConnectionSessionEnvelope> =>
  requestTypedJson<AgentConnectionSessionEnvelope>("POST", "/api/autolaunch/v1/agent/agent-connections", {
    body,
    requireAgentAuth: true,
    configPath,
  });

const readAutolaunchAgentConnection = async (
  connectionId: string,
  configPath?: string,
): Promise<AgentConnectionSessionEnvelope> =>
  requestTypedJson<AgentConnectionSessionEnvelope>(
    "GET",
    `/api/autolaunch/v1/agent/agent-connections/${encodeURIComponent(connectionId)}`,
    {
      requireAgentAuth: true,
      configPath,
    },
  );

const waitForAutolaunchAgentConnection = async (
  payload: AgentConnectionSessionEnvelope,
  args: ParsedCliArgs,
  configPath?: string,
): Promise<AgentConnectionSessionEnvelope> => {
  let current = payload;
  const intervalSeconds = parsePollingIntervalSeconds(args);

  while (current.connection.status === "pending") {
    await new Promise((resolve) => setTimeout(resolve, intervalSeconds * 1000));
    current = await readAutolaunchAgentConnection(current.connection.connection_id, configPath);
  }

  return current;
};

export const runAutolaunchConnectStart = async (
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> => {
  const planId = getFlag(args, "plan");
  const label = getFlag(args, "label");
  const body: JsonObject = {
    ...(planId ? { plan_id: planId } : {}),
    ...(label ? { agent_label: label } : {}),
  };

  const payload = await createAutolaunchAgentConnection(body, configPath);
  const finalPayload = getBooleanFlag(args, "watch")
    ? await waitForAutolaunchAgentConnection(payload, args, configPath)
    : payload;

  if (getBooleanFlag(args, "json")) {
    printJson(finalPayload);
    return;
  }

  printText(renderConnectionStartReceipt(payload, configPath));

  if (finalPayload !== payload) {
    printText(renderConnectionStartReceipt(finalPayload, configPath));
  }
};

export const runAutolaunchPair = async (
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> => {
  const { code, nonce } = requirePairingCode(args);
  const { identity } = loadAgentAuthState(configPath);
  const agent = requireIdentity(identity);
  const signer = await configuredSigner(configPath);
  const signingWalletAddress = await signer.address();

  assertSigningWalletMatchesIdentity(signingWalletAddress, agent.walletAddress);

  const message = challengeMessage(nonce);
  const label = getFlag(args, "label") ?? (agent.label === "" ? undefined : agent.label);
  const body: JsonObject = {
    pairing_code: code,
    challenge_message: message,
    agent_wallet_address: agent.walletAddress,
    agent_chain_id: agent.chainId,
    agent_registry_address: agent.registryAddress,
    agent_token_id: agent.tokenId,
    signature_type: "evm_personal_sign",
    signature: await signer.signMessage(message),
    signed_at: new Date().toISOString(),
    ...(label !== undefined ? { agent_label: label } : {}),
  };

  const payload = await requestTypedJson<AgentPairingSessionEnvelope>(
    "POST",
    "/api/autolaunch/v1/app/agent-pairings/complete",
    {
      body,
      configPath,
    },
  );

  if (getBooleanFlag(args, "json")) {
    printJson(payload);
    return;
  }

  printText(renderPairingReceipt(payload));
};
