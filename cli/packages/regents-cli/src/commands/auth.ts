import { daemonCall } from "../daemon-client.js";
import { getFlag, parseIntegerFlag, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

const callAuth = async (
  method: Parameters<typeof daemonCall>[0],
  params?: Record<string, unknown>,
  configPath?: string,
): Promise<void> => {
  printJson(await daemonCall(method, params, configPath));
};

export async function runAuthSiwaLogin(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<void> {
  await callAuth(
    "auth.siwa.login",
    {
      walletAddress: getFlag(args, "wallet-address") as `0x${string}` | undefined,
      chainId: parseIntegerFlag(args, "chain-id"),
      audience: getFlag(args, "audience"),
    },
    configPath,
  );
}

export async function runAuthSiwaStatus(configPath?: string): Promise<void> {
  await callAuth("auth.siwa.status", undefined, configPath);
}

export async function runAuthSiwaLogout(configPath?: string): Promise<void> {
  await callAuth("auth.siwa.logout", undefined, configPath);
}
