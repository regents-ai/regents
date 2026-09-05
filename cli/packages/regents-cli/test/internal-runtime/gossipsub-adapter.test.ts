import { describe, expect, it } from "vitest";

import { RegentError } from "../../src/internal-runtime/errors.js";
import { StubGossipsubAdapter } from "../../src/internal-runtime/transports/gossipsub-adapter.js";

describe("local gossipsub status adapter", () => {
  it("reports disabled status and has no live chat subscription", async () => {
    const adapter = new StubGossipsubAdapter();
    await expect(adapter.status()).resolves.toMatchObject({
      enabled: false,
      configured: false,
      connected: false,
      status: "disabled",
      eventSocketPath: null,
    });
    await expect(adapter.subscribeChat(() => undefined)).rejects.toMatchObject(
      new RegentError(
        "chat_relay_disabled",
        "chat transport is disabled in config",
      ),
    );
  });
});
