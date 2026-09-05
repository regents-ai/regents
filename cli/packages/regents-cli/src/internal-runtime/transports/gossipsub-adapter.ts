import type { ChatLiveEvent, GossipsubStatus } from "../../internal-types/index.js";

import { RegentError } from "../errors.js";

type ChatListener = (event: ChatLiveEvent) => void;

export const DEFAULT_CHAT_SCOPE = "system";

export interface GossipsubAdapter {
  start(): Promise<void>;
  stop(): Promise<void>;
  status(): Promise<GossipsubStatus>;
  subscribeChat(listener: ChatListener, scopes?: readonly string[]): Promise<() => void>;
}

const baseDisabledStatus = (eventSocketPath: string | null): GossipsubStatus => ({
  enabled: false,
  configured: false,
  connected: false,
  subscribedTopics: [],
  peerCount: 0,
  lastError: null,
  eventSocketPath,
  status: "disabled",
  note: "Chat transport disabled",
});

export class StubGossipsubAdapter implements GossipsubAdapter {
  async start(): Promise<void> {}

  async stop(): Promise<void> {}

  async status(): Promise<GossipsubStatus> {
    return baseDisabledStatus(null);
  }

  async subscribeChat(): Promise<() => void> {
    throw new RegentError("chat_relay_disabled", "chat transport is disabled in config");
  }
}
