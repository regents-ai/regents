import net from "node:net";
import crypto from "node:crypto";

import type { JsonRpcResponse, RegentRpcMethod, RegentRpcResult } from "../../internal-types/index.js";

import { JsonRpcError } from "../errors.js";

const extractJsonRpcErrorCode = (data: unknown): string => {
  if (!data || typeof data !== "object") {
    return "jsonrpc_error";
  }

  return String((data as { code?: string }).code ?? "jsonrpc_error");
};

const parseJsonRpcResponse = <TMethod extends RegentRpcMethod>(
  line: string,
  expectedId: string,
): JsonRpcResponse<RegentRpcResult<TMethod>> => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line);
  } catch (error) {
    throw new JsonRpcError("daemon returned invalid JSON", { cause: error });
  }

  if (!parsed || typeof parsed !== "object") {
    throw new JsonRpcError("daemon returned an invalid JSON-RPC response");
  }

  const response = parsed as Partial<JsonRpcResponse<RegentRpcResult<TMethod>>>;
  if (response.jsonrpc !== "2.0" || typeof response.id !== "string") {
    throw new JsonRpcError("daemon returned an invalid JSON-RPC envelope");
  }

  if (response.id !== expectedId) {
    throw new JsonRpcError("daemon returned a mismatched JSON-RPC response id");
  }

  if ("error" in response) {
    const errorBody = response.error;
    if (
      !errorBody ||
      typeof errorBody !== "object" ||
      typeof (errorBody as { code?: unknown }).code !== "number" ||
      typeof (errorBody as { message?: unknown }).message !== "string"
    ) {
      throw new JsonRpcError("daemon returned an invalid JSON-RPC error response");
    }
  } else if (!("result" in response)) {
    throw new JsonRpcError("daemon returned a JSON-RPC response without a result");
  }

  return response as JsonRpcResponse<RegentRpcResult<TMethod>>;
};

const buildJsonRpcRequest = <TMethod extends RegentRpcMethod>(id: string, method: TMethod, params?: unknown) => ({
  jsonrpc: "2.0" as const,
  id,
  method,
  ...(params === undefined ? {} : { params }),
});

export async function callJsonRpc<TMethod extends RegentRpcMethod>(
  socketPath: string,
  method: TMethod,
  params?: unknown,
): Promise<RegentRpcResult<TMethod>> {
  const id = crypto.randomUUID();

  return new Promise<RegentRpcResult<TMethod>>((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let buffer = "";
    let settled = false;

    const cleanup = (): void => {
      socket.removeAllListeners();
      socket.end();
      socket.destroy();
    };

    const settle = (callback: () => void): void => {
      if (settled) {
        return;
      }

      settled = true;
      cleanup();
      callback();
    };

    socket.setEncoding("utf8");
    socket.once("error", (error) => {
      settle(() => {
        reject(
          new JsonRpcError("Regent local runtime is not running.", {
            code: "runtime_unavailable",
            cause: error,
            details: {
              socket_path: socketPath,
            },
            nextSteps: ["Run `regents run` in another terminal.", "Retry this command."],
          }),
        );
      });
    });

    socket.once("close", () => {
      settle(() => {
        reject(new JsonRpcError("daemon connection closed before a JSON-RPC response was received"));
      });
    });

    socket.on("data", (chunk) => {
      buffer += chunk;
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex < 0) {
        return;
      }

      settle(() => {
        const line = buffer.slice(0, newlineIndex).trim();

        if (line === "") {
          reject(new JsonRpcError("daemon returned an empty JSON-RPC response"));
          return;
        }

        try {
          const response = parseJsonRpcResponse<TMethod>(line, id);
          if ("error" in response) {
            reject(
              new JsonRpcError(response.error.message, {
                code: extractJsonRpcErrorCode(response.error.data),
                rpcCode: response.error.code,
              }),
            );
            return;
          }

          resolve(response.result);
        } catch (error) {
          reject(error);
        }
      });
    });

    socket.once("connect", () => {
      socket.write(`${JSON.stringify(buildJsonRpcRequest(id, method, params))}\n`);
    });
  });
}
