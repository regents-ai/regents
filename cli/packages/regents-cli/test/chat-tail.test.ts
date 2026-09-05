import { beforeEach, describe, expect, it, vi } from "vitest";

import { captureOutput } from "../../../test-support/test-helpers.js";

const { requestProductResponseMock } = vi.hoisted(() => ({
  requestProductResponseMock: vi.fn(),
}));

vi.mock("../src/internal-runtime/product-http-client.js", async () => {
  const actual = await vi.importActual<
    typeof import("../src/internal-runtime/product-http-client.js")
  >("../src/internal-runtime/product-http-client.js");
  return { ...actual, requestProductResponse: requestProductResponseMock };
});

const { tailAutolaunchChatScopes } = await import("../src/commands/chat.js");

const streamResponse = (lines: readonly unknown[]): Response => {
  const encoder = new TextEncoder();
  return new Response(
    new ReadableStream<Uint8Array>({
      start(controller) {
        for (const line of lines) {
          controller.enqueue(encoder.encode(`${JSON.stringify(line)}\n`));
        }
        controller.close();
      },
    }),
    { status: 200, headers: { "content-type": "application/x-ndjson" } },
  );
};

describe("Autolaunch chat tail", () => {
  beforeEach(() => requestProductResponseMock.mockReset());

  it("subscribes to the requested product stream scopes", async () => {
    requestProductResponseMock.mockResolvedValueOnce({
      requestId: "req-1",
      response: streamResponse([]),
    });

    await tailAutolaunchChatScopes(
      ["topic:auctions", "token:abc"],
      null,
      "/tmp/regent.config.json",
    );

    expect(requestProductResponseMock).toHaveBeenCalledWith(
      expect.objectContaining({
        service: "autolaunch",
        method: "GET",
        path: "/api/autolaunch/v1/chat/stream?scopes=topic%3Aauctions%2Ctoken%3Aabc",
        configPath: "/tmp/regent.config.json",
        timeoutMs: 0,
      }),
    );
  });

  it("honors JSON output on a human terminal", async () => {
    requestProductResponseMock.mockResolvedValueOnce({
      requestId: "req-json",
      response: streamResponse([
        { event: "ready", scopes: ["system"] },
        {
          event: "message.created",
          message: { id: 7, scope: "system", body: "tty json event" },
        },
      ]),
    });
    const isTTY = Object.getOwnPropertyDescriptor(process.stdout, "isTTY");
    const previousNoColor = process.env.NO_COLOR;
    const previousTerm = process.env.TERM;
    Object.defineProperty(process.stdout, "isTTY", { value: true, configurable: true });
    process.env.TERM = "xterm-256color";
    delete process.env.NO_COLOR;

    try {
      const output = await captureOutput(async () =>
        tailAutolaunchChatScopes(["system"], null, "/tmp/regent.config.json", true),
      );
      expect(output.stdout).toBe(
        `${JSON.stringify({
          event: "message.created",
          message: { id: 7, scope: "system", body: "tty json event" },
        })}\n`,
      );
    } finally {
      if (isTTY) {
        Object.defineProperty(process.stdout, "isTTY", isTTY);
      } else {
        delete (process.stdout as unknown as Record<string, unknown>).isTTY;
      }
      process.env.TERM = previousTerm;
      if (previousNoColor === undefined) {
        delete process.env.NO_COLOR;
      } else {
        process.env.NO_COLOR = previousNoColor;
      }
    }
  });

  it("renders the human chat panel on a terminal without JSON output", async () => {
    requestProductResponseMock.mockResolvedValueOnce({
      requestId: "req-panel",
      response: streamResponse([
        { event: "ready", scopes: ["system"] },
        {
          event: "message.created",
          message: { id: 8, scope: "system", body: "panel event" },
        },
      ]),
    });
    const isTTY = Object.getOwnPropertyDescriptor(process.stdout, "isTTY");
    const previousNoColor = process.env.NO_COLOR;
    const previousTerm = process.env.TERM;
    Object.defineProperty(process.stdout, "isTTY", { value: true, configurable: true });
    process.env.TERM = "xterm-256color";
    delete process.env.NO_COLOR;

    try {
      const output = await captureOutput(async () =>
        tailAutolaunchChatScopes(["system"], null, "/tmp/regent.config.json"),
      );
      expect(output.stdout).toContain("CHAT LISTENING");
      expect(output.stdout).toContain("message.created");
      expect(output.stdout).toContain("panel event");
    } finally {
      if (isTTY) {
        Object.defineProperty(process.stdout, "isTTY", isTTY);
      } else {
        delete (process.stdout as unknown as Record<string, unknown>).isTTY;
      }
      process.env.TERM = previousTerm;
      if (previousNoColor === undefined) {
        delete process.env.NO_COLOR;
      } else {
        process.env.NO_COLOR = previousNoColor;
      }
    }
  });

  it("surfaces HTTP stream errors", async () => {
    requestProductResponseMock.mockResolvedValueOnce({
      requestId: "req-error",
      response: new Response(
        JSON.stringify({
          error: { code: "too_many_chat_scopes", message: "Choose fewer rooms." },
        }),
        { status: 422, headers: { "content-type": "application/json" } },
      ),
    });

    await expect(
      tailAutolaunchChatScopes(["system"], null, "/tmp/regent.config.json"),
    ).rejects.toThrow("Choose fewer rooms.");
  });
});
