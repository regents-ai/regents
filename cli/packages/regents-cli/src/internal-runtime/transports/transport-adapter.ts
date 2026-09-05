import type { TransportStatus } from "../../internal-types/index.js";

export interface TransportAdapter {
  start(): Promise<void>;
  stop(): Promise<void>;
  status(): Promise<TransportStatus>;
}
