import type { ChatLiveEvent, RegentConfig } from "../internal-types/index.js";

import {
  listChatSubscriptions,
  readChatCursors,
  writeChatCursors,
  type ChatProduct,
} from "../internal-runtime/index.js";
import {
  ProductHttpError,
  requestProductResponse,
  type ProductServiceName,
} from "../internal-runtime/product-http-client.js";
import { messageWithRetryAfter } from "../internal-runtime/rate-limit-message.js";
import { parseIntegerFlag, type ParsedCliArgs } from "../parse.js";
import { CLI_PALETTE, isHumanTerminal, printJson, printJsonLine, renderPanel, tone } from "../printer.js";
import { resolveChatAuthorFilter, type ChatAuthorFilter, type ChatAuthorMessage } from "./chat-filter.js";
import { collectUnreadMessages, CHAT_UNREAD_PAGE_LIMIT } from "./chat-unread.js";

const DEFAULT_SCOPES = ["system"] as const;
const WALLET_ADDRESS_PATTERN = /^0x[0-9a-fA-F]{40}$/u;

const isChatLiveEvent = (payload: unknown): payload is ChatLiveEvent => {
  if (!payload || typeof payload !== "object") {
    return false;
  }

  const candidate = payload as Partial<ChatLiveEvent>;
  return typeof candidate.event === "string" && !!candidate.message && typeof candidate.message === "object";
};

const truncate = (value: string, max = 96): string => {
  if (value.length <= max) {
    return value;
  }

  return `${value.slice(0, Math.max(0, max - 1))}…`;
};

const renderChatEvent = (event: ChatLiveEvent): string => {
  const message = event.message as Record<string, unknown>;
  const scopeLabel = typeof message.scope === "string" && message.scope !== "" ? message.scope : "chat";
  const lines = [
    `${tone("event", CLI_PALETTE.secondary)} ${tone(event.event, CLI_PALETTE.primary, true)}`,
  ];

  if (typeof message.id === "string" || typeof message.id === "number") {
    lines.push(`${tone("id", CLI_PALETTE.secondary)} ${tone(String(message.id), CLI_PALETTE.primary)}`);
  }

  if (typeof message.scope === "string" && message.scope !== "") {
    lines.push(`${tone("scope", CLI_PALETTE.secondary)} ${tone(message.scope, CLI_PALETTE.primary)}`);
  }

  if (typeof message.body === "string" && message.body.trim() !== "") {
    lines.push(`${tone("body", CLI_PALETTE.secondary)} ${tone(truncate(message.body.trim()), CLI_PALETTE.primary)}`);
  }

  const author = message.author_label ?? message.author_wallet_address ?? message.author;
  if (typeof author === "string" && author !== "") {
    lines.push(`${tone("author", CLI_PALETTE.secondary)} ${tone(author, CLI_PALETTE.primary)}`);
  }

  if (typeof message.created_at === "string") {
    lines.push(`${tone("time", CLI_PALETTE.secondary)} ${tone(message.created_at, CLI_PALETTE.secondary)}`);
  }

  return renderPanel(`◆ CHAT · ${scopeLabel} · ${event.event}`, lines, {
    borderColor: CLI_PALETTE.emphasis,
    titleColor: CLI_PALETTE.title,
  });
};

export const parseChatCursorFlags = (args: ParsedCliArgs): { before?: number; after?: number } => {
  const before = parseIntegerFlag(args, "before");
  const after = parseIntegerFlag(args, "after");

  if (before !== undefined && after !== undefined) {
    throw new Error("--before and --after cannot be used together");
  }

  return { before, after };
};

const normalizeWalletAddress = (value: string, label: string): `0x${string}` => {
  if (!WALLET_ADDRESS_PATTERN.test(value)) {
    throw new Error(`${label} must be a 0x wallet address`);
  }

  return value.toLowerCase() as `0x${string}`;
};

export const dmScopeForWallets = (walletA: string, walletB: string): string => {
  const wallets = [
    normalizeWalletAddress(walletA, "sender wallet"),
    normalizeWalletAddress(walletB, "counterpart wallet"),
  ].sort();

  return `dm:${wallets[0]}:${wallets[1]}`;
};

/**
 * Resolve the scopes for a variadic chat command: explicit positional scopes
 * win, then the locally saved subscriptions for the product, then ["system"].
 */
export const resolveChatScopes = (
  positionalScopes: readonly string[],
  config: RegentConfig,
  product: ChatProduct,
): readonly string[] => {
  if (positionalScopes.length > 0) {
    return positionalScopes;
  }

  const subscriptions = listChatSubscriptions(config, product);
  return subscriptions.length > 0 ? subscriptions : DEFAULT_SCOPES;
};

export interface ChatUnreadScopeResult {
  scope: string;
  unread_count: number;
  cursor: number | null;
  messages: ChatAuthorMessage[];
}

export interface ChatUnreadResult {
  peek: boolean;
  data: ChatUnreadScopeResult[];
}

/**
 * Shared unread driver for both products: per scope, page forward from the saved
 * cursor, report the new messages oldest-first, and advance the cursor to the
 * newest fetched id unless peeking.
 */
