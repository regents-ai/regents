import type { RegentConfig } from "../internal-types/index.js";

import { CliUsageError } from "../cli-usage-error.js";
import { isWalletEntry, listChatFollows } from "../internal-runtime/index.js";
import { getBooleanFlag, getFlags, type ParsedCliArgs } from "../parse.js";

export interface ChatAuthorMessage {
  author_wallet_address?: string | null;
  author_label?: string | null;
  [key: string]: unknown;
}

export type ChatAuthorFilter = ((message: ChatAuthorMessage) => boolean) | null;

const matchesEntry = (entry: string, message: ChatAuthorMessage): boolean => {
  if (isWalletEntry(entry)) {
    return (
      typeof message.author_wallet_address === "string" &&
      message.author_wallet_address.toLowerCase() === entry.toLowerCase()
    );
  }

  return typeof message.author_label === "string" && message.author_label === entry;
};

/**
 * Build the client-side author filter for `--from <wallet|label>` (repeatable)
 * and `--following`. Wallet entries match author_wallet_address
 * case-insensitively; everything else matches author_label exactly. Returns
 * null when no filter flags were given.
 */
export const resolveChatAuthorFilter = (args: ParsedCliArgs, config: RegentConfig): ChatAuthorFilter => {
  const entries = [...getFlags(args, "from")];

  if (getBooleanFlag(args, "following")) {
    const follows = listChatFollows(config);
    if (follows.length === 0) {
      throw new CliUsageError({
        code: "chat_follow_list_empty",
        message:
          "The saved follow list is empty. Add a wallet or label with `regents chat follows add <wallet|label>` first.",
      });
    }

    entries.push(...follows);
  }

  if (entries.length === 0) {
    return null;
  }

  return (message) => entries.some((entry) => matchesEntry(entry, message));
};
