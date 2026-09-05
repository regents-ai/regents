import fs from "node:fs";
import net from "node:net";

import { CliUsageError } from "../cli-usage-error.js";

const PROBE_TIMEOUT_MS = 500;

const socketHasListener = async (socketPath: string): Promise<boolean> =>
  new Promise((resolve) => {
    const probe = net.connect(socketPath);
    let settled = false;

    const finish = (alive: boolean): void => {
      if (settled) {
        return;
      }

      settled = true;
      probe.destroy();
      resolve(alive);
    };

    probe.once("connect", () => finish(true));
    probe.once("error", () => finish(false));
    // A probe that neither connects nor errors is treated as live so a
    // slow-but-running daemon is never orphaned by unlinking its socket.
    probe.setTimeout(PROBE_TIMEOUT_MS, () => finish(true));
  });

/**
 * Make a Unix socket path safe to listen on. A leftover socket file is only
 * removed after a connection probe proves nothing is listening on it; a live
 * listener fails the start instead of being orphaned.
 */
export const claimUnixSocketPath = async (socketPath: string): Promise<void> => {
  if (!fs.existsSync(socketPath)) {
    return;
  }

  if (await socketHasListener(socketPath)) {
    throw new CliUsageError({
      code: "runtime_already_running",
      message: `A Regents runtime is already running at ${socketPath}. Stop it before starting another.`,
    });
  }

  fs.rmSync(socketPath, { force: true });
};
