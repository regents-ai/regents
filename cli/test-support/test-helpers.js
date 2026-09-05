import fs from "node:fs/promises";

const toString = (chunk, encoding) => {
  if (typeof chunk === "string") {
    return chunk;
  }

  if (Buffer.isBuffer(chunk)) {
    return chunk.toString(typeof encoding === "string" ? encoding : "utf8");
  }

  return String(chunk);
};

export async function captureOutput(fn) {
  const stdoutChunks = [];
  const stderrChunks = [];
  const originalStdoutWrite = process.stdout.write.bind(process.stdout);
  const originalStderrWrite = process.stderr.write.bind(process.stderr);

  process.stdout.write = ((chunk, encoding, callback) => {
    stdoutChunks.push(toString(chunk, encoding));
    if (typeof callback === "function") {
      callback();
    }
    return true;
  });

  process.stderr.write = ((chunk, encoding, callback) => {
    stderrChunks.push(toString(chunk, encoding));
    if (typeof callback === "function") {
      callback();
    }
    return true;
  });

  try {
    const result = await Promise.resolve().then(fn);
    return {
      result,
      stdout: stdoutChunks.join(""),
      stderr: stderrChunks.join(""),
    };
  } finally {
    process.stdout.write = originalStdoutWrite;
    process.stderr.write = originalStderrWrite;
  }
}

export async function waitForFileRemoval(filePath, timeoutMs = 10_000, pollIntervalMs = 50) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    try {
      await fs.access(filePath);
    } catch {
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
  }

  throw new Error(`timed out waiting for file removal: ${filePath}`);
}
