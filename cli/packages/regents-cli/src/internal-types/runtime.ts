export interface LocalAgentIdentity {
  walletAddress: `0x${string}`;
  chainId: number;
  registryAddress?: `0x${string}`;
  tokenId?: string;
  label?: string;
}

export interface TransportStatus {
  enabled: boolean;
  status: "disabled" | "starting" | "ready" | "stopped" | "stub" | "error" | "degraded";
  note?: string;
}

export interface RuntimeStatus {
  running: boolean;
  socketPath: string;
  stateDir: string;
  logLevel: "debug" | "info" | "warn" | "error";
  authenticated: boolean;
  session: {
    walletAddress: `0x${string}`;
    chainId: number;
    receiptExpiresAt: string;
  } | null;
  agentIdentity: LocalAgentIdentity | null;
  agent: import("./agent.js").RegentAgentStatus | null;
  gossipsub: import("./gossipsub.js").GossipsubStatus;
}
