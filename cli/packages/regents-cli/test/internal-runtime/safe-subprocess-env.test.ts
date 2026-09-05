import { describe, expect, it } from "vitest";

import {
  buildSafeSubprocessEnv,
  isBlockedSubprocessEnvName,
} from "../../src/internal-runtime/safe-subprocess-env.js";

describe("safe subprocess environment", () => {
  it("keeps ordinary process settings and removes wallet and service secrets", () => {
    const env = buildSafeSubprocessEnv({
      PATH: "/usr/bin",
      HOME: "/tmp/home",
      LANG: "en_US.UTF-8",
      REGENT_WALLET_PRIVATE_KEY: "secret",
      OPENAI_API_KEY: "secret",
      AWS_SECRET_ACCESS_KEY: "secret",
      PRIVY_ACCESS_TOKEN: "secret",
      CDP_KEY_SECRET: "secret",
      X_PAYMENT: "payment",
    });

    expect(env.PATH).toBe("/usr/bin");
    expect(env.HOME).toBe("/tmp/home");
    expect(env.LANG).toBe("en_US.UTF-8");
    expect(env.REGENT_WALLET_PRIVATE_KEY).toBeUndefined();
    expect(env.OPENAI_API_KEY).toBeUndefined();
    expect(env.AWS_SECRET_ACCESS_KEY).toBeUndefined();
    expect(env.PRIVY_ACCESS_TOKEN).toBeUndefined();
    expect(env.CDP_KEY_SECRET).toBeUndefined();
    expect(env.X_PAYMENT).toBeUndefined();
  });

  it("rejects sensitive overrides unless the caller explicitly trusts the name", () => {
    expect(() => buildSafeSubprocessEnv({}, { REGENT_WALLET_PRIVATE_KEY: "secret" })).toThrow(
      "refusing to pass sensitive environment variable",
    );

    const env = buildSafeSubprocessEnv(
      { PATH: "/usr/bin" },
      { REGENT_TECHTREE_BASE_URL: "http://127.0.0.1:4020" },
      { trustedOverrideNames: ["REGENT_TECHTREE_BASE_URL"] },
    );

    expect(env.PATH).toBe("/usr/bin");
    expect(env.REGENT_TECHTREE_BASE_URL).toBe("http://127.0.0.1:4020");
  });

  it("blocks secret-like names case-insensitively", () => {
    expect(isBlockedSubprocessEnvName("openai_api_key")).toBe(true);
    expect(isBlockedSubprocessEnvName("regent_wallet_private_key")).toBe(true);
    expect(isBlockedSubprocessEnvName("PATH")).toBe(false);
  });
});
