import { describe, expect, it } from "vitest";

import { captureOutput } from "../../../test-support/test-helpers.js";
import {
  TEST_WALLET,
  setupCliEntrypointHarness,
} from "./helpers/cli-entrypoint-support.js";

const harness = setupCliEntrypointHarness();

describe("CLI command dispatch", () => {
  it.each([
    {
      name: "auth login",
      args: [
        "auth",
        "login",
        "--wallet-address",
        TEST_WALLET,
        "--chain-id",
        "8453",
        "--audience",
        "techtree",
      ],
      expected: {
        method: "auth.siwa.login",
        params: {
          walletAddress: TEST_WALLET,
          chainId: 8453,
          audience: "techtree",
        },
      },
    },
    {
      name: "auth status",
      args: ["auth", "status"],
      expected: { method: "auth.siwa.status" },
    },
    {
      name: "auth logout",
      args: ["auth", "logout"],
      expected: { method: "auth.siwa.logout" },
    },
    {
      name: "agent init",
      args: ["agent", "init"],
      expected: expect.objectContaining({
        initialized: true,
        currentProfile: expect.objectContaining({ name: "owner" }),
      }),
    },
    {
      name: "agent status",
      args: ["agent", "status"],
      expected: expect.objectContaining({
        initialized: true,
        profiles: expect.arrayContaining([
          expect.objectContaining({ name: "owner" }),
        ]),
      }),
    },
    {
      name: "agent profile list",
      args: ["agent", "profile", "list"],
      expected: {
        data: expect.arrayContaining([
          expect.objectContaining({ name: "owner" }),
        ]),
      },
    },
    {
      name: "agent profile get",
      args: ["agent", "profile", "get"],
      expected: { data: expect.objectContaining({ name: "owner" }) },
    },
    {
      name: "agent harness list",
      args: ["agent", "harness", "list"],
      expected: {
        data: expect.arrayContaining([
          expect.objectContaining({ name: "hermes" }),
        ]),
      },
    },
    {
      name: "gossipsub status",
      args: ["gossipsub", "status"],
      expected: { method: "gossipsub.status" },
    },
  ])("dispatches $name", async ({ args, expected }) => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([...args, "--config", harness.configPath]),
    );
    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(JSON.parse(output.stdout)).toEqual(expected);
  });

  it("dispatches notebook init and pair as local runtime methods", async () => {
    const init = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "notebooks",
        "init",
        "--workspace-path",
        "notes",
        "--kind",
        "freeform",
        "--title",
        "Notes",
        "--config",
        harness.configPath,
      ]),
    );
    expect(init.result).toBe(0);
    expect(JSON.parse(init.stdout)).toMatchObject({
      method: "techtree.notebooks.init",
      params: {
        workspace_path: "notes",
        kind: "freeform",
        title: "Notes",
      },
    });

    const pair = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "notebooks",
        "pair",
        "--workspace-path",
        "notes",
        "--config",
        harness.configPath,
      ]),
    );
    expect(pair.result).toBe(0);
    expect(JSON.parse(pair.stdout)).toMatchObject({
      method: "techtree.notebooks.pair",
      params: { workspace_path: "notes" },
    });
  });

  it("dispatches Verify run, status, and receipt show as local runtime methods", async () => {
    const run = await captureOutput(async () => harness.runCliEntrypoint([
      "techtree", "verify", "run", "--builtin", "--fixture", "--config", harness.configPath,
    ]));
    expect(run.result).toBe(0);
    expect(JSON.parse(run.stdout)).toMatchObject({ method: "techtree.verify.run", params: { builtin: true, executor: "fixture" } });

    const prime = await captureOutput(async () => harness.runCliEntrypoint([
      "techtree", "verify", "run", "--builtin", "--prime", "--config", harness.configPath,
    ]));
    expect(prime.result).toBe(0);
    expect(JSON.parse(prime.stdout)).toMatchObject({ method: "techtree.verify.run", params: { builtin: true, executor: "prime" } });

    const status = await captureOutput(async () => harness.runCliEntrypoint([
      "techtree", "verify", "status", "--comparison-id", "comparison-123", "--config", harness.configPath,
    ]));
    expect(status.result).toBe(0);
    expect(JSON.parse(status.stdout)).toMatchObject({ method: "techtree.verify.status", params: { comparison_id: "comparison-123" } });

    const show = await captureOutput(async () => harness.runCliEntrypoint([
      "techtree", "verify", "receipt", "show", "--digest", "a".repeat(64), "--config", harness.configPath,
    ]));
    expect(show.result).toBe(0);
    expect(JSON.parse(show.stdout)).toMatchObject({ method: "techtree.verify.receipt.show", params: { digest: "a".repeat(64) } });
  });

  it("does not dispatch deleted old-tree commands", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "node",
        "get",
        "1",
        "--json",
        "--config",
        harness.configPath,
      ]),
    );
    expect(output.result).toBe(2);
    expect(output.stdout).toBe("");
    expect(JSON.parse(output.stderr)).toMatchObject({
      error: { code: "unknown_command" },
    });
  });

  it("does not dispatch the deleted Hermes connector", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "agent",
        "connect",
        "hermes",
        "--json",
        "--config",
        harness.configPath,
      ]),
    );
    expect(output.result).toBe(2);
    expect(output.stdout).toBe("");
    expect(JSON.parse(output.stderr)).toMatchObject({
      error: { code: "unknown_command" },
    });
  });
});
