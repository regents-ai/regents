import fs from "node:fs";
import { resolve } from "node:path";
import { loadYaml } from "./dependency-preflight.mjs";
import { buildCliCommandMetadata, checkCliCommandMetadata } from "./generate-cli-command-metadata.mjs";

const root = resolve(import.meta.dirname, "..");
const YAML = await loadYaml(root);
const contractPath = resolve(root, "docs/shared-cli-contract.yaml");
const contract = YAML.parse(fs.readFileSync(contractPath, "utf8"));
const failures = [];
const fail = (message) => failures.push(message);

if (!contract || typeof contract !== "object" || contract.version !== 1) {
  fail("Shared CLI contract must set version: 1");
}
if (contract?.openapi || Array.isArray(contract?.commands)) {
  fail("Shared CLI contract must use command_groups");
}
if (!Array.isArray(contract?.command_groups) || contract.command_groups.length === 0) {
  fail("Shared CLI contract must define command_groups");
}

const commands = [];
for (const [index, group] of (contract?.command_groups ?? []).entries()) {
  for (const field of ["name", "interface", "auth_mode"]) {
    if (typeof group?.[field] !== "string" || group[field].trim() === "") {
      fail(`Shared CLI contract command_groups[${index}] is missing ${field}`);
    }
  }
  if (!Array.isArray(group?.commands) || group.commands.length === 0) {
    fail(`Shared CLI contract command_groups[${index}] has no commands`);
    continue;
  }
  commands.push(...group.commands.map((command) => command.replace(/^regents?\s+/u, "")));
}

if (new Set(commands).size !== commands.length) {
  fail("Shared CLI contract contains duplicate commands");
}

const metadata = buildCliCommandMetadata();
const shippedCommands = new Set(metadata.commands);
for (const command of commands) {
  if (!shippedCommands.has(command)) fail(`Shared CLI contract command has no local route: ${command}`);
}

for (const command of [["meta", "check"].join(" "), ["meta", "render"].join(" ")]) {
  if (shippedCommands.has(command)) fail(`Retired command is still shipped: ${command}`);
}

const generated = checkCliCommandMetadata();
if (!generated.metadataOk) fail("Generated CLI command metadata is out of date");
if (!generated.commandListOk) fail("Generated CLI command list is out of date");

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("repository-local CLI contract check passed");
