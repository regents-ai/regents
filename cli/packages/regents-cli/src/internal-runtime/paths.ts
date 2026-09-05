import os from "node:os";
import path from "node:path";
import fs from "node:fs";
import crypto from "node:crypto";

export const SECURE_DIR_MODE = 0o700;
export const SECURE_FILE_MODE = 0o600;

export function expandHome(input: string): string {
  if (input === "~") {
    return os.homedir();
  }

  if (input.startsWith("~/")) {
    return path.join(os.homedir(), input.slice(2));
  }

  return input;
}

export function defaultStateDir(): string {
  return path.join(os.homedir(), ".regent", "state");
}

export function defaultSocketPath(): string {
  return path.join(os.homedir(), ".regent", "run", "regent.sock");
}

export function defaultConfigPath(): string {
  return path.join(os.homedir(), ".regent", "config.json");
}

export function ensureParentDir(filePath: string): void {
  const dirPath = path.dirname(filePath);
  const existed = fs.existsSync(dirPath);
  fs.mkdirSync(dirPath, { recursive: true, mode: SECURE_DIR_MODE });
  if (!existed) {
    fs.chmodSync(dirPath, SECURE_DIR_MODE);
  }
}

export function ensureSecureDir(dirPath: string): void {
  fs.mkdirSync(dirPath, { recursive: true, mode: SECURE_DIR_MODE });
  fs.chmodSync(dirPath, SECURE_DIR_MODE);
}

export function writeFileAtomicSync(
  filePath: string,
  payload: string | Buffer,
  mode = SECURE_FILE_MODE,
): void {
  const resolved = path.resolve(filePath);
  ensureParentDir(resolved);

  const tempPath = `${resolved}.${crypto.randomUUID()}.tmp`;
  let wroteTemp = false;

  try {
    fs.writeFileSync(tempPath, payload, { mode, flag: "wx" });
    wroteTemp = true;

    const fileHandle = fs.openSync(tempPath, "r");
    try {
      fs.fsyncSync(fileHandle);
    } finally {
      fs.closeSync(fileHandle);
    }

    fs.renameSync(tempPath, resolved);
    fs.chmodSync(resolved, mode);
  } catch (error) {
    if (wroteTemp || fs.existsSync(tempPath)) {
      fs.rmSync(tempPath, { force: true });
    }
    throw error;
  }
}

export function writeJsonFileAtomicSync(filePath: string, value: unknown, mode = SECURE_FILE_MODE): void {
  writeFileAtomicSync(filePath, `${JSON.stringify(value, null, 2)}\n`, mode);
}
