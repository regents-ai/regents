import { daemonCall } from "../daemon-client.js";
import { printJson } from "../printer.js";

export async function runGossipsubStatus(configPath?: string): Promise<void> {
  printJson(await daemonCall("gossipsub.status", undefined, configPath));
}
