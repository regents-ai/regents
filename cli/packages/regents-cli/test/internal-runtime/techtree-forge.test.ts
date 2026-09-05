import { describe, expect, it } from "vitest";

import {
  handleTechtreeForgeFamilyShow,
  handleTechtreeForgeFamilyValidate,
} from "../../src/internal-runtime/handlers/techtree/forge.js";

const family = {
  schema_version: 1,
  family_id: "techtree.contract-drift-repair.v1",
  product_status: "planned",
  kind: "deterministic_contract_drift_repair",
  executor: "hermes",
  intervention: { artifact: "SKILL.md", changed_file_count: 1 },
  verifier: { protocol: "deterministic_contract_drift", protocol_version: 1 },
} as const;

describe("Techtree Forge family Verify runtime", () => {
  it("returns stable JSON for the one closed family", async () => {
    const first = await handleTechtreeForgeFamilyShow();
    const second = await handleTechtreeForgeFamilyShow();

    expect(first).toEqual(family);
    expect(JSON.stringify(first)).toBe(JSON.stringify(second));
  });

  it("accepts only a changed SKILL.md candidate", async () => {
    await expect(
      handleTechtreeForgeFamilyValidate({
        input: {
          family,
          baseline: { files: { "SKILL.md": "before" } },
          candidate: { files: { "SKILL.md": "after" } },
        },
      }),
    ).resolves.toEqual({
      schema_version: 1,
      valid: true,
      family_id: family.family_id,
      changed_files: ["SKILL.md"],
    });
  });

  it("rejects alternate executors, unchanged candidates, and extra files", async () => {
    const validate = (input: unknown) =>
      handleTechtreeForgeFamilyValidate({ input: input as never });

    await expect(
      validate({
        family: { ...family, executor: "alternate" },
        baseline: { files: { "SKILL.md": "before" } },
        candidate: { files: { "SKILL.md": "after" } },
      }),
    ).rejects.toThrow("family.executor must equal 'hermes'");
    await expect(
      validate({
        family,
        baseline: { files: { "SKILL.md": "same" } },
        candidate: { files: { "SKILL.md": "same" } },
      }),
    ).rejects.toThrow("must differ");
    await expect(
      validate({
        family,
        baseline: { files: { "SKILL.md": "before" } },
        candidate: { files: { "SKILL.md": "after", "README.md": "after" } },
      }),
    ).rejects.toThrow("additional fields");
  });
});
