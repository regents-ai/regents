import { describe, expect, it } from "vitest";

import { CLI_COMMANDS } from "../src/command-registry.js";
import { cliHandlerRegistry } from "../src/routes/index.js";

describe("CLI handler registry coverage", () => {
  it("has a registry handler for every generated contract command", () => {
    for (const command of CLI_COMMANDS) {
      expect(cliHandlerRegistry[command], command).toBeDefined();
    }
  });

  it("does not register handlers for commands that are not in the contract metadata", () => {
    const commandSet = new Set<string>(CLI_COMMANDS);
    for (const command of Object.keys(cliHandlerRegistry)) {
      expect(commandSet.has(command), command).toBe(true);
    }
  });

  it("registers exactly one handler per contract command", () => {
    expect(Object.keys(cliHandlerRegistry).sort()).toEqual([...CLI_COMMANDS].sort());
  });
});