export const collectUnreadForScopes = async (input: {
  scopes: readonly string[];
  filter: ChatAuthorFilter;
  peek: boolean;
  config: RegentConfig;
  product: ChatProduct;
  fetchPage: (scope: string, after?: number) => Promise<{
    data: ChatAuthorMessage[];
    pagination?: { limit?: number; next_cursor?: number | null };
  }>;
}): Promise<ChatUnreadResult> => {
  const cursors = readChatCursors(input.config, input.product);
  const nextCursors: Record<string, number> = { ...cursors };
  const data: ChatUnreadScopeResult[] = [];

  for (const scope of input.scopes) {
    const cursor = cursors[scope];
    const { messages, newestId } = await collectUnreadMessages(
      (after) => input.fetchPage(scope, after),
      cursor,
    );

    if (newestId !== undefined) {
      nextCursors[scope] = newestId;
    }

    const visible = input.filter ? messages.filter(input.filter) : messages;
    data.push({
      scope,
      unread_count: visible.length,
      cursor: newestId ?? cursor ?? null,
      messages: visible,
    });
  }

  if (!input.peek) {
    writeChatCursors(input.config, input.product, nextCursors);
  }

  return { peek: input.peek, data };
};

const streamPath = (pathTemplate: string, scopes: readonly string[]): string => {
  const query = new URLSearchParams({ scopes: scopes.join(",") });
  return `${pathTemplate}?${query.toString()}`;
};

const streamErrorMessage = async (
  response: Response,
  fallback: string,
): Promise<string> => {
  try {
    const payload = await response.json() as unknown;
    const error = payload && typeof payload === "object" ? (payload as { error?: unknown }).error : undefined;
    const message =
      error && typeof error === "object" && typeof (error as { message?: unknown }).message === "string"
        ? String((error as { message: string }).message)
        : fallback;

    return messageWithRetryAfter(response.status, response.headers, message);
  } catch {
    return messageWithRetryAfter(response.status, response.headers, fallback);
  }
};

export async function tailProductChatStream(
  input: {
    service: ProductServiceName;
    path: string;
    commandName: string;
    scopes: readonly string[];
    filter: ChatAuthorFilter;
    configPath?: string;
    json?: boolean;
  },
): Promise<void> {
  const humanOutput = !input.json && isHumanTerminal();
  const requestPath = streamPath(input.path, input.scopes);
  const controller = new AbortController();
  const handleSignal = (): void => controller.abort();

  process.on("SIGINT", handleSignal);
  process.on("SIGTERM", handleSignal);

  try {
    const { response, requestId } = await requestProductResponse({
      service: input.service,
      method: "GET",
      path: requestPath,
      configPath: input.configPath,
      commandName: input.commandName,
      timeoutMs: 0,
      signal: controller.signal,
      headers: { accept: "application/x-ndjson" },
    });

    if (!response.ok) {
      throw new ProductHttpError({
        service: input.service,
        status: response.status,
        path: requestPath,
        requestId,
        message: await streamErrorMessage(
          response,
          `Regent ${input.service} chat stream failed (${response.status}).`,
        ),
      });
    }

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error("expected chat stream response body");
    }

    if (humanOutput) {
      process.stdout.write(
        `${renderPanel("◆ CHAT LISTENING", [
          `${tone("scopes", CLI_PALETTE.secondary)} ${tone(input.scopes.join(", "), CLI_PALETTE.primary, true)}`,
          `${tone("stream", CLI_PALETTE.secondary)} ${tone(requestPath, CLI_PALETTE.primary)}`,
        ], {
          borderColor: CLI_PALETTE.emphasis,
          titleColor: CLI_PALETTE.title,
        })}\n\n`,
      );
    }

    const decoder = new TextDecoder();
    let buffer = "";

    while (!controller.signal.aborted) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      buffer += decoder.decode(value, { stream: true });

      while (true) {
        const newlineIndex = buffer.indexOf("\n");
        if (newlineIndex < 0) {
          break;
        }

        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);

        if (!line) {
          continue;
        }

        let payload: unknown;

        try {
          payload = JSON.parse(line) as unknown;
        } catch {
          throw new Error("chat stream returned invalid JSON");
        }

        if (isChatLiveEvent(payload)) {
          if (input.filter && !input.filter(payload.message)) {
            continue;
          }

          if (humanOutput) {
            process.stdout.write(`${renderChatEvent(payload)}\n\n`);
          } else {
            printJsonLine(payload);
          }
          continue;
        }

        if (payload && typeof payload === "object" && "event" in payload && payload.event === "heartbeat") {
          continue;
        }

        if (payload && typeof payload === "object" && "event" in payload && payload.event === "ready") {
          continue;
        }

        if (payload && typeof payload === "object" && "error" in payload) {
          throw new Error(
            `chat stream error: ${String((payload as { error?: unknown }).error ?? "unknown")}`,
          );
        }
      }
    }
  } catch (error) {
    if (controller.signal.aborted || (error instanceof DOMException && error.name === "AbortError")) {
      return;
    }

    throw error;
  } finally {
    process.off("SIGINT", handleSignal);
    process.off("SIGTERM", handleSignal);
  }
}

export async function tailAutolaunchChatScopes(
  scopes: readonly string[],
  filter: ChatAuthorFilter,
  configPath?: string,
  json?: boolean,
): Promise<void> {
  await tailProductChatStream({
    service: "autolaunch",
    path: "/api/autolaunch/v1/chat/stream",
    commandName: "regents autolaunch chat tail",
    scopes,
    filter,
    configPath,
    json,
  });
}
