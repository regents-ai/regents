import {
  addChatFollow,
  listChatFollows,
  loadConfig,
  removeChatFollow,
} from "../internal-runtime/index.js";
import { requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

const requireFollowEntry = (args: ParsedCliArgs): string =>
  requireArg(args.positionals[3], "wallet or label");

export async function runChatFollowsAdd(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const entry = requireFollowEntry(args);
  const config = loadConfig(configPath);
  printJson({ ok: true, entry, ...addChatFollow(config, entry) });
}

export async function runChatFollowsRemove(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const entry = requireFollowEntry(args);
  const config = loadConfig(configPath);
  printJson({ ok: true, entry, ...removeChatFollow(config, entry) });
}

export async function runChatFollowsList(configPath?: string): Promise<void> {
  const config = loadConfig(configPath);
  printJson({ ok: true, follows: listChatFollows(config) });
}
