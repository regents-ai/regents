import crypto from "node:crypto";
import path from "node:path";

const MAX_UNIX_SOCKET_PATH_BYTES = 100;

export const resolveRelaySocketPath = (runtimeSocketPath: string, suffix: string): string => {
  const parsed = path.parse(runtimeSocketPath);
  const baseDir = parsed.dir || path.dirname(runtimeSocketPath);
  const baseName = parsed.ext === ".sock" ? parsed.name : path.basename(runtimeSocketPath);
  const preferred = path.join(baseDir, `${baseName}.${suffix}.sock`);

  if (Buffer.byteLength(preferred, "utf8") <= MAX_UNIX_SOCKET_PATH_BYTES) {
    return preferred;
  }

  const shortId = crypto.createHash("sha256").update(runtimeSocketPath).digest("hex").slice(0, 12);
  return path.join("/tmp", `regent-${shortId}.${suffix}.sock`);
};
