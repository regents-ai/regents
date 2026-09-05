import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import type {
  JsonRpcResponse,
  TechtreeUpliftReportParams,
  TechtreeUpliftReportResult,
} from "../../../internal-types/index.js";
import { JsonRpcError } from "../../errors.js";
import { runVerifyRuntimePython } from "./forge.js";

const MINIMUM_PYTHON_MINOR = 12;
const REPORT_PROCESS_TIMEOUT_MS = 120_000;
const PYTHON_REMEDY = "Install Python 3.12 or newer and ensure python3 is on PATH.";
const UPLIFT_RPC_ERROR_CODES: Readonly<Record<number, string>> = {
  [-32007]: "uplift_receipt_not_found",
  [-32008]: "uplift_input_unmatched",
  [-32009]: "uplift_report_collision",
  [-32010]: "uplift_report_conflict",
  [-32003]: "verify_runtime_unavailable",
};

const nextSteps = (code: number): readonly string[] => code === -32007
  ? ["Run `regents techtree verify run --builtin --fixture --json` to produce a receipt set."]
  : ["Correct the receipt set and retry `regents techtree uplift report --receipt-digest <digest>... --json`."];

const unavailable = (message: string, cause?: unknown): JsonRpcError => new JsonRpcError(message, {
  code: "verify_runtime_unavailable",
  cause,
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
    { runtimeDirectory: directory, purpose: "checking the Python version for Uplift" },
  );
  const match = /^(\d+)\.(\d+)$/.exec(result.stdout.trim());
  if (result.exitCode !== 0 || !match) {
    throw unavailable(`python3 could not report a supported version for Uplift. ${PYTHON_REMEDY}`);
  }
  const major = Number(match[1]);
  const minor = Number(match[2]);
  if (major < 3 || (major === 3 && minor < MINIMUM_PYTHON_MINOR)) {
    throw unavailable(`python3 ${major}.${minor} is too old for Uplift. ${PYTHON_REMEDY}`);
  }
};

const callUpliftRuntime = async <T>(params: Record<string, unknown>): Promise<T> => {
  const directory = runtimeDirectory();
  await ensureSupportedPython(directory);
  const requestId = "techtree-uplift";
  const result = await runVerifyRuntimePython(["-m", "verify_runtime"], {
    runtimeDirectory: directory,
    purpose: "running techtree.uplift.report",
    input: JSON.stringify({ jsonrpc: "2.0", id: requestId, method: "techtree.uplift.report", params }),
    timeoutMs: REPORT_PROCESS_TIMEOUT_MS,
  });
  if (result.exitCode !== 0) {
    throw unavailable("The bundled Verify runtime exited before returning an Uplift report. Reinstall @regentslabs/cli and retry.");
  }
  let response: JsonRpcResponse<T>;
  try {
    response = JSON.parse(result.stdout.trim()) as JsonRpcResponse<T>;
  } catch (error) {
    throw new JsonRpcError("Verify runtime returned malformed JSON for Uplift. Reinstall @regentslabs/cli and retry.", {
      code: "verify_runtime_invalid_json",
      cause: error,
    });
  }
  if (response.jsonrpc !== "2.0" || response.id !== requestId) {
    throw new JsonRpcError("Verify runtime returned a malformed Uplift JSON-RPC result. Reinstall @regentslabs/cli and retry.", {
      code: "verify_runtime_invalid_response",
    });
  }
  if ("error" in response) {
    const code = UPLIFT_RPC_ERROR_CODES[response.error.code] ?? "invalid_uplift_request";
    throw new JsonRpcError(response.error.message, {
      code,
      rpcCode: response.error.code,
      nextSteps: nextSteps(response.error.code),
    });
  }
  return response.result;
};

export function handleTechtreeUpliftReport(
  stateDir: string,
  params: TechtreeUpliftReportParams,
): Promise<TechtreeUpliftReportResult> {
  return callUpliftRuntime({
    state_dir: stateDir,
    receipt_digests: [...params.receipt_digests],
    tolerance: params.tolerance ?? null,
  });
}
