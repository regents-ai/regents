import fs from "node:fs";
import path from "node:path";

import { parse } from "yaml";
import { describe, expect, it } from "vitest";

import { CLI_COMMANDS } from "../src/command-registry.js";
import { coreHandlers } from "../src/routes/core.js";

const root = path.resolve(import.meta.dirname, "../../..");
const retiredCommands = [["meta", "check"].join(" "), ["meta", "render"].join(" ")];

describe("standalone CLI hard cut", () => {
  it("removes retired maintenance commands from contract, routes, and generated help", () => {
    const contract = parse(fs.readFileSync(path.join(root, "docs/shared-cli-contract.yaml"), "utf8"));
    const contractCommands = contract.command_groups.flatMap((group: { commands?: string[] }) => group.commands ?? []);
    for (const command of retiredCommands) {
      expect(contractCommands).not.toContain(command);
      expect(coreHandlers).not.toHaveProperty(command);
      expect(CLI_COMMANDS).not.toContain(command);
    }
  });

  it("deletes private workspace discovery and rendering code", () => {
    const retiredFiles = [
      ["scripts", ["render", ["me", "ta"].join("")].join("-") + ".mjs"],
      ["packages/regents-cli/src/commands", ["me", "ta.ts"].join("")],
      ["packages/regents-cli/src/workspace", "manifest.js"],
    ];
    for (const parts of retiredFiles) expect(fs.existsSync(path.join(root, ...parts))).toBe(false);
  });

  it("keeps repository checks free of external workspace path discovery", () => {
    const files = [
      "scripts/check-workspace.mjs",
      "scripts/check-contract-inputs.mjs",
      "scripts/check-openapi-types.mjs",
      "scripts/check-cli-contract.mjs",
      "scripts/check-mcp-tools.mjs",
      "scripts/check-shared-services-contract.mjs",
    ];
    const forbidden = [
      ["meta", "stack.yaml"].join("/"),
      ["repo", "yaml"].join("."),
      ["..", "platform", "contracts"].join("/"),
    ];
    for (const file of files) {
      const source = fs.readFileSync(path.join(root, file), "utf8");
      for (const fragment of forbidden) expect(source, `${file}: ${fragment}`).not.toContain(fragment);
    }
  });
});
