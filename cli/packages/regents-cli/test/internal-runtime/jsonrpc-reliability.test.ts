import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { callJsonRpc } from "../../src/internal-runtime/jsonrpc/client.js";
import { JsonRpcServer } from "../../src/internal-runtime/jsonrpc/server.js";
import { describeNetwork } from "../../../../test-support/integration.js";

const waitForEvent = (emitter: net.Socket, event: string): Promise<void> =>
  new Promise((resolve) => {
    emitter.once(event, () => {
      resolve();
    });
  });

const readLine = (socket: net.Socket): Promise<string> =>
  new Promise((resolve, reject) => {
    let buffer = "";
    const onData = (chunk: string): void => {
      buffer += chunk;
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex < 0) {
        return;
      }

      socket.off("data", onData);
      resolve(buffer.slice(0, newlineIndex));
    };

    socket.on("data", onData);
    socket.once("error", reject);
  });

describeNetwork("JSON-RPC reliability", () => {
  let tempDir = "";
  let socketPath = "";

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regents-jsonrpc-"));
    socketPath = path.join(tempDir, "regent.sock");
  });

  afterEach(() => {
    vi.restoreAllMocks();
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  describe("client socket cleanup", () => {
    let rawServer: net.Server | null = null;

    afterEach(async () => {
      const activeServer = rawServer;
      rawServer = null;
      if (activeServer) {
        await new Promise<void>((resolve) => {
          activeServer.close(() => {
            resolve();
          });
        });
      }
    });

    const listenRawServer = async (onConnection: (socket: net.Socket) => void): Promise<void> => {
      rawServer = net.createServer((socket) => {
        socket.resume();
        onConnection(socket);
      });
      await new Promise<void>((resolve) => {
        rawServer?.listen(socketPath, () => {
          resolve();
        });
      });
    };

    it("destroys the socket and removes listeners when the response handler throws", async () => {
      await listenRawServer((socket) => {
        socket.write("not-json\n");
      });

      const createConnection = vi.spyOn(net, "createConnection");

      await expect(callJsonRpc(socketPath, "runtime.ping")).rejects.toMatchObject({
        message: "daemon returned invalid JSON",
      });

      const clientSocket = createConnection.mock.results[0]?.value as net.Socket;
      expect(clientSocket.destroyed).toBe(true);
      expect(clientSocket.listenerCount("data")).toBe(0);
      expect(clientSocket.listenerCount("error")).toBe(0);
      expect(clientSocket.listenerCount("close")).toBe(0);
    });

    it("destroys the socket when the daemon closes the connection without responding", async () => {
      await listenRawServer((socket) => {
        socket.end();
      });

      const createConnection = vi.spyOn(net, "createConnection");

      await expect(callJsonRpc(socketPath, "runtime.ping")).rejects.toMatchObject({
        message: "daemon connection closed before a JSON-RPC response was received",
      });

      const clientSocket = createConnection.mock.results[0]?.value as net.Socket;
      expect(clientSocket.destroyed).toBe(true);
      expect(clientSocket.listenerCount("data")).toBe(0);
    });
  });

  describe("server handler rejection", () => {
    let server: JsonRpcServer | null = null;

    afterEach(async () => {
      const activeServer = server;
      server = null;
      await activeServer?.stop();
    });

    it("responds with a JSON-RPC error and keeps serving the same and other sockets", async () => {
      let calls = 0;
      server = new JsonRpcServer(socketPath, async () => {
        calls += 1;
        if (calls === 1) {
          // Reject with a value whose message getter throws, so the server's
          // own error-response construction fails and handleLine rejects.
          throw {
            get message(): string {
              throw new Error("error formatting failed");
            },
          };
        }

        return { ok: true };
      });
      await server.start();

      const socket = net.createConnection(socketPath);
      socket.setEncoding("utf8");
      await waitForEvent(socket, "connect");

      socket.write(`${JSON.stringify({ jsonrpc: "2.0", id: "req-1", method: "runtime.ping" })}\n`);
      const firstLine = await readLine(socket);
      expect(JSON.parse(firstLine)).toEqual({
        jsonrpc: "2.0",
        id: null,
        error: { code: -32603, message: "internal error" },
      });

      socket.write(`${JSON.stringify({ jsonrpc: "2.0", id: "req-2", method: "runtime.ping" })}\n`);
      const secondLine = await readLine(socket);
      expect(JSON.parse(secondLine)).toEqual({
        jsonrpc: "2.0",
        id: "req-2",
        result: { ok: true },
      });

      socket.destroy();

      await expect(callJsonRpc(socketPath, "runtime.ping")).resolves.toEqual({ ok: true });
      expect(calls).toBe(3);
    });
  });

  describe("socket path claiming", () => {
    let servers: JsonRpcServer[] = [];

    afterEach(async () => {
      const activeServers = servers;
      servers = [];
      for (const activeServer of activeServers) {
        await activeServer.stop().catch(() => {});
      }
    });

    it("refuses to start while another daemon is listening on the socket", async () => {
      const first = new JsonRpcServer(socketPath, async () => ({ ok: true }));
      servers.push(first);
      await first.start();

      const second = new JsonRpcServer(socketPath, async () => ({ ok: false }));

      await expect(second.start()).rejects.toMatchObject({
        name: "CliUsageError",
        code: "runtime_already_running",
      });

      // The first daemon is untouched and still answers on its socket.
      await expect(callJsonRpc(socketPath, "runtime.ping")).resolves.toEqual({ ok: true });
    });

    it("removes a genuinely stale socket file and starts", async () => {
      // A leftover socket path with nothing listening behind it: the probe
      // connection fails, so the guard may unlink it.
      fs.writeFileSync(socketPath, "");
      expect(fs.existsSync(socketPath)).toBe(true);

      const server = new JsonRpcServer(socketPath, async () => ({ ok: true }));
      servers.push(server);
      await server.start();

      await expect(callJsonRpc(socketPath, "runtime.ping")).resolves.toEqual({ ok: true });
    });
  });
});
