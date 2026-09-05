import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import type {
  JsonRpcResponse,
  TechtreeVerifyReceiptShowResult,
  TechtreeVerifyRunParams,
  TechtreeVerifyRunResult,
  TechtreeVerifyStatusParams,
} from "../../../internal-types/index.js";
import { JsonRpcError } from "../../errors.js";
import { runVerifyRuntimePython } from "./forge.js";

const MINIMUM_PYTHON_MINOR = 12;
const FIXTURE_PROCESS_TIMEOUT_MS = 120_000;
const HERMES_PROCESS_TIMEOUT_MS = 2_500_000;
const PYTHON_REMEDY = "Install Python 3.12 or newer and ensure python3 is on PATH.";
const VERIFY_RPC_ERROR_CODES: Readonly<Record<number, string>> = {
  [-32004]: "verify_record_not_found",
  [-32003]: "verify_runtime_unavailable",
  [-32005]: "verify_comparison_busy",
  [-32006]: "verify_spend_exhausted",
};

const unavailable = (
  message: string,
  options?: { cause?: unknown; details?: Record<string, unknown> },
): JsonRpcError => new JsonRpcError(message, {
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
    throw unavailable("Bundled Verify runtime files are missing. Reinstall @regentslabs/cli.");
  }
  return found;
};

const ensureSupportedPython = async (directory: string): Promise<void> => {
  const result = await runVerifyRuntimePython(
    ["-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"],
    { runtimeDirectory: directory, purpose: "checking the Python version for Verify" },
  );
  const match = /^(\d+)\.(\d+)$/.exec(result.stdout.trim());
  if (result.exitCode !== 0 || !match) {
    throw unavailable(`python3 could not report a supported version for Verify. ${PYTHON_REMEDY}`, {
      details: { exit_code: result.exitCode, stderr: result.stderr.trim() },
    });
  }
  const major = Number(match[1]);
  const minor = Number(match[2]);
  if (major < 3 || (major === 3 && minor < MINIMUM_PYTHON_MINOR)) {
    throw unavailable(`python3 ${major}.${minor} is too old for Verify. ${PYTHON_REMEDY}`);
  }
};

const callVerifyRuntime = async <T>(
  method: string,
  params: Record<string, unknown>,
  timeoutMs: number,
): Promise<T> => {
  const directory = runtimeDirectory();
  await ensureSupportedPython(directory);
  const requestId = "techtree-verify";
  const request = JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params });
  const result = await runVerifyRuntimePython(["-m", "verify_runtime"], {
    runtimeDirectory: directory,
    purpose: `running ${method}`,
    input: request,
    timeoutMs,
  });
  if (result.exitCode !== 0) {
    throw unavailable("The bundled Verify runtime exited before returning a result. Reinstall @regentslabs/cli and confirm python3 3.12 or newer works.", {
      details: { exit_code: result.exitCode, stderr: result.stderr.trim() },
    });
  }

  let response: JsonRpcResponse<T>;
  try {
    response = JSON.parse(result.stdout.trim()) as JsonRpcResponse<T>;
  } catch (error) {
    throw new JsonRpcError("Verify runtime returned malformed JSON. Reinstall @regentslabs/cli and retry.", {
      code: "verify_runtime_invalid_json",
      cause: error,
    });
  }
  if (response.jsonrpc !== "2.0" || response.id !== requestId) {
    throw new JsonRpcError("Verify runtime returned a malformed JSON-RPC result. Reinstall @regentslabs/cli and retry.", {
      code: "verify_runtime_invalid_response",
    });
  }
  if ("error" in response) {
    const code = VERIFY_RPC_ERROR_CODES[response.error.code] ?? "invalid_verify_request";
    throw new JsonRpcError(response.error.message, { code, rpcCode: response.error.code });
  }
  return response.result;
};

export function handleTechtreeVerifyRun(
  stateDir: string,
  params: TechtreeVerifyRunParams,
): Promise<TechtreeVerifyRunResult> {
  return callVerifyRuntime(
    "techtree.verify.run",
    {
      state_dir: stateDir,
      builtin: params.builtin,
      executor: params.executor,
      hermes_command: params.hermes_command ?? null,
    },
    params.executor === "fixture" ? FIXTURE_PROCESS_TIMEOUT_MS : HERMES_PROCESS_TIMEOUT_MS,
  );
}

export function handleTechtreeVerifyStatus(
  stateDir: string,
  params: TechtreeVerifyStatusParams,
): Promise<TechtreeVerifyRunResult> {
  return callVerifyRuntime("techtree.verify.status", {
    state_dir: stateDir,
    comparison_id: params.comparison_id,
  }, FIXTURE_PROCESS_TIMEOUT_MS);
}

export function handleTechtreeVerifyReceiptShow(
  stateDir: string,
  params: { digest: string },
): Promise<TechtreeVerifyReceiptShowResult> {
  return callVerifyRuntime("techtree.verify.receipt.show", {
    state_dir: stateDir,
    digest: params.digest,
  }, FIXTURE_PROCESS_TIMEOUT_MS);
}
