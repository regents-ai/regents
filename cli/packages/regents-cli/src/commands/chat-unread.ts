import type { ChatAuthorMessage } from "./chat-filter.js";

export interface ChatUnreadPage {
  data: ChatAuthorMessage[];
  pagination?: { limit?: number; next_cursor?: number | null };
}

const MAX_UNREAD_PAGES = 20;

export const CHAT_UNREAD_PAGE_LIMIT = 100;

const numericId = (message: ChatAuthorMessage): number | undefined =>
  typeof message.id === "number" ? message.id : undefined;

/**
 * Collect unread messages for one scope using after-cursor pagination. With a
 * saved cursor, pages are already forward-ordered by the API. With no saved
 * cursor, only the newest page is treated as unread and returned oldest-first.
 */
export const collectUnreadMessages = async (
  fetchPage: (after?: number) => Promise<ChatUnreadPage>,
  cursor: number | undefined,
): Promise<{ messages: ChatAuthorMessage[]; newestId: number | undefined }> => {
  const collected: ChatAuthorMessage[] = [];
  let after = cursor;
  let newestId = cursor;

  for (let pageIndex = 0; pageIndex < MAX_UNREAD_PAGES; pageIndex += 1) {
    const page = await fetchPage(after);
    const data = page.data ?? [];

    for (const message of data) {
      const id = numericId(message);
      if (id !== undefined && (newestId === undefined || id > newestId)) {
        newestId = id;
      }
    }

    for (const message of data) {
      const id = numericId(message);
      if (cursor !== undefined && id !== undefined && id <= cursor) {
        continue;
      }

      collected.push(message);
    }

    const nextCursor = page.pagination?.next_cursor ?? null;
    if (nextCursor === null) {
      break;
    }

    after = nextCursor;

    if (cursor === undefined) {
      break;
    }
  }

  return {
    messages: cursor === undefined ? collected.reverse() : collected,
    newestId,
  };
};
