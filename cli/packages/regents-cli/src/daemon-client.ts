import { callJsonRpc, loadConfig } from "./internal-runtime/index.js";
import type { RegentRpcMethod, RegentRpcParams, RegentRpcResult } from "./internal-types/index.js";

export async function daemonCall<TMethod extends RegentRpcMethod>(
  method: TMethod,
  params?: RegentRpcParams<TMethod>,
  configPath?: string,
): Promise<RegentRpcResult<TMethod>> {
  const config = loadConfig(configPath);
  return callJsonRpc(config.runtime.socketPath, method, params);
}
