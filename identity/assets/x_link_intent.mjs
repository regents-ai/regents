// A five-minute continuation for Privy's full-page X redirect. This is intent,
// never identity evidence. Only fresh signed proof can update the shared store.
export function createXLinkIntent(storage, appId, {now = Date.now, nonce = () => crypto.randomUUID()} = {}) {
  const key = "regent:profile-x-link:v1";
  const read = () => {
    try {
      const intent = JSON.parse(storage.getItem(key));
      return intent && intent.appId === appId && typeof intent.subject === "string" &&
        typeof intent.nonce === "string" && Number.isFinite(intent.expiresAt) &&
        intent.expiresAt > now() && intent.expiresAt <= now() + 300_000 ? intent : null;
    } catch { return null; }
  };
  const clear = id => {
    try {
      if (JSON.parse(storage.getItem(key))?.nonce !== id) return false;
      storage.removeItem(key);
      return storage.getItem(key) === null;
    } catch { return false; }
  };
  return {
    begin(subject) {
      if (read()) throw new Error("link_already_in_progress");
      const intent = {appId, subject, nonce: nonce(), expiresAt: now() + 300_000};
      storage.setItem(key, JSON.stringify(intent));
      if (read()?.nonce !== intent.nonce) throw new Error("link_continuation_unavailable");
      return intent.nonce;
    },
    claim({user, linkMethod, linkedAccount}) {
      const intent = read();
      if (!intent || linkMethod !== "twitter" || linkedAccount?.type !== "twitter_oauth" ||
          user?.id !== intent.subject) return null;
      return clear(intent.nonce) ? intent.subject : null;
    },
    cancel(id) { if (id) clear(id); },
  };
}
