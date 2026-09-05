import type { SiwaAudience } from "./auth.js";
import type { RegentExecutorHarnessKind } from "./agent.js";

export type RegentLogLevel = "debug" | "info" | "warn" | "error";

export interface RegentRuntimeConfig {
  socketPath: string;
  stateDir: string;
  logLevel: RegentLogLevel;
}

export interface RegentServiceConfig {
  baseUrl: string;
  requestTimeoutMs: number;
}

export interface RegentVoiceConfig {
  /** Name of the env var holding the OpenAI API key (env-indirection; the raw key is never stored in config). */
  openaiApiKeyEnv: string;
  /** Port the local Hermes voice gateway binds. */
  port: number;
  /** Realtime model bound to the ephemeral client_secret at mint time. */
  model: string;
  /** Input-audio transcription model. */
  transcriptionModel: string;
  /** Default output voice. */
  defaultVoice: string;
  /** Reasoning effort for the realtime session. */
  reasoningEffort: "minimal" | "low" | "medium" | "high" | "xhigh";
  /** Ephemeral secret / session lifetime in seconds. */
  sessionTtlSeconds: number;
  /** Path to the voice tool registry JSON (byte-parity with the hosted registry). */
  toolRegistryPath: string;
}

export interface RegentServicesConfig {
  siwa: RegentServiceConfig;
  platform: RegentServiceConfig;
  autolaunch: RegentServiceConfig;
  voice: RegentVoiceConfig;
}

export interface RegentAuthConfig {
  audience: SiwaAudience;
  defaultChainId: number;
}

export interface RegentWalletConfig {
  privateKeyEnv: string;
  keystorePath: string;
}

export interface RegentGossipsubConfig {
  enabled: boolean;
  listenAddrs: string[];
  bootstrap: string[];
  peerIdPath: string;
}

export interface RegentHarnessConfig {
  enabled: boolean;
  entrypoint: string;
  workspaceRoot: string;
  profiles: string[];
}

export interface RegentAgentsConfig {
  defaultHarness: RegentExecutorHarnessKind;
  harnesses: Record<string, RegentHarnessConfig>;
}

export interface RegentConfig {
  runtime: RegentRuntimeConfig;
  auth: RegentAuthConfig;
  services: RegentServicesConfig;
  wallet: RegentWalletConfig;
  gossipsub: RegentGossipsubConfig;
  agents: RegentAgentsConfig;
}
