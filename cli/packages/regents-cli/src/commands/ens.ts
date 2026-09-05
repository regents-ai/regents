import { getBooleanFlag, getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";
import {
  txRequestFromWalletAction,
  submitPreparedTxRequest,
  type JsonObject,
} from "./autolaunch/shared.js";
import { requestProductJson } from "./product-http.js";

const requestPlatformJson = async (
  method: "POST",
  path: string,
  body: Record<string, unknown>,
  configPath?: string,
): Promise<JsonObject> => {
  return requestProductJson<JsonObject>(
    method,
    path,
    {
      body,
      configPath,
      requireAgentAuth: true,
      authAudience: "platform",
      service: "platform",
      commandName: "regents ens set-primary",
    },
  );
};
export async function runEnsSetPrimary(
  args: ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  const ensName = requireArg(getFlag(args, "ens"), "ens");
  const payload = await requestPlatformJson(
    "POST",
    "/api/platform/ens/prepare-primary",
    { ens_name: ensName },
    configPath,
  );

  const prepared =
    payload.prepared && typeof payload.prepared === "object"
      ? (payload.prepared as JsonObject)
      : null;
  const txRequest = txRequestFromWalletAction(prepared?.wallet_action);

  if (!txRequest || !getBooleanFlag(args, "submit")) {
    printJson(payload);
    return;
  }

  const txHash = await submitPreparedTxRequest(txRequest, configPath);
  printJson({ ...payload, submitted: true, tx_hash: txHash });
}
