import { randomUUID } from "node:crypto";
import http, { type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";

import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";

import { createRegentsMcpServer } from "./server.js";

const MAX_BODY_BYTES = 1_048_576;

type ActiveTransport = {
  transport: StreamableHTTPServerTransport;
  closeKernel: () => Promise<void>;
};

export interface RegentsMcpHttpServerOptions {
  configPath?: string;
  host: string;
  port: number;
  bearerToken: string;
}

const headerValue = (value: string | string[] | undefined): string | undefined =>
  Array.isArray(value) ? value[0] : value;

const sendJson = (res: ServerResponse, statusCode: number, body: unknown): void => {
  if (res.headersSent) {
    return;
  }

  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
  });
  res.end(JSON.stringify(body));
};

const readJsonBody = async (req: IncomingMessage): Promise<unknown> => {
  const chunks: Buffer[] = [];
  let totalBytes = 0;

  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    totalBytes += buffer.byteLength;

    if (totalBytes > MAX_BODY_BYTES) {
      throw new Error("MCP request body is too large.");
    }

    chunks.push(buffer);
  }

  const rawBody = Buffer.concat(chunks).toString("utf8");
  return rawBody === "" ? undefined : JSON.parse(rawBody);
};

const unauthorized = (res: ServerResponse): void =>
  sendJson(res, 401, {
    jsonrpc: "2.0",
    error: {
      code: -32001,
      message: "Unauthorized",
    },
    id: null,
  });

const badRequest = (res: ServerResponse, message: string): void =>
  sendJson(res, 400, {
    jsonrpc: "2.0",
    error: {
      code: -32000,
      message,
    },
    id: null,
  });

const internalError = (res: ServerResponse): void =>
  sendJson(res, 500, {
    jsonrpc: "2.0",
    error: {
      code: -32603,
      message: "Internal server error",
    },
    id: null,
  });

const requireBearer = (
  req: IncomingMessage,
  res: ServerResponse,
  bearerToken: string,
): boolean => {
  if (headerValue(req.headers.authorization) !== `Bearer ${bearerToken}`) {
    unauthorized(res);
    return false;
  }

  return true;
};

export async function startRegentsMcpHttpServer(options: RegentsMcpHttpServerOptions) {
  if (!options.bearerToken) {
    throw new Error("REGENTS_MCP_TOKEN is required for streamable HTTP MCP.");
  }

  const transports = new Map<string, ActiveTransport>();

  const closeSession = async (sessionId: string): Promise<void> => {
    const active = transports.get(sessionId);
    if (!active) {
      return;
    }

    transports.delete(sessionId);
    await active.transport.close();
    await active.closeKernel();
  };

  const server = http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url ?? "/", `http://${req.headers.host ?? "127.0.0.1"}`);

    if (requestUrl.pathname !== "/mcp") {
      sendJson(res, 404, { ok: false, error: "not_found" });
      return;
    }

    if (!requireBearer(req, res, options.bearerToken)) {
      return;
    }

    const sessionId = headerValue(req.headers["mcp-session-id"]);

    try {
      if (req.method === "POST") {
        const body = await readJsonBody(req);
        let active = sessionId ? transports.get(sessionId) : undefined;

        if (!active) {
          if (sessionId || !isInitializeRequest(body)) {
            badRequest(res, "Bad Request: No valid session ID provided.");
            return;
          }

          const mcp = await createRegentsMcpServer({
            configPath: options.configPath,
            mode: "platform-http",
          });

          let kernelClosed = false;
          const closeKernel = async () => {
            if (kernelClosed) {
              return;
            }

            kernelClosed = true;
            await mcp.close();
          };

          const transport = new StreamableHTTPServerTransport({
            sessionIdGenerator: () => randomUUID(),
            onsessioninitialized: (initializedSessionId) => {
              transports.set(initializedSessionId, {
                transport,
                closeKernel,
              });
            },
          });

          transport.onclose = () => {
            const initializedSessionId = transport.sessionId;
            if (initializedSessionId) {
              transports.delete(initializedSessionId);
            }
            void closeKernel();
          };

          await mcp.server.connect(transport);
          await transport.handleRequest(req, res, body);
          return;
        }

        await active.transport.handleRequest(req, res, body);
        return;
      }

      if (req.method === "GET" || req.method === "DELETE") {
        if (!sessionId) {
          badRequest(res, "Bad Request: No valid session ID provided.");
          return;
        }

        const active = transports.get(sessionId);
        if (!active) {
          badRequest(res, "Bad Request: No valid session ID provided.");
          return;
        }

        await active.transport.handleRequest(req, res);

        if (req.method === "DELETE") {
          await closeSession(sessionId);
        }

        return;
      }

      res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
      res.end("method not allowed");
    } catch {
      internalError(res);
    }
  });

  await new Promise<void>((resolve, reject) => {
    const onError = (error: Error) => {
      server.off("listening", onListening);
      reject(error);
    };
    const onListening = () => {
      server.off("error", onError);
      resolve();
    };

    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(options.port, options.host);
  });

  const address = server.address() as AddressInfo;

  return {
    url: `http://${options.host}:${address.port}/mcp`,
    close: async () => {
      for (const sessionId of [...transports.keys()]) {
        await closeSession(sessionId);
      }

      await new Promise<void>((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    },
  };
}

export async function runRegentsMcpHttp(options: RegentsMcpHttpServerOptions): Promise<void> {
  const running = await startRegentsMcpHttpServer(options);
  process.stderr.write(`Regents MCP HTTP listening on ${running.url}\n`);

  await new Promise<void>((resolve) => {
    const shutdown = () => resolve();
    process.once("SIGINT", shutdown);
    process.once("SIGTERM", shutdown);
  });

  await running.close();
}
