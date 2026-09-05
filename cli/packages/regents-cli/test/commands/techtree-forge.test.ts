import { beforeEach, describe, expect, it, vi } from "vitest";

import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const family = {
  schema_version: 1,
  family_id: "techtree.contract-drift-repair.v1",
  product_status: "planned",
  kind: "deterministic_contract_drift_repair",
  executor: "hermes",
  intervention: { artifact: "SKILL.md", changed_file_count: 1 },
  verifier: { protocol: "deterministic_contract_drift", protocol_version: 1 },
} as const;

const { showMock, validateMock } = vi.hoisted(() => ({
  showMock: vi.fn(),
  validateMock: vi.fn(),
}));

vi.mock("../../src/internal-runtime/handlers/techtree/forge.js", () => ({
  handleTechtreeForgeFamilyShow: showMock,
  handleTechtreeForgeFamilyValidate: validateMock,
}));

describe("techtree forge family commands", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("prints the closed family contract", async () => {
    showMock.mockResolvedValue(family);
    const { runTechtreeForgeFamilyShow } = await import("../../src/commands/techtree-forge.js");

    const output = await captureOutput(() => runTechtreeForgeFamilyShow());

    expect(showMock).toHaveBeenCalledWith();
    expect(parsePrintedJson(output.stdout)).toEqual(family);
  });

  it("passes one parsed closed input to validation", async () => {
    const input = {
      family,
      baseline: { files: { "SKILL.md": "before" } },
      candidate: { files: { "SKILL.md": "after" } },
    };
    validateMock.mockResolvedValue({
      schema_version: 1,
      valid: true,
      family_id: family.family_id,
      changed_files: ["SKILL.md"],
    });
    const { runTechtreeForgeFamilyValidate } = await import("../../src/commands/techtree-forge.js");
    const { parseCliArgs } = await import("../../src/parse.js");

    const output = await captureOutput(() =>
      runTechtreeForgeFamilyValidate(
        parseCliArgs(["techtree", "forge", "family", "validate", "--input-json", JSON.stringify(input)]),
      ),
    );

    expect(validateMock).toHaveBeenCalledWith({ input });
    expect(parsePrintedJson(output.stdout)).toEqual({
      schema_version: 1,
      valid: true,
      family_id: family.family_id,
      changed_files: ["SKILL.md"],
    });
  });

  it("rejects missing and malformed inline JSON before invoking the runtime", async () => {
    const { runTechtreeForgeFamilyValidate } = await import("../../src/commands/techtree-forge.js");
    const { parseCliArgs } = await import("../../src/parse.js");

    await expect(
      runTechtreeForgeFamilyValidate(parseCliArgs(["techtree", "forge", "family", "validate"])),
    ).rejects.toThrow("--input-json is required");
    await expect(
      runTechtreeForgeFamilyValidate(
        parseCliArgs(["techtree", "forge", "family", "validate", "--input-json", "{"]),
      ),
    ).rejects.toThrow("--input-json must be valid JSON");
    expect(validateMock).not.toHaveBeenCalled();
  });
});
