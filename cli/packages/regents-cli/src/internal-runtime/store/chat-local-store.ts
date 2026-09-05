import fs from "node:fs";
import path from "node:path";

import type { RegentConfig } from "../../internal-types/index.js";

import { writeJsonFileAtomicSync } from "../paths.js";

export type ChatProduct = "autolaunch";

const WALLET_PATTERN = /^0x[0-9a-fA-F]{40}$/;

interface ChatFollowsFile {
  readonly schema: "regents.chat-follows.v1";
  readonly follows: readonly string[];
}

interface ChatSubscriptionsFile {
  readonly schema: "regents.chat-subscriptions.v1";
  readonly products: Readonly<Record<string, readonly string[]>>;
}

interface ChatCursorsFile {
  readonly schema: "regents.chat-cursors.v1";
  readonly products: Readonly<Record<string, Readonly<Record<string, number>>>>;
}

const followsFilePath = (config: RegentConfig): string =>
  path.join(config.runtime.stateDir, "chat-follows.json");

const subscriptionsFilePath = (config: RegentConfig): string =>
  path.join(config.runtime.stateDir, "chat-subscriptions.json");

const cursorsFilePath = (config: RegentConfig): string =>
  path.join(config.runtime.stateDir, "chat-cursors.json");

const readJsonFile = <T>(filePath: string, schema: string, empty: T): T => {
  if (!fs.existsSync(filePath)) {
    return empty;
  }

  const raw = fs.readFileSync(filePath, "utf8");
  if (raw.trim() === "") {
    return empty;
  }

  const parsed = JSON.parse(raw) as { schema?: string } & T;
  return parsed && parsed.schema === schema ? parsed : empty;
};

const emptyFollowsFile = (): ChatFollowsFile => ({ schema: "regents.chat-follows.v1", follows: [] });

const emptySubscriptionsFile = (): ChatSubscriptionsFile => ({
  schema: "regents.chat-subscriptions.v1",
  products: {},
});

const emptyCursorsFile = (): ChatCursorsFile => ({ schema: "regents.chat-cursors.v1", products: {} });

export const isWalletEntry = (entry: string): boolean => WALLET_PATTERN.test(entry);

const sameFollowEntry = (left: string, right: string): boolean =>
  isWalletEntry(left) && isWalletEntry(right)
    ? left.toLowerCase() === right.toLowerCase()
    : left === right;

export const listChatFollows = (config: RegentConfig): readonly string[] =>
  readJsonFile(followsFilePath(config), "regents.chat-follows.v1", emptyFollowsFile()).follows;

export const addChatFollow = (
  config: RegentConfig,
  entry: string,
): { follows: readonly string[]; added: boolean } => {
  const current = listChatFollows(config);
  if (current.some((existing) => sameFollowEntry(existing, entry))) {
    return { follows: current, added: false };
  }

  const follows = [...current, entry];
  writeJsonFileAtomicSync(followsFilePath(config), { schema: "regents.chat-follows.v1", follows });
  return { follows, added: true };
};

export const removeChatFollow = (
  config: RegentConfig,
  entry: string,
): { follows: readonly string[]; removed: boolean } => {
  const current = listChatFollows(config);
  const follows = current.filter((existing) => !sameFollowEntry(existing, entry));
  if (follows.length === current.length) {
    return { follows: current, removed: false };
  }

  writeJsonFileAtomicSync(followsFilePath(config), { schema: "regents.chat-follows.v1", follows });
  return { follows, removed: true };
};

export const listChatSubscriptions = (config: RegentConfig, product: ChatProduct): readonly string[] =>
  readJsonFile(subscriptionsFilePath(config), "regents.chat-subscriptions.v1", emptySubscriptionsFile())
    .products[product] ?? [];

const writeChatSubscriptions = (
  config: RegentConfig,
  product: ChatProduct,
  scopes: readonly string[],
): void => {
  const file = readJsonFile(
    subscriptionsFilePath(config),
    "regents.chat-subscriptions.v1",
    emptySubscriptionsFile(),
  );
  writeJsonFileAtomicSync(subscriptionsFilePath(config), {
    schema: "regents.chat-subscriptions.v1",
    products: { ...file.products, [product]: scopes },
  });
};

export const addChatSubscription = (
  config: RegentConfig,
  product: ChatProduct,
  scope: string,
): { scopes: readonly string[]; added: boolean } => {
  const current = listChatSubscriptions(config, product);
  if (current.includes(scope)) {
    return { scopes: current, added: false };
  }

  const scopes = [...current, scope];
  writeChatSubscriptions(config, product, scopes);
  return { scopes, added: true };
};

export const removeChatSubscription = (
  config: RegentConfig,
  product: ChatProduct,
  scope: string,
): { scopes: readonly string[]; removed: boolean } => {
  const current = listChatSubscriptions(config, product);
  const scopes = current.filter((existing) => existing !== scope);
  if (scopes.length === current.length) {
    return { scopes: current, removed: false };
  }

  writeChatSubscriptions(config, product, scopes);
  return { scopes, removed: true };
};

export const readChatCursors = (
  config: RegentConfig,
  product: ChatProduct,
): Readonly<Record<string, number>> =>
  readJsonFile(cursorsFilePath(config), "regents.chat-cursors.v1", emptyCursorsFile()).products[product] ?? {};

export const writeChatCursors = (
  config: RegentConfig,
  product: ChatProduct,
  cursors: Readonly<Record<string, number>>,
): void => {
  const file = readJsonFile(cursorsFilePath(config), "regents.chat-cursors.v1", emptyCursorsFile());
  writeJsonFileAtomicSync(cursorsFilePath(config), {
    schema: "regents.chat-cursors.v1",
    products: { ...file.products, [product]: cursors },
  });
};
