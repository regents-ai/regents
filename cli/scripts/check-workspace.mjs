import fs from "node:fs";
import path from "node:path";
import { loadYaml } from "./dependency-preflight.mjs";
import { checkCliCommandMetadata } from "./generate-cli-command-metadata.mjs";

const root = path.resolve(import.meta.dirname, "..");
const YAML = await loadYaml(root);
const failures = [];

const fail = (message) => failures.push(message);
const fileExists = (filePath) => {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
};

const requiredFiles = [
  "package.json",
  "pnpm-workspace.yaml",
  "docs/shared-cli-contract.yaml",
  "docs/regent-services-contract.openapiv3.yaml",
  "docs/ash-techtree-contract.openapiv3.yaml",
  "docs/json-rpc-methods.yaml",
  "docs/json-rpc-methods.md",
  "docs/schemas/wallet-action.schema.yaml",
  "packages/regents-cli/package.json",
  "packages/regents-cli/src/generated/cli-command-metadata.ts",
  "packages/regents-cli/src/generated/platform-openapi.ts",
  "packages/regents-cli/src/generated/ash-techtree-openapi.ts",
  "packages/regents-cli/src/generated/regent-services-openapi.ts",
];

for (const relativePath of requiredFiles) {
  if (!fileExists(path.resolve(root, relativePath))) {
    fail(`missing repository-local input: ${relativePath}`);
  }
}

const cliContract = YAML.parse(fs.readFileSync(path.resolve(root, "docs/shared-cli-contract.yaml"), "utf8"));
if (cliContract?.version !== 1 || !Array.isArray(cliContract.command_groups)) {
  fail("docs/shared-cli-contract.yaml must use the local v1 command_groups contract");
}

const metadataCheck = checkCliCommandMetadata();
if (!metadataCheck.metadataOk) {
  fail(`generated CLI command metadata is out of date: ${path.relative(root, metadataCheck.outputPath)}`);
}
if (!metadataCheck.commandListOk) {
  fail(`generated CLI command list is out of date: ${path.relative(root, metadataCheck.commandListPath)}`);
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("repository-local workspace check passed");
