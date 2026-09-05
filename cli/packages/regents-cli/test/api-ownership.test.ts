import fs from "node:fs";

import { describe, expect, it } from "vitest";

import { CLI_COMMANDS } from "../src/command-registry.js";
import { apiCommandOwnership } from "../src/contracts/api-ownership.js";

const loadGeneratedPathSet = (relativePath: string): Set<string> => {
  const source = fs.readFileSync(new URL(relativePath, import.meta.url), "utf8");
  return new Set(Array.from(source.matchAll(/^    "([^"]+)": \{$/gmu), (match) => match[1]));
};

const pathsByOwner = {
  techtree: loadGeneratedPathSet("../src/generated/ash-techtree-openapi.ts"),
  autolaunch: loadGeneratedPathSet("../src/generated/autolaunch-openapi.ts"),
  platform: loadGeneratedPathSet("../src/generated/platform-openapi.ts"),
  "shared-services": new Set([
    ...loadGeneratedPathSet("../src/generated/regent-services-openapi.ts"),
    ...loadGeneratedPathSet("../src/generated/platform-openapi.ts"),
  ]),
} as const;

describe("API command ownership registry", () => {
  it("keeps every registered command string unique and shipped locally", () => {
    const commands = apiCommandOwnership.flatMap((group) => group.commands);
    expect(new Set(commands).size).toBe(commands.length);
    expect(commands.filter((command) => !CLI_COMMANDS.includes(command))).toEqual([]);
  });

  it("uses only current status labels", () => {
    expect(new Set(apiCommandOwnership.map((group) => group.status))).toEqual(
      new Set(["current", "current-local-and-api", "local"]),
    );
  });

  it("keeps declared paths aligned with repository-local copied API bindings", () => {
    const missingPaths = apiCommandOwnership.flatMap((group) =>
      group.pathTemplates
        .filter((pathTemplate) => !pathsByOwner[group.owner].has(pathTemplate))
        .map((pathTemplate) => ({ owner: group.owner, commands: group.commands, pathTemplate })),
    );
    expect(missingPaths).toEqual([]);
  });

  it("only leaves paths empty for documented local-only command groups", () => {
    expect(apiCommandOwnership.filter(
      (group) => group.pathTemplates.length === 0 && (group.status !== "local" || !group.note),
    )).toEqual([]);
  });

  it("classifies the surviving notebook commands as local-only", () => {
    const group = apiCommandOwnership.find((entry) => entry.owner === "techtree");
    expect(group).toMatchObject({
      commands: ["techtree notebooks init", "techtree notebooks pair"],
      owner: "techtree",
      status: "local",
      pathTemplates: [],
    });
  });
});
