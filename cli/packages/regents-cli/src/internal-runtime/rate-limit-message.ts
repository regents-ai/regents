export const messageWithRetryAfter = (
  status: number,
  headers: Headers,
  message: string,
): string => {
  if (status !== 429) {
    return message;
  }

  const retryAfter = retryAfterLabel(headers.get("retry-after"));
  if (!retryAfter) {
    return message;
  }

  return `${stripTrailingPeriod(message)}. Try again in ${retryAfter}.`;
};

const retryAfterLabel = (value: string | null): string | null => {
  if (!value?.trim()) {
    return null;
  }

  const trimmed = value.trim();
  const seconds = Number.parseInt(trimmed, 10);
  if (Number.isFinite(seconds) && seconds > 0 && String(seconds) === trimmed) {
    return pluralizeSeconds(seconds);
  }

  const retryAt = Date.parse(trimmed);
  if (!Number.isNaN(retryAt)) {
    return pluralizeSeconds(Math.max(1, Math.ceil((retryAt - Date.now()) / 1000)));
  }

  return null;
};

const pluralizeSeconds = (seconds: number): string =>
  seconds === 1 ? "1 second" : `${seconds} seconds`;

const stripTrailingPeriod = (value: string): string => value.replace(/\.+$/u, "");
