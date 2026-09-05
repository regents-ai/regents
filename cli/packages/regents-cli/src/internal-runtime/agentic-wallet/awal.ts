import { execFile } from "node:child_process";
import { promisify } from "node:util";

import { RegentError } from "../errors.js";

const execFileAsync = promisify(execFile);

export const AWAL_VERSION = "2.10.0";

export interface AwalResult {
  readonly ok: true;
  readonly command: readonly string[];
  readonly data: unknown;
}

const secretKeyPattern = /secret|private|token|otp|payment|header|authorization/iu;
const secretArgPreviousToken = new Set(["--otp", "-h", "--headers"]);

export const redactAwalValue = (value: unknown): unknown => {
  if (Array.isArray(value)) {
    return value.map(redactAwalValue);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        secretKeyPattern.test(key) ? "[redacted]" : redactAwalValue(entry),
      ]),
    );
  }

  return value;
};

export const awalCommand = (args: readonly string[]): readonly string[] => [
  "npx",
  "-y",
  `awal@${AWAL_VERSION}`,
  ...args,
];

export const redactAwalCommand = (command: readonly string[]): readonly string[] => {
  let redactNextCount = 0;
  return command.map((entry) => {
    if (redactNextCount > 0) {
      redactNextCount -= 1;
      return "[redacted]";
    }
    if (entry === "verify") {
      redactNextCount = 2;
    }
    if (secretArgPreviousToken.has(entry)) {
      redactNextCount = 1;
    }
    return entry;
  });
};

export const runAwalJson = async (args: readonly string[]): Promise<AwalResult> => {
  const command = awalCommand(args);
  try {
    const { stdout } = await execFileAsync(command[0], command.slice(1), {
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024,
      shell: false,
    });
    const parsed = stdout.trim() ? JSON.parse(stdout) : {};
    return { ok: true, command: redactAwalCommand(command), data: redactAwalValue(parsed) };
  } catch (error) {
    throw new RegentError(
      "awal_command_failed",
      "Agentic Wallet command failed.",
      error,
    );
  }
};
