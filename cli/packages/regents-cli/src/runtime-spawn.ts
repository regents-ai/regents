import { spawn } from "node:child_process";

export async function spawnDetachedRuntime(configPath?: string): Promise<void> {
  const invokedPath = process.argv[1];
  if (!invokedPath) {
    throw new Error("unable to resolve the current Regents CLI entrypoint for daemon startup");
  }

  const child = spawn(process.execPath, [invokedPath, "run", ...(configPath ? ["--config", configPath] : [])], {
    detached: true,
    stdio: "ignore",
  });
  child.unref();
}
