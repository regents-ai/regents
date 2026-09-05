import { beforeEach, describe, expect, it, vi } from "vitest";

import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { daemonCallMock } = vi.hoisted(() => ({ daemonCallMock: vi.fn() }));

vi.mock("../../src/daemon-client.js", () => ({ daemonCall: daemonCallMock }));

describe("techtree verify commands", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    daemonCallMock.mockResolvedValue({ schema_version: 1, status: "completed" });
  });

  it("runs the exact offline built-in fixture path", async () => {
    const { runTechtreeVerifyRun } = await import("../../src/commands/techtree-verify.js");
    const { parseCliArgs } = await import("../../src/parse.js");
    const output = await captureOutput(() => runTechtreeVerifyRun(
      parseCliArgs(["techtree", "verify", "run", "--builtin", "--fixture"]),
      "/tmp/regent.config.json",
    ));
    expect(daemonCallMock).toHaveBeenCalledWith("techtree.verify.run", {
      builtin: true,
      executor: "fixture",
      hermes_command: undefined,
    }, "/tmp/regent.config.json");
    expect(parsePrintedJson(output.stdout)).toEqual({ schema_version: 1, status: "completed" });
  });

  it("requires explicit configuration for the Hermes path", async () => {
    const { runTechtreeVerifyRun } = await import("../../src/commands/techtree-verify.js");
    const { parseCliArgs } = await import("../../src/parse.js");
    await expect(runTechtreeVerifyRun(parseCliArgs(["--builtin"]))).rejects.toThrow("Use --fixture");
    await expect(runTechtreeVerifyRun(parseCliArgs(["--builtin", "--hermes-command-json", "{}"]))).rejects.toThrow("JSON string array");
    await captureOutput(() => runTechtreeVerifyRun(parseCliArgs(["--builtin", "--hermes-command-json", '["hermes","verify"]'])));
    expect(daemonCallMock).toHaveBeenLastCalledWith("techtree.verify.run", {
      builtin: true,
      executor: "hermes",
      hermes_command: ["hermes", "verify"],
    }, undefined);
  });

  it("dispatches the config-gated Prime executor without live access", async () => {
    const { runTechtreeVerifyRun } = await import("../../src/commands/techtree-verify.js");
    const { parseCliArgs } = await import("../../src/parse.js");
    await captureOutput(() => runTechtreeVerifyRun(parseCliArgs(["--builtin", "--prime"])));
    expect(daemonCallMock).toHaveBeenLastCalledWith("techtree.verify.run", {
      builtin: true,
      executor: "prime",
      hermes_command: undefined,
    }, undefined);
    await expect(runTechtreeVerifyRun(parseCliArgs(["--builtin", "--prime", "--fixture"]))).rejects.toThrow("mutually exclusive");
  });

  it("reads comparison status and receipts by stable identifiers", async () => {
    const { runTechtreeVerifyReceiptShow, runTechtreeVerifyStatus } = await import("../../src/commands/techtree-verify.js");
    const { parseCliArgs } = await import("../../src/parse.js");
    await captureOutput(() => runTechtreeVerifyStatus(parseCliArgs(["--comparison-id", "comparison-123"])));
    expect(daemonCallMock).toHaveBeenLastCalledWith("techtree.verify.status", { comparison_id: "comparison-123" }, undefined);
    await captureOutput(() => runTechtreeVerifyReceiptShow(parseCliArgs(["--digest", "a".repeat(64)])));
    expect(daemonCallMock).toHaveBeenLastCalledWith("techtree.verify.receipt.show", { digest: "a".repeat(64) }, undefined);
  });
});
