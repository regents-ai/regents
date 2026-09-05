import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import type {
  JsonRpcResponse,
  TechtreeForgeFamilyContract,
  TechtreeForgeFamilyValidationInput,
  TechtreeForgeFamilyValidationResult,
} from "../../../internal-types/index.js";
import { JsonRpcError } from "../../errors.js";

const MINIMUM_PYTHON_MINOR = 12;
const PYTHON_PROCESS_TIMEOUT_MS = 30_000;
const MAX_PYTHON_OUTPUT_BYTES = 4 * 1024 * 1024;
const PYTHON_REMEDY =
  "Install Python 3.12 or newer and ensure it is available as python3 on PATH.";

type PythonProcessResult = {
  exitCode: number | null;
  stdout: string;
  stderr: string;
};

type PythonProcessOptions = {
  runtimeDirectory: string;
  purpose: string;
  input?: string;
  timeoutMs?: number;
};

const verifyRuntimeUnavailable = (
  message: string,
  options?: { cause?: unknown; details?: Record<string, unknown> },
): JsonRpcError =>
  new JsonRpcError(message, {
    code: "verify_runtime_unavailable",
    cause: options?.cause,
    details: options?.details,
  });

const runtimeDirectory = (): string => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const candidates = [
    path.resolve(here, "../../../verify-runtime"),
    path.resolve(here, "../../../../../verify-runtime"),
  ];
  const found = candidates.find((candidate) =>
    existsSync(path.join(candidate, "verify_runtime", "__main__.py")),
  );
  if (!found) {
    throw verifyRuntimeUnavailable(
      "Bundled Verify runtime files are missing. Reinstall @regentslabs/cli.",
    );
  }
  return found;
};

export const runVerifyRuntimePython = (
  args: readonly string[],
  options: PythonProcessOptions,
): Promise<PythonProcessResult> =>
  new Promise((resolve, reject) => {
    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let settled = false;
    const timeoutMs = options.timeoutMs ?? PYTHON_PROCESS_TIMEOUT_MS;
    const child = spawn("python3", [...args], {
      cwd: options.runtimeDirectory,
      env: {
        ...process.env,
        PYTHONDONTWRITEBYTECODE: "1",
        PYTHONNOUSERSITE: "1",
        PYTHONPATH: options.runtimeDirectory,
      },
      stdio: ["pipe", "pipe", "pipe"],
    });

    const finish = (callback: () => void): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      callback();
    };

    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      finish(() => {
        reject(
          verifyRuntimeUnavailable(
            `python3 timed out after ${timeoutMs}ms while ${options.purpose}. ${PYTHON_REMEDY}`,
            { details: { timeout_ms: timeoutMs } },
          ),
        );
      });
    }, timeoutMs);

    const capture = (
      stream: "stdout" | "stderr",
      chunks: Buffer[],
      capturedBytes: number,
      chunk: Buffer,
    ): number => {
      const remaining = MAX_PYTHON_OUTPUT_BYTES - capturedBytes;
      if (remaining > 0) {
        chunks.push(chunk.subarray(0, remaining));
      }
      if (chunk.length > remaining) {
        child.kill("SIGKILL");
        finish(() => reject(verifyRuntimeUnavailable(
          `python3 ${stream} exceeded ${MAX_PYTHON_OUTPUT_BYTES} bytes while ${options.purpose}.`,
          { details: { stream, max_output_bytes: MAX_PYTHON_OUTPUT_BYTES } },
        )));
      }
      return capturedBytes + Math.min(chunk.length, Math.max(remaining, 0));
    };

    child.stdout.on("data", (chunk: Buffer) => {
      stdoutBytes = capture("stdout", stdoutChunks, stdoutBytes, chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderrBytes = capture("stderr", stderrChunks, stderrBytes, chunk);
    });
    child.stdin.on("error", () => undefined);
    child.once("error", (error) => {
      finish(() => {
        reject(
          verifyRuntimeUnavailable(
            `python3 could not start while ${options.purpose}. ${PYTHON_REMEDY}`,
            { cause: error },
          ),
        );
      });
    });
    child.once("close", (code) => {
      finish(() => resolve({
        exitCode: code,
        stdout: Buffer.concat(stdoutChunks).toString("utf8"),
        stderr: Buffer.concat(stderrChunks).toString("utf8"),
      }));
    });

    child.stdin.end(options.input);
  });

const ensureSupportedPython = async (directory: string): Promise<void> => {
  const result = await runVerifyRuntimePython(
    ["-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"],
    { runtimeDirectory: directory, purpose: "checking the Python version" },
  );
  const match = /^(\d+)\.(\d+)$/.exec(result.stdout.trim());

  if (result.exitCode !== 0 || !match) {
    throw verifyRuntimeUnavailable(
      `python3 could not report a supported version while checking the bundled Verify runtime. ${PYTHON_REMEDY}`,
      { details: { exit_code: result.exitCode, stderr: result.stderr.trim() } },
    );
  }

  const major = Number(match[1]);
  const minor = Number(match[2]);
  if (major < 3 || (major === 3 && minor < MINIMUM_PYTHON_MINOR)) {
    throw verifyRuntimeUnavailable(
      `python3 ${major}.${minor} is too old for the bundled Verify runtime. ${PYTHON_REMEDY}`,
    );
  }
};

const callVerifyRuntime = async <T>(method: string, params?: unknown): Promise<T> => {
  const directory = runtimeDirectory();
  await ensureSupportedPython(directory);

  const requestId = "forge-family";
  const request = {
    jsonrpc: "2.0" as const,
    id: requestId,
    method,
    ...(params === undefined ? {} : { params }),
  };
  const result = await runVerifyRuntimePython(["-m", "verify_runtime"], {
    runtimeDirectory: directory,
    purpose: "running the bundled Verify runtime",
    input: JSON.stringify(request),
  });

  if (result.exitCode !== 0) {
    throw verifyRuntimeUnavailable(
      `The bundled Verify runtime exited before returning a result. Reinstall @regentslabs/cli and confirm python3 3.12 or newer works.`,
      { details: { exit_code: result.exitCode, stderr: result.stderr.trim() } },
    );
  }

  let response: JsonRpcResponse<T>;
  try {
    response = JSON.parse(result.stdout.trim()) as JsonRpcResponse<T>;
  } catch (error) {
    throw new JsonRpcError("Verify runtime returned invalid JSON.", {
      code: "verify_runtime_invalid_json",
      cause: error,
    });
  }

  if (response.jsonrpc !== "2.0" || response.id !== requestId) {
    throw new JsonRpcError("Verify runtime returned an invalid JSON-RPC envelope.", {
      code: "verify_runtime_invalid_response",
    });
  }
  if ("error" in response) {
    throw new JsonRpcError(response.error.message, {
      code: "invalid_forge_family",
      rpcCode: response.error.code,
    });
  }
  return response.result;
};

export async function handleTechtreeForgeFamilyShow(): Promise<TechtreeForgeFamilyContract> {
  return callVerifyRuntime("techtree.forge.family.show");
}

export async function handleTechtreeForgeFamilyValidate(
  params: { input: TechtreeForgeFamilyValidationInput },
): Promise<TechtreeForgeFamilyValidationResult> {
  return callVerifyRuntime("techtree.forge.family.validate", params);
}
