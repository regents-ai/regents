import fs from "node:fs";
import net from "node:net";

import type { JsonRpcFailure, JsonRpcRequest, JsonRpcSuccess, RegentRpcMethod } from "../../internal-types/index.js";

import { JsonRpcError, RegentError, errorMessage } from "../errors.js";
import { ensureParentDir } from "../paths.js";
import { claimUnixSocketPath } from "../unix-socket-guard.js";
import { REGENT_RPC_METHOD_SET } from "./methods.js";

export type JsonRpcHandler = (method: RegentRpcMethod, params: unknown) => Promise<unknown>;

const parseRequest = (payload: string): JsonRpcRequest<unknown> => {
  const parsed = JSON.parse(payload) as Partial<JsonRpcRequest<unknown>>;
  if (
    parsed.jsonrpc !== "2.0" ||
    typeof parsed.id !== "string" ||
    typeof parsed.method !== "string" ||
    !REGENT_RPC_METHOD_SET.has(parsed.method as RegentRpcMethod)
  ) {
    throw new JsonRpcError("invalid JSON-RPC request", { code: "invalid_request", rpcCode: -32600 });
  }

  return parsed as JsonRpcRequest<unknown>;
};

const jsonRpcError = (
  id: string | null,
  code: number,
  message: string,
  data?: unknown,
): JsonRpcFailure => ({
  jsonrpc: "2.0",
  id,
  error: data === undefined ? { code, message } : { code, message, data },
});

const jsonRpcSuccess = (id: string, result: unknown): JsonRpcSuccess<unknown> => ({
  jsonrpc: "2.0",
  id,
  result,
});

const errorResponse = (requestId: string | null, error: unknown): JsonRpcFailure => {
  if (error instanceof JsonRpcError) {
    return jsonRpcError(requestId, error.rpcCode ?? -32000, error.message, { code: error.code });
  }

  if (error instanceof RegentError) {
    return jsonRpcError(requestId, -32000, error.message, { code: error.code });
  }

  if (error instanceof SyntaxError) {
    return jsonRpcError(null, -32700, "parse error");
  }

  return jsonRpcError(requestId, -32000, errorMessage(error));
};

export class JsonRpcServer {
  readonly socketPath: string;
  readonly handler: JsonRpcHandler;
  private server: net.Server | null = null;

  constructor(socketPath: string, handler: JsonRpcHandler) {
    this.socketPath = socketPath;
    this.handler = handler;
  }

  async start(): Promise<void> {
    if (this.server) {
      return;
    }

    ensureParentDir(this.socketPath);
    await claimUnixSocketPath(this.socketPath);

    this.server = net.createServer((socket) => {
      let buffer = "";

      socket.setEncoding("utf8");
      socket.on("data", (chunk) => {
        buffer += chunk;

        while (true) {
          const newlineIndex = buffer.indexOf("\n");
          if (newlineIndex < 0) {
            break;
          }

          const line = buffer.slice(0, newlineIndex).trim();
          buffer = buffer.slice(newlineIndex + 1);

          if (line === "") {
            continue;
          }

          this.handleLine(socket, line).catch(() => {
            if (socket.destroyed) {
              return;
            }

            try {
              socket.write(`${JSON.stringify(jsonRpcError(null, -32603, "internal error"))}\n`);
            } catch {
              socket.destroy();
            }
          });
        }
      });
    });

    await new Promise<void>((resolve, reject) => {
      this.server?.once("error", reject);
      this.server?.listen(this.socketPath, () => {
        this.server?.off("error", reject);
        resolve();
      });
    });
  }

  async stop(): Promise<void> {
    const activeServer = this.server;
    this.server = null;

    if (activeServer) {
      await new Promise<void>((resolve, reject) => {
        activeServer.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    }

    if (fs.existsSync(this.socketPath)) {
      fs.rmSync(this.socketPath, { force: true });
    }
  }

  private async handleLine(socket: net.Socket, line: string): Promise<void> {
    let request: JsonRpcRequest<unknown> | null = null;

    try {
      request = parseRequest(line);
      const result = await this.handler(request.method, request.params);
      socket.write(`${JSON.stringify(jsonRpcSuccess(request.id, result))}\n`);
    } catch (error) {
      socket.write(`${JSON.stringify(errorResponse(request?.id ?? null, error))}\n`);
    }
  }
}
